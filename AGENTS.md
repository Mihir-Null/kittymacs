# Repository collaboration guidance

`ARCHITECTURE.md` is the single source of truth for the design and the decisions behind it. Record a material decision there, in the same change that makes it, as the current design rather than as history; history lives in Git. There is no ADR folder or ticket catalogue.

Everything generated is authored in `literate/*.org` and tangled with `tools/tangle.el`: `early-init.el`, `init.el` and `lisp/*.el` from the Emacs chapters, `flake.nix` and `nix/` from `literate/90-nix.org`. Generated files are tracked; never edit one by hand. Chapters follow `literate/conventions.org` (IDs, tags, links, a closing Check).

The `justfile` runs everything. Before committing, from the repository root:

```sh
just check          # tangle-check, doc-test, and the tests that need no packages
```

With an installed package directory (`just install` makes one in `var/elpa`, or set `KITTYMACS_TEST_PACKAGES`):

```sh
just compile        # byte-compile every module
just test-packages  # leader and Org-roam tests, and the startup verifier
```

With Nix (`nix develop` provides Emacs, just and the linters):

```sh
just nix-check      # deadnix, statix, nixfmt; flake check; both example hosts evaluate
```

`just frames-test` needs a graphical session and is run by hand. CI (`.github/workflows/ci.yml`) runs the other recipes; `literate/80-maintenance.org` explains each one.
