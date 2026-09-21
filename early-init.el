;;; early-init.el --- Before the first frame -*- lexical-binding: t; -*-
;; Generated from literate/10-startup.org; edit the Org source, then tangle.

;;; Code:

(defvar kittymacs-lisp-dir (expand-file-name "lisp/" user-emacs-directory)
  "Directory of the generated configuration modules.")

(defvar kittymacs-var-dir (expand-file-name "var/" user-emacs-directory)
  "Directory for everything Emacs writes on its own.  Ignored by Git.")

(defvar kittymacs-cache-dir (expand-file-name "cache/" kittymacs-var-dir)
  "Directory for caches that can be deleted at any time.")

(defvar kittymacs-etc-dir (expand-file-name "etc/" kittymacs-var-dir)
  "Directory for state worth keeping: saved customizations, shell history.")

(setq package-user-dir (expand-file-name "elpa/" kittymacs-var-dir)
      package-gnupghome-dir (expand-file-name "gnupg/" package-user-dir)
      package-enable-at-startup nil)
(setopt package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                           ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                           ("melpa" . "https://melpa.org/packages/")))
;; An Emacs.app started from the Dock inherits no shell PATH, so the gpg,
;; git and language servers that Nix or Homebrew installed are invisible
;; until the shells chapter imports the login environment.  Put those
;; directories on `exec-path' now (later entries win) so the archive check
;; below can find gpg.  The title bar is made transparent here, before the
;; first frame; the platform chapter gives it the theme's appearance.
(when (eq system-type 'darwin)
  (dolist (directory (list "/usr/local/bin"
                           "/opt/homebrew/bin"
                           "/nix/var/nix/profiles/default/bin"
                           (expand-file-name "~/.nix-profile/bin")
                           (concat "/etc/profiles/per-user/" (user-login-name) "/bin")
                           "/run/current-system/sw/bin"))
    (when (and (file-directory-p directory) (not (member directory exec-path)))
      (push directory exec-path)))
  (push '(ns-transparent-titlebar . t) default-frame-alist))

;; GNU ELPA signs its archive index and Emacs verifies it with the first
;; gpg on `exec-path'.  On Windows that is Git for Windows' MSYS gpg, which
;; cannot open a Windows keyring directory: every signature then fails and
;; the archives silently vanish.  Put Gpg4win's native gpg first when it is
;; installed; without one, skip the check rather than lose the archives.
(let ((gpg4win (or (and (file-directory-p "C:/Program Files/GnuPG/bin") "C:/Program Files/GnuPG/bin")
                   (and (file-directory-p "C:/Program Files (x86)/GnuPG/bin") "C:/Program Files (x86)/GnuPG/bin"))))
  (cond (gpg4win (push gpg4win exec-path))
        ((or (eq system-type 'windows-nt) (not (executable-find "gpg")))
         (setq package-check-signature nil))))

(when (featurep 'native-compile)
  (startup-redirect-eln-cache (expand-file-name "eln-cache/" kittymacs-cache-dir))
  (setopt native-comp-async-report-warnings-errors 'silent))

(setq gc-cons-threshold most-positive-fixnum)
(add-hook 'emacs-startup-hook (lambda () (setq gc-cons-threshold (* 64 1024 1024))))

(setopt frame-inhibit-implied-resize t
        inhibit-startup-screen t
        initial-scratch-message nil
        load-prefer-newer t)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

(when (eq system-type 'windows-nt)
  (setq w32-get-true-file-attributes nil
        inhibit-compacting-font-caches t))

;;; early-init.el ends here
