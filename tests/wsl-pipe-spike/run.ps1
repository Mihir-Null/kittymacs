# Run pipe.el on a hosted Windows runner, each mode in its own capped Emacs, so a
# hang in one leaves the others' results.  A spike, not to merge.

param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string]$Results = 'wsl-pipe-results',
    [int]$LimitSeconds = 300
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

& "$here/../wsl-spike/prove-wsl2.ps1" -Distribution $Distribution

wsl.exe -d $Distribution -u root --exec sh -c 'command -v python3 >/dev/null || { apt-get update -qq && apt-get install -y -qq python3; }'
if ($LASTEXITCODE -ne 0) { throw 'No python3 in the distribution' }
wsl.exe -d $Distribution --cd $here --exec cp echo.py /tmp/echo.py
if ($LASTEXITCODE -ne 0) { throw 'Could not copy echo.py' }

New-Item -ItemType Directory -Force -Path $Results | Out-Null
$resultsPath = (Resolve-Path $Results).Path
$python = (Get-Command python).Source
"python: $python"
"emacs: $((Get-Command emacs).Source)"

$env:SPIKE_WSL = $Distribution
$env:SPIKE_PYTHON = $python
$env:SPIKE_ECHO = (Join-Path $here 'echo.py')

function Invoke-Mode {
    param([string]$Mode, [string[]]$EmacsArguments)
    $env:SPIKE_MODE = $Mode
    $env:SPIKE_OUT = Join-Path $resultsPath "$Mode.tsv"
    $start = Get-Date
    $process = Start-Process -FilePath (Get-Command emacs).Source -ArgumentList $EmacsArguments -PassThru
    $finished = $process.WaitForExit($LimitSeconds * 1000)
    $seconds = [int]((Get-Date) - $start).TotalSeconds
    if ($finished) {
        "=== $Mode ended by itself after $seconds s"
    } else {
        "=== $Mode HIT THE LIMIT of $LimitSeconds s"
        Add-Content -Path $env:SPIKE_OUT -Value "LIMIT`t$Mode`tstopped from outside after $seconds s"
        Stop-Process -Id $process.Id -Force
    }
    # What one mode left behind must not carry over.
    Get-Process wsl, wslhost, cat -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Test-Path $env:SPIKE_OUT) { Get-Content $env:SPIKE_OUT } else { "no results from $Mode" }
}

$pipe = Join-Path $here 'pipe.el'
# The main, duplex, stuck and gui modes ran once, in run 42267500824, and need no repeat.
Invoke-Mode 'sweep' @('--batch', '-Q', '-l', "`"$pipe`"")
$tune = Join-Path $here 'tramp-tune.el'
Invoke-Mode 'tune' @('--batch', '-Q', '-l', "`"$tune`"")
exit 0
