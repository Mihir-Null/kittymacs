<h1 align="center">
  <a href="https://git.io/typing-svg">
    <img src="https://readme-typing-svg.demolab.com?font=Patrick+Hand&size=48&duration=2000&pause=1000&color=CB56FF&center=true&vCenter=true&random=true&width=435&lines=kittymacs;%3A3macs" alt=":3 kittymacs" />
  </a>
  
![Emacs](https://img.shields.io/badge/gnuemacs-%237F5AB6.svg?style=for-the-badge&logo=gnuemacs&logoColor=white)
![Org Mode](https://img.shields.io/badge/orgmode-%2377AA99.svg?style=for-the-badge&logo=org&logoColor=white)
![Last Commit](https://img.shields.io/github/last-commit/Mihir-Null/kittymacs?style=for-the-badge&logo=git&logoColor=white&color=teal)
![License](https://img.shields.io/github/license/Mihir-Null/kittymacs?style=for-the-badge&color=orange)
![CI/CD](https://img.shields.io/github/actions/workflow/status/Mihir-Null/kittymacs/ci.yml?style=for-the-badge&logo=githubactions&logoColor=white&label=CI%2FCD&color=green)

</h1>

A user-friendly, batteries-included, opinionated Emacs configuration built around [Meow](https://github.com/meow-edit/meow)'s editing paradigm of selection -> extend via visual hints -> act. 
It is (meant to be) for Meow what Doom and evil-collection are for Evil. It breaks meow's minimal extension rule to implement a real `SPC` leader instead of Meow's keypad, a labelled menu for every major mode under `SPC m`, integrations for the most popular packages, and everything discoverable through which-key and `C-h`. The original keypad still exists, but more as a compatibility option.
New editing surfaces are OS windows, so your window manager arranges them.

The whole configuration is written as a literate org-roam book (thank you Donald Knuth) in [`literate/`](literate/index.org): every chapter explains one part of the editor, shows the small piece of Lisp that configures it, and explains why.

## Install

Requires GNU Emacs 30.1 or later (developed on 31.1). Clone into your init directory, or point Emacs at the clone:

```sh
git clone https://github.com/Mihir-Null/kittymacs.git ~/.emacs.d
```

```sh
emacs --init-directory=/path/to/kittymacs
```

The first start installs the Emacs Lisp packages it needs into `var/elpa/`. The terminal ([ghostel](https://github.com/dakra/ghostel)) and its Consult extension are cloned from their repository rather than fetched from MELPA, so the first start also needs `git`; ghostel downloads its small native module the first time you open a terminal, not at startup. Emacs verifies GNU ELPA's signed index with `gpg`, so install [Gpg4win](https://gpg4win.org/) if on Windows (GnuPG is usually already present on Linux, and `brew install gnupg` provides it on macOS); the startup file points Emacs at it, because the `gpg` that Git for Windows ships cannot verify anything from Emacs. Without a native `gpg` the check is skipped. Language servers, `ripgrep`, Git, a spell checker (`hunspell`, on Windows most simply from MSYS2), `python3` (Treemacs colours directories by Git status with it) and fonts are yours to install; On windows these are easiest to configure and install via msys2 or wsl. On macOS, [the Nix flake](nix/README.org) installs Emacs and every one of them in one `darwin-rebuild`, and Homebrew works too. The configuration checks for dependencies and degrades quietly. Icons need [Symbols Nerd Font Mono](https://www.nerdfonts.com/); the editing font is Google Sans Code if present, otherwise the platform default.

## Dive in

- `SPC SPC` runs any command by name. `SPC` then a letter opens a group; wait for the popup or press `C-h`.
- `SPC h ?` opens the cheat sheet; `SPC h t` starts Meow's interactive tutorial; `SPC h k` explains any key.
- `SPC f f` opens a file, `SPC b b` switches buffers, `SPC s s` searches lines, `SPC v s` opens Magit.
- `SPC o e` opens a real terminal ([ghostel](https://github.com/dakra/ghostel)) and `SPC t d` the project tree ([Treemacs](https://github.com/Alexander-Miller/treemacs)).
- `SPC m` is the menu for the current mode: in Org it schedules and captures, in Dired it copies and renames, in Magit it stages and commits.
- `SPC C c` opens the reading guide when you want to change something.

## Directory Map

```
.emacs.d/
  early-init.el, init.el   the only files Emacs reads on its own, ~90 lines together
  literate/                the chapters; edit these
  lisp/                    generated modules (kittymacs-*.el), cheat sheet, themes, private.el
  tests/                   tangle tests, startup verifier, leader tests, frame tests
  tools/tangle.el          the builder
  flake.nix, nix/          Nix: a nix-darwin module, a home-manager module, a dev shell
  var/                     packages, caches, custom.el (ignored by Git)
```

Startup is a flat, ordered list of `require`s in `init.el`. Each module comes from one chapter. Packages are declared where they are used with `use-package … :ensure t`. Machine-specific settings go in `lisp/private.el` (`SPC C p` creates it from the example); it is loaded once, early, and ignored by Git.

## Make it your own

Edit a chapter, then rebuild and check:

```
M-x kittymacs-literate-tangle      (SPC C t)
M-x kittymacs-literate-check       (SPC C k)
```

or from a shell, without loading the configuration:

```sh
emacs -Q --batch -l tools/tangle.el -- --write
```

Restart Emacs and commit the chapter with its generated file. Startup never tangles, so a clone works without a build step. [ARCHITECTURE.md](ARCHITECTURE.md) records the design and the decisions behind it; [`literate/index.org`](literate/index.org) explains how to add a chapter, a key, or a mode menu.

## Verify

From the repository root, with an existing package directory:

```sh
emacs -Q --batch -l tools/tangle.el -- --check
emacs -Q --batch -l tests/tangle-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
EMACS_DOTS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
EMACS_DOTS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/verify-config.el
```

The verifier copies the configuration to a temporary directory, forbids package installation, starts it, and checks the leader, the localleader key, the dashboard buttons, the theme toggle and every `SPC` row of the cheat sheet against the live keymap. The platform tests bind `system-type` to each operating system in turn, so the macOS, Windows and Linux branches all run on any machine without packages. [GitHub Actions](.github/workflows/ci.yml) runs the same checks on every push: the tangle check, then a fresh clone that installs its packages and starts on Emacs 30.1 and 31.1 on Linux, plus informational Windows and macOS runs, and a Nix job that checks the flake and evaluates its nix-darwin example; a weekly run repeats the fresh install without the package cache to catch upstream breakage. `tests/frames-tests.el` covers frame policy and needs a graphical session: `M-x ert RET ^dots-frames- RET`.

## Windows notes

Windows Emacs resolves `~` to `AppData/Roaming` when `HOME` is unset, so a `.emacs.d` under your profile folder is not found by default. On the machine this was built on, `AppData/Roaming/.emacs.d` is a directory junction to the repository at `C:/Users/walnu/.config/emacs-dots/`; `--init-directory` is the alternative. PowerShell is the default shell; `SPC o m` opens an MSYS2 UCRT64 shell when MSYS2 is at `C:/msys64/` (set `kittymacs-msys2-root` in `private.el` otherwise). The terminal talks to Windows ConPTY directly, so no POSIX helper is needed. Do not recursively delete a junction or its target.

## macOS notes

Emacs from the Dock has no shell `PATH`, so the startup file puts the Nix profiles and Homebrew on `exec-path` when they exist, and the shells chapter then imports your login shell's environment (`~/.zprofile` included). Option is Meta and Command is Super, so `⌘C`, `⌘V`, `⌘S`, `⌘Z` and `⌘⇧Z` do what you expect; the right Option key still types accented characters. `⌘Q` closes the frame while others remain and quits Emacs from the last one, because frames are this configuration's windows. Deleting a file moves it to the Trash, through the `trash` command (`brew install trash`, or the Nix module) when present so Finder's Put Back works. The title bar follows the theme. `SPC f o` reveals the current file in Finder. Dired uses GNU `ls` as `gls` (`brew install coreutils`) when it is installed, for directories-first listings. `private.el` can change the modifier keys through `kittymacs-macos-modifiers`. The whole macOS policy is one section of [the platform chapter](literate/30-platform.org); deploying with nix-darwin is described in [nix/README.org](nix/README.org).

## Licence

GPL-3.0-or-later. Copyright (C) 2026 Mihir Talati. Portions are distilled from Lambda-Emacs and Colin McLear's configuration, both GPL-3.0-or-later, and each generated module says so in its header.

## Credits

Much of the policy is distilled from [Lambda-Emacs](https://codeberg.org/Lambda-Emacs/lambda-emacs) and [Colin McLear's configuration](https://codeberg.org/mclear-tools/dotemacs) (GPL-3.0-or-later); each chapter outlines what it took. The Meow grammar follows Meow's documented layout. The Sonokai theme is a tracked port in `lisp/themes/`. Everything else is the work of the packages' authors, declared in the chapters that use them.
