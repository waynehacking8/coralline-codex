[CmdletBinding()]
param(
    [string]$CodexHome = '',
    [string]$BinDir = '',
    [string]$CodexBin = '',
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$ShellHook,
    [string]$ProfilePath = ''
)

$ErrorActionPreference = 'Stop'
$Source = $PSScriptRoot
if (-not $CodexHome) { $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' } }
if (-not $BinDir) { $BinDir = Join-Path $HOME '.local\bin' }
$InstallDir = Join-Path $CodexHome 'coralline-codex'
$ThemeDir = Join-Path $CodexHome 'themes'
$Config = Join-Path $CodexHome 'coralline-codex.windows.json'
$ShellState = Join-Path $CodexHome 'coralline-codex-powershell.json'
$BackupRoot = Join-Path $CodexHome 'coralline-codex-backups'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $BackupRoot $Stamp
$Wrapper = Join-Path $InstallDir 'bin\coralline-codex.ps1'
$CommandShim = Join-Path $BinDir 'coralline-codex.cmd'
$StartMarker = '# >>> coralline-codex managed PowerShell integration >>>'
$EndMarker = '# <<< coralline-codex managed PowerShell integration <<<'
$PreviousVersion = if (Test-Path -LiteralPath (Join-Path $InstallDir 'VERSION')) { (Get-Content -LiteralPath (Join-Path $InstallDir 'VERSION') -Raw).Trim() } else { '' }

function Backup-File([string]$Path, [string]$Bucket) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    New-Item -ItemType Directory -Force -Path $Bucket | Out-Null
    $target = Join-Path $Bucket ((Split-Path -Leaf $Path) + ".bak.$Stamp")
    Copy-Item -LiteralPath $Path -Destination $target
    return $target
}

function Remove-ManagedHook([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $text = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?ms)^' + [regex]::Escape($StartMarker) + '.*?^' + [regex]::Escape($EndMarker) + '\r?\n?'
    $clean = [regex]::Replace($text, $pattern, '').TrimEnd() + [Environment]::NewLine
    if ($clean -eq $text) { return $false }
    Backup-File $Path (Join-Path $BackupRoot 'powershell') | Out-Null
    Set-Content -LiteralPath $Path -Value $clean -Encoding UTF8
    return $true
}

function Remove-ShellIntegration {
    if (-not (Test-Path -LiteralPath $ShellState)) { return }
    $state = Get-Content -LiteralPath $ShellState -Raw | ConvertFrom-Json
    if ($state.profile) {
        if (Remove-ManagedHook ([string]$state.profile)) {
            Write-Output "Managed PowerShell hook removed from $($state.profile)"
        }
    }
    Remove-Item -LiteralPath $ShellState -Force
}

if ($Uninstall) {
    if (-not (Test-Path -LiteralPath $InstallDir)) {
        Write-Output "Coralline Codex is not installed in $CodexHome"
        exit 0
    }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Remove-ShellIntegration
    if (Test-Path -LiteralPath $Config) { Move-Item -LiteralPath $Config -Destination (Join-Path $BackupDir (Split-Path -Leaf $Config)) }
    if (Test-Path -LiteralPath $ThemeDir) {
        New-Item -ItemType Directory -Force -Path (Join-Path $BackupDir 'themes') | Out-Null
        Get-ChildItem -LiteralPath $ThemeDir -Filter 'coralline-*.tmTheme' | ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $BackupDir 'themes')
        }
    }
    if (Test-Path -LiteralPath $CommandShim) { Remove-Item -LiteralPath $CommandShim -Force }
    Move-Item -LiteralPath $InstallDir -Destination (Join-Path $BackupDir 'install')
    Write-Output "Uninstalled Coralline Codex. Recoverable backup: $BackupDir"
    Write-Output 'Codex config.toml was not changed.'
    exit 0
}

if (-not $CodexBin) {
    $command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { throw 'The Codex CLI is required.' }
    $CodexBin = $command.Source
}
$CodexBin = (Resolve-Path -LiteralPath $CodexBin).Path
$python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) { $python = Get-Command python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $python) { throw 'Python 3.8+ is required.' }

