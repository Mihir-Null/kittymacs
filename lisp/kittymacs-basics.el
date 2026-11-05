;;; kittymacs-basics.el --- Small packages for undo, whitespace and windows -*- lexical-binding: t; -*-
;; Generated from literate/26-basics.org; edit the Org source, then tangle.

;;; Code:
(use-package ws-butler
  :ensure t
  :hook ((text-mode prog-mode) . ws-butler-mode))
(use-package vundo
  :ensure t
  :commands vundo
  :custom
  (vundo-glyph-alist vundo-unicode-symbols)
  (vundo-compact-display t)
  :config
  (with-eval-after-load 'meow
    (add-to-list 'meow-mode-state-list '(vundo-mode . motion))))
(use-package ace-window
  :ensure t
  :commands (ace-window ace-swap-window aw-flip-window))

(use-package popper
  :ensure t
  :demand t
  :bind (("M-`" . popper-toggle)
         ("C-`" . popper-cycle)
         ("C-M-`" . popper-toggle-type))
  :custom
  (popper-window-height 20)
  (popper-group-function #'popper-group-by-directory)
  (popper-reference-buffers
   '("\\*Messages\\*"
     "Output\\*$"
     "\\*Async Shell Command\\*"
     help-mode
     compilation-mode))
  :config
  (popper-mode 1)
  (popper-echo-mode 1))
(use-package rainbow-mode
  :ensure t
  :commands rainbow-mode)

(provide 'kittymacs-basics)
;;; kittymacs-basics.el ends here
