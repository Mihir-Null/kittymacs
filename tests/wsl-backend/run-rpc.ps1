# The wsl-rpc transport beside wslm, on real WSL2.  A hosted runner's job, because
# this is the one place tramp-rpc's code runs.  It changes the distribution and runs
# `wsl --shutdown`: never point it at a machine with work on it.
#
# The workflow runs `just install` first with the feature on, as a user's start does.

param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$Results = 'wsl-rpc-results',
    [string]$Packages = 'var/elpa'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# A script block, because a function's own parameters would take -d as -Debug.
function Invoke-Checked {
    param([scriptblock]$Block)
    & $Block
    if ($LASTEXITCODE -ne 0) { throw "Exit $LASTEXITCODE from: $Block" }
}

& "$here/prove-wsl2.ps1" -Distribution $Distribution

New-Item -ItemType Directory -Force -Path $Results | Out-Null
$resultsFull = (Resolve-Path $Results).Path

# One home for the pin: what the configuration installs is what gets built.
$module = Get-Content (Join-Path $here '../../lisp/kittymacs-remote-rpc.el') -Raw
$repository = [regex]::Match($module, 'kittymacs-remote-rpc-repository "([^"]+)"').Groups[1].Value
$revision = [regex]::Match($module, 'kittymacs-remote-rpc-revision "([0-9a-f]{40})"').Groups[1].Value
if (-not $repository -or -not $revision) { throw 'No pin in the module' }
"The pin: $repository at $revision"

Invoke-Checked { wsl.exe -d $Distribution -u root --cd $here --exec bash rpc-root.sh }
Invoke-Checked { wsl.exe --terminate $Distribution }
Invoke-Checked { wsl.exe -d $Distribution --cd $here --exec bash rpc-fixtures.sh }
Invoke-Checked {
    wsl.exe -d $Distribution --cd $here --exec bash rpc-build-server.sh $repository $revision |
        Tee-Object -FilePath (Join-Path $resultsFull 'server-build.log')
}

$env:KITTYMACS_WSL_DISTRIBUTION = $Distribution
$env:KITTYMACS_TEST_PACKAGES = (Resolve-Path $Packages).Path -replace '\\', '/'
$env:KITTYMACS_RPC_ROUNDS = '3'
$script = (Join-Path $here 'rpc.el') -replace '\\', '/'

function Invoke-Phase {
    param([string]$Phase, [int]$Minutes)
    "::group::$Phase"
    $env:KITTYMACS_RPC_PHASE = $Phase
    $log = Join-Path $resultsFull "$Phase.log"
    $out = Join-Path $resultsFull "$Phase.md"
    $process = Start-Process -FilePath emacs -NoNewWindow -PassThru `
        -ArgumentList '-Q', '--batch', '-l', $script `
        -RedirectStandardError $log -RedirectStandardOutput $out
    if (-not $process.WaitForExit($Minutes * 60 * 1000)) {
        "Emacs passed $Minutes minutes: stopping it"
        Add-Content -Path $out -Value "`n$Phase passed its limit of $Minutes minutes`n`nFAIL"
        $process.Kill($true)
    }
    # What one phase left behind must not carry over.
    Get-Process wsl, wslhost, cat -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    wsl.exe --terminate $Distribution
    if (Test-Path $log) { Get-Content $log -Tail 200 }
    "::endgroup::"
    "## $Phase" | Add-Content -Path (Join-Path $resultsFull 'report.md')
    Get-Content $out | Add-Content -Path (Join-Path $resultsFull 'report.md')
}

# The killed write first, because it is what the owner reads first, and it fits a
# short limit, so a later hang cannot cost it.
Invoke-Phase -Phase 'killed-write' -Minutes 15
Invoke-Phase -Phase 'compare' -Minutes 30
Invoke-Phase -Phase 'ergonomics' -Minutes 25
Invoke-Phase -Phase 'dead' -Minutes 15

$report = Join-Path $resultsFull 'report.md'
Get-Content $report
if ($env:GITHUB_STEP_SUMMARY) { Get-Content $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY }
if (Get-Content $report | Select-String -Quiet '^FAIL$') { throw 'A check failed: see the report' }
