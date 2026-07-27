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
$MinimumCodexVersion = [version]'0.145.0'
$DefaultNativeFields = @('model-with-reasoning', 'run-state', 'context-remaining', 'five-hour-limit', 'weekly-limit', 'used-tokens', 'git-branch', 'branch-changes', 'fast-mode', 'task-progress')

function Read-CorallineConfig {
    if (Test-Path -LiteralPath $ConfigPath) {
        return Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{
        theme = 'claude-coral'; nativeStatus = $true; codexBin = ''
        nativeFields = $DefaultNativeFields
    }
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

function Assert-CodexVersion([string]$Executable) {
    $output = (& $Executable --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Failed to run Codex: $Executable" }
    if ($output -notmatch '(\d+\.\d+\.\d+)') { throw "Could not parse Codex version: $output" }
    $found = [version]$Matches[1]
    if ($found -lt $MinimumCodexVersion) {
        throw "Codex $MinimumCodexVersion or newer is required (found $found)."
    }
}

function Test-CodexInteractive([string[]]$Arguments) {
    $valueOptions = @(
        '-c', '--config', '--enable', '--disable', '--remote', '--remote-auth-token-env',
        '-m', '--model', '--local-provider', '-p', '--profile', '-s', '--sandbox',
        '-C', '--cd', '--add-dir', '-a', '--ask-for-approval'
    )
    $nonInteractive = @(
        'exec', 'e', 'review', 'login', 'logout', 'mcp', 'plugin', 'mcp-server',
        'app-server', 'remote-control', 'completion', 'update', 'doctor', 'sandbox',
        'debug', 'apply', 'a', 'archive', 'delete', 'unarchive', 'cloud', 'exec-server',
        'features', 'help'
    )
    $expectValue = $false
    $interactiveCommand = $false
    foreach ($argument in $Arguments) {
        if ($expectValue) { $expectValue = $false; continue }
        if ($interactiveCommand) {
            if ($argument -in @('-h', '--help', '-V', '--version')) { return $false }
            continue
        }
        if ($argument -eq '--') { return $true }
        if ($argument -in @('-i', '--image')) { return $true }
        if ($argument -in $valueOptions) { $expectValue = $true; continue }
        if ($argument -match '^--(config|enable|disable|remote|remote-auth-token-env|model|local-provider|profile|sandbox|cd|add-dir|ask-for-approval)=') { continue }
        if ($argument -in @('-h', '--help', '-V', '--version')) { return $false }
        if ($argument -in @('resume', 'fork')) { $interactiveCommand = $true; continue }
        if ($argument -in $nonInteractive) { return $false }
        if ($argument.StartsWith('-')) { continue }
        return $true
    }
    return $true
}

function Test-HasNoAltScreen([string[]]$Arguments) {
    foreach ($argument in $Arguments) {
        if ($argument -eq '--') { return $false }
        if ($argument -eq '--no-alt-screen') { return $true }
    }
    return $false
}

$Config = Read-CorallineConfig
$CodexBin = Resolve-CodexBinary $Config
$Command = if ($CodexArgs.Count) { $CodexArgs[0] } else { 'run' }
$Rest = if ($CodexArgs.Count -gt 1) { @($CodexArgs[1..($CodexArgs.Count - 1)]) } else { @() }

switch ($Command) {
    'usage' {
        $pythonArgs = @(
            (Join-Path $Root 'lib\usage.py'), 'status', '--codex-bin', $CodexBin,
            '--rate-cache', (Join-Path $CodexHome 'coralline-codex-cache\rate.env'),
            '--history', (Join-Path $CodexHome 'coralline-codex-cache\usage-history.json')
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
                { $_ -in @('-NativeFields', '--native-fields') } {
                    $index++
                    if ($index -ge $Rest.Count) { throw 'configure: missing native-fields value' }
                    $configureArgs.NativeFields = $Rest[$index]
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
        Assert-CodexVersion $CodexBin
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

if ($Rest.Count -and $Rest[0] -in @('--full-companion', '--no-companion')) {
    $mode = $Rest[0]
    $Rest = if ($Rest.Count -gt 1) { @($Rest[1..($Rest.Count - 1)]) } else { @() }
    if ($mode -eq '--full-companion') {
        [Console]::Error.WriteLine('--full-companion requires Bash and tmux. Use WSL for the full companion.')
        exit 2
    }
}

Assert-CodexVersion $CodexBin
$Native = @()
if ($Config.nativeStatus -ne $false) {
    $Theme = if ($Config.theme) { [string]$Config.theme } else { 'claude-coral' }
    $Fields = if ($Config.PSObject.Properties.Name -contains 'nativeFields') { @($Config.nativeFields) } else { $DefaultNativeFields }
    $StatusOverride = @()
    if (-not ($Fields.Count -eq 1 -and $Fields[0] -eq 'inherit')) {
        $FieldList = ($Fields | ForEach-Object { '"' + [string]$_ + '"' }) -join ','
        $StatusOverride = @('-c', "tui.status_line=[$FieldList]")
    }
    $Native = @(
        $StatusOverride
        '-c', 'tui.status_line_use_colors=true',
        '-c', "tui.theme=`"coralline-$Theme`""
    )
}
[string[]]$Inline = if ((Test-CodexInteractive $Rest) -and -not (Test-HasNoAltScreen $Rest)) { '--no-alt-screen' } else { @() }
& $CodexBin @Native @Inline @Rest
exit $LASTEXITCODE
