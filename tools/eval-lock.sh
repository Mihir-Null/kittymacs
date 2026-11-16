#!/usr/bin/env bash
# tools/eval-lock.sh COMMAND...: run COMMAND under the machine's one heavy-eval
# lock, ~/.cache/emptynet-eval.lock, so two evaluations or builds never run at
# once, whichever repository starts them. The justfile's heavy Nix commands
# run through it, so no caller has to remember.
#
# Copied, logic unchanged, from tools/eval-lock.sh in the owner's NixOS
# configuration repository, which takes the same lock; a later version will
# keep one copy for every repository instead of one each.
#
# - flock(1) from util-linux, the dev shell's `flock` on the Mac. It waits for
#   the lock, however long another run holds it.
# - Nesting is safe: when an ancestor already holds the lock, as in
#   `flock ~/.cache/emptynet-eval.lock just eval` or `just nix-check` calling
#   eval, its descriptor is inherited here. Taking the lock on that descriptor
#   succeeds at once, so the command runs instead of waiting on itself.
# - No flock on PATH (a Mac outside `nix develop`): it says so and runs the
#   command unlocked.
set -euo pipefail

lock="$HOME/.cache/emptynet-eval.lock"

if ! command -v flock >/dev/null 2>&1; then
  echo "eval-lock: no flock on PATH; running unlocked" >&2
  exec "$@"
fi

mkdir -p "${lock%/*}"
touch "$lock"
real=$(readlink -f "$lock")

# An inherited descriptor on the lock file: an ancestor's flock holds it.
for fd in "/proc/$$/fd"/*; do
  [ "$(readlink "$fd" 2>/dev/null)" = "$real" ] || continue
  if flock -n "${fd##*/}"; then exec "$@"; fi
done

exec flock "$lock" "$@"
