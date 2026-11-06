#!/bin/bash
# As root in the distribution: the programs the trial measures, and a plain user,
# since an owner's backend does not log in as root.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends git clangd libc6-dev gcc procps curl ca-certificates

id spike >/dev/null 2>&1 || useradd --create-home --shell /bin/bash spike

# The default user takes effect when the distribution next starts.
printf '\n[user]\ndefault=spike\n' >> /etc/wsl.conf
