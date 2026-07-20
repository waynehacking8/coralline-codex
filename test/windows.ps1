$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('coralline-codex-windows-' + [guid]::NewGuid().ToString('N'))
$Passes = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "not ok - $Message" }
}
function Assert-Contains([string]$Value, [string]$Needle, [string]$Message) {
    Assert-True ($Value.Contains($Needle)) "$Message (missing: $Needle)"
}
function Pass([string]$Message) {
    $script:Passes++
    Write-Output ("ok {0:D2} - {1}" -f $script:Passes, $Message)
}

try {
    New-Item -ItemType Directory -Force -Path $TestRoot | Out-Null
    $CodexHome = Join-Path $TestRoot 'Codex Home'
    $BinDir = Join-Path $TestRoot 'bin with spaces'
    $ProfilePath = Join-Path $TestRoot 'PowerShell profile.ps1'
    $FakeDir = Join-Path $TestRoot 'fake codex'
    New-Item -ItemType Directory -Force -Path $CodexHome, $BinDir, $FakeDir | Out-Null
    Set-Content -LiteralPath (Join-Path $CodexHome 'config.toml') -Value @'
model = "gpt-test"
approval_policy = "never"
'@ -Encoding UTF8
    $ConfigHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $CodexHome 'config.toml')).Hash
    Set-Content -LiteralPath $ProfilePath -Value '$global:UserSetting = "keep"' -Encoding UTF8

    $FakePython = Join-Path $FakeDir 'fake_codex.py'
    Set-Content -LiteralPath $FakePython -Value @'
import json
import sys

if "app-server" in sys.argv:
    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        if method == "initialize":
            print(json.dumps({"id": message["id"], "result": {"userAgent": "windows-test"}}), flush=True)
        elif method == "account/rateLimits/read":
            print(json.dumps({"id": message["id"], "result": {"rateLimits": {
                "planType": "pro", "primary": {"usedPercent": 21, "windowDurationMins": 10080, "resetsAt": 2000000000}
            }}}), flush=True)
        elif method == "account/usage/read":
            print(json.dumps({"id": message["id"], "result": {"summary": {"lifetimeTokens": 987654}}}), flush=True)
elif "--version" in sys.argv:
    print("codex-cli windows-test")
else:
    print(json.dumps(sys.argv[1:]))
'@ -Encoding UTF8
    if ($env:OS -eq 'Windows_NT') {
        $FakeCodex = Join-Path $FakeDir 'codex.cmd'
        Set-Content -LiteralPath $FakeCodex -Value "@echo off`r`npython `"$FakePython`" %*`r`n" -Encoding ASCII
    } else {
        $FakeCodex = Join-Path $FakeDir 'codex'
        Set-Content -LiteralPath $FakeCodex -Value "#!/usr/bin/env bash`npython3 `"$FakePython`" `"`$@`"`n" -Encoding utf8NoBOM
        & chmod 755 $FakeCodex
    }

    & (Join-Path $Root 'install.ps1') -CodexHome $CodexHome -BinDir $BinDir -CodexBin $FakeCodex -ShellHook -ProfilePath $ProfilePath | Out-Null
    $Wrapper = Join-Path $CodexHome 'coralline-codex\bin\coralline-codex.ps1'
    $CommandShim = Join-Path $BinDir 'coralline-codex.cmd'
    Assert-True (Test-Path -LiteralPath $Wrapper) 'PowerShell wrapper was installed'
    Assert-True (Test-Path -LiteralPath $CommandShim) 'Windows command shim was installed'
    Assert-True (Test-Path -LiteralPath (Join-Path $CodexHome 'coralline-codex\lib\usage.py')) 'usage helper was installed'
    Assert-True ((Get-ChildItem -LiteralPath (Join-Path $CodexHome 'themes') -Filter 'coralline-*.tmTheme').Count -eq 9) 'nine native themes were installed'
    Pass 'native Windows installer creates the complete runtime'

    $ProfileText = Get-Content -LiteralPath $ProfilePath -Raw
    Assert-Contains $ProfileText '# >>> coralline-codex managed PowerShell integration >>>' 'PowerShell hook marker installed'
    Assert-Contains $ProfileText '$global:UserSetting = "keep"' 'PowerShell profile content preserved'
    . $ProfilePath
    $HookOutput = (codex --version | Out-String)
    Assert-Contains $HookOutput 'codex-cli windows-test' 'PowerShell codex function launches the wrapper'
    Pass 'PowerShell shell integration is functional'

    $RunOutput = (& $Wrapper --yolo | Out-String)
    Assert-Contains $RunOutput 'tui.status_line=' 'native footer override is passed to Codex'
    Assert-Contains $RunOutput 'tui.theme=' 'native Coralline theme override is passed to Codex'
    Assert-Contains $RunOutput '--yolo' 'user Codex arguments are preserved'
    $UsageOutput = (& $Wrapper usage | Out-String)
    Assert-Contains $UsageOutput '7d: 79% remaining' 'official app-server quota works on Windows'
    Assert-Contains $UsageOutput '987.7k lifetime' 'account token activity works on Windows'
    Pass 'Windows launcher provides themed native status and exact usage data'

    & $Wrapper configure -Theme nord | Out-Null
    $WindowsConfig = Get-Content -LiteralPath (Join-Path $CodexHome 'coralline-codex.windows.json') -Raw | ConvertFrom-Json
    Assert-True ($WindowsConfig.theme -eq 'nord') 'Windows theme configuration was not persisted'
    & $Wrapper verify | Out-Null
    Pass 'Windows configuration and verification commands work'

    & (Join-Path $Root 'install.ps1') -CodexHome $CodexHome -BinDir $BinDir -CodexBin $FakeCodex -Update | Out-Null
    Assert-Contains (Get-Content -LiteralPath $ProfilePath -Raw) 'coralline-codex managed PowerShell integration' 'update removed shell hook'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $CodexHome 'config.toml')).Hash -eq $ConfigHash) 'update changed config.toml'
    Pass 'Windows update preserves shell integration and Codex configuration'

    & (Join-Path $CodexHome 'coralline-codex\install.ps1') -CodexHome $CodexHome -BinDir $BinDir -Uninstall | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $CodexHome 'coralline-codex'))) 'Windows runtime was not removed'
    Assert-True (-not (Test-Path -LiteralPath $CommandShim)) 'Windows command shim was not removed'
    Assert-True (-not (Get-Content -LiteralPath $ProfilePath -Raw).Contains('coralline-codex managed PowerShell integration')) 'PowerShell hook was not removed'
    Assert-Contains (Get-Content -LiteralPath $ProfilePath -Raw) '$global:UserSetting = "keep"' 'PowerShell uninstall changed unrelated profile content'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $CodexHome 'config.toml')).Hash -eq $ConfigHash) 'uninstall changed config.toml'
    Pass 'Windows uninstall is scoped and recoverable'

    Write-Output "1..$Passes"
} finally {
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
