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

;; `setq', not `setopt', throughout this file: `setopt' would load Customize
;; and, for the package options, package.el with url and EIEIO, all before
;; the first frame is drawn.  See the startup chapter.
(setq package-user-dir (expand-file-name "elpa/" kittymacs-var-dir)
      package-gnupghome-dir (expand-file-name "gnupg/" package-user-dir)
      package-enable-at-startup nil
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/")
                         ("melpa" . "https://melpa.org/packages/")
                         ("melpa-stable" . "https://stable.melpa.org/packages/")))
;; An Emacs.app started from the Dock inherits no shell PATH, so the gpg,
;; git and language servers that Nix or Homebrew installed are invisible
;; until the shells chapter imports the login environment.  Put those
;; directories on `exec-path' now (later entries win) so the archive check
;; below can find gpg, and remember them for the shells chapter.  The title
;; bar is made transparent here, before the first frame; the platform
;; chapter gives it the theme's appearance.
(defvar kittymacs-launcher-path nil
  "Directories `early-init.el' put on `exec-path' for an Emacs from the Dock.")
(when (eq system-type 'darwin)
  (dolist (directory (list "/usr/local/bin"
                           "/opt/homebrew/bin"
                           "/nix/var/nix/profiles/default/bin"
                           (expand-file-name "~/.nix-profile/bin")
                           (concat "/etc/profiles/per-user/" (user-login-name) "/bin")
                           "/run/current-system/sw/bin"))
    (when (file-directory-p directory)
      (push directory kittymacs-launcher-path)
      (unless (member directory exec-path)
        (push directory exec-path))))
  (push '(ns-transparent-titlebar . t) default-frame-alist))

;; GNU ELPA signs its archive index and Emacs verifies it with the first
;; gpg on `exec-path'.  On Windows that is Git for Windows' POSIX gpg, which
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
  (setq native-comp-async-report-warnings-errors 'silent))

(setq gc-cons-threshold (* 128 1024 1024))
(add-hook 'emacs-startup-hook (lambda () (setq gc-cons-threshold (* 64 1024 1024))))

;; Size frames by the pixel, so a tiling window manager's tile is filled
;; exactly instead of to the nearest whole character cell.
(setq frame-resize-pixelwise t)

(setq frame-inhibit-implied-resize t
      inhibit-startup-screen t
      initial-scratch-message nil
      load-prefer-newer t)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)
;; WSLg: no compositor frame; Windows already frames and places the window.
(when (file-directory-p "/mnt/wslg")
  (push '(undecorated . t) default-frame-alist))
;; The frame parameter hides the menu bar; the mode has to agree, or the
;; first `SPC t m' would switch a hidden menu bar "off" and show nothing.
(menu-bar-mode -1)

(when (eq system-type 'windows-nt)
  (setq w32-get-true-file-attributes nil
        inhibit-compacting-font-caches t))
(defvar kittymacs-quickstart-loaded nil
  "Non-nil when this start activated its packages from the quickstart file.")

(defun kittymacs-quickstart-file ()
  "Return the quickstart file's name for this Emacs and these package directories."
  (expand-file-name
   (format "package-quickstart-%s.el"
           (sha1 (prin1-to-string
                  (cons emacs-version
                        (mapcar #'file-truename
                                (cons package-user-dir package-directory-list))))))
   kittymacs-cache-dir))

(defun kittymacs-quickstart--written ()
  "Return every quickstart file here, whatever directories it was written for."
  (and (file-directory-p kittymacs-cache-dir)
       (directory-files kittymacs-cache-dir t "\\`package-quickstart-[0-9a-f]+\\.elc?\\'")))

(defun kittymacs-quickstart--current-p (file)
  "Return non-nil when FILE is compiled, and newer than every package directory."
  (let ((compiled (concat file "c")))
    (not (memq nil (mapcar (lambda (directory) (file-newer-than-file-p compiled directory))
                           (cons package-user-dir package-directory-list))))))

(defun kittymacs-activate-packages ()
  "Activate the installed packages, from the quickstart file when it is current.
With no such file, `package-initialize' does what it always did."
  (let ((file (kittymacs-quickstart-file)))
    (if (not (kittymacs-quickstart--current-p file))
        (package-initialize)
      (setq kittymacs-quickstart-loaded t)
      (let ((package-quickstart-file file))
        (package-activate-all))
      ;; Only a scan fills this: the file did not load, so have it written again.
      (when package-alist
        (delete-file (concat file "c"))))))

(defun kittymacs-quickstart--off-file ()
  "Return the file saying that this machine turned the quickstart file off."
  (expand-file-name "quickstart-off" kittymacs-var-dir))

(defun kittymacs-quickstart--delete ()
  "Delete every quickstart file."
  (setq package-quickstart nil)
  (mapc #'delete-file (kittymacs-quickstart--written)))

(defun kittymacs-quickstart-remove ()
  "Delete every quickstart file, and keep this machine scanning until it asks again."
  (interactive)
  (kittymacs-quickstart--delete)
  (make-directory kittymacs-var-dir t)
  (write-region "kittymacs-quickstart-write turns the quickstart file on again.\n"
                nil (kittymacs-quickstart--off-file) nil 'silent))

(defvar warning-minimum-log-level)

(defun kittymacs-quickstart--quietly (refresh)
  "Call REFRESH with no compile warning, from this code or from Emacs's own refresh.
An autoloads file may name a function only its package defines.  Batch prints
whatever gets logged, so hiding it from the display would not be enough."
  (require 'warnings)
  (let ((warning-minimum-log-level :error))
    (funcall refresh)))

(advice-add 'package-quickstart-refresh :around #'kittymacs-quickstart--quietly)

(defun kittymacs-quickstart-write ()
  "Write the quickstart file for this Emacs and these package directories.
This also undoes `kittymacs-quickstart-remove'; see the startup chapter."
  (interactive)
  (require 'package)
  (kittymacs-quickstart--delete)
  (delete-file (kittymacs-quickstart--off-file))
  (make-directory kittymacs-cache-dir t)
  (setq package-quickstart-file (kittymacs-quickstart-file)
        package-quickstart t)
  (package-quickstart-refresh))

(defun kittymacs-quickstart--keep-current ()
  "Keep this machine's quickstart file right from now on; it has written one before."
  (setq package-quickstart-file (kittymacs-quickstart-file)
        package-quickstart t)
  (unless (kittymacs-quickstart--current-p package-quickstart-file)
    (kittymacs-quickstart-write)))

(defun kittymacs-quickstart--wanted-p ()
  "Return non-nil on a new machine that has no quickstart file and has not refused one."
  (and (file-exists-p (kittymacs-features--stamp-file))
       (not (file-exists-p (kittymacs-quickstart--off-file)))
       (not (kittymacs-quickstart--written))))

(defun kittymacs-quickstart--settle ()
  "Write the file on a new machine, unless this session failed to install a package."
  (when (and (kittymacs-quickstart--wanted-p)
             (not kittymacs-features--failed))
    (kittymacs-quickstart-write)))

(defun kittymacs-quickstart--settle-when-idle ()
  "Call `kittymacs-quickstart--settle' once this start has gone idle."
  (run-with-idle-timer 2 nil #'kittymacs-quickstart--settle))

;;; early-init.el ends here
