;;; kittymacs-basics.el --- Small packages for undo, whitespace and windows -*- lexical-binding: t; -*-
;; Generated from literate/26-basics.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)
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

(keymap-set kittymacs-buffer-map "u" (cons "undo tree" #'vundo))
(defun kittymacs-frames-only-p ()
  "Return non-nil while frames-only mode is on."
  (bound-and-true-p frames-only-mode))

(when (kittymacs-feature-p 'window-picker)
  (use-package ace-window
    :ensure t
    :commands (ace-window ace-swap-window aw-flip-window))

  (defun kittymacs-window-jump ()
    "Jump to a window by letter, or to a frame by name in frames-only mode."
    (interactive)
    (if (kittymacs-frames-only-p)
        (call-interactively #'select-frame-by-name)
      (call-interactively #'ace-window)))

  (defun kittymacs-window-swap ()
    "Swap two windows; in frames-only mode, say that there are none to swap."
    (interactive)
    (if (kittymacs-frames-only-p)
        (user-error "Frames-only mode is on, so the window manager arranges frames; SPC t f turns it off")
      (call-interactively #'ace-swap-window)))

  (keymap-set kittymacs-window-map "w" (cons "jump to window" #'kittymacs-window-jump))
  (keymap-set kittymacs-window-map "s" (cons "swap windows" #'kittymacs-window-swap)))

(defvar kittymacs-popper-keys-on t
  "Non-nil while Popper's keys are bound: whenever frames-only mode is off.")

(defvar kittymacs-popper-keys-map (make-sparse-keymap)
  "Popper's keys, live while `kittymacs-popper-keys-on' is non-nil.")

(defun kittymacs--popper-keys-follow-frames ()
  "Turn Popper's keys off while frames-only mode is on, and on otherwise."
  (setq kittymacs-popper-keys-on (not (kittymacs-frames-only-p))))

(when (kittymacs-feature-p 'popups)
  (keymap-set kittymacs-popper-keys-map "M-`" #'popper-toggle)
  (keymap-set kittymacs-popper-keys-map "C-`" #'popper-cycle)
  (keymap-set kittymacs-popper-keys-map "C-M-`" #'popper-toggle-type)
  (add-to-list 'minor-mode-map-alist (cons 'kittymacs-popper-keys-on kittymacs-popper-keys-map))
  (add-hook 'frames-only-mode-hook #'kittymacs--popper-keys-follow-frames)
  (kittymacs--popper-keys-follow-frames)

  (use-package popper
    :ensure t
    :demand t
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
    (popper-echo-mode 1)))
(when (kittymacs-feature-p 'color-names)
  (use-package rainbow-mode
    :ensure t
    :commands rainbow-mode)

  (keymap-set kittymacs-toggle-map "r" (cons "colour names" #'rainbow-mode)))

(provide 'kittymacs-basics)
;;; kittymacs-basics.el ends here
