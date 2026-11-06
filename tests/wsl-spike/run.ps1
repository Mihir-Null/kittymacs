# Measure wsl.exe against ssh from native Windows Emacs to a WSL2 distribution.
#
# The workflow runs this, and it also runs by hand with PowerShell 7 from the root
# of a checkout that has run `just install`:
#
#   wsl --install Ubuntu-24.04 --no-launch   # a distribution just for this
#   tests/wsl-spike/run.ps1
#
# It changes that distribution: it installs packages, adds a user called spike and
# makes it the default.  It also runs `wsl --shutdown`, which stops every
# distribution on the machine.  Do not point it at one you work in.
#
# The results land in wsl-spike-results.  They hold no key: the throwaway key lives
# in a temporary directory that this script removes.

param(
    [string]$Distribution = 'Ubuntu-24.04',
    [string[]]$Transports = @('wsl', 'sshx', 'ssh'),
    [string]$Results = 'wsl-spike-results',
    [string]$Packages = 'var/elpa',
    [int]$LimitMinutes = 30
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# Windows's own OpenSSH, which an owner has, rather than Git for Windows's.
$env:Path = "$env:SystemRoot\System32\OpenSSH;$env:Path"
(Get-Command ssh).Source
ssh -V 2>&1
(Get-Command emacs).Source

& "$here/prove-wsl2.ps1" -Distribution $Distribution

function Invoke-Checked {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Command)
    & $Command[0] @($Command | Select-Object -Skip 1)
    if ($LASTEXITCODE -ne 0) { throw "Exit $LASTEXITCODE from: $Command" }
}

Invoke-Checked wsl.exe -d $Distribution -u root --cd $here --exec bash setup-distro.sh
Invoke-Checked wsl.exe --terminate $Distribution
Invoke-Checked wsl.exe -d $Distribution --cd $here --exec bash setup-fixtures.sh

# The long form of the path: a short name such as RUNNER~1 would go through Tramp's quoting.
$secrets = Join-Path (Get-Item ([IO.Path]::GetTempPath())).FullName "wsl-spike-$PID"
New-Item -ItemType Directory -Path $secrets | Out-Null
try {
    $key = Join-Path $secrets 'key'
    ssh-keygen -q -t ed25519 -N '' -C wsl-spike -f $key
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen failed' }
    # OpenSSH refuses a key that anyone else can read.
    icacls $key /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null
    $public = Get-Content "$key.pub" -Raw
    Invoke-Checked wsl.exe -d $Distribution --exec sh -c 'umask 077; mkdir -p ~/.ssh; printf "%s\n" "$1" >> ~/.ssh/authorized_keys' sh $public.Trim()

    $config = Join-Path $secrets 'config'
    @"
Host wslspike
  HostName 127.0.0.1
  Port 2222
  User spike
  IdentityFile $($key -replace '\\', '/')
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile NUL
  BatchMode yes
  ConnectTimeout 15
"@ | Set-Content -Path $config -Encoding ascii

    New-Item -ItemType Directory -Force -Path $Results | Out-Null
    $resultsFull = (Resolve-Path $Results).Path
    $env:KITTYMACS_SPIKE_DISTRIBUTION = $Distribution
    $env:KITTYMACS_SPIKE_SSH_CONFIG = $config -replace '\\', '/'
    $env:KITTYMACS_TEST_PACKAGES = (Resolve-Path $Packages).Path -replace '\\', '/'
    $env:KITTYMACS_TEST_PROFILE = 'full'
    $spike = (Join-Path $here 'spike.el') -replace '\\', '/'

    foreach ($transport in $Transports) {
        "::group::$transport"
        $env:KITTYMACS_SPIKE_TRANSPORT = $transport
        $env:KITTYMACS_SPIKE_RESULT = (Join-Path $resultsFull "$transport.eld") -replace '\\', '/'
        $log = Join-Path $resultsFull "$transport.log"
        $process = Start-Process -FilePath emacs -NoNewWindow -PassThru `
            -ArgumentList '-Q', '--batch', '-l', $spike `
            -RedirectStandardError $log -RedirectStandardOutput "$log.out"
        if ($process.WaitForExit($LimitMinutes * 60 * 1000)) {
            "Emacs exited with $($process.ExitCode)"
        } else {
            "Emacs passed $LimitMinutes minutes: stopping it"
            $process.Kill($true)
        }
        Get-Content $log -Tail 400
        "::endgroup::"
    }

    $summary = Join-Path $resultsFull 'summary.md'
    $env:KITTYMACS_SPIKE_SUMMARISE = $resultsFull -replace '\\', '/'
    Start-Process -FilePath emacs -NoNewWindow -Wait `
        -ArgumentList '-Q', '--batch', '-l', $spike `
        -RedirectStandardOutput $summary -RedirectStandardError "$summary.err"
    Get-Content "$summary.err"
    Get-Content $summary
    if ($env:GITHUB_STEP_SUMMARY) {
        Get-Content $summary | Add-Content -Path $env:GITHUB_STEP_SUMMARY
    }
}
finally {
    Remove-Item -Recurse -Force $secrets
}
