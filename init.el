;;; init.el --- kittymacs -*- lexical-binding: t; -*-
;; Generated from literate/10-startup.org; edit the Org source, then tangle.

;;; Code:

(when (< emacs-major-version 31)
  (error "kittymacs needs Emacs 31.1 or later; this is Emacs %s" emacs-version))
(add-to-list 'load-path kittymacs-lisp-dir)
(package-initialize)
(require 'use-package)
(setopt use-package-enable-imenu-support t)

(defvar kittymacs--archives-refreshed nil
  "Non-nil once this session has refreshed the archive index, or tried to.")

(defun kittymacs-ensure-package (name args state &optional no-refresh)
  "Install the package that `use-package' NAME's `:ensure' ARGS names.
The `use-package-ensure-function' of kittymacs.  Before the session's
first install it refreshes the cached archive index, whose tarballs may
be gone; then `use-package-ensure-elpa' installs.  STATE and NO-REFRESH
are passed through."
  (unless (or kittymacs--archives-refreshed
              (seq-every-p (lambda (ensure)
                             (let ((package (if (eq ensure t) (use-package-as-symbol name) ensure)))
                               (or (null package)
                                   (package-installed-p (if (consp package) (car package) package)))))
                           args))
    (setq kittymacs--archives-refreshed t)
    (condition-case-unless-debug err
        (package-refresh-contents)
      (error
       (display-warning 'kittymacs
                        (format "Could not refresh the package archives: %s
Installing from the cached index, which may name tarballs that are gone."
                                (error-message-string err))
                        :warning))))
  (use-package-ensure-elpa name args state no-refresh))

(setopt use-package-ensure-function #'kittymacs-ensure-package)

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

(defun kittymacs-after-init (function &optional depth)
  "Call FUNCTION from `after-init-hook' at DEPTH; on an error, warn and carry on.
FUNCTION is skipped, with a warning, when nothing has defined it by then:
its package failed to install.  Under `--debug-init' an error is not
caught, so it shows a backtrace."
  (add-hook 'after-init-hook
            (lambda ()
              (if (not (fboundp function))
                  (display-warning 'kittymacs
                                   (format "%s is not defined, so it was not called after init; did its package install?"
                                           function)
                                   :error)
                (condition-case-unless-debug err
                    (funcall function)
                  (error
                   (display-warning 'kittymacs
                                    (format "%s failed after init: %s"
                                            function (error-message-string err))
                                    :error)))))
            depth))

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

;; Applications: shells, programming, Org, reading, notebooks, agents, suggestions, and finally frame policy.
(kittymacs-require-module 'kittymacs-shell)
(kittymacs-require-module 'kittymacs-programming)
(kittymacs-require-module 'kittymacs-treesit)
(kittymacs-require-module 'kittymacs-languages)
(kittymacs-require-module 'kittymacs-terminal)
(kittymacs-require-module 'kittymacs-org)
(kittymacs-require-module 'kittymacs-org-node)
(kittymacs-require-module 'kittymacs-reading)
(kittymacs-require-module 'kittymacs-notebooks)
(kittymacs-require-module 'kittymacs-agents)
(kittymacs-require-module 'kittymacs-suggestions)
(kittymacs-require-module 'kittymacs-frames)

;; Settings saved by M-x customize come last, so they override the chapters.
(load custom-file 'noerror 'nomessage)

;;; init.el ends here
