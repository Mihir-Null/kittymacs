# kittymacs: the loop. Read "The loop" in literate/80-maintenance.org once;
# then this file is the reference card.
#
# The Emacs recipes need only Emacs 31.1 or later and run on every platform
# (on Windows, `just` uses the sh that Git for Windows installs). The Nix
# recipes need Nix; `nix develop` gives a shell with Emacs, just and the
# Nix linters together.

default: check

# Batch Emacs with this checkout as its init directory, so early-init.el
# puts packages, caches and grammars under ./var, as a real startup does.
# The stable nixpkgs `eval` also checks the flake against: a host whose
# flake has kittymacs follow its own nixpkgs evaluates
# kittymacs on that release, which may lack attributes unstable has. Move it
# to each new release.
stable := "nixos-26.05"

# The same release of the two inputs a host pairs with it, and Emacs from
# unstable, because that release has no Emacs 31. See "The evaluation matrix".
stable_flags := "--override-input nixpkgs github:NixOS/nixpkgs/" + stable + " --override-input home-manager github:nix-community/home-manager/release-26.05 --override-input nix-darwin github:nix-darwin/nix-darwin/nix-darwin-26.05 --override-input kittymacs/nixpkgs github:NixOS/nixpkgs/nixpkgs-unstable"

emacs := "emacs -Q --batch --eval '(setq user-emacs-directory (file-name-as-directory (expand-file-name \".\")))'"

# The tests that load the configuration need its installed packages: the
# var/elpa of a checkout that has started once (`just install` makes one).
packages := env_var_or_default("KITTYMACS_TEST_PACKAGES", justfile_directory() / "var" / "elpa")

# KITTYMACS_TEST_PROFILE chooses what `just install` installs: minimal, full, or
# every, which adds each optional feature. Unset, this machine's settings decide,
# and a fresh clone with none gets the default, minimal.

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
# chapter ends with a Check; prose names only keys and packages that exist, and
# code follows the rules the chapters state. See literate/conventions.org.
doc-test:
    emacs -Q --batch -l tests/kittymacs-doc-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-lint-tests.el -f ert-run-tests-batch-and-exit

# The tests that need no packages: the builder; the startup guards and the
# Nix package list; each operating system's platform branch (on any
# machine); the Tree-sitter grammar policy, offline; Org table wrapping; the
# onboarding screens, with scripted keys and through a real pty.
test:
    emacs -Q --batch -l tests/kittymacs-tangle-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-startup-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-msys2-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-remote-rpc-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-smooth-scroll-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-exwm-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-open-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-hover-docs-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-treesit-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-which-key-frame-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-org-table-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-buffer-tabs-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-bench-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-catalogue-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-features-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-quickstart-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-meow-state-cursor-tests.el -f ert-run-tests-batch-and-exit
    emacs -Q --batch -l tests/kittymacs-onboard-tests.el -f ert-run-tests-batch-and-exit

# 3. Everything that needs only Emacs. Run before every commit.
check: tangle-check doc-test test

# Start the configuration once in batch, so it installs its packages into
# var/elpa. A fresh clone does the same on its first graphical start.
install:
    {{emacs}} --eval '(setq native-comp-jit-compilation nil package-native-compile nil)' \
      -l tests/kittymacs-test-selection.el \
      -l early-init.el --eval '(package-refresh-contents)' -l init.el \
      --eval '(when (kittymacs-feature-p (quote linked-notes)) (require (quote org-roam)))' \
      -f kittymacs-quickstart--settle \
      --eval '(princ (format "%d packages active\n" (length package-activated-list)))'

