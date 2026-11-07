#!/bin/bash
# rpc-server-answers.sh SERVER VERSION: send SERVER one system.info request, and fail
# unless it answers with VERSION.  The server has no --version, so this asks through
# its own protocol: a 4-byte big-endian length, then MessagePack.
set -eu

server=$1
version=$2

# {"version": "2.0", "id": 1, "method": "system.info"}, 36 bytes.
# It stops at the end of its input, perhaps before it answers, so that stays open.
answer=$( { printf '\0\0\0\044\203\247version\2432.0\242id\001\246method\253system.info'; sleep 3; } |
  timeout 20 "$server" | tr -c '[:print:]' ' ')
echo "$answer"

case $answer in
  *"$version"*protocol_revision*) echo "It answers, as version $version." ;;
  *) echo "No answer with version $version." >&2; exit 1 ;;
esac
