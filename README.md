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

A new installation starts small: Meow, Vertico, Orderless, Marginalia, Consult, Embark, Corfu, Cape, Magit, diff-hl, envrc and Vundo, on the built-in Modus theme and Emacs's own mode line. Everything else below is a feature you turn on, one at a time or together with the `full` profile: [First start](#first-start) says how, and [the catalogue](literate/20-catalogue.org) lists them all.

- **Editing:** Meow's selection grammar with numbered hints, Tree-sitter "things" (functions, classes, arguments) to select by, and Avy jumps.
- **Discoverability:** which-key on every prefix, an offline cheat sheet (`SPC h ?`), Meow's tutor (`SPC h t`), Helpful, and Casual menus for the built-in modes.
- **Completion:** Vertico, Orderless, Marginalia, Consult and Embark in the minibuffer; Corfu and Cape in the buffer; Yasnippet templates.
- **Files and projects:** Dired with directories first on every platform, a Treemacs sidebar, `project.el` projects in Tabspaces workspaces, ripgrep search.
- **Version control:** Magit with Meow-friendly Motion state and a `SPC m` menu, VC, diff-hl in the gutter; Forge and pr-review for pull requests, magit-todos, git-link and orgit, difftastic's diffs by syntax, and diff-review for reviewing a branch, a worktree's uncommitted changes or a fetched pull request (`SPC v u`) locally.
- **A real terminal:** [ghostel](https://github.com/dakra/ghostel) (libghostty), with Meow inside it; Eshell alongside.
- **Remote machines:** Tramp with named backends (`SPC o b`), and guards so that a dead connection cannot stall a start or an idle Emacs.
- **Notes:** Org with an agenda, Org QL queries by tag and TODO state, and Org-roam graphs scoped per project.
- **Reading papers:** pdf-tools renders PDFs inside Emacs; org-noter keeps a notes file beside each one, in step with the page; `pdf:` links point at a page or a highlight.
- **Notebooks:** Jupyter notebooks edited as [Jupytext](https://jupytext.readthedocs.io) scripts: `# %%` cells you run with `C-c C-c`, an optional Jupyter kernel, LaTeX in Markdown cells drawn in place, and each project's own environment through direnv.
- **A coding agent:** Claude Code in an Emacs buffer through [agent-shell](https://github.com/xenodium/agent-shell), under `SPC a`; every edit it proposes waits for your answer.
  With claude-code-ide as the agent, Claude's parallel Change sessions get a board: `SPC a d` lists them with their reviews, `SPC a j` jumps to one waiting for you, `SPC a C` starts one, and a verdict in diff-review wakes the session it concerns.
- **Suggestions as you type:** GitHub Copilot's grey ghost text and next-edit suggestions through [copilot.el](https://github.com/copilot-emacs/copilot.el), off until you turn them on (`SPC t a`, or `kittymacs-suggestions`).
- **Programming:** Eglot language servers (opt-in per mode), Flymake, structural editing, pinned Tree-sitter grammars that load only when they work.
- **Every platform:** Linux, macOS, Windows (PowerShell, with Linux on a WSL2 backend) and the Android port, each with its own tested policy.

## Dependencies

| Dependency | Needed for | Without it |
|---|---|---|
| **GNU Emacs 31.1+** | everything | — |
| **Git** | installing packages, Magit | no Magit; package installs from Git fail |
| **GnuPG** (`gpg`) | verifying GNU ELPA's signed index | the signature check is skipped |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | project search (`SPC s d`), and faster `xref` searches | that search fails; `xref` uses `grep` |
| [fd](https://github.com/sharkdp/fd) | `M-x consult-fd` | use `SPC f f` or `SPC p f` instead |
| `hunspell` or `aspell`, plus a dictionary | spell checking | spell checking stays off |
| `python3` | Treemacs' directory collapsing and Git colours | Treemacs uses its simpler modes |
| `epdfinfo` (pdf-tools' server; the Nix module installs it) | reading PDFs | PDFs open as images in DocView; `M-x pdf-tools-install` builds it |
| `direnv` (the Nix module installs it) | each project's own environment (`.envrc`) | every buffer has Emacs's global environment |
| `jupytext` (the Nix module installs it) | opening `.ipynb` files as scripts | `.ipynb` files fail to open; edit the paired `.py` |
| `math-preview` (the Nix module installs it) | drawing LaTeX (`SPC m n m`) | the command says how to install it with `npm` |
| emacs-zmq's native module (the Nix module provides it) | Jupyter kernels, once `kittymacs-notebooks-jupyter` is on | emacs-zmq downloads or builds one, asking first |
| `claude-agent-acp`, and a `claude` login | `SPC a`, the coding agent | the agent cannot start |
| `copilot-language-server` (the Nix modules' `programs.kittymacs.suggestions.enable`; unfree), a GitHub Copilot plan and `M-x copilot-login` | suggestions (`SPC t a`) | suggestions stay off and say what is missing; `M-x copilot-install-server` installs the server with `npm` |
| [Symbols Nerd Font Mono](https://www.nerdfonts.com/) | icons | icons are hidden |
| Google Sans Code | the preferred editing font | the platform's default font |
| Google Sans Flex | prose in Org | the platform's sans |
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

Install Emacs and the tools from your distribution. Check `emacs --version` first: many distributions still ship Emacs 30 or older, which is too old; there, use [Nix](#nix) or build Emacs 31 from source.

```sh
# Debian / Ubuntu (a release whose emacs package is 31)
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
- **Linux programs run on a WSL2 backend,** while Emacs stays on Windows. Install a distribution with `wsl --install Ubuntu-24.04`, name it as a backend with `:transport wsl` (see [Configure](#configure)), and press `SPC o b`. The `wsl-backend` [Nix template](#nix) sets up its tools, and `SPC o B` says what it has. `SPC o e` in one of its buffers opens a terminal in the distribution, on your login shell. In a WSL shell, `kittymacs-open .` opens that folder in Windows Emacs, as `code .` does in VS Code, and starts Emacs if it is not running. It comes with `packages.backend`.
- **A spell checker and a C compiler** are optional, and kittymacs looks for them on `PATH`. Without a compiler for Tree-sitter grammars, files open in their classic modes.
- **A fallback for Windows-side files.** A WSL2 backend is the normal way, and where file I/O across WSL would ruin performance, the optional `msys2-fallback` feature offers MSYS2's shell on `SPC o m`, plus its Hunspell and compiler, from `C:\msys64` or `kittymacs-msys2-root`. Each start warns while it is on, and with it off nothing looks for MSYS2. See [its chapter](literate/37-msys2.org). A file under `/mnt/` opened through a WSL backend says it is slow, once, and `SPC o w` reopens it natively.
- PowerShell is the default shell. The terminal talks to Windows' ConPTY directly, with no POSIX helper.

### Android

There are two ways, and they are alternatives rather than layers:

| | The Android port (`org.gnu.emacs`) | nix-on-droid |
|---|---|---|
| What runs | a native graphical Emacs | an ordinary Linux Emacs inside a PRoot |
| External programs | from [Termux](https://termux.dev), installed from builds with a matching `sharedUserId`; on a telephone with Android's Terminal app, also from its Linux virtual machine over Tramp | from Nix |
| Terminal | Eshell (the port cannot load ghostel's module) | ghostel |
| Display | native | needs [Termux:X11](https://github.com/termux/termux-x11) |

**The Android port** runs kittymacs unmodified:

- Install the port and Termux from a matching pair of builds, such as [these](https://sourceforge.net/projects/android-ports-for-gnu-emacs/files/termux/), so Emacs may run Termux's `git`, `ripgrep` and `hunspell`. Without the pairing, everything that needs them switches itself off.
- Frames-only mode is off: on Android a frame is an entry in the task switcher. Set `kittymacs-frames-only` to `t` in `private.el` on a tablet with a desktop mode.
- With a hardware keyboard, Alt is Meta and `C-SPC` reaches Emacs, so the leader works as everywhere else.
- On-screen keyboards edit the buffer directly, which only suits Insert state, so kittymacs follows Meow's state. Set `kittymacs-android-modal-text-conversion` to `nil` if your keyboard misbehaves.

**Android's Linux virtual machine as a backend.** Pixels and other telephones with Android's Terminal app run a Debian virtual machine. The port stays the screen, and the machine runs the programs: open a project there as `/ssh:vm:~/project/`, and Eglot, Magit, project search and Eshell use the machine's language servers, `git` and `rg`. kittymacs looks programs up on the remote login shell's `PATH`, so a Nix profile there is found.

- In the paired Termux: `pkg install openssh`. Tramp runs `ssh`; that is all Termux provides here.
- In the virtual machine: an SSH server on port 2222, allowed when the Terminal app offers to forward it; then Nix and `nix profile install github:Mihir-Null/kittymacs#tools`.
- In Eshell inside Emacs: `ssh-keygen`, and a `Host vm` entry in `~/.ssh/config` for `127.0.0.1` port 2222.

[The remote chapter](literate/36-remote.org) has every step and the reasons for each.

**nix-on-droid** uses the Home Manager module; [`nix/example-nix-on-droid/flake.nix`](nix/example-nix-on-droid/flake.nix) is a complete device. The two cannot be combined: Nix programs exist only inside the PRoot.

### Nix

The flake's modules install Emacs, the editing, prose and icon fonts, and the tools of the features a machine selects, pinned by the flake's lock; the configuration itself stays a writable clone, with its state in `var/`. The Lisp packages are the exception: by default the configuration installs them from the archives at first start, since no binary cache carries them. Set `programs.kittymacs.packagesFromNix = true` to have Nix build them into Emacs instead, pinned by the lock, at the cost of compiling them on the machine after each flake update.

```nix
{
  inputs.kittymacs.url = "github:Mihir-Null/kittymacs";
  inputs.kittymacs.inputs.nixpkgs.follows = "nixpkgs";
}
```

To start from a complete host, copy a template, then edit the names its first lines give:

```sh
nix flake init -t github:Mihir-Null/kittymacs#home-manager   # or nix-darwin, nixos, wsl-backend
```

- **nix-darwin, NixOS:** import `kittymacs.darwinModules.default` or `kittymacs.nixosModules.default` and set `programs.kittymacs.enable = true;`. Neither clones anything, so clone the configuration yourself.
- **Home Manager** (any Linux, macOS, nix-on-droid): import `kittymacs.homeManagerModules.default` and set `programs.kittymacs.source` to where the clone should live. The first switch clones it, at the revision your `flake.lock` pins, and links it to `~/.config/emacs`; after that the checkout is yours.
- **Without a module:** `nix profile install github:Mihir-Null/kittymacs#default github:Mihir-Null/kittymacs#tools`.
- **One profile, in one environment:** `#minimal` or `#full` is Emacs, that profile's Lisp packages built in, its tools and fonts. Nix compiles the packages on the machine.
- **A machine Emacs reaches from elsewhere:** `#backend`, or `programs.kittymacs.backend.enable = true;`, installs headless tools: Git, ripgrep, fd, direnv, inotify-tools on Linux and a few language servers, with no Emacs and no fonts.
- **In a host's own packages:** `kittymacs.overlays.default` adds `pkgs.kittymacs`, the same set built from your nixpkgs.

kittymacs needs Emacs 31. If your nixpkgs has an older one, evaluation stops and names the option: set `programs.kittymacs.package = kittymacs.packages.<system>.default;`, and remove the `follows` line from your inputs, so that input keeps its own nixpkgs.

**Trying it.** Each of these needs a checkout, and says what to clone if it finds none. It looks at `KITTYMACS_CHECKOUT`, this directory, `~/.config/emacs` and `~/.emacs.d`.

```sh
nix run github:Mihir-Null/kittymacs            # start Emacs on the checkout, with the tools on its PATH
nix run github:Mihir-Null/kittymacs#onboard    # choose features, on screens that write its private.el
nix run github:Mihir-Null/kittymacs#doctor     # report Emacs, the checkout, the host-layer files and the tools
```

**Choosing features.** With any of the modules, options choose [the catalogue](literate/20-catalogue.org)'s features, so you write no Elisp:

```nix
programs.kittymacs = {
  profile = "full";                  # or "minimal"
  features.lang-nix.enable = true;   # beyond the profile
  features.jump.enable = false;      # out of it
  settings.kittymacs-frames-only = false;
};
```

- The Home Manager module writes these to `~/.config/kittymacs/conf.d/10-nix.el`, and a system module to `/etc/kittymacs/conf.d/10-nix.el`. Either loads before `private.el`, so your own settings still win. With none of them set, it writes nothing, and the rules in [First start](#first-start) apply.
- A feature name the catalogue lacks fails at evaluation, naming the option.
- With `packagesFromNix`, Nix builds only what the chosen features need. A feature `private.el` adds still installs from the archives.
- `settings` sets other options by name, `hostFiles.<name>` adds a host file of your own, and `extraPackages` builds more Emacs packages in.

[The Nix chapter](literate/90-nix.org) documents every option and output, the daemon, the templates and both example hosts.

### First start

**To choose what it installs first,** run `just onboard` in the clone, with nothing installed yet. It needs only Emacs. The screens go through a profile, then each feature with its example, then a backend if you work on another machine, then a few settings and a preview of the change, and `C-g` at any point writes nothing.

- It writes a marked block in `lisp/private.el` and leaves the rest of that file as it is. It keeps the old file as `private.el~`, follows a symbolic link to the real file, and refuses with a message if the file does not read as Lisp or cannot be written.
- Without a terminal it can draw in, it prints the options to set by hand and exits with status 3.
- With Nix it starts from what `10-nix.el` chose, and prints the matching `programs.kittymacs` options. `private.el` loads after the host layer, so what the block says wins.
- `SPC C o` runs the same screens later. A start with nothing chosen says so in the echo area, and never starts anything by itself.

To start straight away instead:

1. Start Emacs. The first start installs the `minimal` profile into `var/elpa/`; this takes under a minute, and later starts take seconds. A line in the echo area names the profile and the key that changes it, and the theme is the built-in Modus.
2. Press `SPC h t` for Meow's ten-minute tutorial, and `SPC h C` for Meow's own cheat sheet.
3. For everything else, press `SPC C o`, or put `(setopt kittymacs-profile 'full)` in `lisp/private.el`. The next start installs what that needs, which takes a minute or two, and brings the Sonokai theme, doom-modeline and the home page.
4. Optional, when you want them:
   - With the `terminal` feature, `SPC o e` opens a terminal; the first time, it offers to download ghostel's small native module.
   - Opening a file whose Tree-sitter grammar is missing asks to build it; `M-x kittymacs-treesit-install-grammars` builds the usual ones in one go (both need Git and a C compiler).
   - With the `linked-notes` feature, `SPC n s` indexes your Org-roam notes, once per graph.

**A machine from before `minimal` became the default keeps what it has.** It stays on `full`, and each start warns and names `SPC C o`, until it chooses a profile. Setting `kittymacs-profile` to either value ends the warning.

Nothing is written outside the clone: packages, caches, history and `custom.el` all live in `var/`, which Git ignores.

## Getting started

Where a key needs a feature beyond `minimal`, the row names it.

| Keys | Does |
|---|---|
| `SPC SPC` | run any command by name |
| `SPC` then a letter | open a group; wait for the popup, or press `C-h` |
| `SPC h ?` / `SPC h t` / `SPC h k` | cheat sheet (`home-page`) / Meow tutorial / explain a key |
| `SPC f f` / `SPC b b` | open a file / switch buffer |
| `SPC p p` | open a project, in its own workspace with `workspaces` |
| `SPC s s` / `SPC s d` | search lines / search the project with ripgrep |
| `SPC v s` | Magit |
| `SPC o e` / `SPC t d` | terminal / project tree (`file-tree`) |
| `SPC m` | the current mode's menu |
| `SPC n` | linked notes (`linked-notes`): find, insert, capture, backlinks |
| `SPC a a` | Claude Code in this project (`agents`) |
| `SPC C c` | the reading guide to the configuration |
| `SPC C o` | choose features again; a change takes effect at the next start |

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
| `kittymacs-theme`, `kittymacs-light-theme` | the dark theme, and the one `SPC t t` toggles to; a `doom-` theme needs the `doom-look` feature, and Modus stands in without it |
| `kittymacs-font-family`, `kittymacs-font-size`, `kittymacs-prose-font-family`, `kittymacs-nerd-font`, `kittymacs-icons` | fonts and icons |
| `kittymacs-org-prose` | whether Org sets prose in the proportional font (`SPC t P` per buffer) |
| `kittymacs-org-directory`, `kittymacs-org-roam-directory`, `kittymacs-project-directory` | where notes and projects live |
| `kittymacs-profile`, `kittymacs-features`, `kittymacs-features-excluded` | where this machine starts (`minimal`, the default on a new machine, or `full`), and which features of [the catalogue](literate/20-catalogue.org) to add or leave out; the next start installs what they need |
| `kittymacs-structural-editing-modes` | the modes where Puni keeps brackets balanced |
| `kittymacs-eglot-auto-start-modes`, `kittymacs-language-packages` | language servers started automatically; extra language packages (`nix`, `racket`, `guile`) |
| `kittymacs-frames-only` | whether new surfaces become OS windows |
| `kittymacs-macos-modifiers`, `kittymacs-termux-root` | per-platform keys and paths |
| `kittymacs-keypad-key` | a key under `SPC` for Meow's original keypad |
| `kittymacs-backends`, `kittymacs-backend-tools` | the machines you work on, and what `SPC o B` looks for there |
| `kittymacs-remote-nix-path`, `kittymacs-remote-auto-capfs` | where Tramp searches after the login shell's `PATH`; which completion sources run unasked in a remote buffer |

- **Another package's option** that a chapter also sets must go in an `after-init-hook` function at the end of `private.el`, or the chapter will overwrite it; the example file shows how, and [the maintenance chapter](literate/80-maintenance.org) explains why.
- **`M-x customize`** saves to `var/etc/custom.el`, which loads after everything else and always wins.
- **A Nix module or dotfiles repository** can put `*.el` files in `~/.config/kittymacs/conf.d/`. They load in name order just before `private.el`, so your own settings still win.
- **To start faster**, a new machine writes one file that activates every package, so a start need not scan them. `just quickstart-remove` turns it off for good, and `just quickstart` or `M-x kittymacs-quickstart-write` turns it on, which a machine from before this default must do to get it; [the startup chapter](literate/10-startup.org) has the details.
- **To work on another machine**, name it as a backend, and this Emacs stays the screen while that machine runs Magit's `git`, Eglot's server, `compile` and the agent.

  ```elisp
  (setopt kittymacs-backends
          '(("build" :transport ssh :host "build.example.org" :root "~/src/project/")))
  ```

  `SPC o b` opens the project there, and `SPC o B` lists which tools the machine has, and what to run for those it lacks. [A backend's environment](literate/36-remote.org) says where its programs' variables come from. A buffer there shows `[name]` in the mode line, with a `?` when nothing is connected, and clicking it, or `SPC o R`, reconnects. `:transport` is `ssh`, `wsl` for a WSL2 distribution from native Windows Emacs, or any other method Tramp offers. Give an ssh machine a key or a `ControlMaster` line in `~/.ssh/config`, because a backend starts its processes directly, and that path cannot ask for a password; `:direct-async nil` turns it off. Two things stop on a remote file so that a dead connection cannot stall Emacs: automatic saving and auto-save files, so save with `C-x C-s`, and a crash loses what you typed since. [The remote chapter](literate/36-remote.org) has the rest.
- **To change the configuration itself**, edit its chapter in `literate/`, then `SPC C t` to regenerate the Lisp and restart. See [Develop](#develop).

## Update

```sh
cd ~/.config/emacs
git pull
```

Then, inside Emacs, `M-x package-upgrade-all` upgrades the installed packages; restart afterwards. Packages the Nix modules installed move with the flake's lock instead (`nix flake update`, then switch). With [just](https://github.com/casey/just), `just update-packages` does the same from a shell, `just update-grammars` rebuilds the Tree-sitter grammars at their pinned revisions, and `just update` also moves the Nix flake's lock.

## Troubleshooting

**Start with the basics.**

- `emacs --debug-init` shows a backtrace for an error during startup.
- Warnings and errors open in a window at the bottom of the current frame, not as a new OS window; `*Messages*` (`SPC h e`) has the full log.
- To rule out your own settings, move `lisp/private.el` and `var/etc/custom.el` aside and restart.

**Packages.**

- *Packages fail to install, or a signature check fails:* check that `gpg` works (`gpg --version`); on Windows it must be Gpg4win's. Then `M-x package-refresh-contents` and restart.
- *A package is broken after an update:* quit Emacs, delete `var/elpa/`, and start again; kittymacs reinstalls what this machine's features need.
- *ghostel came from Git rather than MELPA* (left over from an older install): delete its directory in `var/elpa/` (and `consult-ghostel`'s) and restart.

**Features that quietly switch off.** kittymacs turns a feature off when its program is missing, rather than failing. If something does nothing:

- *No terminal:* `SPC o e` explains what is missing; `M-x ghostel-download-module` fetches the native module. The Android port opens Eshell instead.
- *No icons, or boxes instead of icons:* install Symbols Nerd Font Mono and restart; set `kittymacs-icons` to `t` for a terminal Emacs that already uses a Nerd Font.
- *No spell checking:* install `hunspell` or `aspell` with a dictionary, on `PATH`.
- *No Tree-sitter highlighting:* run `M-x kittymacs-treesit-install-grammars` (needs Git and a C compiler); until a grammar loads, its files open in the classic mode, and a grammar you declined is offered again in the next session.
- *No language server:* `SPC l e` starts Eglot in the current buffer; add the mode to `kittymacs-eglot-auto-start-modes` to start it automatically. The server itself is yours to install.
- *A PDF opens as a picture, not in pdf-tools:* `epdfinfo` is missing. The Nix module installs it; otherwise `M-x pdf-tools-install` builds it (it needs poppler and a C compiler).
- *Emacs offers to build `epdfinfo` although Nix installed it:* Emacs cannot see the Nix profile. `M-: (executable-find "epdfinfo")` should name a path in `/nix/store`; if it is nil, decline the build and check `M-: exec-path` for `~/.nix-profile/bin` (or `/etc/profiles/per-user/<you>/bin` on NixOS). On macOS the shells chapter puts the profiles back after importing the login shell's `PATH`, so restart Emacs after updating.
- *`SPC a a` fails to start:* `claude-agent-acp` must be on the path Emacs sees (`M-: (executable-find "claude-agent-acp")`), and `claude` must be logged in once in a terminal (`/login`).
- *`SPC t a` says suggestions need the server:* `copilot-language-server` must be on the path Emacs sees (`M-: (executable-find "copilot-language-server")`), or installed by `M-x copilot-install-server`. Then `M-x copilot-login` once; `M-x copilot-diagnose` reports the server and the account.
- *Org-roam does nothing:* your Emacs needs SQLite (`M-: (sqlite-available-p)`), and each graph needs one `SPC n s`.

**Platform problems.**

- *Windows: Emacs ignores the clone:* see the `HOME` and junction note under [Windows](#windows).
- *macOS: programs installed with Homebrew or Nix are not found:* start Emacs once from a terminal to compare; the shells chapter imports the environment of your *login* shell, so set `PATH` in `~/.zprofile`, not only `~/.zshrc`.
- *A program on a remote machine is not found* (Eglot, Magit or search over Tramp): `SPC o B` shows what a backend has. Tramp reads the remote login shell's `PATH` once per connection, and then the Nix profiles. After installing something there, run `M-x tramp-cleanup-connection`.
- *A command waits on a dead connection:* `C-g` ends it, and `M-x tramp-cleanup-connection` closes the connection. The first edit after a save, a save, and any command you run on a remote file still wait for the machine.
- *Android: a program from Termux is not found:* the port and Termux must come from a matching pair of builds; check `kittymacs-termux-root`.

**Check the installation itself.** From a shell in the clone, with [just](https://github.com/casey/just):

```sh
just check          # the generated files match their chapters; package-free tests pass
KITTYMACS_TEST_PROFILE=full just install  # the packages the next check needs; skip it if this machine is on full
just test-packages  # starts the configuration in isolation, on full, and fails on any warning
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
| `KITTYMACS_TEST_PROFILE=full just install`, `just compile`, `just test-packages`, `just test-quickstart` | network, then installed packages | a fresh install byte-compiles, and the leader, Org-roam, theme and startup-verifier tests pass, under `full`, the last also from a quickstart file |
| `just frames-test` | a display | the frame policy |
| `just nix-check` | Nix | the generated Nix lints, the flake and both example hosts evaluate, and the selection options reach a real start |

[The maintenance chapter](literate/80-maintenance.org) explains each recipe and the builder; [the conventions](literate/conventions.org) say how a chapter is written; [ARCHITECTURE.md](ARCHITECTURE.md) records the design and every decision behind it. `nix develop` gives a shell with Emacs, `just` and the Nix linters. [CI](.github/workflows/ci.yml) runs the recipes on every push, on Emacs 31.1, on Linux, macOS and Windows.

## Credits and licence

kittymacs is GPL-3.0-or-later. Copyright (C) 2026 Mihir Talati.

Much of the policy is distilled from [Lambda-Emacs](https://codeberg.org/Lambda-Emacs/lambda-emacs) and [Colin McLear's configuration](https://codeberg.org/mclear-tools/dotemacs), both GPL-3.0-or-later; each chapter outlines what it took, and each generated module says so in its header. The Meow grammar follows Meow's documented layout, and the Sonokai theme is a tracked port in `lisp/themes/`. Everything else is the work of the packages' authors, credited in the chapters that use them.
