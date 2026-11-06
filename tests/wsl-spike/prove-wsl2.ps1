# Fail unless DISTRIBUTION runs on real WSL2, because WSL1 results do not count.
# Two independent witnesses: Windows's own list says version 2, and the kernel
# inside names itself as built for WSL2.  WSL1 has no Linux kernel: it answers
# uname with a 4.4 release ending in "Microsoft".

param([Parameter(Mandatory)][string]$Distribution)

$ErrorActionPreference = 'Stop'
# Without this wsl.exe prints UTF-16, which a pattern below would never match.
$env:WSL_UTF8 = '1'

wsl.exe --version
wsl.exe --status
$list = wsl.exe --list --verbose
$list

$row = $list | Where-Object { $_ -match "\b$([regex]::Escape($Distribution))\b" }
if (-not $row) { throw "$Distribution is not in wsl.exe --list --verbose" }
if ($row -notmatch '\s2\s*$') { throw "$Distribution is not version 2: $row" }

$kernel = wsl.exe -d $Distribution -- uname -r
"uname -r: $kernel"
if ($kernel -notmatch 'microsoft-standard-WSL2') {
    throw "Not a WSL2 kernel: $kernel"
}
wsl.exe -d $Distribution -- sh -c 'cat /proc/version; nproc; free -m; df -h /'
if ($LASTEXITCODE -ne 0) { throw "A kernel probe failed with $LASTEXITCODE" }
"Real WSL2: $Distribution"
