;;; kittymacs-meow-state-cursor.el --- Meow's state in colour -*- lexical-binding: t; -*-
;; Generated from literate/52-meow-state-cursor.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)

(defvar kittymacs-meow-state-cursor-mode)
(declare-function meow--update-cursor "meow-core" ())

(defconst kittymacs-meow-state-cursor-sources
  '((normal . warning)
    (insert . success)
    (motion . link)
    (keypad . font-lock-keyword-face)
    (beacon . font-lock-string-face))
  "Each Meow state, and the face whose foreground gives its colour.")

(defun kittymacs-meow-state-cursor--face (format-string state)
  "Return the face FORMAT-STRING names for STATE, or nil if it does not exist yet."
  (let ((face (intern (format format-string state))))
    (and (facep face) face)))

(defun kittymacs-meow-state-cursor--colour (source)
  "Return the foreground of the face SOURCE in this theme, or the cursor's colour."
  (let ((colour (face-foreground source nil t)))
    (if (and (stringp colour) (color-defined-p colour))
        colour
      (face-background 'cursor nil t))))

(defun kittymacs-meow-state-cursor--paint (&rest _)
  "Give every state its colour from the current theme."
  (pcase-dolist (`(,state . ,source) kittymacs-meow-state-cursor-sources)
    (let ((colour (kittymacs-meow-state-cursor--colour source)))
      (when-let* ((cursor (kittymacs-meow-state-cursor--face "meow-%s-cursor" state)))
        (set-face-attribute cursor nil :inherit 'unspecified :background colour))
      (dolist (format-string '("meow-%s-indicator" "doom-modeline-meow-%s-state"))
        (when-let* ((face (kittymacs-meow-state-cursor--face format-string state)))
          (set-face-attribute face nil :foreground colour :weight 'bold)))))
  (when (fboundp 'meow--update-cursor)
    (meow--update-cursor)))

(defun kittymacs-meow-state-cursor--unpaint ()
  "Hand every state's faces back to their own definitions and the theme."
  (pcase-dolist (`(,state . ,_) kittymacs-meow-state-cursor-sources)
    (dolist (format-string '("meow-%s-cursor" "meow-%s-indicator" "doom-modeline-meow-%s-state"))
      (when-let* ((face (kittymacs-meow-state-cursor--face format-string state)))
        (dolist (attribute '(:inherit :background :foreground :weight))
          (set-face-attribute face t attribute 'unspecified))
        (custom-theme-recalc-face face))))
  (when (fboundp 'meow--update-cursor)
    (meow--update-cursor)))

(defvar kittymacs-meow-state-cursor--lighters nil
  "The entries of `minor-mode-alist' this mode changed, as they were.")

(defun kittymacs-meow-state-cursor--wrap-lighters ()
  "Put each state's face on its mark in `minor-mode-alist'."
  (pcase-dolist (`(,state . ,_) kittymacs-meow-state-cursor-sources)
    (when-let* ((mode (intern (format "meow-%s-mode" state)))
                (entry (assq mode minor-mode-alist))
                (face (kittymacs-meow-state-cursor--face "meow-%s-indicator" state)))
      (unless (assq mode kittymacs-meow-state-cursor--lighters)
        (push (cons mode (cdr entry)) kittymacs-meow-state-cursor--lighters)
        (setcdr entry `((:propertize ,(cadr entry) face ,face)))))))

(defun kittymacs-meow-state-cursor--unwrap-lighters ()
  "Put back each entry of `minor-mode-alist' this mode changed."
  (pcase-dolist (`(,mode . ,value) kittymacs-meow-state-cursor--lighters)
    (setcdr (assq mode minor-mode-alist) value))
  (setq kittymacs-meow-state-cursor--lighters nil))

(define-minor-mode kittymacs-meow-state-cursor-mode
  "Colour the cursor and the mode line's mark by Meow's state."
  :global t
  :group 'kittymacs
  (cond (kittymacs-meow-state-cursor-mode
         (add-hook 'enable-theme-functions #'kittymacs-meow-state-cursor--paint)
         (kittymacs-meow-state-cursor--wrap-lighters)
         (kittymacs-meow-state-cursor--paint))
        (t
         (remove-hook 'enable-theme-functions #'kittymacs-meow-state-cursor--paint)
         (kittymacs-meow-state-cursor--unwrap-lighters)
         (kittymacs-meow-state-cursor--unpaint))))

(keymap-set kittymacs-toggle-map "c" (cons "state colours" #'kittymacs-meow-state-cursor-mode))
(kittymacs-meow-state-cursor-mode 1)

(provide 'kittymacs-meow-state-cursor)
;;; kittymacs-meow-state-cursor.el ends here
