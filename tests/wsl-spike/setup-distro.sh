#!/bin/bash
# As root in the distribution: the programs the spike measures, and a plain user,
# since an owner's backend does not log in as root.  sshd is started by spike.el,
# because a shutdown stops it.
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends openssh-server git clangd libc6-dev gcc procps

id spike >/dev/null 2>&1 || useradd --create-home --shell /bin/bash spike
ssh-keygen -A
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config.d/spike.conf <<'EOF'
PasswordAuthentication no
EOF

# The default user takes effect when the distribution next starts.
printf '\n[user]\ndefault=spike\n' >> /etc/wsl.conf
