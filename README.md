<div align="center">

<a href="https://git.io/typing-svg"><img src="https://readme-typing-svg.demolab.com?font=Patrick+Hand&size=48&duration=2000&pause=1000&color=40E0D0&center=true&vCenter=true&random=true&width=435&lines=kittymacs;%3A3macs" alt=":3 kittymacs" /></a>

**A Meow-first Emacs configuration: selection first modal editing paired with a real `SPC` leader and a literate source you can read like a wiki.**

![Emacs](https://img.shields.io/badge/gnuemacs-%237F5AB6.svg?style=for-the-badge&logo=gnuemacs&logoColor=white)
![Org Mode](https://img.shields.io/badge/orgmode-%2377AA99.svg?style=for-the-badge&logo=org&logoColor=white)
![Last Commit](https://img.shields.io/github/last-commit/Mihir-Null/kittymacs?style=for-the-badge&logo=git&logoColor=white&color=teal)
![License](https://img.shields.io/github/license/Mihir-Null/kittymacs?style=for-the-badge&color=orange)
![CI](https://img.shields.io/github/actions/workflow/status/Mihir-Null/kittymacs/ci.yml?style=for-the-badge&logo=githubactions&logoColor=white&label=CI&color=green)

[Install](#install) • [Getting started](#getting-started) • [Configure](#configure) • [Troubleshooting](#troubleshooting) • [Reading guide](literate/index.org)

</div>

---

## Contents

- [Introduction](#introduction)
- [Features](#features)
- [Dependencies](#dependencies)
- [Install](#install)
  - [Linux](#linux) · [macOS](#macos) · [Windows](#windows) · [Android](#android) · [Nix](#nix)
  - [First start](#first-start)
- [Getting started](#getting-started)
- [Configure](#configure)
- [Update](#update)
- [Troubleshooting](#troubleshooting)
- [Develop](#develop)
- [Credits and licence](#credits-and-licence)

## Introduction

kittymacs is a user-friendly, batteries-included, opinionated Emacs configuration built around [Meow](https://github.com/meow-edit/meow)'s editing model: select something, then act on it. It aims to be for Meow what Doom and evil-collection are for Evil.

It rests on three ideas:

- **`SPC` is a real keymap.** Meow's keypad translates keys; kittymacs binds `SPC` to an ordinary Emacs keymap instead, so `C-h k`, which-key and every help command see exactly the keys you press. The keypad remains as an option.
- **Every mode has a menu.** `SPC m` opens the current major mode's own labelled menu: scheduling in Org, renaming in Dired, staging in Magit.
- **Frames, not windows.** New editing surfaces open as OS windows, so your desktop's window manager arranges them.

The whole configuration is a literate wiki (thank you, Donald Knuth). Every chapter in [`literate/`](literate/index.org) explains one part of the editor, shows the Lisp that configures it, and says why. Emacs loads the Lisp tangled from those chapters; you read and edit the chapters.

## Features

- **Editing:** Meow's selection grammar with numbered hints, Tree-sitter "things" (functions, classes, arguments) to select by, and Avy jumps.
- **Discoverability:** which-key on every prefix, an offline cheat sheet (`SPC h ?`), Meow's tutor (`SPC h t`), Helpful, and Casual menus for the built-in modes.
- **Completion:** Vertico, Orderless, Marginalia, Consult and Embark in the minibuffer; Corfu and Cape in the buffer; Yasnippet templates.
- **Files and projects:** Dired with directories first on every platform, a Treemacs sidebar, `project.el` projects in Tabspaces workspaces, ripgrep search.
- **Version control:** Magit with Meow-friendly Motion state and a `SPC m` menu, VC, diff-hl in the gutter.
- **A real terminal:** [ghostel](https://github.com/dakra/ghostel) (libghostty), with Meow inside it; Eshell and Tramp alongside.
- **Notes:** Org with an agenda, Org QL queries by tag and TODO state, and Org-roam graphs scoped per project.
- **Programming:** Eglot language servers (opt-in per mode), Flymake, structural editing, pinned Tree-sitter grammars that load only when they work.
- **Every platform:** Linux, macOS, Windows (PowerShell and MSYS2) and the Android port, each with its own tested policy.

## Dependencies

| Dependency | Needed for | Without it |
|---|---|---|
| **GNU Emacs 30.1+** (developed on 31.1) | everything | — |
| **Git** | installing packages, Magit | no Magit; package installs from Git fail |
| **GnuPG** (`gpg`) | verifying GNU ELPA's signed index | the signature check is skipped |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | project search (`SPC s d`, `SPC s D`), and faster `xref` searches | those two searches fail; `xref` uses `grep` |
| [fd](https://github.com/sharkdp/fd) | `M-x consult-fd` | use `SPC f f` or `SPC p f` instead |
| `hunspell` or `aspell`, plus a dictionary | spell checking | spell checking stays off |
| `python3` | Treemacs' directory collapsing and Git colours | Treemacs uses its simpler modes |
| [Symbols Nerd Font Mono](https://www.nerdfonts.com/) | icons | icons are hidden |
| Google Sans Code | the preferred editing font | the platform's default font |
| SQLite support in Emacs (built in on most builds) | Org-roam's index | Org-roam stays off |
| A C compiler | Tree-sitter grammars | classic major modes are used |
| Language servers (pyright, nil, clangd, …) | Eglot | no language server features |

Everything except Emacs is optional: kittymacs looks for each program at startup and quietly turns off what needs a missing one.

## Install

Clone the repository as your Emacs configuration. Emacs reads `~/.emacs.d` first and `~/.config/emacs` only when `~/.emacs.d` does not exist, so move an old `~/.emacs.d` aside first:

```sh
git clone https://github.com/Mihir-Null/kittymacs.git ~/.config/emacs
```

To try kittymacs without replacing your configuration, clone it anywhere and point Emacs at it:

```sh
git clone https://github.com/Mihir-Null/kittymacs.git ~/src/kittymacs
emacs --init-directory ~/src/kittymacs
```

Then follow your platform's section, and read [First start](#first-start).

### Linux

Install Emacs and the tools from your distribution. Check `emacs --version` first: some distributions still ship Emacs 29, which is too old.

```sh
# Debian / Ubuntu (Debian 13+, Ubuntu 25.04+ for Emacs 30)
sudo apt install emacs git gnupg ripgrep fd-find hunspell hunspell-en-us python3

# Fedora
sudo dnf install emacs git gnupg2 ripgrep fd-find hunspell hunspell-en-US python3

# Arch
sudo pacman -S emacs git gnupg ripgrep fd hunspell hunspell-en_us python ttf-nerd-fonts-symbols-mono
```

- Install Symbols Nerd Font Mono from [nerdfonts.com](https://www.nerdfonts.com/) if your distribution does not package it.
- Under WSLg, frames have no title bar of their own; Windows places and resizes them.

### macOS

With [Homebrew](https://brew.sh):

```sh
brew install --cask emacs
brew install git gnupg ripgrep fd hunspell python coreutils trash
brew install --cask font-symbols-only-nerd-font
```

- Homebrew's `hunspell` has no dictionary; put `en_US.aff` and `en_US.dic` in `~/Library/Spelling`.
- `coreutils` gives Dired GNU `ls` (as `gls`), so directories list first; `trash` makes deleted files restorable with Finder's Put Back.
- An Emacs started from the Dock has no shell `PATH`. kittymacs adds the Homebrew and Nix directories itself, then imports your login shell's environment (`~/.zprofile` included).
- Option is Meta and Command is Super: `⌘C`, `⌘V`, `⌘S`, `⌘Z` and `⌘⇧Z` work as in other apps, and the right Option key still types accented characters.
- `⌘Q` closes the current frame while others remain, and quits from the last one.

With Nix, the [nix-darwin module](#nix) installs Emacs and all of the above in one `darwin-rebuild switch`.

### Windows

```powershell
winget install GNU.Emacs GnuPG.Gpg4win Git.Git BurntSushi.ripgrep.MSVC sharkdp.fd
```

- **Use Gpg4win's `gpg`.** The `gpg` that Git for Windows ships cannot open a Windows keyring for Emacs, so every signature check would fail. kittymacs puts Gpg4win first on its path when it is installed.
- **Point Emacs at the clone.** With `HOME` unset, Emacs looks for `.emacs.d` in `AppData\Roaming`, not your profile folder. Either start Emacs with `--init-directory`, or make a junction:

  ```powershell
  New-Item -ItemType Junction -Path "$env:APPDATA\.emacs.d" -Target "$HOME\src\kittymacs"
  ```

  Never recursively delete a junction or its target: that deletes the clone.
- **Unix tools from [MSYS2](https://www.msys2.org/)** (optional): a spell checker and a C compiler for Tree-sitter grammars. kittymacs looks in `C:\msys64` (set `kittymacs-msys2-root` otherwise):

  ```sh
  pacman -S mingw-w64-ucrt-x86_64-hunspell mingw-w64-ucrt-x86_64-hunspell-en mingw-w64-ucrt-x86_64-gcc
  ```

- PowerShell is the default shell. `SPC o m` opens an MSYS2 UCRT64 shell in the terminal; the terminal talks to Windows' ConPTY directly, with no POSIX helper.

### Android

There are two ways, and they are alternatives rather than layers:

| | The Android port (`org.gnu.emacs`) | nix-on-droid |
|---|---|---|
| What runs | a native graphical Emacs | an ordinary Linux Emacs inside a PRoot |
| External programs | from [Termux](https://termux.dev), installed from builds with a matching `sharedUserId` | from Nix |
| Terminal | Eshell (the port cannot load ghostel's module) | ghostel |
| Display | native | needs [Termux:X11](https://github.com/termux/termux-x11) |

**The Android port** runs kittymacs unmodified:

- Install the port and Termux from a matching pair of builds, such as [these](https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/), so Emacs may run Termux's `git`, `ripgrep` and `hunspell`. Without the pairing, everything that needs them switches itself off.
- Frames-only mode is off: on Android a frame is an entry in the task switcher. Set `kittymacs-frames-only` to `t` in `private.el` on a tablet with a desktop mode.
- With a hardware keyboard, Alt is Meta and `C-SPC` reaches Emacs, so the leader works as everywhere else.
- On-screen keyboards edit the buffer directly, which only suits Insert state, so kittymacs follows Meow's state. Set `kittymacs-android-modal-text-conversion` to `nil` if your keyboard misbehaves.

**nix-on-droid** uses the Home Manager module; [`nix/example-nix-on-droid/flake.nix`](nix/example-nix-on-droid/flake.nix) is a complete device. The two cannot be combined: Nix programs exist only inside the PRoot.

### Nix

The flake installs everything *around* the configuration (Emacs, the tools and the icon font); the configuration itself stays a writable clone, because it installs its packages into `var/`.

```nix
{
  inputs.kittymacs.url = "github:Mihir-Null/kittymacs";
  inputs.kittymacs.inputs.nixpkgs.follows = "nixpkgs";
}
```

- **nix-darwin:** import `kittymacs.darwinModules.default` and set `programs.kittymacs.enable = true;`.
- **Home Manager** (any Linux, macOS, nix-on-droid): import `kittymacs.homeManagerModules.default` and set `programs.kittymacs.source` to where the clone should live. The first switch clones it, at the revision your `flake.lock` pins, and links it to `~/.config/emacs`; after that the checkout is yours.
- **Without a module:** `nix profile install github:Mihir-Null/kittymacs#default github:Mihir-Null/kittymacs#tools`.

[The Nix chapter](literate/90-nix.org) documents every option, the daemon, and both example hosts.

### First start

1. Start Emacs. The first start installs the Lisp packages kittymacs declares into `var/elpa/`; this takes a minute or two, and later starts take seconds.
2. Press `SPC h t` for Meow's ten-minute tutorial, and `SPC h ?` for the cheat sheet.
3. Optional, when you want them:
   - `SPC o e` opens a terminal; the first time, it offers to download ghostel's small native module.
   - `M-x kittymacs-treesit-install-all-grammars` builds the pinned Tree-sitter grammars (needs Git and a C compiler).
   - `SPC n s` indexes your Org-roam notes, once per graph.

Nothing is written outside the clone: packages, caches, history and `custom.el` all live in `var/`, which Git ignores.

## Getting started

| Keys | Does |
|---|---|
| `SPC SPC` | run any command by name |
| `SPC` then a letter | open a group; wait for the popup, or press `C-h` |
| `SPC h ?` / `SPC h t` / `SPC h k` | cheat sheet / Meow tutorial / explain a key |
| `SPC f f` / `SPC b b` | open a file / switch buffer |
| `SPC p p` | open a project in its own workspace |
| `SPC s s` / `SPC s d` | search lines / search the project with ripgrep |
| `SPC v s` | Magit |
| `SPC o e` / `SPC t d` | terminal / project tree |
| `SPC m` | the current mode's menu |
| `SPC n` | linked notes: find, insert, capture, backlinks |
| `SPC C c` | the reading guide to the configuration |

In Normal state, Meow selects first and acts second: `w` selects a word, `x` a line, `o` a block; `,` and `.` select inside or around a thing; `d` deletes, `c` changes, `y` copies the selection. `i` enters Insert state and `ESC` leaves it. The cheat sheet has the full grammar.

## Configure

**Machine settings go in `lisp/private.el`.** `SPC C p` creates it from [`lisp/private.example.el`](lisp/private.example.el) and opens it; Git ignores it. It is read early, so most chapters see your values:

```elisp
(setopt kittymacs-font-family "JetBrains Mono"
        kittymacs-theme 'doom-one
        kittymacs-org-directory (expand-file-name "~/notes/")
        kittymacs-eglot-auto-start-modes '(python-ts-mode))
```

| Option | Sets |
|---|---|
| `kittymacs-theme`, `kittymacs-light-theme` | the dark theme, and the one `SPC t t` toggles to |
| `kittymacs-font-family`, `kittymacs-font-size`, `kittymacs-nerd-font`, `kittymacs-icons` | fonts and icons |
| `kittymacs-org-directory`, `kittymacs-org-roam-directory`, `kittymacs-project-directory` | where notes and projects live |
| `kittymacs-eglot-auto-start-modes`, `kittymacs-language-packages` | language servers started automatically; extra language packages (`nix`, `racket`, `guile`) |
| `kittymacs-frames-only` | whether new surfaces become OS windows |
| `kittymacs-macos-modifiers`, `kittymacs-msys2-root`, `kittymacs-termux-root` | per-platform keys and paths |
| `kittymacs-keypad-key` | a key under `SPC` for Meow's original keypad |

- **Another package's option** that a chapter also sets must go in an `after-init-hook` function at the end of `private.el`, or the chapter will overwrite it; the example file shows how, and [the maintenance chapter](literate/80-maintenance.org) explains why.
- **`M-x customize`** saves to `var/etc/custom.el`, which loads after everything else and always wins.
- **To change the configuration itself**, edit its chapter in `literate/`, then `SPC C t` to regenerate the Lisp and restart. See [Develop](#develop).

## Update

```sh
cd ~/.config/emacs
git pull
```

Then, inside Emacs, `M-x package-upgrade-all` upgrades the installed packages; restart afterwards. With [just](https://github.com/casey/just), `just update-packages` does the same from a shell, `just update-grammars` rebuilds the Tree-sitter grammars at their pinned revisions, and `just update` also moves the Nix flake's lock.

## Troubleshooting

**Start with the basics.**

- `emacs --debug-init` shows a backtrace for an error during startup.
- Warnings and errors open in a window at the bottom of the current frame, not as a new OS window; `*Messages*` (`SPC h e`) has the full log.
- To rule out your own settings, move `lisp/private.el` and `var/etc/custom.el` aside and restart.

**Packages.**

- *Packages fail to install, or a signature check fails:* check that `gpg` works (`gpg --version`); on Windows it must be Gpg4win's. Then `M-x package-refresh-contents` and restart.
- *A package is broken after an update:* quit Emacs, delete `var/elpa/`, and start again; kittymacs reinstalls everything it declares.
- *ghostel came from Git rather than MELPA* (left over from an older install): delete its directory in `var/elpa/` (and `consult-ghostel`'s) and restart.

**Features that quietly switch off.** kittymacs turns a feature off when its program is missing, rather than failing. If something does nothing:

- *No terminal:* `SPC o e` explains what is missing; `M-x ghostel-download-module` fetches the native module. The Android port opens Eshell instead.
- *No icons, or boxes instead of icons:* install Symbols Nerd Font Mono and restart; set `kittymacs-icons` to `t` for a terminal Emacs that already uses a Nerd Font.
- *No spell checking:* install `hunspell` or `aspell` with a dictionary; on Windows, MSYS2's `hunspell` in `C:\msys64`.
- *No Tree-sitter highlighting:* run `M-x kittymacs-treesit-install-all-grammars` (needs Git and a C compiler); a mode switches to Tree-sitter only once its grammar loads.
- *No language server:* `SPC l e` starts Eglot in the current buffer; add the mode to `kittymacs-eglot-auto-start-modes` to start it automatically. The server itself is yours to install.
- *Org-roam does nothing:* your Emacs needs SQLite (`M-: (sqlite-available-p)`), and each graph needs one `SPC n s`.

**Platform problems.**

- *Windows: Emacs ignores the clone:* see the `HOME` and junction note under [Windows](#windows).
- *macOS: programs installed with Homebrew or Nix are not found:* start Emacs once from a terminal to compare; the shells chapter imports the environment of your *login* shell, so set `PATH` in `~/.zprofile`, not only `~/.zshrc`.
- *Android: a program from Termux is not found:* the port and Termux must come from a matching pair of builds; check `kittymacs-termux-root`.

**Check the installation itself.** From a shell in the clone, with [just](https://github.com/casey/just):

```sh
just check          # the generated files match their chapters; package-free tests pass
just test-packages  # starts the configuration in isolation and fails on any warning
```

The second runs the same startup verifier as CI: it checks that every module loads, every `SPC` key runs a command, and your `private.el` overrides survive. If it passes but your Emacs misbehaves, the cause is outside the configuration; if it fails, [open an issue](https://github.com/Mihir-Null/kittymacs/issues) with its output, your Emacs version and your operating system.

## Develop

Everything Emacs loads is generated from the chapters in [`literate/`](literate/index.org):

| Path | Holds |
|---|---|
| `literate/` | the chapters (`NN-name.org`), the reading guide and the conventions: **edit these** |
| `early-init.el`, `init.el`, `lisp/kittymacs-*.el` | generated Lisp; one module per chapter |
| `flake.nix`, `nix/` | generated from the Nix chapter |
| `lisp/keybindings.org`, `lisp/themes/` | the cheat sheet and the Sonokai theme port |
| `tools/tangle.el`, `justfile` | the builder and the recipes that run everything |
| `tests/` | the test suites and the startup verifier |

The loop:

1. Edit a chapter: the prose and its code block together.
2. `just tangle` (or `SPC C t`) regenerates the files; startup never tangles, so a clone needs no build step.
3. `just check` (or `SPC C k` for the tangle alone) before committing; commit the chapter with its generated files.

| Recipe | Needs | Checks |
|---|---|---|
| `just check` | Emacs | chapters match generated files; pages follow the conventions; builder, platform and Tree-sitter tests |
| `just install`, `just compile`, `just test-packages` | network, then installed packages | a fresh install byte-compiles, and the leader, Org-roam and startup-verifier tests pass |
| `just frames-test` | a display | the frame policy |
| `just nix-check` | Nix | the generated Nix lints, and the flake and both example hosts evaluate |

[The maintenance chapter](literate/80-maintenance.org) explains each recipe and the builder; [the conventions](literate/conventions.org) say how a chapter is written; [ARCHITECTURE.md](ARCHITECTURE.md) records the design and every decision behind it. `nix develop` gives a shell with Emacs, `just` and the Nix linters. [CI](.github/workflows/ci.yml) runs the recipes on every push, on Emacs 30.1 and 31.1, on Linux, macOS and Windows.

## Credits and licence

kittymacs is GPL-3.0-or-later. Copyright (C) 2026 Mihir Talati.

Much of the policy is distilled from [Lambda-Emacs](https://codeberg.org/Lambda-Emacs/lambda-emacs) and [Colin McLear's configuration](https://codeberg.org/mclear-tools/dotemacs), both GPL-3.0-or-later; each chapter outlines what it took, and each generated module says so in its header. The Meow grammar follows Meow's documented layout, and the Sonokai theme is a tracked port in `lisp/themes/`. Everything else is the work of the packages' authors, credited in the chapters that use them.
