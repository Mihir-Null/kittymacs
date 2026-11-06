# Native Windows Emacs against a real WSL2 distribution, through `:transport wsl'.
#
# The workflow runs this, and it also runs by hand with PowerShell 7 from the root
# of a checkout that has run `just install`:
#
#   wsl --install Ubuntu-24.04 --no-launch   # a distribution just for this
#   tests/wsl-backend/run.ps1
#
# It changes that distribution: it adds a user called backend and makes it the
# default.  Do not point it at one you work in.

param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$Results = 'wsl-backend-results',
    [string]$Packages = 'var/elpa',
    [int]$LimitMinutes = 15
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

& "$here/prove-wsl2.ps1" -Distribution $Distribution

# A script block, because a function's own parameters would take -d as -Debug.
function Invoke-Checked {
    param([scriptblock]$Block)
    & $Block
    if ($LASTEXITCODE -ne 0) { throw "Exit $LASTEXITCODE from: $Block" }
}

# A plain user, since an owner's backend does not log in as root.  The default user
# takes effect when the distribution next starts.  No double quotes in the scripts:
# wsl.exe would have to get them through a second parse.
Invoke-Checked { wsl.exe -d $Distribution -u root --exec sh -c 'id backend >/dev/null 2>&1 || useradd --create-home --shell /bin/bash backend; grep -q default=backend /etc/wsl.conf || printf ''\n[user]\ndefault=backend\n'' >> /etc/wsl.conf' }
Invoke-Checked { wsl.exe --terminate $Distribution }
Invoke-Checked { wsl.exe -d $Distribution --exec sh -c 'mkdir -p ~/project; echo hello > ~/project/file' }

New-Item -ItemType Directory -Force -Path $Results | Out-Null
$log = Join-Path $Results 'connect.log'
$report = Join-Path $Results 'report.md'
$env:KITTYMACS_WSL_DISTRIBUTION = $Distribution
$env:KITTYMACS_WSL_KERNEL = 'microsoft-standard-WSL2'
$env:KITTYMACS_TEST_PACKAGES = (Resolve-Path $Packages).Path -replace '\\', '/'
$connect = (Join-Path $here 'connect.el') -replace '\\', '/'

$process = Start-Process -FilePath emacs -NoNewWindow -PassThru `
    -ArgumentList '-Q', '--batch', '-l', $connect `
    -RedirectStandardError $log -RedirectStandardOutput $report
$finished = $process.WaitForExit($LimitMinutes * 60 * 1000)
if (-not $finished) { $process.Kill($true) }

Get-Content $log -Tail 200
Get-Content $report
if ($env:GITHUB_STEP_SUMMARY) { Get-Content $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY }

if (-not $finished) { throw "Emacs passed $LimitMinutes minutes" }
# The report's own line, because Start-Process does not reliably give an exit code.
if (-not (Get-Content $report | Select-String -Quiet '^PASS$')) { throw 'A check failed: see the table above' }
