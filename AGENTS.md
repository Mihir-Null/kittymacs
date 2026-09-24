# Repository collaboration guidance

`ARCHITECTURE.md` is the single source of truth for the design and the decisions behind it. Record a material decision there, in the same change that makes it, as the current design rather than as history; history lives in Git. There is no ADR folder, ticket catalogue or documentation validator.

Runtime configuration is authored in `literate/*.org` and tangled with `tools/tangle.el`; generated Lisp is tracked. Before committing, run from the repository root:

```sh
emacs -Q --batch -l tools/tangle.el -- --check
emacs -Q --batch -l tests/kittymacs-tangle-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-treesit-tests.el -f ert-run-tests-batch-and-exit
KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-org-roam-tests.el -f ert-run-tests-batch-and-exit
KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/verify-config.el
```

The first four need no packages. The last three need an installed package directory (`var/elpa` of a configuration that has started once); CI runs them after a fresh install, together with a byte-compilation of `lisp/*.el`. `tests/kittymacs-frames-tests.el` needs a graphical session and is run by hand, as README.md describes.

The Nix layer (`flake.nix`, `nix/`) is checked with `nix flake check --no-build` and by evaluating the examples in `nix/example` and `nix/example-nix-on-droid` with the `kittymacs` input overridden to the checkout; `nix/README.org` lists the exact commands.
