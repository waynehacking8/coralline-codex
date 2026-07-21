[CmdletBinding()]
param(
    [string]$CodexHome = '',
    [string]$Theme = '',
    [ValidateSet('on', 'off')]
    [string]$NativeStatus = '',
    [string]$NativeFields = '',
    [switch]$Show
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
if (-not $CodexHome) { $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' } }
$ConfigPath = Join-Path $CodexHome 'coralline-codex.windows.json'
$Backups = Join-Path $CodexHome 'coralline-codex-backups\windows-config'
$Themes = @()
Get-Content -LiteralPath (Join-Path $Root 'themes\palettes.tsv') | ForEach-Object {
    if ($_ -and -not $_.StartsWith('#')) { $script:Themes += ($_ -split "`t")[0] }
}

$Config = if (Test-Path -LiteralPath $ConfigPath) {
    Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} else {
    [pscustomobject]@{
        version = 1; theme = 'claude-coral'; nativeStatus = $true; codexBin = ''
        nativeFields = @('model-with-reasoning', 'run-state', 'context-remaining', 'five-hour-limit', 'weekly-limit', 'used-tokens', 'fast-mode', 'task-progress')
    }
}

if (-not $Theme -and -not $NativeStatus -and -not $NativeFields -and -not $Show) {
    Write-Output 'Coralline Codex for Windows'
    for ($index = 0; $index -lt $Themes.Count; $index++) {
        Write-Output ("  {0,2}) {1}" -f ($index + 1), $Themes[$index])
    }
    $choice = Read-Host "Theme [$($Config.theme)]"
    if ($choice) {
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Themes.Count) {
            $Theme = $Themes[[int]$choice - 1]
        } else { $Theme = $choice }
    }
}

if ($Theme) {
    if ($Themes -notcontains $Theme) { throw "Unknown theme: $Theme" }
    $Config.theme = $Theme
}
if ($NativeStatus) { $Config.nativeStatus = ($NativeStatus -eq 'on') }
if ($NativeFields) {
    $AllowedFields = @(
        'model', 'model-name', 'model-with-reasoning', 'reasoning', 'current-dir', 'project-name', 'project-root',
        'git-branch', 'pull-request-number', 'branch-changes', 'run-state', 'status', 'permissions', 'approval-mode',
        'approval', 'context-remaining', 'context-used', 'context-usage', 'five-hour-limit', 'weekly-limit',
        'codex-version', 'context-window-size', 'used-tokens', 'total-input-tokens', 'total-output-tokens',
        'thread-id', 'session-id', 'fast-mode', 'raw-output', 'thread-title', 'workspace-headline', 'task-progress'
    )
    $ParsedFields = if ($NativeFields -eq 'inherit') { @('inherit') } else { @($NativeFields -split '[, ]+' | Where-Object { $_ }) }
    foreach ($Field in $ParsedFields) {
        if ($AllowedFields -notcontains $Field) { throw "Unknown native status field: $Field" }
    }
    if ($Config.PSObject.Properties.Name -contains 'nativeFields') { $Config.nativeFields = $ParsedFields }
    else { $Config | Add-Member -NotePropertyName nativeFields -NotePropertyValue $ParsedFields }
}

if ($Theme -or $NativeStatus -or $NativeFields) {
    New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null
    if (Test-Path -LiteralPath $ConfigPath) {
        New-Item -ItemType Directory -Force -Path $Backups | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $Backups "coralline-codex.windows.json.bak.$stamp")
    }
    $Config | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Output "Configuration updated: $ConfigPath"
}
if ($Show -or (-not $Theme -and -not $NativeStatus -and -not $NativeFields)) {
    $Config | ConvertTo-Json
}
