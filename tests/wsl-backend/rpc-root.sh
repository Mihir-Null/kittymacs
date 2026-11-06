#!/bin/bash
# As root in the distribution: what the wsl-rpc job measures with, and a plain user,
# since an owner's backend does not log in as root.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends git clangd libc6-dev gcc procps curl ca-certificates strace

id backend >/dev/null 2>&1 || useradd --create-home --shell /bin/bash backend
grep -q default=backend /etc/wsl.conf || printf '\n[user]\ndefault=backend\n' >> /etc/wsl.conf
