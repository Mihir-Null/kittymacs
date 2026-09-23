;;; private.example.el --- Example local overrides -*- lexical-binding: t; -*-
;; Generated from literate/80-maintenance.org; edit the Org source, then tangle.

;; Copy to private.el for account/machine-specific values that should not be committed.
;; init.el loads private.el after the portable platform variables are defined and
;; before the later UI/programming modules consume their policy variables.

;; Identity
;; (setq user-full-name "Your Name"
;;       user-mail-address "you@example.com")

;; Paths
;; These variables are already defined when private.el is loaded, so `setopt' is useful.
;; (setopt kittymacs-project-directory (expand-file-name "~/src/"))
;; (setopt kittymacs-org-directory (expand-file-name "~/Documents/my-org/"))

;; Linked notes: prebind these before the Org-roam chapter loads.
;; (setq kittymacs-org-roam-directory (expand-file-name "~/notes/"))
;; (setq kittymacs-org-roam-excluded-directories
;;       '("legacy" ".git" "secrets" "cache" "caches" ".cache" "var"))
;; For a project, establish buffer-local org-roam-directory and
;; org-roam-db-location; compute the latter with kittymacs-org-roam-db-path.
;; The database must stay outside the graph. See literate/71-org-roam.org.

;; Terminal
;; MSYS2's location, when it is not the normal C:/msys64/.  The platform
;; chapter defines this before private.el loads, so `setopt' works.
;; (setopt kittymacs-msys2-root "D:/Tools/msys64/")
;;
;; Which shell the terminal runs, and where the escape key goes while a
;; full-screen program is drawing (`auto', `terminal' or `meow').
;; (setopt ghostel-shell '("/bin/zsh" "--login"))
;; (setopt kittymacs-terminal-escape 'terminal)
;;
;; Let programs in the terminal write the system clipboard (OSC 52).  Handy
;; over SSH; it also lets anything you `cat' set your clipboard.
;; (setopt ghostel-enable-osc52 t)
;;
;; Route every `compile', `recompile' and `project-compile' through a real
;; terminal instead of Emacs's own compilation buffer.
;; (with-eval-after-load 'ghostel (ghostel-compile-global-mode 1))

;; macOS
;; Modifier keys are applied after this file loads, so `setopt' works here.
;; Swap Command and Option, or give the right Option key to Emacs too:
;; (setopt kittymacs-macos-modifiers '((ns-command-modifier . meta)
;;                                   (ns-option-modifier . super)
;;                                   (ns-right-option-modifier . meta)))

;; Language tooling
;; Eglot is available manually through SPC l e. Automatic startup and external
;; language packages are opt-in because their servers/runtimes are platform-owned.
;; (setq kittymacs-eglot-auto-start-modes '(python-mode python-ts-mode)
;;       kittymacs-language-packages '(nix racket guile))
;; UI
;; `kittymacs-ui' is loaded later, so use `setq' here; its `defcustom' forms will
;; preserve these pre-bound values.
;; (setq kittymacs-theme 'doom-dark+
;;       kittymacs-light-theme 'doom-one-light
;;       kittymacs-font-family "GoogleSansCode Nerd Font"
;;       kittymacs-icons 'auto
;;       kittymacs-nerd-font "Symbols Nerd Font Mono")

;; The primary programming font and the dedicated Nerd Icons symbol font are kept
;; separate. `kittymacs-font-family' changes only the default face family, preserving
;; the platform's existing point size. If the family is absent, the starter keeps the
;; platform default rather than failing startup.
