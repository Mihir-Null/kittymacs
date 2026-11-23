;;; kittymacs-meow-tests.el --- Meow key dispatch and scroll coexistence -*- lexical-binding: t; -*-
;; Run with an installed Meow package directory via KITTYMACS_TEST_PACKAGES.
(require 'ert)
(require 'cl-lib)
(require 'package)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path
             (expand-file-name "../lisp"
                               (file-name-directory (or load-file-name buffer-file-name))))
(require 'use-package)
(setq use-package-ensure-function #'ignore)
(require 'kittymacs-meow)

(defvar kittymacs-meow-test-scroll-mode nil)
(defvar-keymap kittymacs-meow-test-scroll-map
  "C-d" #'scroll-up-command)

(ert-deftest kittymacs-meow-delete-does-not-dispatch-through-scrolling-C-d ()
  "A Normal-state C-d scroll binding must not turn d into a scroll key."
  (should (eq meow--kbd-delete-char #'delete-char))
  (with-temp-buffer
    (text-mode)
    (insert "abc")
    (goto-char (point-min))
    (meow--switch-state 'normal)
    (let ((kittymacs-meow-test-scroll-mode t)
          (minor-mode-map-alist
           (cons (cons 'kittymacs-meow-test-scroll-mode
                       kittymacs-meow-test-scroll-map)
                 minor-mode-map-alist)))
      (should (eq (key-binding (kbd "C-d")) #'scroll-up-command))
      (should (eq (key-binding (kbd "d")) #'meow-delete))
      (call-interactively (key-binding (kbd "d")))
      (should (equal (buffer-string) "bc")))))

(ert-deftest kittymacs-meow-change-char-does-not-dispatch-through-scrolling-C-d ()
  "The same internal delete binding is used by Meow's change-char command."
  (with-temp-buffer
    (text-mode)
    (insert "abc")
    (goto-char (point-min))
    (meow--switch-state 'normal)
    (let ((kittymacs-meow-test-scroll-mode t)
          (minor-mode-map-alist
           (cons (cons 'kittymacs-meow-test-scroll-mode
                       kittymacs-meow-test-scroll-map)
                 minor-mode-map-alist)))
      (call-interactively #'meow-change-char)
      (should (equal (buffer-string) "bc"))
      (should (meow-insert-mode-p)))))

(provide 'kittymacs-meow-tests)
;;; kittymacs-meow-tests.el ends here
