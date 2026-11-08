;;; kittymacs-meow-state-cursor-tests.el --- Meow's state in colour, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-meow-state-cursor-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages: these define Meow's faces as Meow does, with its lighters,
;; and a small theme stands for the real ones.
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-catalogue)

(defconst kittymacs-state-test-states '(normal insert motion keypad beacon))

(dolist (state kittymacs-state-test-states)
  (custom-declare-face (intern (format "meow-%s-cursor" state)) '((t (:inherit cursor))) "Test." :group 'basic-faces)
  (custom-declare-face (intern (format "meow-%s-indicator" state)) '((t ())) "Test." :group 'basic-faces)
  (let ((mode (intern (format "meow-%s-mode" state))))
    (set mode nil)
    (push (list mode (format " [%s]" (upcase (substring (symbol-name state) 0 1)))) minor-mode-alist)))

(defvar kittymacs-state-test-cursor-updates 0)
(defun meow--update-cursor () (cl-incf kittymacs-state-test-cursor-updates))

(defconst kittymacs-state-test-lighters (copy-tree minor-mode-alist))

(require 'kittymacs-features)
(require 'kittymacs-meow-state-cursor)

(defmacro kittymacs-state-test-with-colours (colours &rest body)
  "Run BODY with `face-foreground' answering from the alist COLOURS."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'face-foreground)
              (lambda (face &rest _) (alist-get face ,colours)))
             ((symbol-function 'face-background)
              (lambda (face &rest _) (and (eq face 'cursor) "#123456")))
             ((symbol-function 'color-defined-p) (lambda (colour) (stringp colour))))
     ,@body))

(defconst kittymacs-state-test-theme
  '((warning . "#aa0000") (success . "#00aa00") (link . "#0000aa")
    (font-lock-keyword-face . "#aa00aa") (font-lock-string-face . "#00aaaa")))

(ert-deftest kittymacs-state-full-has-it-minimal-does-not-and-it-installs-nothing ()
  (let ((entry (alist-get 'meow-state-cursor kittymacs-catalogue)))
    (should (eq (plist-get entry :profile) 'full))
    (should (eq (plist-get entry :group) 'look))
    (should-not (plist-get entry :packages))
    (should (memq 'meow (plist-get entry :deps)))
    (should-not (memq 'meow-state-cursor (kittymacs-features--compute 'minimal nil nil)))
    (should (memq 'meow-state-cursor (kittymacs-features--compute 'full nil nil)))
    (should-not (memq 'meow-state-cursor
                      (kittymacs-features--compute 'full nil '(meow-state-cursor))))))

(ert-deftest kittymacs-state-each-state-takes-its-theme-colour ()
  (kittymacs-state-test-with-colours kittymacs-state-test-theme
    (kittymacs-meow-state-cursor--paint)
    (should (equal (face-attribute 'meow-normal-cursor :background) "#aa0000"))
    (should (equal (face-attribute 'meow-insert-cursor :background) "#00aa00"))
    (should (equal (face-attribute 'meow-motion-cursor :background) "#0000aa"))
    (should (equal (face-attribute 'meow-beacon-cursor :background) "#00aaaa"))
    (should (equal (face-attribute 'meow-insert-indicator :foreground) "#00aa00"))
    (should (equal (face-attribute 'meow-keypad-indicator :foreground) "#aa00aa"))
    (should (eq (face-attribute 'meow-insert-indicator :weight) 'bold))))

(ert-deftest kittymacs-state-a-cursor-face-loses-its-inheritance ()
  "Meow reads `:inherit' before `:background', so the colour would do nothing."
  (kittymacs-state-test-with-colours kittymacs-state-test-theme
    (kittymacs-meow-state-cursor--paint)
    (dolist (state kittymacs-state-test-states)
      (should (eq (face-attribute (intern (format "meow-%s-cursor" state)) :inherit) 'unspecified)))))

(ert-deftest kittymacs-state-a-face-with-no-colour-leaves-the-theme-cursor ()
  (kittymacs-state-test-with-colours '((warning . unspecified) (success . "#00aa00"))
    (kittymacs-meow-state-cursor--paint)
    (should (equal (face-attribute 'meow-normal-cursor :background) "#123456"))
    (should (equal (face-attribute 'meow-insert-cursor :background) "#00aa00"))))

(ert-deftest kittymacs-state-a-new-theme-paints-again ()
  (should (memq #'kittymacs-meow-state-cursor--paint enable-theme-functions))
  (kittymacs-state-test-with-colours kittymacs-state-test-theme
    (kittymacs-meow-state-cursor--paint)
    (should (equal (face-attribute 'meow-insert-cursor :background) "#00aa00")))
  (kittymacs-state-test-with-colours '((success . "#112233"))
    (run-hook-with-args 'enable-theme-functions 'some-theme)
    (should (equal (face-attribute 'meow-insert-cursor :background) "#112233"))))

(ert-deftest kittymacs-state-a-painted-cursor-updates-at-once ()
  (let ((kittymacs-state-test-cursor-updates 0))
    (kittymacs-state-test-with-colours kittymacs-state-test-theme
      (kittymacs-meow-state-cursor--paint))
    (should (= kittymacs-state-test-cursor-updates 1))))

(ert-deftest kittymacs-state-the-default-mode-lines-mark-takes-the-face ()
  (let ((entry (assq 'meow-normal-mode minor-mode-alist)))
    (should (equal (cadr entry) '(:propertize " [N]" face meow-normal-indicator)))))

(ert-deftest kittymacs-state-turning-it-off-leaves-everything-as-it-was ()
  (kittymacs-state-test-with-colours kittymacs-state-test-theme
    (kittymacs-meow-state-cursor--paint))
  (kittymacs-meow-state-cursor-mode -1)
  (unwind-protect
      (progn
        (dolist (state kittymacs-state-test-states)
          (should (eq (face-attribute (intern (format "meow-%s-cursor" state)) :inherit) 'cursor))
          (should (eq (face-attribute (intern (format "meow-%s-cursor" state)) :background) 'unspecified))
          (should (eq (face-attribute (intern (format "meow-%s-indicator" state)) :foreground) 'unspecified))
          (should (eq (face-attribute (intern (format "meow-%s-indicator" state)) :weight) 'unspecified)))
        (should (equal (assq 'meow-normal-mode minor-mode-alist)
                       (assq 'meow-normal-mode kittymacs-state-test-lighters)))
        (should-not (memq #'kittymacs-meow-state-cursor--paint enable-theme-functions)))
    (kittymacs-meow-state-cursor-mode 1)))

(ert-deftest kittymacs-state-turning-it-on-twice-does-not-wrap-twice ()
  (kittymacs-meow-state-cursor-mode 1)
  (kittymacs-meow-state-cursor-mode 1)
  (should (equal (cadr (assq 'meow-normal-mode minor-mode-alist))
                 '(:propertize " [N]" face meow-normal-indicator))))

(ert-deftest kittymacs-state-has-its-toggle ()
  (should (eq (keymap-lookup kittymacs-toggle-map "c") 'kittymacs-meow-state-cursor-mode)))

;;; kittymacs-meow-state-cursor-tests.el ends here