New-Item -ItemType Directory -Force -Path $CodexHome, $BinDir, $ThemeDir | Out-Null
$Stage = Join-Path $CodexHome ('.coralline-codex-stage.' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null
    foreach ($file in @('VERSION', 'CHANGELOG.md', 'LICENSE', 'NOTICE.md', 'README.md', 'README.zh-TW.md', 'install.sh', 'install.ps1', 'configure.sh', 'configure.ps1')) {
        if (Test-Path -LiteralPath (Join-Path $Source $file)) { Copy-Item -LiteralPath (Join-Path $Source $file) -Destination $Stage }
    }
    foreach ($directory in @('bin', 'lib', 'themes', 'tools', 'test', 'docs')) {
        Copy-Item -LiteralPath (Join-Path $Source $directory) -Destination $Stage -Recurse
    }
    & $python.Source (Join-Path $Stage 'tools\generate_themes.py') --palettes (Join-Path $Stage 'themes\palettes.tsv') --output (Join-Path $Stage 'themes\generated')
    if ($LASTEXITCODE -ne 0) { throw 'Theme generation failed.' }
    if (Test-Path -LiteralPath $InstallDir) {
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        Move-Item -LiteralPath $InstallDir -Destination (Join-Path $BackupDir 'install')
    }
    Move-Item -LiteralPath $Stage -Destination $InstallDir
    $Stage = ''
} finally {
    if ($Stage -and (Test-Path -LiteralPath $Stage)) { Remove-Item -LiteralPath $Stage -Recurse -Force }
}

Get-ChildItem -LiteralPath (Join-Path $InstallDir 'themes\generated') -Filter '*.tmTheme' | ForEach-Object {
    $target = Join-Path $ThemeDir $_.Name
    if (Test-Path -LiteralPath $target) {
        Backup-File $target (Join-Path $BackupDir 'themes') | Out-Null
    }
    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
}
$shimText = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Wrapper`" %*`r`n"
Set-Content -LiteralPath $CommandShim -Value $shimText -Encoding ASCII

if (Test-Path -LiteralPath $Config) {
    $settings = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    Backup-File $Config (Join-Path $BackupRoot 'windows-config') | Out-Null
    $settings.codexBin = $CodexBin
} else {
    $settings = [pscustomobject]@{ version = 1; theme = 'claude-coral'; nativeStatus = $true; codexBin = $CodexBin }
}
$settings | ConvertTo-Json | Set-Content -LiteralPath $Config -Encoding UTF8

if ($ShellHook) {
    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserAllHosts }
    $profileDirectory = Split-Path -Parent $ProfilePath
    New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
    $old = if (Test-Path -LiteralPath $ProfilePath) { Get-Content -LiteralPath $ProfilePath -Raw } else { '' }
    $pattern = '(?ms)^' + [regex]::Escape($StartMarker) + '.*?^' + [regex]::Escape($EndMarker) + '\r?\n?'
    $clean = [regex]::Replace($old, $pattern, '').TrimEnd()
    $escapedWrapper = $Wrapper.Replace("'", "''")
    $block = @"
$StartMarker
function global:codex {
    & '$escapedWrapper' @args
}
$EndMarker
"@
    $new = if ($clean) { $clean + [Environment]::NewLine + [Environment]::NewLine + $block.Trim() + [Environment]::NewLine } else { $block.Trim() + [Environment]::NewLine }
    if ($new -ne $old) {
        Backup-File $ProfilePath (Join-Path $BackupRoot 'powershell') | Out-Null
        Set-Content -LiteralPath $ProfilePath -Value $new -Encoding UTF8
    }
    @{ version = 1; profile = $ProfilePath } | ConvertTo-Json | Set-Content -LiteralPath $ShellState -Encoding UTF8
    Write-Output "Managed PowerShell hook installed in $ProfilePath"
}

$CurrentVersion = (Get-Content -LiteralPath (Join-Path $InstallDir 'VERSION') -Raw).Trim()
Write-Output "Coralline Codex $CurrentVersion installed."
Write-Output "  command: $CommandShim"
Write-Output "  runtime: $InstallDir"
Write-Output "  config:  $Config"
Write-Output '  Codex config.toml: unchanged'
if ($PreviousVersion -and $PreviousVersion -ne $CurrentVersion) {
    Write-Output ''
    Write-Output "Updated $PreviousVersion -> $CurrentVersion. New in this release:"
    $show = $false
    foreach ($line in Get-Content -LiteralPath (Join-Path $InstallDir 'CHANGELOG.md')) {
        if ($line.StartsWith("## $CurrentVersion ")) { $show = $true; continue }
        if ($show -and $line.StartsWith('## ')) { break }
        if ($show -and $line.StartsWith('- ')) { Write-Output "  $line" }
    }
}