# Byte-compile every module, to catch errors a load would hit. The .elc
# files go to the temporary directory, so startup keeps loading the sources.
# Under the full profile, whatever this machine chose, so that what compiling
# loads is the same everywhere. Needs `KITTYMACS_TEST_PROFILE=full just install`.
compile:
    {{emacs}} -l early-init.el -f package-activate-all -L lisp \
      --eval '(setq kittymacs-profile (quote full))' \
      --eval '(setq use-package-ensure-function (quote ignore))' \
      --eval '(setq byte-compile-dest-file-function (lambda (file) (expand-file-name (concat (file-name-nondirectory file) "c") temporary-file-directory)))' \
      -f batch-byte-compile lisp/*.el

# The tests that load installed packages: the SPC and SPC m machinery, real
# Org-roam graphs in SQLite, the look without doom, a remote machine through a
# Tramp method that needs no ssh, and the startup verifier,
# which replays a real startup and fails on any warning. All under the full
# profile: `KITTYMACS_TEST_PROFILE=full just install` makes its directory.
test-packages:
    KITTYMACS_TEST_PROFILE=full KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=full KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-org-roam-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=full KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-theme-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=full KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-remote-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=full KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/verify-config.el

# What runs against a package directory holding the minimal profile and nothing
# else: `KITTYMACS_TEST_PROFILE=minimal just install` makes one. The verifier
# then also checks that the directory holds exactly what that profile needs.
test-minimal:
    KITTYMACS_TEST_PROFILE=minimal KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=minimal KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-theme-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=minimal KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-remote-tests.el -f ert-run-tests-batch-and-exit
    KITTYMACS_TEST_PROFILE=minimal KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/verify-config.el

# Start once per feature, off in turn from full and on in turn from minimal. Needs
# every feature's packages: `KITTYMACS_TEST_PROFILE=every just install`.
test-features:
    KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-feature-probes.el

# The startup verifier again, this time starting from a quickstart file it
# writes first. It fails if the file was ignored. KITTYMACS_TEST_PROFILE chooses
# the profile, as for test-minimal, and full if it is unset, as for test-packages.
test-quickstart:
    KITTYMACS_TEST_PROFILE="${KITTYMACS_TEST_PROFILE:-full}" KITTYMACS_TEST_QUICKSTART=1 KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/verify-config.el

# A machine with nothing: starts in a temporary copy, from its first install on,
# and asserts what each one leaves for the next. Needs the network.
test-new-machine:
    emacs -Q --batch -l tests/kittymacs-new-machine.el

# Let this machine start from one file instead of scanning var/elpa, which a new
# machine does without asking. Not -Q: a Nix Emacs's site-start.el sets the
# package-directory-list a real start hashes. "The quickstart file" in
# literate/10-startup.org explains it.
quickstart:
    emacs --batch --eval '(setq user-emacs-directory (file-name-as-directory (expand-file-name ".")))' -l early-init.el -f kittymacs-quickstart-write

# Delete it, and keep it off; every start scans until `just quickstart` runs again.
quickstart-remove:
    {{emacs}} -l early-init.el -f kittymacs-quickstart-remove

# Write a private.el with the onboarding screens for several selections, then
# start the verifier on each. Needs what `KITTYMACS_TEST_PROFILE=every just install`
# installs, and one start per selection, one at a time.
test-onboard-start:
    KITTYMACS_TEST_PACKAGES={{quote(packages)}} emacs -Q --batch -l tests/kittymacs-onboard-start.el

# Choose what this checkout installs, on screens that write lisp/private.el.
# Where no terminal can draw them, it says what to set by hand and exits 3.
# See literate/22-onboarding.org.
onboard:
    @if [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]; then \
      emacs -nw -Q -l lisp/kittymacs-onboard.el -f kittymacs-onboard-main; \
    else \
      emacs -Q --batch -l lisp/kittymacs-onboard.el -f kittymacs-onboard-main; \
    fi

# Count what the code and prose cost. Needs no packages. Reports only.
# "Measuring" in literate/80-maintenance.org explains the numbers.
size:
    emacs -Q --batch -l tools/bench.el -- --size

# Start Emacs many times and report what startup costs, in a terminal and, with
# a DISPLAY, in a frame. Needs installed packages; takes minutes. Reports only.
bench:
    emacs -Q --batch -l tools/bench.el -- --startup

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

# Evaluate the flake on every system it supports, on its own nixpkgs and on
# the stable release a host may make it follow, then the two example hosts
# against this checkout. Nothing is built.
eval:
    nix flake check --no-build --all-systems
    nix flake check --no-build --all-systems --no-write-lock-file \
      --override-input nixpkgs github:NixOS/nixpkgs/{{stable}}
    {{just_executable()}} sources
    {{just_executable()}} sources --override-input nixpkgs github:NixOS/nixpkgs/{{stable}}
    nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/example#darwinConfigurations.example.config.environment.systemPackages \
      --apply 'ps: map (p: p.name) ps'
    nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/example-nix-on-droid#nixOnDroidConfigurations.default.config.home-manager.config.home.packages \
      --apply 'ps: map (p: p.name) ps'

# Fail if any derivation behind the Emacs package build, a dependency's
# included, clones a whole ELPA repository from Savannah; the matches print.
# Why: "The Emacs packages" in literate/90-nix.org. Nothing is built; FLAGS
# can point nixpkgs elsewhere.
sources *FLAGS:
    nix derivation show -r --no-write-lock-file {{FLAGS}} .#packages.x86_64-linux.with-packages > "${TMPDIR:-/tmp}/kittymacs-derivations.json"
    ! grep -o 'savannah[.]gnu[.]org/git/elpa[^"]*' "${TMPDIR:-/tmp}/kittymacs-derivations.json"

# Evaluate real Home Manager hosts against this checkout, then start Emacs once
# per host with what each generated, and fail if Elisp's answer is not what the
# options said. A feature the catalogue lacks, a reserved host file name and two
# coding agents at once must fail evaluation, naming the options. "The selection check" in
# literate/90-nix.org explains it.
nix-selection:
    nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/selection-check#hosts > "${TMPDIR:-/tmp}/kittymacs-selection.json"
    KITTYMACS_NIX_REPORT="${TMPDIR:-/tmp}/kittymacs-selection.json" emacs -Q --batch -l tests/kittymacs-nix-selection.el
    ! nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/selection-check#typo 2> "${TMPDIR:-/tmp}/kittymacs-typo.txt"
    grep -F 'programs.kittymacs.features.no-such-feature' "${TMPDIR:-/tmp}/kittymacs-typo.txt"
    ! nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/selection-check#twoAgents 2> "${TMPDIR:-/tmp}/kittymacs-two-agents.txt"
    grep -F 'only one of the agent set can be on' "${TMPDIR:-/tmp}/kittymacs-two-agents.txt"
    ! nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --json ./nix/selection-check#reserved 2> "${TMPDIR:-/tmp}/kittymacs-reserved.txt"
    grep -F 'programs.kittymacs.hostFiles."10-nix"' "${TMPDIR:-/tmp}/kittymacs-reserved.txt"
    ! nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" \
      --raw ./nix/selection-check#darwinReserved 2> "${TMPDIR:-/tmp}/kittymacs-reserved.txt"
    grep -F 'programs.kittymacs.hostFiles."10-nix"' "${TMPDIR:-/tmp}/kittymacs-reserved.txt"

# Every case of the matrix, on the lock and on stable, each in its own process.
# "The evaluation matrix" in literate/90-nix.org says what each proves. Nothing
# is built.
nix-matrix:
    {{just_executable()}} nix-matrix-on lock
    {{just_executable()}} nix-matrix-on stable {{stable_flags}}

# One channel of the matrix: NAME for the output, then FLAGS for its nixpkgs.
nix-matrix-on name *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{quote(justfile_directory())}}
    evaluate() {
      nix eval --no-write-lock-file --override-input kittymacs "path:$PWD" {{FLAGS}} "$@"
    }
    errors=$(mktemp)
    for case in $(evaluate --raw ./nix/eval-matrix#cases --apply 'c: toString (builtins.attrNames c)'); do
      evaluate --raw "./nix/eval-matrix#cases.$case" > /dev/null
      echo "ok {{name}} $case"
    done
    for case in $(evaluate --raw ./nix/eval-matrix#mustFail --apply 'c: toString (builtins.attrNames c)'); do
      if evaluate --raw "./nix/eval-matrix#mustFail.$case" > /dev/null 2> "$errors"; then
        echo "FAIL {{name}} mustFail.$case evaluated"
        exit 1
      fi
      says=$(evaluate --raw "./nix/eval-matrix#mustFailSays.$case")
      grep -F "$says" "$errors" > /dev/null
      echo "ok {{name}} mustFail.$case"
    done
    version=$(evaluate --raw ./nix/eval-matrix#defaultEmacsVersion)
    if [ "${version%%.*}" -ge 31 ]; then
      evaluate --raw ./nix/eval-matrix#defaultEmacs > /dev/null
      echo "ok {{name}} defaultEmacs passes on Emacs $version"
    else
      if evaluate --raw ./nix/eval-matrix#defaultEmacs > /dev/null 2> "$errors"; then
        echo "FAIL {{name}} defaultEmacs evaluated on Emacs $version"
        exit 1
      fi
      grep -F 'and programs.kittymacs.package is Emacs' "$errors" > /dev/null
      echo "ok {{name}} defaultEmacs refused on Emacs $version, naming the option"
    fi

# Every template as a user gets it, in an empty directory, on the lock and on
# stable. KITTYMACS is the flake to instantiate from, and it may be a branch.
nix-templates kittymacs=("path:" + justfile_directory()):
    {{just_executable()}} nix-templates-on lock {{quote(kittymacs)}}
    {{just_executable()}} nix-templates-on stable {{quote(kittymacs)}} {{stable_flags}}

# One channel of the templates: NAME for the output, KITTYMACS and FLAGS.
nix-templates-on name kittymacs *FLAGS:
    #!/usr/bin/env bash
    set -euo pipefail
    instantiate() {
      local directory
      directory=$(mktemp -d)
      (cd "$directory" && nix flake init --template {{quote(kittymacs)}}"#$1" > /dev/null)
      nix eval --raw --no-write-lock-file --override-input kittymacs {{quote(kittymacs)}} {{FLAGS}} \
        "$directory#$2" > /dev/null
      rm -rf "$directory"
      echo "ok {{name}} $1"
    }
    instantiate home-manager homeConfigurations.me.activationPackage.drvPath
    instantiate nix-darwin darwinConfigurations.mac.system.drvPath
    instantiate nixos nixosConfigurations.machine.config.system.build.toplevel.drvPath
    instantiate wsl-backend homeConfigurations.me.activationPackage.drvPath

# Build the backend's tools, and fail if a font or a GUI toolkit is in the closure.
# The matches print. It builds, so CI leaves it out.
nix-backend-closure:
    nix build --no-link .#backend
    ! nix path-info --recursive .#backend | grep -E -- '-(gtk|qt|libX11|fontconfig|emacs)[-+0-9]'

# Everything that needs Nix.
nix-check: lint eval nix-selection nix-matrix nix-templates

# Everything CI runs on Linux, in order, under the profile its last two recipes need.
all: check nix-check
    KITTYMACS_TEST_PROFILE=full {{just_executable()}} install
    {{just_executable()}} compile
    {{just_executable()}} test-packages

# Move the flake's nixpkgs, and so the Emacs and tools the Nix modules
# install; then refresh the archives and upgrade every installed Emacs
# package; then rebuild the usual Tree-sitter grammars at their pinned commits.
# Commit flake.lock afterwards; var/ is not tracked.
update: update-flake update-packages update-grammars

update-flake:
    nix flake update

update-packages:
    {{emacs}} -l early-init.el \
      --eval '(progn (package-initialize) (package-refresh-contents) (package-upgrade-all nil))'

# Rebuild every grammar in kittymacs-treesit-languages, at the commit Emacs's
# own mode pins, or kittymacs pins in literate/74-languages.org for a mode
# from a package. Run it after an Emacs upgrade. Needs git and a C compiler.
update-grammars:
    {{emacs}} -l early-init.el -L lisp -l kittymacs-platform -l kittymacs-treesit \
      --eval '(princ (format "built %S\n" (kittymacs-treesit-install-grammars kittymacs-treesit-languages t)))'
