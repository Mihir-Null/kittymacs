# kittymacs: the loop. Read "The loop" in literate/80-maintenance.org once;
# then this file is the reference card.
#
# The Emacs recipes need only Emacs 30.1 or later and run on every platform
# (on Windows, `just` uses the sh that Git for Windows installs). The Nix
# recipes need Nix; `nix develop` gives a shell with Emacs, just and the
# Nix linters together.

default: check

# Batch Emacs with this checkout as its init directory, so early-init.el
# puts packages, caches and grammars under ./var, as a real startup does.
emacs := "emacs -Q --batch --eval '(setq user-emacs-directory (file-name-as-directory (expand-file-name \".\")))'"

# The tests that load the configuration need its installed packages: the
# var/elpa of a checkout that has started once (`just install` makes one).
packages := env_var_or_default("KITTYMACS_TEST_PACKAGES", justfile_directory() / "var" / "elpa")

# 1. Org -> code. Every literate/NN-name.org chapter writes the files its
#    :tangle headers name: early-init.el, init.el and lisp/*.el from the
#    Emacs chapters, flake.nix and nix/ from the Nix chapter. The builder
#    tangles into a temporary directory first, validates everything, and
#    only then copies what changed.
tangle:
    emacs -Q --batch -l tools/tangle.el -- --write

# 2. Prove the committed generated files match their chapters (CI runs this).
tangle-check:
    emacs -Q --batch -l tools/tangle.el -- --check

# Every page has an ID, a title and one kind tag from the vocabulary; every
# id:, file: and heading link resolves; the index lists every chapter; every
# chapter ends with a Check. See literate/conventions.org.
doc-test:
    emacs -Q --batch -l tests/kittymacs-doc-tests.el -f ert-run-tests-batch-and-exit

# The tests that need no packages: the builder; each operating system's
# platform branch (on any machine); the Tree-sitter grammar policy, offline.
test:
    emacs -Q --batch -l tests/kittymacs-tangle-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-treesit-tests.el -f ert-run-tests-batch-and-exit

# 3. Everything that needs only Emacs. Run before every commit.
check: tangle-check doc-test test

# Start the configuration once in batch, so it installs its packages into
# var/elpa. A fresh clone does the same on its first graphical start.
install:
    {{emacs}} --eval '(setq native-comp-jit-compilation nil package-native-compile nil)' \
      -l early-init.el --eval '(package-refresh-contents)' -l init.el \
      --eval '(require (quote org-roam))' \
      --eval '(princ (format "%d packages active\n" (length package-activated-list)))'

# Byte-compile every module, to catch errors a load would hit. The .elc
# files go to the temporary directory, so startup keeps loading the sources.
compile:
    {{emacs}} -l early-init.el -f package-activate-all -L lisp \
      --eval '(setq use-package-ensure-function (quote ignore))' \
      --eval '(setq byte-compile-dest-file-function (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") temporary-file-directory)))' \
      -f batch-byte-compile lisp/*.el

# The tests that load installed packages: the SPC and SPC m machinery, real
# Org-roam graphs in SQLite, and the startup verifier, which replays a real
# startup and fails on any warning.
test-packages:
    KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-org-roam-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/verify-config.el

# Frame policy needs a graphical session: this opens one, runs the frame
# tests and leaves the results on screen.
frames-test:
    emacs --init-directory=. -l tests/kittymacs-frames-tests.el --eval '(ert "^kittymacs-frames-")'

# Lint what the Nix chapter generates. deadnix fails on a binding nothing
# uses, statix on Nix anti-patterns, nixfmt on Nix that `nix fmt` would change.
lint:
    deadnix --fail $(git ls-files '*.nix')
    statix check .
    nixfmt --check $(git ls-files '*.nix')

# Evaluate the flake on every system it supports, then the two example hosts
# against this checkout. Nothing is built.
eval:
    nix flake check --no-build --all-systems
    nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/example#darwinConfigurations.example.config.environment.systemPackages \
      --apply 'ps: map (p: p.name) ps'
    nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/example-nix-on-droid#nixOnDroidConfigurations.default.config.home-manager.config.home.packages \
      --apply 'ps: map (p: p.name) ps'

# Everything that needs Nix.
nix-check: lint eval

# Everything CI runs on Linux, in order.
all: check nix-check install compile test-packages

# Move the flake's nixpkgs, and so the Emacs and tools the Nix modules
# install; then refresh the archives and upgrade every installed Emacs
# package; then rebuild every Tree-sitter grammar at its pinned revision.
# Commit flake.lock afterwards; var/ is not tracked.
update: update-flake update-packages update-grammars

update-flake:
    nix flake update

update-packages:
    {{emacs}} -l early-init.el \
      --eval '(progn (package-initialize) (package-refresh-contents) (package-upgrade-all nil))'

# The pins live in literate/74-languages.org; change one there, tangle, then
# run this. Needs git and a C compiler.
update-grammars:
    {{emacs}} -l early-init.el -L lisp -l kittymacs-platform -l kittymacs-treesit \
      --eval '(dolist (source kittymacs-treesit-language-source-alist) (kittymacs-treesit-install-language-grammar (car source)))'
