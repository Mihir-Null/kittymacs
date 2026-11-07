;;; kittymacs-which-key-frame.el --- which-key in a child frame -*- lexical-binding: t; -*-
;; Generated from literate/43-which-key-frame.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'which-key)
(require 'kittymacs-leader)

(declare-function posframe-delete "posframe" (buffer-or-name))
(declare-function which-key-posframe--hide "which-key-posframe" ())
(declare-function which-key-posframe--show-buffer "which-key-posframe" (act-popup-dim))

(use-package which-key-posframe
  :ensure t
  :defer t
  :custom
  (which-key-posframe-border-width 1)
  (which-key-posframe-poshandler #'kittymacs-which-key-frame--position))

(defun kittymacs-which-key-frame--position (info)
  "Return the corner above the mode line, from the pixels in INFO."
  (cons (max 0 (- (plist-get info :parent-frame-width)
                  (plist-get info :posframe-width)))
        (max 0 (- (plist-get info :parent-frame-height)
                  (plist-get info :posframe-height)
                  (plist-get info :mode-line-height)
                  (plist-get info :minibuffer-height)))))

(defun kittymacs-which-key-frame--show (dimensions)
  "Show the menu of DIMENSIONS in a child frame, or a terminal's side window."
  (if (display-graphic-p)
      (progn
        (require 'which-key-posframe)
        (which-key-posframe--show-buffer dimensions))
    (which-key--show-buffer-side-window dimensions)))

(defun kittymacs-which-key-frame--hide ()
  "Hide the menu, wherever it is."
  (when (featurep 'which-key-posframe)
    (which-key-posframe--hide))
  (unless (display-graphic-p)
    (which-key--hide-buffer-side-window)))

(defun kittymacs-which-key-frame--max-dimensions (_window-width)
  "Return the room for the menu as (HEIGHT . WIDTH), by the kind of selected frame."
  (if (display-graphic-p)
      (cons (max 1 (floor (* which-key-side-window-max-height (frame-height))))
            (frame-width))
    (which-key--side-window-max-dimensions)))
(defvar kittymacs-which-key-frame--saved nil
  "The which-key settings to put back: its popup type and three functions.")

(defconst kittymacs-which-key-frame--settings
  '(which-key-popup-type
    which-key-custom-show-popup-function
    which-key-custom-hide-popup-function
    which-key-custom-popup-max-dimensions-function)
  "The which-key settings this mode changes.")

(define-minor-mode kittymacs-which-key-frame-mode
  "Show which-key's menu in a child frame on a graphical frame."
  :global t
  :group 'kittymacs
  (which-key--hide-popup-ignore-command)
  (cond
   (kittymacs-which-key-frame-mode
    (unless kittymacs-which-key-frame--saved
      (setq kittymacs-which-key-frame--saved
            (mapcar #'symbol-value kittymacs-which-key-frame--settings)))
    (setq which-key-popup-type 'custom
          which-key-custom-show-popup-function #'kittymacs-which-key-frame--show
          which-key-custom-hide-popup-function #'kittymacs-which-key-frame--hide
          which-key-custom-popup-max-dimensions-function
          #'kittymacs-which-key-frame--max-dimensions))
   (kittymacs-which-key-frame--saved
    (seq-mapn #'set kittymacs-which-key-frame--settings kittymacs-which-key-frame--saved)
    (setq kittymacs-which-key-frame--saved nil)
    (when (and (featurep 'which-key-posframe) (buffer-live-p which-key--buffer))
      (posframe-delete which-key--buffer)))))

(keymap-set kittymacs-toggle-map "W" (cons "which-key in a frame" #'kittymacs-which-key-frame-mode))
(kittymacs-which-key-frame-mode 1)

(provide 'kittymacs-which-key-frame)
;;; kittymacs-which-key-frame.el ends here
