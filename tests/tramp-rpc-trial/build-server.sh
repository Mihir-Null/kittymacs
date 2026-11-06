#!/bin/bash
# As the backend's user, inside the distribution: build tramp-rpc's server from the
# pinned source, the first argument, with the oldest Rust it says it supports.  The
# build is timed from here, after the toolchain is in place.
set -eu
exec 2>&1

source=$1
rustup_version=1.28.2
toolchain=1.88.0

mkdir -p "$HOME/bin" "$HOME/tramp-rpc-src"
cp -r "$source/Cargo.toml" "$source/Cargo.lock" "$source/server" "$HOME/tramp-rpc-src/"

cd "$HOME"
curl -sSf -o rustup-init \
  "https://static.rust-lang.org/rustup/archive/$rustup_version/x86_64-unknown-linux-gnu/rustup-init"
chmod +x rustup-init
./rustup-init -y --no-modify-path --profile minimal --default-toolchain "$toolchain"
export PATH="$HOME/.cargo/bin:$PATH"

cd "$HOME/tramp-rpc-src"
start=$(date +%s)
cargo build --release --locked -p tramp-rpc-server
end=$(date +%s)
install -m 755 target/release/tramp-rpc-server "$HOME/bin/tramp-rpc-server"

echo "server built in $((end - start)) s with $(rustc --version), $(nproc) CPUs"
ls -l "$HOME/bin/tramp-rpc-server"
