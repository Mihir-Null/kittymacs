#!/bin/bash
# kill-at-change.sh TARGET OLD-SIZE COMM: kill -KILL COMM as soon as TARGET's size
# leaves OLD-SIZE.  Truncating is the first thing that moves it.
target=$1
old=$2
comm=$3

echo ready
end=$(($(date +%s) + 60))
while :; do
  size=$(stat -c %s "$target" 2>/dev/null)
  [ "$size" != "$old" ] && break
  [ "$(date +%s)" -ge "$end" ] && { echo "timed out at size $size"; exit 1; }
done
pkill -KILL -x "$comm"
echo "killed at size $size"
