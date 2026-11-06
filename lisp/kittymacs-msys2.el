;;; kittymacs-msys2.el --- The MSYS2 fallback, for work on Windows-side files -*- lexical-binding: t; -*-
;; Generated from literate/37-msys2.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)

;; Without these a `let' would bind them lexically, and ghostel would never see
;; the shell, when the first terminal of a session is this one.
(defvar ghostel-shell)
(defvar ghostel-environment)
(defvar ghostel-buffer-name)
(declare-function ghostel "ghostel" (&optional arg))

(defcustom kittymacs-msys2-root
  (file-name-as-directory (or (getenv "MSYS2_ROOT") "C:/msys64/"))
  "Root directory of the MSYS2 installation on Windows.
It is read only when the `msys2-fallback' feature is on, so setting it alone
does nothing: add that feature to `kittymacs-features' too."
  :type 'directory
  :group 'kittymacs)

(defun kittymacs-msys2--warn ()
  "Say that this is a fallback, why, and when it makes sense."
  (display-warning
   '(kittymacs msys2-fallback)
   (concat
    "msys2-fallback is on.  This is a fallback: a WSL2 backend (`:transport wsl', SPC o b) "
    "is the normal way to reach Unix programs, since they then run on Linux, and Windows "
    "needs no Unix layer of its own.  It makes sense for work on Windows-side files, "
    "where file I/O across WSL would ruin performance."
    (unless (file-directory-p kittymacs-msys2-root)
      (format "  No MSYS2 at %s: set `kittymacs-msys2-root'." kittymacs-msys2-root)))
   :warning))

(defun kittymacs-msys2-apply ()
  "Warn, and offer MSYS2's programs to this Emacs, after every other."
  (kittymacs-msys2--warn)
  (dolist (directory '("ucrt64/bin" "usr/bin"))
    (add-to-list 'exec-path (expand-file-name directory kittymacs-msys2-root) t))
  (let ((dictionaries (expand-file-name "ucrt64/share/hunspell" kittymacs-msys2-root)))
    (when (and (not (getenv "DICPATH")) (file-directory-p dictionaries))
      (setenv "DICPATH" dictionaries))))

(defun kittymacs-terminal-msys2 (&optional arg)
  "Open an MSYS2 UCRT64 login shell in a terminal.
With prefix ARG, create another one instead of reusing the existing buffer."
  (interactive "P")
  (unless (eq system-type 'windows-nt)
    (user-error "The MSYS2 terminal is for native Windows Emacs"))
  (let ((bash (expand-file-name "usr/bin/bash.exe" kittymacs-msys2-root)))
    (unless (file-executable-p bash)
      (user-error "MSYS2 Bash not found at %s; set `kittymacs-msys2-root' in private.el"
                  bash))
    (let ((ghostel-shell (list bash "--login" "-i"))
          (ghostel-environment (append '("MSYSTEM=UCRT64" "CHERE_INVOKING=1")
                                       ghostel-environment))
          (ghostel-buffer-name "*ghostel: msys2*"))
      (ghostel arg))))

(keymap-set kittymacs-open-map "m" (cons "MSYS2 terminal" #'kittymacs-terminal-msys2))

(kittymacs-msys2-apply)

(provide 'kittymacs-msys2)
;;; kittymacs-msys2.el ends here
