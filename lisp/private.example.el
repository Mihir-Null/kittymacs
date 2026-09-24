;;; private.example.el --- Example local overrides -*- lexical-binding: t; -*-
;; Generated from literate/80-maintenance.org; edit the Org source, then tangle.

;; Copy to private.el for account and machine settings that should not be
;; committed.  init.el loads private.el early, before most chapters, because
;; they read the kittymacs options below while they load.  Set those at top
;; level with `setopt'.  A package option that a chapter also sets must go in
;; the `after-init-hook' function at the end of this file instead: the chapter
;; runs after this file and would replace a top-level value.

;; Identity
;; (setq user-full-name "Your Name"
;;       user-mail-address "you@example.com")

;; Paths
;; (setopt kittymacs-project-directory (expand-file-name "~/src/"))
;; (setopt kittymacs-org-directory (expand-file-name "~/Documents/my-org/"))

;; Linked notes, read when the Org-roam chapter loads.
;; (setopt kittymacs-org-roam-directory (expand-file-name "~/notes/"))
;; (setopt kittymacs-org-roam-excluded-directories
;;         '("legacy" ".git" "secrets" "cache" "caches" ".cache" "var"))
;; For a project, establish buffer-local org-roam-directory and
;; org-roam-db-location; compute the latter with kittymacs-org-roam-db-path.
;; The database must stay outside the graph. See literate/71-org-roam.org.

;; Terminal
;; MSYS2's location, when it is not the normal C:/msys64/.
;; (setopt kittymacs-msys2-root "D:/Tools/msys64/")
;;
;; Where the escape key goes while a full-screen program is drawing in the
;; terminal (`auto', `terminal' or `meow').
;; (setopt kittymacs-terminal-escape 'terminal)

;; macOS
;; Swap Command and Option, or give the right Option key to Emacs too:
;; (setopt kittymacs-macos-modifiers '((ns-command-modifier . meta)
;;                                     (ns-option-modifier . super)
;;                                     (ns-right-option-modifier . meta)))

;; Language tooling
;; Eglot is available manually through SPC l e.  Automatic startup and
;; external language packages are opt-in because their servers and runtimes
;; belong to the platform.
;; (setopt kittymacs-eglot-auto-start-modes '(python-mode python-ts-mode)
;;         kittymacs-language-packages '(nix racket guile))

;; UI
;; (setopt kittymacs-theme 'doom-dark+
;;         kittymacs-light-theme 'doom-one-light
;;         kittymacs-font-family "GoogleSansCode Nerd Font"
;;         kittymacs-icons 'auto
;;         kittymacs-nerd-font "Symbols Nerd Font Mono")

;; Package options that a chapter also sets.  Depth 90 runs this after the
;; chapters' own after-init functions.
;; (add-hook 'after-init-hook
;;           (lambda ()
;;             ;; Let programs in the terminal write the system clipboard
;;             ;; (OSC 52).  Handy over SSH; it also lets anything you `cat'
;;             ;; set your clipboard.
;;             (setopt ghostel-enable-osc52 t)
;;             ;; Route `compile', `recompile' and `project-compile' through
;;             ;; a real terminal instead of Emacs's compilation buffer.
;;             (ghostel-compile-global-mode 1)
;;             ;; Set when ghostel loads, so wait for it.
;;             (with-eval-after-load 'ghostel
;;               (setopt ghostel-shell '("/bin/zsh" "--login"))))
;;           90)
