;;; kittymacs-suggestions.el --- Copilot's ghost text and next edits -*- lexical-binding: t; -*-
;; Generated from literate/78-suggestions.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'kittymacs-defaults)

(declare-function copilot-clear-overlay "copilot" (&optional is-accepted))
(declare-function copilot-complete "copilot" ())
(declare-function copilot-mode "copilot" (&optional arg))
(declare-function copilot-nes-mode "copilot-nes" (&optional arg))
(declare-function copilot-server-executable "copilot" ())
(defgroup kittymacs-suggestions nil
  "Code suggestions from GitHub Copilot."
  :group 'kittymacs)

(defcustom kittymacs-suggestions nil
  "Whether programming buffers that visit a file start with suggestions.
Suggestions send the buffer to GitHub.  `SPC t a' turns them on or off
in one buffer whatever this says."
  :type 'boolean)

(defcustom kittymacs-suggestions-excluded-files
  '("/private\\.el\\'" "\\.gpg\\'" "\\.age\\'" "/\\.ssh/" "/\\.env\\(\\.[^/]*\\)?\\'" "authinfo")
  "Patterns for file names that never get suggestions.
A buffer whose file name matches one is never sent to GitHub."
  :type '(repeat regexp))
(use-package copilot
  :ensure t
  :defer t
  :commands (copilot-login copilot-logout copilot-diagnose)
  :custom
  (copilot-install-dir (expand-file-name "copilot/" kittymacs-cache-dir))
  (copilot-indent-offset-warning-disable t)
  (copilot-enable-predicates '(kittymacs-suggestions-typing-p copilot--buffer-changed))
  (copilot-disable-display-predicates '(kittymacs-suggestions-popup-p)))
(defun kittymacs--suggestions-excluded-p ()
  "Return non-nil if this buffer's file must never be sent to GitHub."
  (and buffer-file-name
       (seq-some (lambda (pattern) (string-match-p pattern buffer-file-name))
                 kittymacs-suggestions-excluded-files)))

(defun kittymacs--suggestions-start ()
  "Turn on ghost text and next edits in this buffer; return non-nil if on."
  (require 'copilot)
  (cond
   ((kittymacs--suggestions-excluded-p)
    (message "Suggestions stay off for %s (kittymacs-suggestions-excluded-files)"
             (file-name-nondirectory buffer-file-name))
    nil)
   ((not (ignore-errors (copilot-server-executable)))
    (message "Suggestions need copilot-language-server on PATH, or M-x copilot-install-server")
    nil)
   (t
    (copilot-mode 1)
    (copilot-nes-mode 1)
    t)))

(defun kittymacs--suggestions-maybe-start ()
  "Turn suggestions on in a programming buffer if `kittymacs-suggestions' is set."
  (when (and kittymacs-suggestions buffer-file-name (not buffer-read-only))
    (kittymacs--suggestions-start)))

(add-hook 'prog-mode-hook #'kittymacs--suggestions-maybe-start)

(defun kittymacs-suggestions-toggle ()
  "Turn Copilot's ghost text and next edits on or off in this buffer."
  (interactive)
  (if (bound-and-true-p copilot-mode)
      (progn
        (copilot-nes-mode -1)
        (copilot-mode -1)
        (message "Suggestions off in this buffer"))
    (when (kittymacs--suggestions-start)
      (message "Suggestions on in this buffer"))))

(defun kittymacs-suggestions-complete ()
  "Ask Copilot for ghost text at point now.
Turns suggestions on in this buffer first if they are off, so an
excluded file is never sent."
  (interactive)
  (when (or (bound-and-true-p copilot-mode)
            (kittymacs--suggestions-start))
    (copilot-complete)))
(defun kittymacs-suggestions-typing-p ()
  "Return non-nil while you type: in Meow's Insert state, or where Meow is off.
A member of `copilot-enable-predicates'."
  (or (not (bound-and-true-p meow-mode))
      (bound-and-true-p meow-insert-mode)))
(defun kittymacs-suggestions-popup-p ()
  "Return non-nil while a completion popup is open.
A member of `copilot-disable-display-predicates'."
  (bound-and-true-p completion-in-region-mode))

(defun kittymacs--suggestions-yield-to-popup ()
  "Clear Copilot's ghost text when a completion popup opens."
  (when (and completion-in-region-mode (bound-and-true-p copilot-mode))
    (copilot-clear-overlay)))

(add-hook 'completion-in-region-mode-hook #'kittymacs--suggestions-yield-to-popup)

(provide 'kittymacs-suggestions)
;;; kittymacs-suggestions.el ends here
