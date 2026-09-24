# kittymacs — architecture and decisions

The single source of truth for the design: what the configuration is, how it is put together, and why. It describes the design as it is now; how it got here is in the Git history. The learner-facing explanation lives in [`literate/index.org`](literate/index.org); this file is for whoever changes the design.

## 1. Intent (the user's words)

kittymacs is a user-friendly, batteries-included, opinionated and extensible Emacs configuration for one person, built on a small sane starter kit (Lambda-Emacs, Colin McLear's config) plus liked packages. It is Meow-first: selection → extension → action, with visual hints. It prefers spawning frames over windows so the desktop window manager manages them. Its main thrust is to be for Meow what Doom/evil-collection are for Evil: retire the Meow keypad, replace on-screen hints and internal keymaps with real literal maps, and integrate the initial package set with the Meow grammar in a clean, extensible way. It must stay learner-friendly: discoverable actions, visual hints, simple to modify and extend, with a heavily explanatory, tutorialised, wiki-style literate config.

## 2. Shape

```
early-init.el, init.el   generated from literate/10-startup.org
literate/*.org           the chapters (NN-name.org) and the reading guide; the source of truth
lisp/kittymacs-*.el      one generated module per chapter; keybindings.org (cheat sheet); themes/; private.el
tests/                   kittymacs-tangle-tests, kittymacs-platform-tests, kittymacs-treesit-tests (no packages);
                         kittymacs-leader-tests, kittymacs-org-roam-tests, verify-config (installed packages);
                         kittymacs-frames-tests (graphical session, by hand)
tools/tangle.el          finds the chapters, validates their targets, tangles and copies the outputs
flake.nix, nix/          nix-darwin and home-manager modules, tool list, dev shell, nix-darwin and nix-on-droid example hosts
var/                     packages, caches, custom.el; ignored
```

Startup is a flat list of `require`s in `init.el`, ordered by dependency: defaults → platform → `private.el` → UI → literate commands → dashboard → completion → help → Dired → Treemacs → VC → navigation → Meow → keys → shells → programming → Tree-sitter → languages → terminal → Org → Org-roam → frames → `custom.el`. There are no staged hooks; the little that must wait until `init.el` has finished (restoring `*scratch*`, turning Tabspaces on) adds itself to `after-init-hook`. The leader module is not in the list: the modules that define localleaders require it.

## 3. The Meow layer

**Leader.** `SPC` is bound to `kittymacs-leader-map`, an ordinary keymap, in Meow's Normal and Motion state maps through Meow's own `meow-normal-define-key` / `meow-motion-define-key`. Because it is a real keymap, `C-h k`, `C-h b`, `where-is`, which-key and Marginalia see the physical keys with no adapter. `C-c C-SPC` opens the same map from Insert state and non-Meow buffers. `meow-keypad` is not bound; `kittymacs-keypad-key` binds it under the leader when set. (`literate/41-leader.org`)

**Localleader.** Meow has no per-mode state maps, so `SPC m` uses one buffer-local entry in `emulation-mode-map-alists`, keyed on `meow-normal-mode` / `meow-motion-mode`, whose map is composed along `derived-mode-all-parents` (most specific first). A `prog-mode` menu is inherited by every language; `emacs-lisp-mode` overrides the keys it redefines. `kittymacs-define-localleader` is one form per mode. The leader map must leave `m` unbound. (`literate/41-leader.org`)

**Integrations.** Each package chapter states which Meow state its buffers start in (`meow-mode-state-list`) and defines its localleader with labelled entries, evil-collection style but literate. Application buffers (Dired, Magit, Help, Info, the agenda, the dashboard) start in Motion so their own keys keep working; shells and commit messages start in Insert.

**Keys.** `literate/42-keys.org` is the single owner of the tree: labelled group keymaps for buffers, files, search, projects, VC, windows/frames, workspaces, code, eval, language server, diagnostics, insert, notes, open, toggle, config, help, quit and a reserved user group, including the help map and the Cape map. No other chapter adds a key under `SPC`; the commands those keys run live with their modules (the inbox command in the Org chapter, the `SPC C` commands in `kittymacs-literate.el`). `SPC p` is `kittymacs-project-map`, whose `:parent` is Emacs's `project-prefix-map`: the `C-x p` commands work under `SPC p` and the map adds a few, while `C-x p` stays exactly Emacs's own menu. Three keys are overridden: `SPC p p` opens the project in a tabspaces workspace (`C-x p p` is plain `project-switch-project`), `SPC p b` is `consult-project-buffer` instead of `project-switch-to-buffer`, and `SPC p G` is `magit-project-status`, so `project-or-external-find-regexp` is only on `C-x p G`. The chapter carries the migration table from the old keys. `lisp/keybindings.org` is the learner cheat sheet; the startup verifier checks every `SPC` row in it against the live map.

## 4. Decisions

User decisions:

1. Extract the vendored Lambda tree fully into our own literate chapters rather than trim it.
2. Literal `SPC` leader; the keypad bound to nothing by default, with `kittymacs-keypad-key` as the opt-in.
3. This file is the only decision record; there is no ADR folder, validator, inventory, progress ledger or catalogue.
4. `early-init.el` and `init.el` are our own short files, tangled from a chapter.
5. There is no GUI test runner; `tests/kittymacs-frames-tests.el` is run by hand in a graphical Emacs.
6. First integrations: Magit, Dired, Org, the terminal and Eshell, Vertico/Consult/Embark, Help and Info.
7. One `private.el` for machine settings, not a second, late file.
8. The personal configuration is an overlay package, not a fork (see below).

Design decisions, with the reason:

### Structure and startup

- **No registry, no transactions.** `with-eval-after-load`, hooks and `derived-mode-p` are the lazy-readiness and specificity mechanisms Emacs already has. The prototype's descriptor validation, readiness states and reentrancy guards solved problems the native design does not have.
- **Tangle with tracked outputs.** Startup never tangles, a clone works without a build step, and `tools/tangle.el` stays proportionate.
- **The chapter list is derived from file names.** Every `literate/NN-name.org` is a chapter and its `:tangle` headers name its outputs, so adding a chapter needs no second place to register it. The builder keeps its safety rules: a target must be Emacs Lisp and must be `early-init.el`, `init.el` or a file in `lisp/` other than `private.el`; no two chapters may write one file; all targets are read before anything is written; and a `lisp/kittymacs-*.el` that no chapter produces is an error, because startup would go on loading a module whose source is gone.
- **`early-init.el` uses `setq`.** Everywhere else options are set with `setopt`, but in `early-init.el` it would load Customize and, for the package options, `package.el` with url and EIEIO, tens of milliseconds before the first frame. The file also calls `(menu-bar-mode -1)` next to the frame parameter that hides the menu bar, so the mode agrees with what is on screen and the first `SPC t m` shows the bar.
- **Options are set with `setopt`, so values must satisfy the option's type.** A value the `:type` rejects raises a warning on every start (Org 9.7 spells "open unfolded" as `nofold`, and wants `org-agenda-start-with-log-mode` to be a list). When a warning names an option, read its `:type`. Only values that differ from Emacs's defaults are set; restating a default hides which choices are ours.
- **The `kittymacs` option group is defined in the defaults module**, the first that loads, and every chapter's group hangs from it.
- **Global modes are switched on one way.** A built-in mode is turned on with `(mode 1)` at top level; a package's global mode in the `:config` of its `use-package`, with `:demand t` when `:bind` or `:hook` would otherwise defer loading. No startup hook turns a mode on, with one exception: `tabspaces-mode` reads `tabspaces-use-filtered-buffers-as-default`, `tabspaces-session`, `tabspaces-session-auto-restore` and `tabspaces-echo-area-enable` once, as it turns on, and none of them has a `:set`, so it is turned on from `after-init-hook` at depth 95, after `custom.el` and the `private.el` function at depth 90.
- **Helpers are top-level functions.** Functions that a hook runs are defined at top level, not inside `:config`, and have the private `kittymacs--` prefix. Functions that are the value of an option (`kittymacs-eshell-prompt`, `kittymacs-magit-display-buffer`, `kittymacs-guess-major-mode` and the like) keep public names, since a user may name them in `private.el`.
- **Built-in commands over wrappers.** Where Emacs or a package already has the command, the key runs it: `dired-up-directory`, `org-insert-structure-template`, `eglot`, `magit-project-status`. Buffer switching skips Emacs's own buffers through `switch-to-prev-buffer-skip-regexp` rather than helper functions, and the dashboard's buttons all go through one `kittymacs--dashboard-run`.
- **Customize and `private.el` get the last word.** `init.el` loads `private.el` early, right after the platform chapter, because chapters read `kittymacs-*` options while they load, and it loads `custom-file` on its last line, so Customize overrides every chapter. A package option that a chapter also sets cannot be set at the top of `private.el`: the chapter runs later and replaces it. It goes in an `after-init-hook` function at depth 90, which runs once `init.el` has finished, and inside it in `with-eval-after-load` when the chapter sets the option only as the package loads. A top-level `with-eval-after-load` in `private.el` would not do: after-load forms run in the order they were registered, so it would run before the chapter's. The verifier replays a real startup and checks that both kinds of override survive.
- **The personal configuration is an overlay package.** Features that are one person's rather than the configuration's (the justfile recipe runner on `SPC p j` with its just-mode declaration, running EmptyNet's recipes in NixOS on WSL on Windows, and an `M-x` that offers only the commands that apply to the current buffer) live in a separate package, `kittymacs-personal`, which `private.el` loads from `after-init-hook`. It binds its key in the public `kittymacs-project-map` (`kittymacs-leader-map` is public for the same use) and never edits this repository, so the shared configuration can change without a merge. Personal machine settings, packages, caches and notes stay out of the public repository.
- **UI loads first.** Theme and fonts before the first frame is drawn, with one theme at startup. Theme-dependent faces hang on Emacs 29's `enable-theme-functions`.
- **Packages declared where used** with `:ensure t`; `init.el` refreshes archives once when none are cached. One Corfu formatter, `nerd-icons-corfu`.
- **The platform module may not declare a package.** `tests/kittymacs-platform-tests.el` loads it with no packages available, so `use-package … :ensure t` there would try to install at test time. Spell-checker discovery lives in the platform chapter because it is a property of the machine; its two front ends (`flyspell-correct`, `consult-flyspell`) are declared in the completion chapter.
- **Never add to a hook that the package later aliases.** `defvaralias` discards the value of the variable it turns into an alias. Magit's `git-commit.el` makes `git-commit-mode-hook` an alias of `git-commit-setup-hook` when it loads, so a function added to the old name before that (as `:hook (git-commit-mode . flyspell-mode)` on a deferred Magit did) silently never runs, and the warning `defvaralias` prints raised a `*Warnings*` frame over the first Magit window. Functions for such a hook are added to its final name inside `with-eval-after-load` of the file that defines it.
- **The default `major-mode` must be a symbol.** Every buffer made by `get-buffer-create` carries it, and `get`, `symbol-name` and `derived-mode-parent` all assume a mode name; `kittymacs-guess-major-mode` is a named function for that reason.
- **Licence is GPL-3.0-or-later**, matching the sources the code is distilled from.

### Keys and Meow

- **Buffer-local emulation entry over a `menu-item :filter`.** Both work; only the emulation entry is visible to `where-is`, which Marginalia uses for M-x annotations.
- **Motion state for Magit and Dired.** In Normal state Meow's grammar shadows Magit's `s`, `u`, `c`; Motion keeps the package's keys and adds only `j`/`k` and the leader.
- **Meow colours its own expansion hints.** `meow-use-dynamic-face-color` is at its default: Meow derives the hint backgrounds from the cursor and region colours of the active theme and recomputes them through its `enable-theme` advice. doom-themes and the Sonokai port style none of Meow's faces, so turning it off left the numbered hints as plain text.
- **The home page is the first landing page.** It carries the kittymacs `:3` banner, buttons for every place the README sends a new user (cheat sheet, reading guide, keys chapter, Meow tutor) and a six-key guide at the bottom, so a fresh install explains itself before anything is opened.

### Frames

- **Frames mean full buffers, not panels.** The frames preference covers buffers you read or edit; sidebars, menus, gutters and the minibuffer stay inside each frame. Treemacs and `imenu-list` are side windows and `diff-hl` is the git gutter (all under `SPC t`). `frames-only-mode` remaps the split commands, so every key bound to them, `SPC w h`/`SPC w v` included, makes a frame while the mode is on.
- **Diagnostics stay inside the frame.** `*Warnings*`, `*Backtrace*` and the compilation logs are things Emacs says, not buffers you work in, so `display-buffer-alist` gives them a window at the bottom of the current frame. Without it any warning, from any package, becomes a focus-stealing OS window.
- **`magit-status` asks in a better order.** From a buffer with no file, `default-directory` is wherever the buffer was born, and `magit-status` there offers to create a repository. `kittymacs-magit-status` tries this buffer's repository, then the current project's, and only then Magit's own prompt. The display function ends with `display-buffer-use-some-window`, because Magit selects whatever window it is handed and a `nil` there is an error.

### Platforms

- **Each operating system is a section of the platform chapter, not a module.** A platform is a set of answers to *where does this machine keep things*. Because `system-type` is a plain variable, `tests/kittymacs-platform-tests.el` binds it per test and exercises every operating system's branch on any machine without packages.
- **macOS.** Lambda's macOS choices were kept where they fit a frames-first Meow configuration: Option is Meta and Command is Super with the right Option left to macOS (one `kittymacs-macos-modifiers` option), non-native full screen, a UTF-8 `LANG` when the Dock supplied none, the Trash through the `trash` tool or `~/.Trash`, Keychain in `auth-sources`, `⌘⇧Z` redo, `⌘Q` that closes a frame while others remain, `C-⌘-f` full screen, and a title bar that follows the theme. Fn is not Hyper, because that turns Fn-arrow paging into Hyper chords; `kittymacs-reveal-in-file-manager` on `SPC f o` covers Finder, Explorer and xdg-open instead of three packages.
- **A Dock-launched Emacs.app sees no shell `PATH`**, so `early-init.el` puts the Nix profiles and Homebrew on `exec-path` on macOS before the GNU ELPA signature check. `exec-path-from-shell` then imports the login shell's environment; its whole policy is the `:if` in the shells chapter, which leaves it out on Windows and Android. Dired uses GNU `ls` as `gls` when coreutils is installed, since BSD `ls` has no `--group-directories-first`.
- **GNU ELPA needs a native gpg.** Emacs verifies the signed GNU ELPA index with the first `gpg` on `exec-path`. On Windows that is Git for Windows' MSYS `gpg`, which cannot open a Windows keyring directory, so every signature fails as "no public key" and the archive silently disappears. `early-init.el` puts Gpg4win's directory first on `exec-path` when it is installed, and leaves `PATH` alone, so subprocesses see no change; on Windows without it, or anywhere without `gpg`, it skips the check.
- **Git for Windows' Unix tools go last on `exec-path`.** Magit's hunk refinement, Ediff and diff-hl call `diff`, `diff3` and `patch` by name, and Windows has none. The platform policy appends Git's `usr/bin` (or MSYS2's) after every other entry, so native programs keep winning, and leaves `PATH` alone.
- **Spelling is decided per buffer, and Ispell is told its dictionary first.** The Flyspell hooks are always added and ask for a checker when a buffer opens, so a checker that `private.el` or `exec-path-from-shell` makes visible later is still found. `DICTIONARY` is set before `ispell-program-name`, whose setter asks Hunspell for its dictionaries; a checker that fails is reported once and Ispell stays loaded. Emacs 30's text-mode dictionary completion is off: with `corfu-auto` it would start a process a few times per word, and `SPC c p w` (`cape-dict`) is the explicit version.
- **Android is a platform branch, not a port.** The Android build reports `system-type` as `android`. The shell prefers Termux's `bash`, then Termux's `sh`, then `/system/bin/sh`. Termux is discovered, never assumed, because Android lets one application read another's files only when they share a user ID; `LD_LIBRARY_PATH` is cleared rather than set. The volume keys stay the port's way to quit (`kittymacs-android-volume-keys` hands them back). Text conversion follows Meow's state through `set-text-conversion-style`, since input methods edit the buffer directly, which is right only in Insert. Dired lists with `ls-lisp`, and `kittymacs-frames-only` defaults to off, because an Android frame is an entry in the task switcher.
- **The terminal cannot follow to Android, and Eshell stands in.** ghostel is installed with `git`, which the port does not ship, and is a native module with no `android-aarch64` build, so `SPC o e` opens Eshell there.

### Terminal, tree and tools

- **ghostel is the terminal.** It is a thin Emacs layer over `libghostty-vt`, so a program in it cannot tell it from a terminal window (Kitty keyboard and graphics protocols, OSC 8 and OSC 7, synchronised output, true colour, automatic shell integration). It uses ConPTY directly on Windows, so no POSIX helper is needed. It has its own chapter (`34-terminal.org`); the MSYS2 root and spell-checker discovery are platform questions and live in `30-platform.org`. The native module lives in `var/ghostel/`, not the package directory, so `package-upgrade` cannot delete a library this Emacs has mapped, and it is downloaded on the first `SPC o e`, never at startup.
- **The terminal is installed from its repository, not an archive.** MELPA's `ghostel` build has been broken and `consult-ghostel` has no recipe, so both use `:vc`, upstream's documented method. Move them back to `:ensure t` when MELPA carries them.
- **Meow's states drive ghostel's input modes.** Terminals start in Insert, where ghostel forwards the keys and `C-c` still reaches Emacs. Leaving Insert freezes the terminal into copy mode, so the scrollback is an ordinary buffer for the selection grammar; entering Insert thaws it. `ESC` goes to the program exactly while the alternate screen is active (`kittymacs-terminal-escape`, overridable with `SPC m ESC`); this bridge is ours because there is no `meow-ghostel`.
- **Which ghostel integrations are on.** The additive ones: Eshell's visual commands, `M-x shell`'s VT parser (only when the native module is present), `ghostel:` Org links, bookmarks, desktop, input methods, `consult-ghostel` and `ghostel-project`. `ghostel-compile-global-mode` is not, because it replaces `compilation-start` for every command built on it; `ghostel-compile` is on `SPC m t` and the global mode is one line in `private.el`.
- **Treemacs is the file-tree sidebar.** It is a panel, so it uses a side window, and `treemacs-is-never-other-window` keeps "other window" from landing in it. `treemacs-project-follow-mode` shows the project you are in, `treemacs-tab-bar` scopes a tree per workspace, `treemacs-magit` notices index changes that file watching cannot, and its state goes under `var/`. Git-ignored files stay visible.
- **Pinned Tree-sitter grammars live in the writable cache and install only on request.** `kittymacs-treesit-grammar-directory` defaults to `var/cache/tree-sitter/` and is put at the front of `treesit-extra-load-path` before every availability check and install, so a later `setopt` applies without a restart. Each recipe is pinned to an exact commit, a mode is remapped to its Tree-sitter version only when both the mode and a loadable grammar exist, and on Windows the recipe uses MSYS2's UCRT64 GCC by absolute path.

### Linked notes

- **A graph is Org-roam's own pair of variables, set once per buffer.** `org-roam-directory` and `org-roam-db-location` are made buffer-local when the buffer's graph is decided, from `hack-local-variables-hook` for Org files, `org-roam-mode-hook` for the backlinks panel (whose major mode restarts on every refresh, so its graph is permanent-local) and `org-capture-mode-hook` for a capture. Org-roam's own code then finds the graph where it looks for it, without being wrapped. There is no graph registry, custom schema or project loader.
- **Databases live in the user cache, named by the graph's real path.** A project checkout never contains a generated file and a read-only one can be indexed. The name is a hash of the `file-truename`, so aliases share an index and worktrees do not. The personal root is resolved with `file-truename` when the module loads, so direct upstream calls share its connection. Nothing syncs at startup and upstream's autosync mode stays off, because turning it on rebuilds the index; `C-u SPC n s` rebuilds a graph from nothing after the same checks as every command.
- **A project graph is declared by the project.** A repository's `.dir-locals.el` sets `kittymacs-org-roam-project` (EmptyNet ships one), and the folder holding that file is the root. `kittymacs-org-roam-excluded-directories` is safe as a directory local, so a project names its own exclusions; they become `org-roam-file-exclude-regexp`, which upstream's listing already honours. The default exclusions are generic (Git's folder and cache folders).
- **The only advice is `:before-while` on `org-roam-id-find`.** It lets Org's own ID index answer when the current graph cannot be used, because Emacs has no SQLite or the root does not exist.

### Nix

- **Nix installs what surrounds the configuration, never the configuration.** `flake.nix` exposes a nix-darwin module, a home-manager module, a `tools` environment and a dev shell, all drawing from one list in `nix/tools.nix`. The configuration installs packages under `var/` and keeps `private.el` beside the modules, so it must be a writable clone; the home-manager module links it to `~/.config/emacs` through an out-of-store symlink. `x86_64-darwin` is not in the flake's systems, because nixpkgs-unstable dropped it.
- **The home-manager module clones a pinned revision, once.** When `source` is missing, activation fetches exactly `revision`, which defaults to the kittymacs revision the host's `flake.lock` records, from `repository`, and moves it into place only once `HEAD` is that commit. A failed clone warns and lets the rest of the activation run, since home-manager can run at boot before the network is up; the next activation tries again. After that the checkout is user state: a later activation that finds another commit prints a notice and changes nothing. `daemon` turns on home-manager's `services.emacs` (systemd on Linux, launchd on macOS); the nix-darwin module keeps its own `daemon`, and a Mac should use one of the two. EmptyNet consumes this module as a contract.
- **The sibling repository is EmptyNet**, formerly NixNet, renamed because it now manages many declarative systems across different boundaries rather than only NixOS machines. It imports the home-manager module and relies on its options (`source`, `repository`, `revision`, `daemon`), and its repository is a project graph through the `.dir-locals.el` described above.
- **nix-on-droid is a second device, not a layer under the Android port.** A Nix store path exists only inside nix-on-droid's PRoot, so the Android port could not execute anything installed there; the two applications are also different users, and Android 10 forbids executing another application's files. nix-on-droid consumes home-manager modules, so `homeManagerModules.default` is the whole integration; `installFonts` is separate from `installPackages` because a console-only Emacs has no use for the icon font.
- **CI evaluates, it does not build.** The example hosts are evaluated against the checkout with the `kittymacs` input overridden: the nix-darwin system needs a Mac to build, and nix-on-droid's activation needs `--impure`, so both checks read the package list the modules produce. The home-manager clone options are read with a `git+file` override, because a `path:` input has no revision to pin.

### CI

- **One startup job, every system.** A matrix runs the fresh install, a byte-compilation of every module, the package suites and the verifier on Linux with the oldest supported and the current Emacs, and informationally on macOS and Windows. Every step is written once in bash. The setup actions are pinned to commits and Dependabot proposes updates. The byte-compile step fails on errors only; its warnings are mostly about functions a module calls without loading them.
- **CI refreshes archive metadata after restoring the package cache**, with a non-interactive call because Emacs 31 refreshes asynchronously when the command is called interactively: cached MELPA metadata can name tarballs the archive has since replaced. The install step requires Org-roam explicitly, so a failed installation stops there instead of cascading into the graph tests. A weekly run skips the cache.

### Kept, added and dropped

- **Kept from Lambda**, attributed per module header: sane defaults, scrolling and mouse settings, persistent scratch, the completion stack configuration, Helpful/Info setup, Dired extensions, Magit settings, project/tab/workspace setup with workspace-filtered buffers, Org display and agenda defaults, programming aids, Eshell settings and aliases, Tramp, the highlighting packages.
- **Added after the first trial:** `org-modern` and `org-appear`, `avy` under `SPC j`, `meow-tree-sitter` things (`f` function, `a` class, `t` test, `y` entry, `,` parameter, `/` comment; the angle-bracket thing on `<`), `vundo` on `SPC b u`, `keycast` on `SPC t k`/`K`, Casual's menus on `?` in every localleader and `C-o` in the built-ins' own maps, and spell checking through `hunspell`/`aspell` or MSYS2's hunspell.
- **Dropped for good reasons:** icomplete fallback, `completion-preview`, the vertico-buffer internals override, the hand-rolled Info picker (`consult-info`), the help transient (a keymap shows in which-key), `peep-dired`, `vdiff-magit`, `git-gutter`, `kind-icon` (one Corfu formatter), `mu4e`/`denote`/`citar` keys (not installed), `svg-tag-mode`, `reveal-mode`, `lambda-themes`, macOS appearance sync (the theme does not follow the system), Fuco's Lisp indent override, `multi-compile`, Homebrew and iTerm helpers, Colin's personal Org file openers and export helpers, `desktop`, time stamps, `anaphora`/`csetq`/`deftoggle`, EAT (ghostel replaced it, and with it the Windows `make-process` adapter), `dired-sidebar` (two file-tree sidebars on one key are worse than either), `expand-region` (never bound; Meow's selection does its job), `rg` (`deadgrep` does the same on `SPC s D`), `reveal-in-osx-finder`, `grab-mac-link` and `osx-lib`. From Org-roam: NTFS junction resolution through a CPython helper, the refusal of remote graph paths, and the check of where a capture template writes. Each needed advice on private upstream functions or a subprocess on every lookup; a junction now simply looks like a separate folder with its own index, and Emacs asks before creating a folder on save.

## 5. Verification

Batch, from the repository root. The first four need no packages; the last three need `KITTYMACS_TEST_PACKAGES` pointing at an existing `var/elpa`:

```sh
emacs -Q --batch -l tools/tangle.el -- --check
emacs -Q --batch -l tests/kittymacs-tangle-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-treesit-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-org-roam-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/verify-config.el
```

`.github/workflows/ci.yml` runs all of them on every push and pull request: the first four on Emacs 31.1; then, on Emacs 30.1 and 31.1 on Linux and informationally on macOS and Windows, a fresh clone that installs its packages by starting `init.el` in batch, a byte-compilation of `lisp/*.el`, and the last three. A Nix job runs `nix flake check`, evaluates the nix-darwin and nix-on-droid examples against the checkout, and checks the home-manager module's clone options; a weekly run skips the package cache.

The verifier starts the real configuration in an isolated copy with installation forbidden, in the order of a real startup (`after-init-time` nil during init, then `after-init-hook` and `delayed-warnings-hook`), and prints `KITTYMACS-VERIFY` with its result. It asserts: no warning is displayed; `private.el` loads once and its overrides survive (top-level and `after-init-hook` ones, including one that `tabspaces-mode` reads as it turns on); `custom.el` loads from `var/etc` and wins over the chapters; every `lisp/kittymacs-*.el` module is loaded; every key in the `SPC` tree runs a command; `SPC` is `kittymacs-leader-map` in both Meow state maps; `SPC l e` is `eglot` and `SPC s l` is `vertico-repeat`; Org-roam neither syncs nor opens a database at startup; the dashboard's two buttons open the guide and the cheat sheet; theme toggling never stacks themes; and every cheat-sheet `SPC` row resolves to its command.

Not covered by CI, for the user to check on the real host:

- A graphical startup and the frame tests (`M-x ert RET ^kittymacs-frames- RET` after loading `tests/kittymacs-frames-tests.el`).
- macOS on a real Mac: the modifier keys, the Trash, the title bar and the Dock-launched `PATH`. The platform tests cover the branches with `system-type` bound to `darwin`, the informational macOS job covers batch startup, and the nix-darwin example is evaluated but not built.
- The home-manager activation itself: CI evaluates the clone script but never runs it.
- Android on a real device. The platform tests cover every branch with `system-type` bound to `android`, and no CI runner is an Android telephone. Unverified, in rough order of how likely they are to want adjusting: whether a paired Termux's `bash` starts cleanly through the executable loader; whether `set-text-conversion-style` on each Meow state transition is quick enough with a particular on-screen keyboard (`kittymacs-android-modal-text-conversion` exists for that); whether the port in use has dynamic module support; and how the default font size reads at phone density. `nix-on-droid switch` is evaluated but not applied to a device.

## 6. Open items

- Packages that nothing declares any more stay in an existing `var/elpa/` (for example `kind-icon`, `expand-region`, `rg`, `lambda-themes`). Prune with `M-x package-autoremove` when convenient.
- Beacon state is untouched by the leader (as intended); `SPC` in Beacon is Meow's default.
- ghostel's native module is downloaded on first use, so the first `SPC o e` on a new machine needs the network; `M-x ghostel-module-compile` builds it instead with Zig. Declining reports what is missing instead of a void function.
- `treemacs-git-mode` runs `deferred` where `python3` exists and `simple` otherwise.
- `kittymacs-leader-alt-key` is fixed at `C-c C-SPC` in the keys chapter; make it an option if it ever needs to change.
- The `yaml-mode`, `typescript-mode` and `typst-mode` rows of `kittymacs-treesit-mode-remaps` name modes that nothing installs, so on a stock Emacs those remaps never fire.
- `kittymacs--org-no-angle-pairs` is still defined inside the Org chapter's `:config`, so the byte compiler cannot see it.

## 7. Extending

- **A key:** `(keymap-set kittymacs-leader-map "u x" #'my-command)` in `private.el`, or a group in `42-keys.org`. Labels: `(cons "label" #'command)`. Project keys go in `kittymacs-project-map`, for example `(keymap-set kittymacs-project-map "j" #'my-project-command)`, which leaves `C-x p` alone.
- **A mode menu:** `(kittymacs-define-localleader 'python-mode "r" (cons "run" #'python-shell-send-buffer))` next to the package.
- **A package:** a chapter named `literate/NN-name.org` with a `use-package … :ensure t` block, a Meow section and a `require` in the startup chapter. The builder finds the chapter by its name; there is nothing else to register.
- **Something personal:** the `kittymacs-personal` overlay, or `private.el` for a single machine, never a branch of this repository.
