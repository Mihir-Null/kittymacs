;;; init.el --- kittymacs -*- lexical-binding: t; -*-
;; Generated from literate/10-startup.org; edit the Org source, then tangle.

;;; Code:

(when (< emacs-major-version 31)
  (error "kittymacs needs Emacs 31.1 or later; this is Emacs %s" emacs-version))
(kittymacs-activate-packages)
(add-to-list 'load-path kittymacs-lisp-dir)
(require 'use-package)
(setopt use-package-enable-imenu-support t)

(defvar kittymacs--archives-refreshed nil
  "Non-nil once this session has refreshed the archive index, or tried to.")

(defun kittymacs-ensure-package (name args state &optional no-refresh)
  "Install the package that `use-package' NAME's `:ensure' ARGS names.
The `use-package-ensure-function' of kittymacs.  Before the session's
first install it refreshes the cached archive index, whose tarballs may
be gone; then `use-package-ensure-elpa' installs.  STATE and NO-REFRESH
are passed through.  A package the installer already failed on is left
alone, since it warned once.  A start from the quickstart file knows only
what that file activated, so it reads the package directories before it
believes that a package is missing."
  (unless (memq name (bound-and-true-p kittymacs-features--failed))
    (let ((installed-p
           (lambda ()
             (seq-every-p (lambda (ensure)
                            (let ((package (if (eq ensure t) (use-package-as-symbol name) ensure)))
                              (or (null package)
                                  (package-installed-p (if (consp package) (car package) package)))))
                          args))))
      (unless (or kittymacs--archives-refreshed
                  (funcall installed-p)
                  (and (bound-and-true-p kittymacs-quickstart-loaded)
                       (not (bound-and-true-p package--initialized))
                       (progn (package-initialize t)
                              (funcall installed-p))))
        (setq kittymacs--archives-refreshed t)
        (condition-case-unless-debug err
            (package-refresh-contents)
          (error
           (display-warning 'kittymacs
                            (format "Could not refresh the package archives: %s
Installing from the cached index, which may name tarballs that are gone."
                                    (error-message-string err))
                            :warning)))))
    (use-package-ensure-elpa name args state no-refresh)))

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

(when (kittymacs-quickstart--written)
  (kittymacs-after-init #'kittymacs-quickstart--keep-current 99))

(defun kittymacs-load-user-file (file)
  "Load FILE, which a host or the user wrote; on an error, warn and carry on.
Under `--debug-init' the error is not caught, so it shows a backtrace."
  (condition-case-unless-debug err
      (load file nil t t)
    (error
     (display-warning 'kittymacs
                      (format "%s did not finish loading: %s
The rest of kittymacs still loads; `--debug-init' shows the backtrace."
                              file (error-message-string err))
                      :error))))

(defvar kittymacs-host-directories
  (list "/etc/kittymacs/conf.d/"
        (expand-file-name "kittymacs/conf.d/" (or (getenv "XDG_CONFIG_HOME") "~/.config")))
  "Directories whose `*.el' files configure this machine, read in this order.
Set before init.el loads to change them, because they are read during init.")

(defun kittymacs-load-host-files ()
  "Load every `*.el' file in `kittymacs-host-directories', in name order."
  (dolist (directory kittymacs-host-directories)
    (when (file-directory-p directory)
      (mapc #'kittymacs-load-user-file
            (directory-files directory t "\\`[^.#].*\\.el\\'")))))

;; Foundation: the feature list, defaults, platform paths, host and machine
;; overrides, what they selected, then the look.
(require 'kittymacs-catalogue)
(require 'kittymacs-features)
(require 'kittymacs-defaults)
(require 'kittymacs-platform)
(kittymacs-load-host-files)
(let ((private (expand-file-name "private.el" kittymacs-lisp-dir)))
  (when (file-exists-p private)
    (kittymacs-load-user-file private)))
(kittymacs-features-resolve)
(kittymacs-features-install)
(when (kittymacs-quickstart--wanted-p)
  (kittymacs-after-init #'kittymacs-quickstart--settle-when-idle 99))
(kittymacs-platform-apply)
(kittymacs-require-module 'kittymacs-basics)
(kittymacs-require-module 'kittymacs-ui)
(when (kittymacs-feature-p 'smooth-scroll)
  (kittymacs-require-module 'kittymacs-smooth-scroll))
(kittymacs-require-module 'kittymacs-literate)
(when (kittymacs-feature-p 'home-page)
  (kittymacs-require-module 'kittymacs-dashboard))

;; Editing: completion, help, files, git, navigation, then Meow and the leader.
(kittymacs-require-module 'kittymacs-completion)
(kittymacs-require-module 'kittymacs-help)
(kittymacs-require-module 'kittymacs-dired)
(when (kittymacs-feature-p 'file-tree)
  (kittymacs-require-module 'kittymacs-treemacs))
(kittymacs-require-module 'kittymacs-vc)
(kittymacs-require-module 'kittymacs-navigation)
(when (kittymacs-feature-p 'buffer-tabs)
  (kittymacs-require-module 'kittymacs-buffer-tabs))
(kittymacs-require-module 'kittymacs-meow)
(when (kittymacs-feature-p 'meow-state-cursor)
  (kittymacs-require-module 'kittymacs-meow-state-cursor))
(kittymacs-require-module 'kittymacs-keys)
(when (kittymacs-feature-p 'which-key-frame)
  (kittymacs-require-module 'kittymacs-which-key-frame))

;; Applications: shells, programming, Org, reading, notebooks, agents, suggestions,
;; then the window manager, and finally frame policy, which reads it.
(kittymacs-require-module 'kittymacs-shell)
(kittymacs-require-module 'kittymacs-remote)
(kittymacs-require-module 'kittymacs-programming)
(kittymacs-require-module 'kittymacs-treesit)
(kittymacs-require-module 'kittymacs-languages)
(when (kittymacs-feature-p 'hover-docs)
  (kittymacs-require-module 'kittymacs-hover-docs))
(kittymacs-require-module 'kittymacs-terminal)
(when (kittymacs-feature-p 'msys2-fallback)
  (kittymacs-require-module 'kittymacs-msys2))
(when (kittymacs-feature-p 'wsl-rpc)
  (kittymacs-require-module 'kittymacs-remote-rpc))
(kittymacs-require-module 'kittymacs-org)
(when (kittymacs-feature-p 'org-extras)
  (kittymacs-require-module 'kittymacs-org-extras))
(when (kittymacs-feature-p 'linked-notes)
  (kittymacs-require-module 'kittymacs-org-roam))
(when (kittymacs-feature-p 'pdf-reading)
  (kittymacs-require-module 'kittymacs-reading))
(when (kittymacs-feature-p 'notebooks)
  (kittymacs-require-module 'kittymacs-notebooks))
(when (kittymacs-feature-p 'agents)
  (kittymacs-require-module 'kittymacs-agents))
(when (kittymacs-feature-p 'suggestions)
  (kittymacs-require-module 'kittymacs-suggestions))
(kittymacs-require-module 'kittymacs-exwm)
(kittymacs-require-module 'kittymacs-frames)
(kittymacs-after-init #'kittymacs-leader-drop-empty-groups 100)

;; Settings saved by M-x customize come last, so they override the chapters.
(load custom-file 'noerror 'nomessage)

;;; init.el ends here
