# A person's first start on native Windows, from a fresh clone, on the default
# profile, with a chosen gpg, in batch or in a frame.  Every error that reaches
# the debugger goes into the report with its backtrace (record.el).
#
#   tests/windows-first-start/run.ps1 -Gpg none -Ui gui
#
# -Gpg none     no gpg on PATH, as Git for Windows' default install leaves it
# -Gpg git      Git for Windows' own gpg on PATH, as its Unix tools option does
# -Gpg gpg4win  Gpg4win installed, and its gpg on PATH
#
# The checkout must not have started before: no var/ and no lisp/private.el.

param(
    [ValidateSet('none', 'git', 'gpg4win')][string]$Gpg = 'none',
    [ValidateSet('batch', 'gui')][string]$Ui = 'batch',
    [string]$Results = 'windows-first-start-results',
    [int]$LimitMinutes = 25
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = (Resolve-Path (Join-Path $here '../..')).Path
if (Test-Path (Join-Path $root 'var')) { throw "$root has started before: var/ exists" }
if (Test-Path (Join-Path $root 'lisp/private.el')) { throw "$root has a lisp/private.el" }

# PATH as this person has it.  Git for Windows' Unix tools come off in every case
# but git, and any other directory holding a gpg comes off unless it is Gpg4win's.
$gpg4win = @('C:\Program Files\GnuPG\bin', 'C:\Program Files (x86)\GnuPG\bin') |
    Where-Object { Test-Path (Join-Path $_ 'gpg.exe') } | Select-Object -First 1
$entries = $env:PATH -split ';' | Where-Object { $_ } | Where-Object {
    $unixTools = $_ -match '\\Git\\(usr\\bin|bin|mingw64\\bin)\\?$'
    $hasGpg = Test-Path (Join-Path $_ 'gpg.exe')
    -not ($unixTools -or ($hasGpg -and $_ -ne $gpg4win))
}
switch ($Gpg) {
    'git' { $entries = @('C:\Program Files\Git\usr\bin') + $entries }
    'gpg4win' {
        if (-not $gpg4win) { throw 'Gpg4win is not installed' }
        $entries = @($gpg4win) + $entries
    }
}
$env:PATH = ($entries | Select-Object -Unique) -join ';'

New-Item -ItemType Directory -Force -Path $Results | Out-Null
$report = (Join-Path (Resolve-Path $Results).Path "report-$Gpg-$Ui.txt")
$env:KITTYMACS_FIRST_START_REPORT = $report -replace '\\', '/'
"PATH: $env:PATH" | Set-Content -Path $report
"gpg found: $((Get-Command gpg -ErrorAction SilentlyContinue).Source)" | Add-Content -Path $report
"Gpg4win: $gpg4win" | Add-Content -Path $report

$record = (Join-Path $here 'record.el') -replace '\\', '/'
$init = ($root -replace '\\', '/') + '/'
$output = Join-Path $Results "output-$Gpg-$Ui.txt"
if ($Ui -eq 'batch') {
    $arguments = @('-Q', '--batch', '-l', $record,
                   '--eval', "(setq user-emacs-directory `"$init`")",
                   '-l', "${init}early-init.el", '-l', "${init}init.el",
                   '-f', 'first-start-finish-batch')
} else {
    # site-start.el loads after early-init.el and before init.el, as nothing in
    # the checkout does; the trailing separator keeps the default load-path.
    $site = Join-Path $env:RUNNER_TEMP 'first-start-site'
    New-Item -ItemType Directory -Force -Path $site | Out-Null
    "(load `"$record`" nil t)" | Set-Content -Path (Join-Path $site 'site-start.el')
    $env:EMACSLOADPATH = "$site;"
    $arguments = @("--init-directory=$init")
}
# Quoted, because Start-Process joins the arguments with spaces.
$quoted = $arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }
$process = Start-Process -FilePath emacs -NoNewWindow -PassThru -ArgumentList $quoted `
    -RedirectStandardError $output -RedirectStandardOutput "$output.out"
$finished = $process.WaitForExit($LimitMinutes * 60 * 1000)
if (-not $finished) { $process.Kill($true) }

Get-Content $output -Tail 100 -ErrorAction SilentlyContinue
Get-Content $report
if (-not $finished) { throw "Emacs passed $LimitMinutes minutes" }
