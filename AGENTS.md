# Repository collaboration guidance

`ARCHITECTURE.md` is the single source of truth for design, decisions and refactor status. Record a material decision there, in the same change that makes it. There is no ADR folder, ticket catalogue or documentation validator.

Runtime configuration is authored in `literate/*.org` and tangled with `tools/tangle.el`; generated Lisp is tracked. Before committing, run from the repository root:

```sh
emacs -Q --batch -l tools/tangle.el -- --check
emacs -Q --batch -l tests/tangle-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
EMACS_DOTS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/verify-config.el
```

The Nix layer (`flake.nix`, `nix/`) is checked with `nix flake check --no-build` and by evaluating `nix/example` with `--override-input kittymacs path:$PWD`; see `nix/README.org`.
