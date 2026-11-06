# tramp-rpc over wsl.exe beside wslm, on a hosted Windows runner.  A trial, not to
# merge.  Each row runs in its own Emacs under a limit, so a hang leaves the others.
# It changes the distribution and runs `wsl --shutdown`: never point it at a machine
# with work on it.

param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$Results = 'tramp-rpc-trial-results',
    [string]$Packages = 'var/elpa',
    [string]$TrampRpc = '.trial/tramp-rpc'
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$quick = [bool]$env:TRIAL_QUICK

# A script block, because a function's own parameters would take -d as -Debug.
function Invoke-Checked {
    param([scriptblock]$Block)
    & $Block
    if ($LASTEXITCODE -ne 0) { throw "Exit $LASTEXITCODE from: $Block" }
}

& "$here/../wsl-backend/prove-wsl2.ps1" -Distribution $Distribution

New-Item -ItemType Directory -Force -Path $Results | Out-Null
$resultsFull = (Resolve-Path $Results).Path
$source = (Resolve-Path $TrampRpc).Path

Invoke-Checked { wsl.exe -d $Distribution -u root --cd $here --exec bash setup-distro.sh }
Invoke-Checked { wsl.exe --terminate $Distribution }
Invoke-Checked { wsl.exe -d $Distribution --cd $here --exec bash setup-fixtures.sh }

$linuxSource = (wsl.exe -d $Distribution --cd $source --exec pwd).Trim()
Invoke-Checked { wsl.exe -d $Distribution --cd $here --exec bash build-server.sh $linuxSource | Tee-Object -FilePath (Join-Path $resultsFull 'build.log') }

$env:TRIAL_CLIENT_PACKAGES = (Join-Path (Get-Location).Path '.trial\client') -replace '\\', '/'
$env:TRIAL_TRAMP_RPC = (Join-Path $source 'lisp') -replace '\\', '/'
Invoke-Checked { emacs -Q --batch -l ((Join-Path $here 'install-client.el') -replace '\\', '/') }

$env:TRIAL_DISTRIBUTION = $Distribution
$env:TRIAL_SERVER = '/home/spike/bin/tramp-rpc-server'
$env:TRIAL_CAT = 'C:/Program Files/Git/usr/bin'
$env:KITTYMACS_TEST_PACKAGES = (Resolve-Path $Packages).Path -replace '\\', '/'
$env:KITTYMACS_TEST_PROFILE = 'full'
$trial = (Join-Path $here 'trial.el') -replace '\\', '/'

function Invoke-Row {
    param(
        [string]$Transport,
        [string]$Boot,
        [string]$Phases,
        [int]$Rounds,
        [int]$Minutes,
        [switch]$Graphical
    )
    $row = "$Transport-$Boot-$(if ($Graphical) { 'gui' } else { 'batch' })"
    "::group::$row"
    $env:TRIAL_TRANSPORT = $Transport
    $env:TRIAL_BOOT = $Boot
    $env:TRIAL_PHASES = $Phases
    $env:TRIAL_ROUNDS = "$Rounds"
    $env:TRIAL_ROW = $row
    $env:TRIAL_RESULT = (Join-Path $resultsFull "$row.eld") -replace '\\', '/'
    $log = Join-Path $resultsFull "$row.log"
    if ($Graphical) {
        $process = Start-Process -FilePath emacs -PassThru -ArgumentList '-Q', '-l', $trial
    } else {
        $process = Start-Process -FilePath emacs -NoNewWindow -PassThru `
            -ArgumentList '-Q', '--batch', '-l', $trial `
            -RedirectStandardError $log -RedirectStandardOutput "$log.out"
    }
    if ($process.WaitForExit($Minutes * 60 * 1000)) {
        "Emacs exited with $($process.ExitCode)"
    } else {
        "Emacs passed $Minutes minutes: stopping it"
        Add-Content -Path "$log.limit" -Value "passed $Minutes minutes"
        $process.Kill($true)
    }
    # What one row left behind must not carry over.
    Get-Process wsl, wslhost, cat -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    wsl.exe --terminate $Distribution
    if (Test-Path $log) { Get-Content $log -Tail 300 }
    "::endgroup::"
}

$all = 'connect files into magit eglot process shell risks trace hang shutdown badhost'
$look = 'connect files into magit eglot process shell'
$real = 'connect kittymacs files magit eglot process hang shutdown'

# A quick run has one round of every row, to find errors in this harness cheaply.
$timing = if ($quick) { 1 } else { 5 }
$looking = if ($quick) { 1 } else { 3 }

Invoke-Row -Transport rpc -Boot plain -Phases $all -Rounds $timing -Minutes 30
Invoke-Row -Transport wslm -Boot plain -Phases $all -Rounds $timing -Minutes 30
Invoke-Row -Transport rpc -Boot plain -Phases $look -Rounds $looking -Minutes 10 -Graphical
Invoke-Row -Transport wslm -Boot plain -Phases $look -Rounds $looking -Minutes 10 -Graphical
Invoke-Row -Transport rpc -Boot config -Phases $real -Rounds 1 -Minutes 12
Invoke-Row -Transport wslm -Boot config -Phases $real -Rounds 1 -Minutes 12
Invoke-Row -Transport rpc -Boot config -Phases $real -Rounds 1 -Minutes 12 -Graphical

$summary = Join-Path $resultsFull 'summary.md'
$env:TRIAL_SUMMARISE = $resultsFull -replace '\\', '/'
Start-Process -FilePath emacs -NoNewWindow -Wait `
    -ArgumentList '-Q', '--batch', '-l', $trial `
    -RedirectStandardOutput $summary -RedirectStandardError "$summary.err"
Get-Content "$summary.err"
Get-Content $summary
if ($env:GITHUB_STEP_SUMMARY) {
    Get-Content $summary | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}
exit 0
