#!/bin/bash
# As the backend's user: rpc-build-server.sh REPOSITORY REVISION builds the server the
# way the doctor tells a person to, so that line is what gets tested.
set -eu
exec 2>&1

repository=$1
revision=$2
rustup_version=1.28.2
toolchain=1.88.0

cd "$HOME"
curl -sSf -o rustup-init \
  "https://static.rust-lang.org/rustup/archive/$rustup_version/x86_64-unknown-linux-gnu/rustup-init"
chmod +x rustup-init
./rustup-init -y --no-modify-path --profile minimal --default-toolchain "$toolchain"
export PATH="$HOME/.cargo/bin:$PATH"

start=$(date +%s)
cargo install --locked --root ~/.local --git "$repository" --rev "$revision" tramp-rpc-server
echo "server built in $(($(date +%s) - start)) s with $(rustc --version), $(nproc) CPUs"
ls -l "$HOME/.local/bin/tramp-rpc-server"
