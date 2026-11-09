# What a command that `wsl.exe --exec /bin/sh' starts finds on NixOS-WSL, for the
# record: nixos.ps1 runs it before and after Emacs connects.  It fails nothing.

echo "argv0=$0 user=$(id -un) uid=$(id -u) home=${HOME:-unset} pwd=$PWD shell=${SHELL:-unset}"
echo "PATH=$PATH"
echo "__NIXOS_SET_ENVIRONMENT_DONE=${__NIXOS_SET_ENVIRONMENT_DONE:-unset}"
echo "variables: $(env | cut -d= -f1 | sort | tr '\n' ' ')"
echo "/bin/sh is $(readlink -f /bin/sh)"
ls -l /bin /usr/bin
grep PRETTY_NAME /etc/os-release
cat /etc/wsl.conf
for tool in uname getconf stty env date systemctl; do
  echo "$tool: $(command -v "$tool" || echo missing)"
done
echo "system: $(systemctl is-system-running 2>&1)"
systemctl --failed --no-legend --no-pager 2>&1
systemd-analyze 2>&1 | head -n 2
loginctl list-sessions --no-legend --no-pager 2>&1

# The login shell Tramp asks for its PATH: how long it takes, and what it prints.
start=$(date +%s%N)
own=$(/bin/sh -l -c 'echo "$PATH"' </dev/null 2>&1)
echo "sh -l took $(( ($(date +%s%N) - start) / 1000000 )) ms and printed: $own"

# Tramp hands its shell a PS1 of its own.  Which shells keep it?
for shell in /bin/sh /run/current-system/sw/bin/sh; do
  echo "$shell is $(readlink -f "$shell")"
  printf 'echo "PS1=[$PS1]"\n' | PS1='kept ' "$shell" -i 2>&1 | grep '^PS1='
done
