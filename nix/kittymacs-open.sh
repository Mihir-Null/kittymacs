#!/bin/sh
# Generated from literate/36-remote.org; edit the Org source, then tangle.
# kittymacs-open [FILE-OR-FOLDER...]: open them in Windows Emacs, from a WSL shell.
# With none, the current folder.

client=${KITTYMACS_EMACSCLIENT:-emacsclient.exe}

fail() {
  printf 'kittymacs-open: %s\n' "$1" >&2
  exit 1
}

[ -n "${WSL_DISTRO_NAME:-}" ] ||
  fail "WSL_DISTRO_NAME is not set, and this runs in a WSL shell."
command -v "$client" >/dev/null 2>&1 ||
  fail "no $client here. Put the bin folder of Windows Emacs on the Windows PATH, or set KITTYMACS_EMACSCLIENT to the program, under /mnt/c."

# What Windows Emacs calls an absolute path: a drive's own name, or a Tramp name.
emacs_name() {
  case $1 in
    /mnt/[a-z] | /mnt/[a-z]/*)
      drive=${1#/mnt/}
      drive=${drive%%/*}
      rest=${1#/mnt/"$drive"}
      printf '%s:%s' "$drive" "${rest:-/}"
      ;;
    *)
      printf '/wslm:%s:%s' "$WSL_DISTRO_NAME" "$1"
      ;;
  esac
}

[ "$#" -gt 0 ] || set -- .
# Each argument leaves the front and its name joins the back, which keeps any spaces.
count=$#
while [ "$count" -gt 0 ]; do
  path=$(realpath -m -- "$1") || fail "cannot resolve $1."
  shift
  set -- "$@" "$(emacs_name "$path")"
  count=$((count - 1))
done

"$client" --quiet --no-wait --alternate-editor=runemacs.exe "$@" ||
  fail "neither a running Emacs nor runemacs.exe answered. Start Windows Emacs, and try again."
