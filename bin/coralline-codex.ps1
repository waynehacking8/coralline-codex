[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$InstalledCodexHome = Split-Path -Parent $Root
$InstalledConfig = Join-Path $InstalledCodexHome 'coralline-codex.windows.json'
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } elseif (Test-Path -LiteralPath $InstalledConfig) { $InstalledCodexHome } else { Join-Path $HOME '.codex' }
$ConfigPath = Join-Path $CodexHome 'coralline-codex.windows.json'

function Read-CorallineConfig {
    if (Test-Path -LiteralPath $ConfigPath) {
        return Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{ theme = 'claude-coral'; nativeStatus = $true; codexBin = '' }
}

function Get-PythonCommand {
    $python = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($python) { return [pscustomobject]@{ executable = $python.Source; prefix = @() } }
    $python3 = Get-Command python3 -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($python3) { return [pscustomobject]@{ executable = $python3.Source; prefix = @() } }
    $launcher = Get-Command py -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($launcher) { return [pscustomobject]@{ executable = $launcher.Source; prefix = @('-3') } }
    throw 'Python 3.8+ is required.'
}

function Invoke-Python([string[]]$PythonArgs) {
    $python = Get-PythonCommand
    $arguments = @($python.prefix) + @($PythonArgs)
    & $python.executable @arguments
}

function Resolve-CodexBinary($Config) {
    if ($env:CORALLINE_CODEX_BIN) { return $env:CORALLINE_CODEX_BIN }
    if ($Config.codexBin) { return [string]$Config.codexBin }
    $command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw 'Could not resolve the real Codex executable.'
}

$Config = Read-CorallineConfig
$CodexBin = Resolve-CodexBinary $Config
if ($CodexArgs.Count -and $CodexArgs[0] -eq '--no-companion') {
    $CodexArgs = if ($CodexArgs.Count -gt 1) { @($CodexArgs[1..($CodexArgs.Count - 1)]) } else { @() }
}
$Command = if ($CodexArgs.Count) { $CodexArgs[0] } else { 'run' }
$Rest = if ($CodexArgs.Count -gt 1) { @($CodexArgs[1..($CodexArgs.Count - 1)]) } else { @() }

switch ($Command) {
    'usage' {
        $pythonArgs = @(
            (Join-Path $Root 'lib\usage.py'), 'status', '--codex-bin', $CodexBin,
            '--rate-cache', (Join-Path $CodexHome 'coralline-codex-cache\rate.env')
        )
        Invoke-Python $pythonArgs
        exit $LASTEXITCODE
    }
    'configure' {
        $configureArgs = @{ CodexHome = $CodexHome }
        for ($index = 0; $index -lt $Rest.Count; $index++) {
            switch ($Rest[$index]) {
                { $_ -in @('-Theme', '--theme') } {
                    $index++
                    if ($index -ge $Rest.Count) { throw 'configure: missing theme value' }
                    $configureArgs.Theme = $Rest[$index]
                }
                { $_ -in @('-NativeStatus', '--native-status') } {
                    $index++
                    if ($index -ge $Rest.Count) { throw 'configure: missing native-status value' }
                    $configureArgs.NativeStatus = $Rest[$index]
                }
                { $_ -in @('-Show', '--show') } { $configureArgs.Show = $true }
                default { throw "configure: unknown option: $($Rest[$index])" }
            }
        }
        & (Join-Path $Root 'configure.ps1') @configureArgs
        exit 0
    }
    'verify' {
        $required = @(
            (Join-Path $Root 'lib\usage.py'),
            (Join-Path $Root 'themes\palettes.tsv'),
            (Join-Path $CodexHome 'themes\coralline-claude-coral.tmTheme')
        )
        foreach ($path in $required) {
            if (-not (Test-Path -LiteralPath $path)) { throw "Missing installed file: $path" }
        }
        & $CodexBin --version
        if ($LASTEXITCODE -ne 0) { throw 'Codex executable verification failed.' }
        Write-Output 'Verification passed.'
        Write-Output 'Native Windows tier: themed Codex footer with plan limits and session tokens.'
        Write-Output 'Use WSL for the full tmux companion bar.'
        exit 0
    }
    'uninstall' {
        & (Join-Path $Root 'install.ps1') -CodexHome $CodexHome -Uninstall
        exit $LASTEXITCODE
    }
    'run' { $Rest = @($Rest) }
    default { $Rest = @($CodexArgs) }
}

if ($env:CORALLINE_CODEX_DISABLE -eq '1') {
    & $CodexBin @Rest
    exit $LASTEXITCODE
}

$Native = @()
if ($Config.nativeStatus -ne $false) {
    $Theme = if ($Config.theme) { [string]$Config.theme } else { 'claude-coral' }
    $Native = @(
        '-c', 'tui.status_line=["model-with-reasoning","context-remaining","five-hour-limit","weekly-limit","used-tokens"]',
        '-c', 'tui.status_line_use_colors=true',
        '-c', "tui.theme=`"coralline-$Theme`""
    )
}
& $CodexBin @Native @Rest
exit $LASTEXITCODE
