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
;; Project commands
;; A project with a justfile needs nothing here: SPC p j lists its recipes.
;; Name a wrapper when the binary is not on PATH -- a Nix development shell, or
;; WSL.  `kittymacs-programming' loads later, so `setq' is the form to use.
;; (setq kittymacs-just-program "/home/you/.nix-profile/bin/just")
;;
;; To give one project commands under their own names, define a minor mode for
;; it and name that mode in each command's `interactive' form.  M-x then offers
;; them only where the mode is on; the completion chapter explains why.
;; (define-minor-mode my-project-mode
;;   "Commands for one project."
;;   :lighter " Proj")
;;
;; (defun my-project-switch ()
;;   "Deploy this project.  Runs in a terminal so sudo can prompt."
;;   (interactive nil my-project-mode)
;;   (kittymacs-just "switch" t))
;;
;; Switch the mode on from the project's own .dir-locals.el, so the knowledge
;; travels with the repository instead of living on this machine:
;;   ((nil . ((mode . my-project))))
