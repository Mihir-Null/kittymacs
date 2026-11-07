#!/bin/bash
# kill-in-window.sh TARGET COMM [second-file]: hold every write(2) of the newest
# server for 300 ms, then kill -KILL it as soon as TARGET has been truncated, or with
# second-file, as soon as its directory holds another file.  That lands in the window
# between file.write's open and its bytes, which a plain race only sometimes hits.
target=$1
comm=$2
mode=${3:-truncated}
directory=$(dirname "$target")

pid=$(pgrep -nx "$comm") || { echo "no server"; exit 1; }
strace -f -qq -o /dev/null -e trace=write -e inject=write:delay_enter=300000 -p "$pid" &
tracer=$!
# Long enough for strace to attach, which is before any bytes need to move.
sleep 0.5
echo ready
end=$(($(date +%s) + 60))
while :; do
  size=$(stat -c %s "$target" 2>/dev/null)
  if [ "$mode" = second-file ]; then
    [ "$(ls -A "$directory" | wc -l)" -gt 1 ] && break
  else
    [ "$size" -lt 1048576 ] 2>/dev/null && break
  fi
  [ "$(date +%s)" -ge "$end" ] && { echo "timed out at size $size"; kill "$tracer"; exit 1; }
done
kill -KILL "$pid"
echo "killed at size $size"
wait "$tracer" 2>/dev/null
exit 0
