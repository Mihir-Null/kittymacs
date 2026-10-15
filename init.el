;;; init.el --- kittymacs -*- lexical-binding: t; -*-
;; Generated from literate/10-startup.org; edit the Org source, then tangle.

;;; Code:

(when (< emacs-major-version 31)
  (error "kittymacs needs Emacs 31.1 or later; this is Emacs %s" emacs-version))
(add-to-list 'load-path kittymacs-lisp-dir)
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))
(require 'use-package)
(setopt use-package-enable-imenu-support t)

(defun kittymacs-require-module (feature)
  "Load the kittymacs module FEATURE; on an error, warn and carry on.
Under `--debug-init' the error is not caught, so it shows a backtrace."
  (condition-case-unless-debug err
      (require feature)
    (error
     (display-warning 'kittymacs
                      (format "%s did not finish loading: %s
The chapters after it still load; `--debug-init' shows the backtrace."
                              feature (error-message-string err))
                      :error))))

;; Foundation: defaults, platform paths, machine overrides, the look.
(require 'kittymacs-defaults)
(require 'kittymacs-platform)
(let ((private (expand-file-name "private.el" kittymacs-lisp-dir)))
  (when (file-exists-p private)
    (load private nil t)))
(kittymacs-platform-apply)
(kittymacs-require-module 'kittymacs-ui)
(kittymacs-require-module 'kittymacs-literate)
(kittymacs-require-module 'kittymacs-dashboard)

;; Editing: completion, help, files, git, navigation, then Meow and the leader.
(kittymacs-require-module 'kittymacs-completion)
(kittymacs-require-module 'kittymacs-help)
(kittymacs-require-module 'kittymacs-dired)
(kittymacs-require-module 'kittymacs-treemacs)
(kittymacs-require-module 'kittymacs-vc)
(kittymacs-require-module 'kittymacs-navigation)
(kittymacs-require-module 'kittymacs-meow)
(kittymacs-require-module 'kittymacs-keys)

;; Applications: shells, programming, Org, reading, agents, suggestions, and finally frame policy.
(kittymacs-require-module 'kittymacs-shell)
(kittymacs-require-module 'kittymacs-programming)
(kittymacs-require-module 'kittymacs-treesit)
(kittymacs-require-module 'kittymacs-languages)
(kittymacs-require-module 'kittymacs-terminal)
(kittymacs-require-module 'kittymacs-org)
(kittymacs-require-module 'kittymacs-org-node)
(kittymacs-require-module 'kittymacs-reading)
(kittymacs-require-module 'kittymacs-agents)
(kittymacs-require-module 'kittymacs-suggestions)
(kittymacs-require-module 'kittymacs-frames)

;; Settings saved by M-x customize come last, so they override the chapters.
(load custom-file 'noerror 'nomessage)

;;; init.el ends here
