;;; kittymacs-exwm-tests.el --- EXWM's start, with no X and no EXWM -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-exwm-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages.  Stand-ins take the place of EXWM and xelb, so the module's
;; real `use-package' form runs here, and nothing installs.
(require 'ert)
(require 'cl-lib)
(require 'use-package)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-catalogue)
(require 'kittymacs-features)

(defvar kittymacs-exwm)
(defvar kittymacs-exwm-test--keysyms nil
  "What `xcb:keysyms:event->keysyms' saw when EXWM turned on.")
(defvar kittymacs-exwm-test--stand-in-result nil
  "What the stand-in for `xcb:keysyms:event->keysyms' returns.")

(defun kittymacs-exwm-test--load ()
  "Load the module as a session would, with stand-ins for EXWM and xelb."
  (let ((use-package-ensure-function #'ignore)
        (kittymacs-features--enabled '(window-manager))
        (kittymacs-exwm t)
        (load-prefer-newer t))
    (provide 'exwm)
    (provide 'exwm-randr)
    (defalias 'xcb:keysyms:event->keysyms
      (lambda (&rest _) kittymacs-exwm-test--stand-in-result))
    (defalias 'exwm-randr-mode #'ignore)
    (defalias 'exwm-workspace-rename-buffer #'ignore)
    (defalias 'exwm-wm-mode
      (lambda (&rest _)
        (setq kittymacs-exwm-test--keysyms (xcb:keysyms:event->keysyms nil ?\H-a))))
    (load (locate-library "kittymacs-exwm.el") nil t t)))

(kittymacs-exwm-test--load)

(ert-deftest kittymacs-exwm-a-missing-modifier-reads-as-a-failed-conversion ()
  "EXWM reads ((0 . 0)) as \"Key unavailable\", and nil turns EXWM off."
  (should (equal (kittymacs-exwm--keysyms-or-failure nil) '((0 . 0)))))

(ert-deftest kittymacs-exwm-a-real-translation-passes-through ()
  (should (equal (kittymacs-exwm--keysyms-or-failure '((97 . 64))) '((97 . 64)))))

(ert-deftest kittymacs-exwm-the-fix-is-on-before-exwm-starts ()
  (should (equal kittymacs-exwm-test--keysyms '((0 . 0)))))

(provide 'kittymacs-exwm-tests)
;;; kittymacs-exwm-tests.el ends here
