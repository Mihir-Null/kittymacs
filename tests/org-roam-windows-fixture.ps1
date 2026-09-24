param(
  [Parameter(Mandatory=$true)][string]$FixtureRoot,
  [Parameter(Mandatory=$true)][string]$Emacs,
  [Parameter(Mandatory=$true)][string]$Python,
  [Parameter(Mandatory=$true)][string]$Packages
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $FixtureRoot) { throw 'Use a new empty fixture path; fixtures are retained.' }
$repo = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Path $FixtureRoot | Out-Null
$root = (Get-Item -LiteralPath $FixtureRoot).FullName
foreach ($dir in @('graph','graph/notes','graph/secrets','outside','db-cache')) {
  New-Item -ItemType Directory -Path (Join-Path $root $dir) -Force | Out-Null
}
Set-Content -LiteralPath (Join-Path $root 'graph/notes/one.org') -Value ":PROPERTIES:`n:ID: one`n:END:`n#+title: One`n" -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'graph/secrets/hidden.org') -Value ":PROPERTIES:`n:ID: hidden`n:END:`n#+title: Hidden`n" -Encoding utf8
Set-Content -LiteralPath (Join-Path $root 'outside/out.org') -Value ":PROPERTIES:`n:ID: outside`n:END:`n#+title: Outside`n" -Encoding utf8
foreach ($pair in @(
  @('alias ü space','graph'),
  @('graph/internal','graph/notes'),
  @('graph/loop','graph'),
  @('graph/escape','outside'),
  @('graph/hidden','graph/secrets'),
  @('cache-alias','graph'),
  @('retarget','graph')

)) {
  New-Item -ItemType Junction -Path (Join-Path $root $pair[0]) -Target (Join-Path $root $pair[1]) | Out-Null
}
& cmd.exe /c mklink /J (Join-Path $root 'graph/dangling') (Join-Path $root 'graph/missing-target') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Dangling fixture failed' }
& cmd.exe /c mklink /J (Join-Path $root 'cycle') (Join-Path $root 'cycle') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cycle fixture failed' }
$env:KITTYMACS_JUNCTION_FIXTURE = $root
$env:KITTYMACS_TEST_PYTHON = $Python
$env:KITTYMACS_TEST_PACKAGES = $Packages
& $Emacs -Q --batch -l (Join-Path $repo 'tests/kittymacs-org-roam-windows-tests.el') --eval '(ert-run-tests-batch-and-exit "^kittymacs-roam-windows-")'
exit $LASTEXITCODE
