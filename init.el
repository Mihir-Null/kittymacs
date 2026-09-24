;;; init.el --- kittymacs -*- lexical-binding: t; -*-
;; Generated from literate/10-startup.org; edit the Org source, then tangle.

;;; Code:

(add-to-list 'load-path kittymacs-lisp-dir)
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))
(require 'use-package)
(setopt use-package-enable-imenu-support t)

;; Foundation: defaults, platform paths, machine overrides, the look.
(require 'kittymacs-defaults)
(require 'kittymacs-platform)
(let ((private (expand-file-name "private.el" kittymacs-lisp-dir)))
  (when (file-exists-p private)
    (load private nil t)))
(kittymacs-platform-apply)
(require 'kittymacs-ui)
(require 'kittymacs-literate)
(require 'kittymacs-dashboard)

;; Editing: completion, help, files, git, navigation, then Meow and the leader.
(require 'kittymacs-completion)
(require 'kittymacs-help)
(require 'kittymacs-dired)
(require 'kittymacs-treemacs)
(require 'kittymacs-vc)
(require 'kittymacs-navigation)
(require 'kittymacs-meow)
(require 'kittymacs-keys)

;; Applications: shells, programming, Org, and finally frame policy.
(require 'kittymacs-shell)
(require 'kittymacs-programming)
(require 'kittymacs-treesit)
(require 'kittymacs-languages)
(require 'kittymacs-terminal)
(require 'kittymacs-org)
(require 'kittymacs-org-roam)
(require 'kittymacs-frames)

;; Settings saved by M-x customize come last, so they override the chapters.
(load custom-file 'noerror 'nomessage)

;;; init.el ends here
