# Native Windows Emacs against a real NixOS-WSL distribution, through `:transport wsl'.
#
# The workflow runs this with the release it downloaded.  By hand, with PowerShell 7
# from the root of a checkout that has run `just install`, on a machine where
# NixOS-WSL is not installed under this name:
#
#   tests/wsl-backend/nixos.ps1 -Image path/to/nixos.wsl
#
# Each call to wsl.exe has a time limit and a line in summary.txt, so a stall shows
# where it is.  Emacs writes Tramp's buffers into the results as it goes.

param(
    [Parameter(Mandatory)][string]$Image,
    [string]$Distribution = 'NixOS',
    [string]$Results = 'wsl-nixos-results',
    [string]$Packages = 'var/elpa',
    [int]$LimitMinutes = 15
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
# Without this wsl.exe prints UTF-16, which a pattern below would never match.
$env:WSL_UTF8 = '1'

New-Item -ItemType Directory -Force -Path $Results | Out-Null
$Results = (Resolve-Path $Results).Path
$summary = Join-Path $Results 'summary.txt'
$empty = Join-Path $Results 'empty-input.txt'
[IO.File]::WriteAllText($empty, '')

# One wsl.exe call, killed past SECONDS.  Its output goes to NAME.txt, and a line
# with how long it took goes to summary.txt.
function Invoke-Wsl {
    param([string]$Name, [string]$Arguments, [int]$Seconds = 120, [string]$Stdin = $empty)
    $output = Join-Path $Results "$Name.txt"
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath wsl.exe -ArgumentList $Arguments -NoNewWindow -PassThru `
        -RedirectStandardInput $Stdin -RedirectStandardOutput $output `
        -RedirectStandardError (Join-Path $Results "$Name.stderr.txt")
    # Reading the handle now is what makes ExitCode available later.
    $null = $process.Handle
    $finished = $process.WaitForExit($Seconds * 1000)
    if (-not $finished) { $process.Kill($true) }
    $outcome = if ($finished) { "exit $($process.ExitCode)" } else { "KILLED after $Seconds s" }
    $line = '{0}: {1:N2} s, {2}' -f $Name, $clock.Elapsed.TotalSeconds, $outcome
    Add-Content -Path $summary -Value $line
    "== $line"
    Get-Content $output, (Join-Path $Results "$Name.stderr.txt")
}

# WSL itself, as Vampire/setup-wsl installs it on a runner that lacks it.
$status = wsl.exe --status 2>&1 | Out-String
$status
if ($LASTEXITCODE -ne 0 -or $status -match 'is not installed') {
    Start-Process wsl.exe '--install --no-distribution'
    $end = (Get-Date).AddMinutes(5)
    do { Start-Sleep -Seconds 10; wsl.exe --status | Out-Null }
    while ($LASTEXITCODE -ne 0 -and (Get-Date) -lt $end)
}
wsl.exe --version
wsl.exe --set-default-version 2

# The release's own instructions: --install --from-file where WSL has it.
if ((wsl.exe --help | Out-String) -match '--from-file') {
    wsl.exe --install --from-file $Image --no-launch --name $Distribution
} else {
    $location = Join-Path $env:RUNNER_TEMP $Distribution
    wsl.exe --import $Distribution $location $Image --version 2
}
if ($LASTEXITCODE -ne 0) { throw "Installing $Image failed with $LASTEXITCODE" }

# A first start runs NixOS's activation, so it gets a long limit.
Invoke-Wsl 'first-start' "-d $Distribution --exec /bin/sh -c `"echo started`"" 300
& "$here/prove-wsl2.ps1" -Distribution $Distribution
Invoke-Wsl 'facts' "-d $Distribution --cd `"$here`" --exec /bin/sh nixos-facts.sh"

# Stopped, as after Windows starts, so that Tramp's call is the one that boots it.
wsl.exe --terminate $Distribution
Invoke-Wsl 'start-stopped' "-d $Distribution --exec /bin/sh -c `"echo started`"" 300
wsl.exe --terminate $Distribution

$log = Join-Path $Results 'emacs.log'
$report = Join-Path $Results 'report.md'
$env:KITTYMACS_WSL_DISTRIBUTION = $Distribution
$env:KITTYMACS_WSL_RESULTS = $Results -replace '\\', '/'
$env:KITTYMACS_TEST_PACKAGES = (Resolve-Path $Packages).Path -replace '\\', '/'
$script = (Join-Path $here 'nixos.el') -replace '\\', '/'

$clock = [Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath emacs -NoNewWindow -PassThru `
    -ArgumentList '-Q', '--batch', '-l', $script `
    -RedirectStandardError $log -RedirectStandardOutput $report
$finished = $process.WaitForExit($LimitMinutes * 60 * 1000)
if (-not $finished) { $process.Kill($true) }
Add-Content -Path $summary -Value ('emacs: {0:N2} s, {1}' -f $clock.Elapsed.TotalSeconds, $(if ($finished) { 'finished' } else { 'KILLED' }))

Invoke-Wsl 'facts-after' "-d $Distribution --cd `"$here`" --exec /bin/sh nixos-facts.sh"
Invoke-Wsl 'journal' "-d $Distribution -u root --exec /bin/sh -c `"journalctl -b --no-pager -o short-monotonic | tail -n 400`""

Get-Content $summary
Get-Content $log -Tail 200
Get-Content $report
if ($env:GITHUB_STEP_SUMMARY) {
    Get-Content $report | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    '```' | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    Get-Content $summary | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    '```' | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}

if (-not $finished) { throw "Emacs passed $LimitMinutes minutes" }
if (-not (Get-Content $report | Select-String -Quiet '^PASS$')) { throw 'A check failed: see the table above' }
