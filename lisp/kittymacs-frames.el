;;; kittymacs-frames.el --- Desktop-managed Emacs frames -*- lexical-binding: t; -*-
;; Generated from literate/45-frames.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)
(defcustom kittymacs-frames-only
  (not (or (eq system-type 'android) (bound-and-true-p kittymacs-exwm)))
  "Whether every auxiliary buffer becomes its own operating-system window.
Off on Android, where an Emacs frame is an activity in the task switcher
rather than a window some desktop window manager arranges for you, and
under EXWM, where Emacs is the window manager.  Set it in `private.el',
before this module is loaded, to override."
  :type 'boolean
  :group 'kittymacs)
(use-package frames-only-mode
  :ensure t
  :commands frames-only-mode
  :custom
  (frames-only-mode-use-windows-for-completion t)
  :config
  (setopt frames-only-mode-configuration-variables
          (cons '(popper-display-control nil)
                (seq-remove (lambda (setting)
                              (memq (car setting)
                                    '(magit-commit-show-diff magit-bury-buffer-function)))
                            frames-only-mode-configuration-variables)))
  (frames-only-mode-remap-common-window-split-keybindings))
(keymap-set kittymacs-toggle-map "f" (cons "frames-only mode" #'frames-only-mode))
(when kittymacs-frames-only
  (require 'frames-only-mode)
  ;; Re-evaluating this file must not overwrite the mode's saved defaults.
  (unless frames-only-mode
    (frames-only-mode 1)))
(dolist (pattern '("\\`\\*Warnings\\*\\'"
                   "\\`\\*Compile-Log\\*\\'"
                   "\\`\\*Backtrace\\*\\'"
                   "\\`\\*Native-compile-Log\\*\\'"
                   "\\`\\*Async-native-compile-log\\*\\'"))
  (add-to-list 'display-buffer-alist
               `(,pattern
                 (display-buffer-reuse-window display-buffer-at-bottom)
                 (window-height . 0.25)
                 (dedicated . t)
                 (reusable-frames . visible))))

(provide 'kittymacs-frames)
;;; kittymacs-frames.el ends here
