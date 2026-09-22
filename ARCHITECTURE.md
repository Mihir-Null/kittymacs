# kittymacs — architecture and decisions

Single source of truth for the design. Updated 2026-09-18, after the terminal, tree and Magit-hook work. The learner-facing explanation lives in [`literate/index.org`](literate/index.org); this file is for whoever changes the design.

## 1. Intent (the user's words)

kittymacs is a user-friendly, batteries-included, opinionated and extensible Emacs configuration for one person, built on a small sane starter kit (Lambda-Emacs, Colin McLear's config) plus liked packages. It is Meow-first: selection → extension → action, with visual hints. It prefers spawning frames over windows so the desktop window manager manages them. Its main thrust is to be for Meow what Doom/evil-collection are for Evil: retire the Meow keypad, replace on-screen hints and internal keymaps with real literal maps, and integrate the initial package set with the Meow grammar in a clean, extensible way. It must stay learner-friendly: discoverable actions, visual hints, simple to modify and extend, with a heavily explanatory, tutorialised, wiki-style literate config.

## 2. Shape

```
early-init.el, init.el   generated from literate/10-startup.org (86 lines together)
literate/*.org           21 chapters + index + manifest.json; the source of truth
lisp/kittymacs-*.el        21 generated modules (3,330 lines); keybindings.org; themes/; private.el
tests/                   tangle-tests (8), kittymacs-platform-tests (19), kittymacs-leader-tests (6), verify-config, frames-tests (5, GUI)
tools/tangle.el          stages, validates and copies generated outputs (125 lines)
flake.nix, nix/          nix-darwin and home-manager modules, tool list, dev shell, nix-darwin and nix-on-droid example hosts
var/                     packages, caches, custom.el; ignored
```

Startup is a flat list of `require`s in `init.el`, ordered by dependency: defaults → platform → `private.el` → UI → literate commands → dashboard → completion → help → Dired → Treemacs → VC → navigation → Meow → keys → shells → programming → Tree-sitter → languages → terminal → Org → frames. There are no staged hooks; modes that need `after-init-hook` add themselves.

Before the refactor the same configuration was 853 lines of vendored Lambda startup, 9,913 lines of vendored Lambda modules (17 never loaded), 2,384 lines of user modules, a 954-line prototype core that was never loaded, 3,740 lines of tests and tooling, and 14,307 lines of process documentation. Net change against `main`: 122 files, +6,338 / −15,531.

## 3. The Meow layer

**Leader.** `SPC` is bound to `kittymacs-leader-map`, an ordinary keymap, in Meow's Normal and Motion state maps through Meow's own `meow-normal-define-key` / `meow-motion-define-key`. Because it is a real keymap, `C-h k`, `C-h b`, `where-is`, which-key and Marginalia see the physical keys with no adapter. `C-c C-SPC` opens the same map from Insert state and non-Meow buffers. `meow-keypad` is not bound; `kittymacs-keypad-key` binds it under the leader when set. (`literate/41-leader.org`)

**Localleader.** Meow has no per-mode state maps, so `SPC m` uses one buffer-local entry in `emulation-mode-map-alists`, keyed on `meow-normal-mode` / `meow-motion-mode`, whose map is composed along `derived-mode-all-parents` (most specific first). A `prog-mode` menu is inherited by every language; `emacs-lisp-mode` overrides the keys it redefines. `kittymacs-define-localleader` is one form per mode. The leader map must leave `m` unbound. (`literate/41-leader.org`)

**Integrations.** Each package chapter states which Meow state its buffers start in (`meow-mode-state-list`) and defines its localleader with labelled entries, evil-collection style but literate. Application buffers (Dired, Magit, Help, Info, the agenda, the dashboard) start in Motion so their own keys keep working; shells and commit messages start in Insert.

**Keys.** `literate/42-keys.org` is the single owner of the tree: labelled group keymaps for buffers, files, search, VC, windows/frames, workspaces, code, eval, language server, diagnostics, insert, open, toggle, config, help, quit and a reserved user group. `SPC p` is Emacs's own `project-prefix-map`. The chapter carries the migration table from the old keys. `lisp/keybindings.org` is the learner cheat sheet; the startup verifier checks every `SPC` row in it against the live map.

## 4. Decisions

User decisions (2026-09-14):

1. Extract the vendored Lambda tree fully into own literate chapters rather than trim it.
2. Literal `SPC` leader; the keypad bound to nothing by default, with `kittymacs-keypad-key` as the opt-in.
3. This file is the only decision record; the ADR folder, validator, inventory, progress ledger and catalogue were deleted.
4. `early-init.el` and `init.el` are our own short files, tangled from a chapter.
5. The GUI test runner was deleted; `tests/frames-tests.el` stays runnable by hand.
6. First integrations: Magit, Dired, Org, EAT and Eshell, Vertico/Consult/Embark, Help and Info.
7. The result lands as a pull request into `main`, superseding branch `uwumacs`.

Agent decisions, with the reason:

- **No registry, no transactions.** `with-eval-after-load`, hooks and `derived-mode-p` are the lazy-readiness and specificity mechanisms Emacs already has. The prototype's descriptor validation, readiness states and reentrancy guards solved problems the native design does not have.
- **Buffer-local emulation entry over a `menu-item :filter`.** Both work; only the emulation entry is visible to `where-is`, which Marginalia uses for M-x annotations.
- **Motion state for Magit and Dired** (was Normal for Magit). In Normal state Meow's grammar shadows Magit's `s`, `u`, `c`; Motion keeps the package's keys and adds only `j`/`k` and the leader.
- **UI loads first.** Theme and fonts before the first frame is drawn; the old two-theme startup (Lambda's dark fallback, then Sonokai) is gone. Theme-dependent faces hang on Emacs 29's `enable-theme-functions`.
- **Meow colours its own expansion hints** (2026-09-14). `meow-use-dynamic-face-color` was `nil`, copied from a setup whose theme styled Meow's faces; doom-themes and the Sonokai port style none of them, so the numbered hints rendered as plain text. The option is back at its default: Meow derives the hint backgrounds from the cursor and region colours of the active theme and recomputes them through its `enable-theme` advice, so the light theme is covered without a kittymacs hook.
- **Packages declared where used** with `:ensure t`; `init.el` refreshes archives once when none are cached. `embark-consult`, previously assumed to install transitively and absent, is now declared and installed. `kind-icon` dropped so `nerd-icons-corfu` is the one Corfu formatter.
- **Tangle with tracked outputs** kept: startup never tangles, a clone works, and `tools/tangle.el` (125 lines) is proportionate.
- **Frames mean full buffers, not panels.** The user's frames preference covers buffers you read or edit; sidebars, menus, gutters and the minibuffer stay inside each frame. Treemacs and `imenu-list` are kept as side windows and `diff-hl` is the git gutter (all under `SPC t`); the same rule now covers `*Warnings*` and the other buffers Emacs raises on its own.
- **Dropped for good reasons:** icomplete fallback, `completion-preview`, the vertico-buffer internals override, the hand-rolled Info picker (`consult-info`), the help transient (a keymap shows in which-key), `peep-dired`, `vdiff-magit`, `git-gutter`, `mu4e`/`denote`/`citar` keys (not installed), `svg-tag-mode`, `reveal-mode`, `lambda-themes`, macOS appearance sync, Fuco's Lisp indent override, `multi-compile`, Homebrew and iTerm helpers, Colin's personal Org file openers and export helpers, `desktop`, time stamps, `anaphora`/`csetq`/`deftoggle`.
- **Added after the first trial (2026-09-14):** `org-modern` and `org-appear` (hidden markers shown at point), `avy` under `SPC j`, `meow-tree-sitter` things (`f` function, `a` class, `t` test, `y` entry, `,` parameter, `/` comment; the angle-bracket thing moved to `<`), `vundo` on `SPC b u`, `keycast` on `SPC t k`/`K`, Casual's menus on `?` in every localleader and `C-o` in the built-ins' own maps, and spell checking wired to `hunspell`/`aspell` on `PATH` or MSYS2's hunspell.
- **GNU ELPA needs a native gpg.** Emacs verifies the signed GNU ELPA index with the `gpg` that `gpgconf` reports; on Windows that is Git for Windows' MSYS `gpg`, which cannot open a Windows keyring directory, so the import yields nothing and every signature fails as "no public key" while the archive silently disappears. `epg` honours `epg-gpg-program` only when set through Customize and otherwise takes the first `gpg` on `exec-path`, so `early-init.el` puts Gpg4win's directory (the documented Windows dependency) first on `exec-path` and `PATH` when it is installed, and skips the check on Windows without it or anywhere without `gpg`. Verified: with that in place both GNU archives verify from a fresh keyring.
- **Options are set with `setopt`, so values must satisfy the option's type.** Org 9.7 (Emacs 30/31) spells "open unfolded" as `nofold` and wants `org-agenda-start-with-log-mode` to be a list of items rather than `t`; the old values raised two `*Warnings*` on every start of a fresh Windows install. Fixed at the source in `70-org.org`; the rule is to read the `:type` when a warning names an option.
- **The home page is the first landing page.** It carries the kittymacs `:3` banner, buttons for every place the README sends a new user (cheat sheet, reading guide, keys chapter, Meow tutor) and a six-key guide at the bottom, so a fresh install explains itself before anything is opened. The verifier still presses the Config and cheat-sheet buttons.
- **macOS is a section of the platform chapter, not a module** (2026-09-14). Lambda's `lem-setup-macos` was the model and its choices were kept where they still fit a frames-first Meow configuration: Option is Meta and Command is Super with the right Option left to macOS (one `kittymacs-macos-modifiers` option), non-native full screen so a full-screen frame does not take its own Space, a UTF-8 `LANG` when the Dock supplied none, the Trash through the `trash` tool or `~/.Trash`, Keychain in `auth-sources`, `⌘⇧Z` redo, `⌘Q` that closes a frame while others remain, and `C-⌘-f` full screen. Not carried: Fn as Hyper (it turns Fn-arrow paging into Hyper chords), `reveal-in-osx-finder`, `grab-mac-link` and `osx-lib` (a twelve-line `kittymacs-reveal-in-file-manager` covers Finder, Explorer and xdg-open on `SPC f o`), and the Mitsuharu-only anti-aliasing flag. "macOS appearance sync" stays dropped in the sense it was dropped (the theme does not follow the system); the reverse, the title bar following the theme, is small and is in. Zero packages were added. Because `system-type` is a plain variable, `tests/kittymacs-platform-tests.el` binds it per test and exercises every operating system's branch on any machine without packages.
- **A Dock-launched Emacs.app sees no shell `PATH`**, so `early-init.el` puts the Nix profiles and Homebrew on `exec-path` on macOS before the GNU ELPA signature check, the same way it puts Gpg4win first on Windows, and `exec-path-from-shell` asks a login shell there (where `path_helper` and Homebrew's `shellenv` run) rather than the plain shell it asks on Linux. Dired uses GNU `ls` as `gls` when coreutils is installed, since BSD `ls` has no `--group-directories-first`.
- **Nix installs what surrounds the configuration, never the configuration.** `flake.nix` exposes a nix-darwin module, a home-manager module, a `tools` environment and a dev shell, all drawing from one list in `nix/tools.nix` (Emacs, git, ripgrep, fd, gnupg, hunspell with a dictionary, and on macOS `gls` and `trash`, plus the Nerd symbols font). The configuration itself is cloned somewhere writable, because it installs packages under `var/` and keeps `private.el` beside the modules; the home-manager module links that clone to `~/.config/emacs` through an out-of-store symlink. `nix/example/flake.nix` is a full nix-darwin host that CI evaluates on Linux with the `kittymacs` input overridden to the checkout, so the module's option set is exercised without a Mac. `x86_64-darwin` is not in the flake's systems: nixpkgs-unstable dropped it in 26.11.
- **ghostel replaces EAT as the terminal** (2026-09-18). The user asked for it by name. It is a thin Emacs layer over `libghostty-vt`, so a program in the terminal cannot tell it from a terminal window: the Kitty keyboard and graphics protocols, OSC 8 links, OSC 7 directory tracking, synchronised output and true colour all work, and shell integration for bash/zsh/fish/nushell is automatic. Three consequences beyond the swap. *The Windows adapter is gone*: EAT launches its child through `/usr/bin/env sh`, which native Windows cannot resolve, so the old module wrapped `make-process` and substituted MSYS2's `env.exe`; ghostel uses ConPTY directly and none of that is needed, leaving `SPC o m` a plain choice of MSYS2's bash. *The terminal chapter is its own chapter* (`34-terminal.org`), because the terminal is no longer a footnote to the platform; `kittymacs-msys2-root` and the spell-checker discovery moved into `30-platform.org`, where they were always platform questions. *The native module lives in `var/ghostel/`*, not the package directory, so `package-upgrade` cannot delete a library this Emacs has mapped; it is downloaded on the first `SPC o e`, never at startup.
- **The terminal is installed from its repository, not an archive** (2026-09-18). CI found both halves of this the hard way. MELPA's `ghostel` build is broken — the index advertises `ghostel-20260914.1114.tar` and the file answers 404 — and `consult-ghostel` has no MELPA recipe at all, so `:ensure t` could install neither. Both now use `:vc`, which is upstream's own documented method: an ordinary Git checkout under `var/elpa/`, about ten megabytes, cloned once and updated with `package-vc-upgrade`. Move them back to `:ensure t` when MELPA carries them. Everything else, Treemacs and its three extensions included, installs from MELPA normally.
- **Meow's states drive ghostel's input modes.** Terminals start in Insert, ghostel's semi-char mode forwards the keys, and `C-c` reaches Emacs, so `C-c C-SPC` still opens the leader. Leaving Insert freezes the terminal into copy mode (buffer-local `meow-insert-exit-hook`), which makes the whole scrollback an ordinary read-only buffer the selection grammar works on; entering Insert thaws it. The one ambiguous key is `ESC`, which a full-screen program needs and Meow also wants: `kittymacs-terminal-escape` defaults to `auto`, sending it to the program exactly while the alternate screen is active, with `SPC m ESC` to override per buffer. This is the same problem `evil-ghostel` solves for Evil; there is no `meow-ghostel`, so the bridge is ours. Implementing it means rebinding `<escape>` in `meow-insert-state-keymap`, the only map consulted before a terminal's own keys — outside a terminal the command is plain `meow-insert-exit`.
- **Which ghostel integrations are on.** Additive ones are on: Eshell's visual commands run in a terminal, `M-x shell` gets ghostel's VT parser (only when the native module is present, since the filter needs it and a machine that declined the download must still have a working shell), `ghostel:` Org links, bookmarks, desktop, input methods, `consult-ghostel` for picking terminals and completing the shell's own history, and `ghostel-project` in `project-switch-commands`. `ghostel-compile-global-mode` is *not*: it replaces `compilation-start` for `compile`, `recompile`, `project-compile` and every package built on them, and a silent global override of Emacs's own compile is more than "use the integration" should mean. `ghostel-compile` is on `SPC m t` instead and the global mode is one documented line in `private.el`.
- **Treemacs is the file-tree sidebar; `dired-sidebar` is dropped** (2026-09-18). The user asked for a tree showing the project they are in, which is `treemacs-project-follow-mode` exactly. Keeping two file-tree sidebars on one key would be worse than either. Dired keeps its job — marking, renaming, copying between directories — and the two are cross-linked. Treemacs is a *panel*, so it uses a side window and stays inside the frame, which is the same rule `imenu-list` and the old sidebar followed; `treemacs-is-never-other-window` matters more here than in most configurations, because a frame normally holds one buffer and the tree, and without it every "other window" lands in the sidebar. State goes under `var/`, since Treemacs otherwise writes `.cache/` beside `init.el`, which Git does not ignore. `treemacs-tab-bar` scopes a tree per workspace to match tabspaces; `treemacs-magit` exists because staging changes Git's index rather than the files, so filesystem watching alone would not notice; `treemacs-nerd-icons` matches the icon font the rest of the configuration already checks for.
- **Never add to a package's hook before the package has loaded** (2026-09-18). `:hook (git-commit-mode . flyspell-mode)` on a deferred Magit created `git-commit-mode-hook` hours before `git-commit.el` aliased it to `git-commit-setup-hook`; `defvaralias` discards the value it overwrites and warns while doing it. The spell checker it asked for never ran, and the warning displayed a buffer — which under frames-only mode is an *operating-system window*, so the first `SPC v s` of a session raised a `*Warnings*` window over the Magit window, which reads as the key having failed. Magit itself is defensive (`:get #'magit-hook-custom-get` merges a pre-set value with its defaults), so nothing of Magit's was lost; the rule still stands, and both the spelling and the Meow state now hang on `git-commit-setup-hook` inside `with-eval-after-load 'git-commit`.
- **Diagnostics stay inside the frame.** `*Warnings*`, `*Backtrace*` and the compilation logs are things Emacs says, not buffers you work in, so `display-buffer-alist` gives them a window at the bottom of the current frame. Without it any warning, from any package, becomes a focus-stealing OS window. This is the "frames mean full buffers, not panels" rule applied to the buffers Emacs raises on its own.
- **`magit-status` asks in a better order.** From a buffer with no file — the home page, a terminal, `*scratch*` — `default-directory` is wherever the buffer was born. When that is not a repository `magit-status` prompts, and offers to *create* one; declining leaves nothing on screen. `kittymacs-magit-status` tries this buffer's repository, then the current project's, and only then Magit's own prompt. The display function also gained `display-buffer-use-some-window` as a final fallback, because Magit selects whatever window it is handed and a `nil` there is an error, not a graceful degradation.
- **The default `major-mode` must be a symbol.** It was a lambda, so every buffer made by `get-buffer-create` carried a function object where Emacs expects a mode name — `get`, `symbol-name` and `derived-mode-parent` all assume a symbol. It is now the named `kittymacs-guess-major-mode`, which does the same thing.
- **The platform module may not declare a package.** `tests/kittymacs-platform-tests.el` loads it with no packages available, so `use-package … :ensure t` there would try to install at test time. The spell-checker discovery lives in the platform chapter because it is a property of the machine; its two front ends (`flyspell-correct`, `consult-flyspell`) are declared in the completion chapter.
- **Android is a platform branch, not a port** (2026-09-21). The Android build of Emacs reports `system-type` as `android`, so every `pcase` and `eq` in this configuration that named a platform fell through to its default: the shell became the compiled-in `/bin/sh`, which does not exist there; `exec-path-from-shell` was installed and *succeeded*, replacing `PATH` with what `/system/bin/sh` reports, which is a `PATH` without Termux; and `frames-only-mode` turned every Help buffer into an entry in the task switcher, because the port maps frames one-to-one onto activities. The chapter structure made the fix a section beside the macOS one rather than a module, for the same reason macOS is a section: it is a set of answers to *where does this machine keep things*. Four answers are the whole of it. **The shell** prefers Termux's `bash`, then Termux's `sh`, then `/system/bin/sh`, which unlike `/bin/sh` is always present, so the fallback is real rather than hopeful. **Termux is discovered, never assumed**: Android forbids one application from reading another's data directory unless the two share a user ID, so `kittymacs-termux-program` returns nil on an unpaired device and every dependent decision degrades; `LD_LIBRARY_PATH` is *cleared* rather than set, because Termux's programs record where their own libraries are and an inherited path interposes Android's system libraries of the same names. **The volume keys** are the port's only way to quit without a physical keyboard, so `kittymacs-android-volume-keys` defaults to leaving them alone and the option exists to be found rather than to be used. **Text conversion follows Meow's state**: Android input methods edit the buffer directly instead of sending key events, which is right in Insert state and destructive in every other, so the buffer-local style is suspended on leaving Insert and restored on entering it — through `set-text-conversion-style`, because assigning the variable only takes effect when the buffer is next selected, which is a whole state transition too late. Elsewhere: Dired lists with `ls-lisp` (Windows' branch) since every Android subprocess goes through an executable loader that traces its children, and the cheapest listing starts no process at all; `kittymacs-frames-only` and `kittymacs-terminal-ghostel` are options rather than hard-coded refusals. Zero packages were added and no existing platform's behaviour changed. Thirteen tests bind `system-type` to `android` exactly as the macOS tests bind `darwin`.
- **ghostel cannot follow to Android, and Eshell is the honest replacement** (2026-09-21). Ghostel is installed with `:vc`, so a first start clones it with `git`, which the Android port does not ship; and it is a native module, for which upstream publishes no `android-aarch64` build — and the port is commonly built with no dynamic module support at all, in which case `module-file-suffix` is nil and no module could load however it arrived. Two independent blockers, so `SPC o e` opens Eshell there: Lisp, no module, no subprocess to start, and it runs Termux's programs where Termux is paired. It is not a terminal and will not run `htop`; saying so is better than an error on every start.
- **nix-on-droid is a second device, not a layer under the first** (2026-09-21). Nix on Android was the obvious way to supply the Android port with `git`, `ripgrep` and the language servers, and it cannot work. A Nix store path exists only inside nix-on-droid's PRoot: every binary's ELF interpreter is baked in as `/nix/store/…-glibc/lib/ld-linux-aarch64.so.1`, which does not resolve on the real Android filesystem, so the kernel cannot start the program from outside the PRoot at all. Two further blockers stand behind that one — nix-on-droid is `com.termux.nix` while the shared-user-ID Emacs builds pair with `com.termux`, and Android 10 forbids executing anything in another application's data directory regardless. So there are two Android deployments and they are alternatives: the port with Termux, or an ordinary GNU/Linux Emacs inside nix-on-droid, where `system-type` is `gnu/linux` and no Android branch applies. The second needed no new Nix code — nix-on-droid consumes home-manager modules, so `homeManagerModules.default` *is* the integration — only `installFonts`, split from `installPackages` because a console-only Emacs has no use for the icon font, and `nix/example-nix-on-droid/flake.nix`, which CI evaluates against the checkout exactly as it evaluates the nix-darwin host. CI evaluates the *package list the module produces*, not the activation package: nix-on-droid cannot build proot-static on a phone, so it hardcodes the store path of a pre-built one and reaches it through `builtins.storePath`, which pure evaluation forbids — every flake-based `nix-on-droid switch` needs `--impure`. Evaluating the package list keeps the check pure and aims it at what this repository actually contributes, which is what the nix-darwin check does too.
- **Ispell is told its dictionary before it is asked for one** (2026-09-21). The platform chapter set `ispell-program-name` with `setopt` and only then set `DICTIONARY`; the option's setter asks Hunspell to list its dictionaries, Hunspell cannot without a default name, and the resulting error aborted the load of Ispell itself. Emacs restores a library's autoload stubs when its load fails, so Ispell never counted as loaded: Flyspell silently stayed off, and every Corfu auto-completion in a text-mode buffer reloaded Ispell, spawned Hunspell, failed, and logged a backtrace, a measured 250 ms stall per word. The environment is now set first and the whole configuration is guarded, so a broken checker reports once and Ispell stays loaded.
- **Text-mode dictionary completion is off** (2026-09-21). Emacs 30 adds `ispell-completion-at-point` to every text-mode buffer. With `corfu-auto` it runs a few times per word, and on Windows there is no plain word list for it to read, so each run only costs a process and an error. `SPC c p w` (`cape-dict`) is the explicit version.
- **Git for Windows' Unix tools go last on `exec-path`** (2026-09-21). Magit's hunk refinement, Ediff and diff-hl call `diff`, `diff3` and `patch` by name; Windows has none, so refinement raised an error in Magit's post-command hook. The platform policy appends Git's `usr/bin` (or MSYS2's) after every other entry, so native programs keep winning, and it leaves `PATH` alone, so subprocesses see no change.
- **Licence is GPL-3.0-or-later**, matching the sources the code is distilled from; the old MIT file from Colin's tooling is replaced.
- **Kept from Lambda**, attributed per module header: sane defaults, scrolling and mouse settings, persistent scratch, the completion stack configuration, Helpful/Info setup, Dired extensions, Magit settings, project/tab/workspace setup with workspace-filtered buffers, Org display and agenda defaults, programming aids, Eshell settings and aliases, Tramp, the highlighting packages. Lambda's EAT setup is gone with EAT.

## 5. Verification

Batch, from the repository root (`EMACS_DOTS_TEST_PACKAGES` points at an existing `var/elpa`):

```sh
emacs -Q --batch -l tools/tangle.el -- --check
emacs -Q --batch -l tests/tangle-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -l tests/verify-config.el
```

All five pass at every commit on this branch, and `.github/workflows/ci.yml` runs them on GitHub for every push and pull request: the tangle check and the platform tests on Emacs 31.1, and a fresh clone that installs its packages by starting `init.el` in batch, then the leader tests and the verifier, on Emacs 30.1 and 31.1 (Linux) with informational Windows and macOS jobs; a Nix job runs `nix flake check` and evaluates the nix-darwin and nix-on-droid examples against the checkout; a weekly run skips the package cache. The verifier starts the real configuration in an isolated copy with installation forbidden and asserts: `private.el` loads once and its overrides survive, `custom.el` loads from `var/etc`, every module feature is present, `SPC` is `kittymacs-leader-map` in both Meow state maps, `SPC l` and `SPC s l` owners, the dashboard's two buttons open the guide and the cheat sheet, theme toggling never stacks themes, and every cheat-sheet `SPC` row resolves to its command.

Not verified here, for the user to check on the real host:

- A graphical startup and the five frame tests (`M-x ert RET ^dots-frames- RET`).
- First start on a fresh clone (package installation path).
- Emacs 30.1: the stated floor; only 31.1 exists on this machine.
- macOS on a real Mac: the modifier keys, the Trash, the title bar and the Dock-launched `PATH`. The platform tests cover the branches with `system-type` bound to `darwin`; the informational macOS CI job covers batch startup; `darwin-rebuild switch` with the module has been evaluated on Linux but not built.
- Android on a real device. The platform tests cover every branch with `system-type` bound to `android`, and they are the only coverage there is: no CI runner is an Android telephone. Specifically unverified, in rough order of how likely they are to want adjusting — whether a paired Termux's `bash` starts cleanly through the executable loader; whether `set-text-conversion-style` on each Meow state transition is quick enough to be invisible with a particular on-screen keyboard (its own documentation warns that resetting an input method is not cheap, which is why `kittymacs-android-modal-text-conversion` exists); whether the port in use has dynamic module support at all, which decides nothing here but would be worth knowing; and how the default 14-point font reads at phone density. `nix-on-droid switch` has been evaluated on Linux but not applied to a device.

## 6. Open items

- `main` carries the physical-hint adapter (PR #4). This branch removes it; merging makes the literal leader the deployed behaviour.
- Installed packages that nothing declares any more remain in `var/elpa/` (for example `kind-icon`, `peep-dired`, `svg-tag-mode`, `lambda-themes`, the macOS, mail, notes, citation and LLM packages). Prune with `M-x package-autoremove` when convenient.
- Beacon state is untouched by the leader (as intended); `SPC` in Beacon is Meow's default.
- ghostel's native module is downloaded on first use, so the first `SPC o e` on a
  new machine needs the network; `M-x ghostel-module-compile` builds it instead
  with Zig 0.16.0. Neither path was exercised here, because this container
  cannot reach GitHub releases: the terminal was verified up to the point where
  it asks, and declining now reports what is missing instead of a void function.
- `treemacs-git-mode` runs `deferred` where `python3` exists and `simple`
  otherwise; only the `simple` path ran here.
- `kittymacs-leader-alt-key` is fixed at `C-c C-SPC` in the keys chapter; make it an option if it ever needs to change.

## 7. Extending

- **A key:** `(keymap-set kittymacs-leader-map "u x" #'my-command)` in `private.el`, or a group in `42-keys.org`. Labels: `(cons "label" #'command)`.
- **A mode menu:** `(kittymacs-define-localleader 'python-mode "r" (cons "run" #'python-shell-send-buffer))` next to the package.
- **A package:** a chapter with a `use-package … :ensure t` block, a Meow section, a manifest entry and a `require` in the startup chapter.

## 8. Refactor log

All on branch `dev/kittymacs-config-review-dc1bee`, each commit verified with the four batch checks.

| Commit | Step |
|---|---|
| `c0e7c97` | Delete the prototype core, GUI runner, unloaded Lambda modules and the process layer (−22,383 lines) |
| `cad3cf4` | Literal leader and localleaders (`41-leader.org`); hint adapter retired; editing chapter rewritten |
| `fc58c61` | Defaults chapter replaces eight Lambda modules |
| `81bb5f5` | Completion and help chapters; `embark-consult` installed; one Corfu formatter |
| `ddb2723` | Dired, VC and navigation chapters; Magit and Dired in Motion with localleaders |
| `6c694a4` | Shells, Org and programming chapters |
| `6bca85f` | Appearance chapter merges fonts, theme, mode line and faces |
| `8785b63` | Keys chapter owns the whole tree; Lambda's last modules gone |
| `0eea287` | Own 86-line startup replaces Lambda's bootstrap and the composition root |
| `210f91a` | `lisp/` and `kittymacs-*` names throughout |
| `cd0127a` | Sidebars restored and `diff-hl` gutter added after the user clarified that frames apply to full buffers, not panels |
| `5e60d4a` | Org polish, avy, meow-tree-sitter, vundo, keycast, Casual menus, spelling wiring, GPL-3.0-or-later licence |
| `d40cf20` | Gpg4win first on `exec-path` so GNU ELPA signatures verify on Windows |
| (this branch) | macOS section of the platform chapter, `SPC f o`, platform tests, Nix flake with nix-darwin and home-manager modules |
| (this branch) | Meow expansion hints coloured from the theme (`meow-use-dynamic-face-color` at its default) |
| (this branch) | ghostel replaces EAT in a new `34-terminal.org`; MSYS2 root and spelling move to the platform chapter |
| (this branch) | `65-treemacs.org` adds the project tree and retires `dired-sidebar` |
| (this branch) | Magit's commit hooks wait for `git-commit`; diagnostics stay inside the frame; `magit-status` prefers the project |

## Scoped linked notes (2026-09-22)

Org-roam loads after Org and before frames, with its package declaration in
`71-org-roam.org`. A graph is the upstream `org-roam-directory` /
`org-roam-db-location` pair. There is no graph registry, custom schema, project
loader or architecture inventory. Physical roots are canonicalized; the default
DB filename hashes that identity under `kittymacs-cache-dir/org-roam`. Aliases
share a cache, distinct worktrees do not. A supplied external DB remains valid;
all buffers for one root must use the same DB because upstream keys connections
by root. Directory locals should set both variables for persistent project scope.

A small scoped-call adapter binds both the originating buffer's variables and
non-local defaults. Binding only buffer-local values failed real SQLite tests:
Org-roam parses in temporary buffers, which otherwise see the personal root.
Commands retain their originating scope and insert position through completion.
Project find/insert require existing nodes; explicit capture displays its root.
Capture saves the pair on its target, indirect buffer and capture plist; an
around-finalize binding protects callbacks after Org changes buffers. Resolved
capture paths are checked before Org writes headers. Upstream panel refresh
reinitializes its major mode, so a permanent panel scope is restored by its mode
hook before backlink queries. The panel uses a side window and Meow Motion;
editing nodes use upstream `org-roam-node-open` and the existing frame policy.

Native SQLite is mandatory for graph operations but not startup. No startup DB
sync or global autosync: enabling upstream autosync itself rebuilds the graph.
Scoped note saves update only their graph; explicit sync covers external edits,
renames and deletions. Sync adds IDs to Org's global ID location index without
importing destination nodes into other graph databases. Destination directory
locals establish scope across sessions; existing upstream connection roots also
identify graphs already used during this session. Default membership excludes
legacy, Git, secrets and cache folders, plus out-of-root symlinks.

Verification includes real Org-roam/SQLite indexing, links, capture finalization,
completion buffer switches, panel rerender, independent global ID navigation,
physical alias identity and missing SQLite degradation. Native Windows junction
and GUI frame behavior require host validation beyond the Linux batch fixture.

### Org-roam review fixes (2026-09-22)

Canonical connection identity also applies at the upstream DB boundary, so
ordinary Org ID lookups and raw package queries cannot reopen a personal alias
as a second connection. ID results refresh the destination scope even when its
buffer predates the graph connection; explicitly established local root/DB pairs
are retained. Membership checks canonicalize both file and root because upstream
only folds Windows drive letters, while Emacs restores the filename's actual
case on visiting it. Capture validates the nearest existing writable parent and
creates permitted intermediate directories before Org opens the target; excluded
and out-of-root directories remain untouched. Real tests cover capture followed
by sync retaining one node, one physical file record and one root connection.
