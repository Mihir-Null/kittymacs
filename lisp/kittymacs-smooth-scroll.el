;;; kittymacs-smooth-scroll.el --- Pixel scrolling and animated page keys -*- lexical-binding: t; -*-
;; Generated from literate/51-smooth-scroll.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'kittymacs-leader)

(defvar kittymacs-smooth-scroll-mode)
(defvar meow-normal-mode)
(defvar ultra-scroll-mode)
(declare-function kittymacs--pulse-line "kittymacs-ui" (&rest _))
(declare-function kittymacs-remote-buffer-p "kittymacs-defaults" (&rest _))
(declare-function mwheel-event-window "mwheel" (event))
(declare-function mwheel-scroll "mwheel" (event &optional arg))
(declare-function pixel-scroll-precision-interpolate "pixel-scroll" (delta &optional old-window factor))

(defun kittymacs-smooth-scroll--plain-p (&optional window)
  "Return non-nil if WINDOW keeps plain scrolling: a terminal or a remote buffer.
WINDOW may be a frame, as a wheel event's can, and nil means the selected one."
  (let ((window (cond ((framep window) (frame-selected-window window))
                      (window)
                      (t (selected-window)))))
    (or (not (display-graphic-p (window-frame window)))
        (with-current-buffer (window-buffer window)
          (kittymacs-remote-buffer-p)))))
(use-package ultra-scroll
  :ensure t
  :commands ultra-scroll-mode)

(defvar kittymacs-smooth-scroll--rest 0.0
  "Pixels a plain window has been asked to scroll, short of a whole line.")

(defun kittymacs-smooth-scroll--plain-wheel (event arg window)
  "Scroll WINDOW by whole lines for EVENT and ARG, adding up its pixels."
  (if-let* ((delta (nth 4 event)))
      (with-selected-window window
        (let* ((height (default-line-height))
               (pixels (+ kittymacs-smooth-scroll--rest (cdr delta)))
               (lines (truncate (/ pixels height))))
          (setq kittymacs-smooth-scroll--rest (- pixels (* lines height)))
          (condition-case nil
              (cond ((< lines 0) (scroll-up (- lines)))
                    ((> lines 0) (scroll-down lines)))
            ((beginning-of-buffer end-of-buffer) nil))))
    (mwheel-scroll event arg)))

(defun kittymacs-smooth-scroll--wheel (scroll event &optional arg)
  "Call SCROLL with EVENT and ARG, unless EVENT's window keeps plain scrolling."
  (let* ((target (mwheel-event-window event))
         (window (if (framep target) (frame-selected-window target) target)))
    (if (kittymacs-smooth-scroll--plain-p window)
        (kittymacs-smooth-scroll--plain-wheel event arg window)
      (funcall scroll event arg))))
(advice-add 'ultra-scroll :around #'kittymacs-smooth-scroll--wheel)
(advice-add 'ultra-scroll-mac :around #'kittymacs-smooth-scroll--wheel)
(defun kittymacs-smooth-scroll--animate (pixels)
  "Scroll by PIXELS with an animation, forward when negative, then pulse the line."
  (condition-case err
      (pixel-scroll-precision-interpolate pixels nil 1)
    ((beginning-of-buffer end-of-buffer)
     (message "%s" (error-message-string err))))
  (kittymacs--pulse-line))

(defun kittymacs-smooth-scroll--page-pixels ()
  "Return how many pixels `scroll-up-command' moves this window by."
  (max (default-line-height)
       (- (window-text-height nil t)
          (* next-screen-context-lines (default-line-height)))))

(defun kittymacs-smooth-scroll-page-down (&optional lines)
  "Scroll forward a page with an animation, or LINES lines without one."
  (interactive "^P")
  (if (or lines (kittymacs-smooth-scroll--plain-p))
      (scroll-up-command lines)
    (kittymacs-smooth-scroll--animate (- (kittymacs-smooth-scroll--page-pixels)))))

(defun kittymacs-smooth-scroll-page-up (&optional lines)
  "Scroll back a page with an animation, or LINES lines without one."
  (interactive "^P")
  (if (or lines (kittymacs-smooth-scroll--plain-p))
      (scroll-down-command lines)
    (kittymacs-smooth-scroll--animate (kittymacs-smooth-scroll--page-pixels))))

(defun kittymacs-smooth-scroll-half-page-down ()
  "Scroll forward half a window, with an animation where one is possible."
  (interactive)
  (if (kittymacs-smooth-scroll--plain-p)
      (scroll-up-command (max 1 (/ (window-body-height) 2)))
    (kittymacs-smooth-scroll--animate (- (/ (window-text-height nil t) 2)))))

(defun kittymacs-smooth-scroll-half-page-up ()
  "Scroll back half a window, with an animation where one is possible."
  (interactive)
  (if (kittymacs-smooth-scroll--plain-p)
      (scroll-down-command (max 1 (/ (window-body-height) 2)))
    (kittymacs-smooth-scroll--animate (/ (window-text-height nil t) 2))))

(defun kittymacs-smooth-scroll--in-normal-state (command)
  "Return COMMAND in Meow's Normal state, and nil anywhere else."
  (and (bound-and-true-p meow-normal-mode) command))

(defvar-keymap kittymacs-smooth-scroll-mode-map
  :doc "The animated page keys."
  "<remap> <scroll-up-command>" #'kittymacs-smooth-scroll-page-down
  "<remap> <scroll-down-command>" #'kittymacs-smooth-scroll-page-up
  "<remap> <pixel-scroll-interpolate-down>" #'kittymacs-smooth-scroll-page-down
  "<remap> <pixel-scroll-interpolate-up>" #'kittymacs-smooth-scroll-page-up
  "C-d" `(menu-item "" kittymacs-smooth-scroll-half-page-down
                    :filter kittymacs-smooth-scroll--in-normal-state)
  "C-u" `(menu-item "" kittymacs-smooth-scroll-half-page-up
                    :filter kittymacs-smooth-scroll--in-normal-state))

(defun kittymacs-smooth-scroll--apply (&optional _frame)
  "Make the pixel scrolling agree with the mode, once a graphical frame exists."
  (cond ((not kittymacs-smooth-scroll-mode)
         (when (bound-and-true-p ultra-scroll-mode)
           (ultra-scroll-mode -1)))
        ((seq-some #'display-graphic-p (frame-list))
         (ultra-scroll-mode 1))))

(define-minor-mode kittymacs-smooth-scroll-mode
  "Scroll by pixels on a graphical frame, and animate the page keys."
  :global t
  :group 'kittymacs
  :keymap kittymacs-smooth-scroll-mode-map
  (if kittymacs-smooth-scroll-mode
      (add-hook 'after-make-frame-functions #'kittymacs-smooth-scroll--apply)
    (remove-hook 'after-make-frame-functions #'kittymacs-smooth-scroll--apply))
  (kittymacs-smooth-scroll--apply))

(keymap-set kittymacs-toggle-map "S" (cons "smooth scrolling" #'kittymacs-smooth-scroll-mode))
(kittymacs-smooth-scroll-mode 1)

(provide 'kittymacs-smooth-scroll)
;;; kittymacs-smooth-scroll.el ends here
