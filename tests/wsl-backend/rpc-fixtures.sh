#!/bin/bash
# As the backend's user: a real repository with one edited file, a directory of 200
# names and a C project for clangd, as the trial had, and the two killers.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cd "$HOME"
mkdir -p project many cproj kill
echo hello > project/file

git clone --quiet --depth 200 https://github.com/magit/magit.git repo
printf '\n# edited\n' >> repo/Makefile
git -C repo config user.name backend
git -C repo config user.email backend@example.org

for i in $(seq 1 200); do : > "many/f$i"; done

cat > cproj/main.c <<'EOF'
#include <stdio.h>

static int add (int a, int b) { return a + b; }

int main (void)
{
  printf ("%d\n", add (40, 2));
  return 0;
}
EOF
printf -- '-std=c11\n' > cproj/compile_flags.txt
git -C cproj init --quiet
git -C cproj add .
git -C cproj -c user.name=backend -c user.email=backend@example.org commit --quiet -m start

# Copied, because /mnt/ is slow, and these race the server.
tr -d '\r' < "$here/rpc-kill-at-change.sh" > kill-at-change.sh
tr -d '\r' < "$here/rpc-kill-in-window.sh" > kill-in-window.sh
