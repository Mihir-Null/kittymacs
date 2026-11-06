#!/bin/bash
# As the backend's user: a real repository with one edited file, a directory of
# 200 names, and a C project for clangd.  Run with HOME set to where they belong.
set -eu

cd "$HOME"
mkdir -p spike many cproj

git clone --quiet --depth 200 https://github.com/magit/magit.git repo
printf '\n# edited\n' >> repo/Makefile
git -C repo config user.name spike
git -C repo config user.email spike@example.org

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
git -C cproj -c user.name=spike -c user.email=spike@example.org commit --quiet -m start
