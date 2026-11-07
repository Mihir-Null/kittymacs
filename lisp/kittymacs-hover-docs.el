;;; kittymacs-hover-docs.el --- A language server's documentation in a child frame -*- lexical-binding: t; -*-
;; Generated from literate/79-hover-docs.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)

(defvar eldoc-box-hover-mode)
(defvar kittymacs-hover-docs-mode)
(declare-function eglot-managed-p "eglot" ())
(declare-function eldoc-display-in-echo-area "eldoc" (docs interactive))

(use-package eldoc-box
  :ensure t
  :commands eldoc-box-hover-mode
  :custom
  (eldoc-box-only-multi-line t)
  (eldoc-box-cleanup-interval 0.5)
  (eldoc-box-clear-with-C-g t))

(defun kittymacs-hover-docs--apply ()
  "Make this buffer's hover documentation agree with the mode, Eglot and its frame."
  (cond ((and kittymacs-hover-docs-mode
              (fboundp 'eglot-managed-p)
              (eglot-managed-p)
              (display-graphic-p))
         (eldoc-box-hover-mode 1))
        ((bound-and-true-p eldoc-box-hover-mode)
         (eldoc-box-hover-mode -1))))

(defun kittymacs-hover-docs--display (display docs interactive)
  "Call DISPLAY with DOCS and INTERACTIVE, or use the echo area in a terminal."
  (if (display-graphic-p)
      (funcall display docs interactive)
    (eldoc-display-in-echo-area docs interactive)))
(advice-add 'eldoc-box--eldoc-display-function :around #'kittymacs-hover-docs--display)
(define-minor-mode kittymacs-hover-docs-mode
  "Show a language server's documentation in a child frame on a graphical frame."
  :global t
  :group 'kittymacs
  (if kittymacs-hover-docs-mode
      (add-hook 'eglot-managed-mode-hook #'kittymacs-hover-docs--apply)
    (remove-hook 'eglot-managed-mode-hook #'kittymacs-hover-docs--apply))
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (kittymacs-hover-docs--apply))))

(keymap-set kittymacs-toggle-map "e" (cons "hover documentation" #'kittymacs-hover-docs-mode))
(kittymacs-hover-docs-mode 1)

(provide 'kittymacs-hover-docs)
;;; kittymacs-hover-docs.el ends here
