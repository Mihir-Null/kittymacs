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

(defun kittymacs-exwm-test--warnings-with-xauth (found)
  "Return the warnings a start gives when `xauth' is FOUND, or is not."
  (let (warnings)
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and found (equal name "xauth") "/usr/bin/xauth")))
              ((symbol-function 'display-warning)
               (lambda (_type message &rest _) (push message warnings))))
      (kittymacs-exwm--warn-without-xauth))
    warnings))

(ert-deftest kittymacs-exwm-a-start-without-xauth-says-why ()
  "xelb finds the cookie through xauth, and an X server that asks for one refuses EXWM."
  (should (string-match-p "No xauth on PATH" (car (kittymacs-exwm-test--warnings-with-xauth nil))))
  (should-not (kittymacs-exwm-test--warnings-with-xauth t)))

(ert-deftest kittymacs-exwm-the-xauth-check-runs-before-exwm-starts ()
  (should (string-search "(kittymacs-exwm--warn-without-xauth)\n    (exwm-wm-mode 1)"
                         (with-temp-buffer
                           (insert-file-contents (locate-library "kittymacs-exwm.el"))
                           (buffer-string)))))

(ert-deftest kittymacs-exwm-the-fix-is-on-before-exwm-starts ()
  (should (equal kittymacs-exwm-test--keysyms '((0 . 0)))))

(defvar exwm-input-global-keys)

(ert-deftest kittymacs-exwm-h-d-launches ()
  "The default table binds H-d to the launcher, everywhere EXWM binds keys."
  (should (equal (assoc "H-d" kittymacs-wm-keys) '("H-d" launch)))
  (should (eq (alist-get (kbd "H-d") exwm-input-global-keys nil nil #'equal)
              #'kittymacs-exwm-launch)))

(ert-deftest kittymacs-exwm-the-launcher-does-not-wait ()
  "The program starts with no buffer, through a pipe, and Emacs returns at once."
  (let (calls)
    (cl-letf (((symbol-function 'start-process-shell-command)
               (lambda (name buffer command)
                 (push (list name buffer command process-connection-type) calls)
                 (make-pipe-process :name "kittymacs-exwm-test" :noquery nil)))
              ((symbol-function 'call-process)
               (lambda (&rest _) (error "The launcher waited in `call-process'")))
              ((symbol-function 'shell-command)
               (lambda (&rest _) (error "The launcher waited in `shell-command'"))))
      (let ((process (kittymacs-exwm-launch "google-chrome")))
        (unwind-protect
            (progn
              (should (equal calls '(("google-chrome" nil "google-chrome" nil))))
              (should (process-live-p process))
              (should-not (process-query-on-exit-flag process))
              (should (eq (process-sentinel process) #'kittymacs-exwm--launch-sentinel)))
          (delete-process process))))))

(ert-deftest kittymacs-exwm-a-failed-launch-says-so ()
  "A program that cannot start puts its shell's complaint in the echo area."
  (let (messages)
    (cl-letf (((symbol-function 'message)
               (lambda (format &rest args) (push (apply #'format format args) messages))))
      (let ((process (kittymacs-exwm-launch "kittymacs-no-such-program"))
            (deadline (+ (float-time) 10)))
        (while (and (process-live-p process) (< (float-time) deadline))
          (accept-process-output process 0.1))
        (accept-process-output nil 0.1)))
    (should (seq-find (lambda (m) (string-match-p "code 127: .*not found" m))
                      messages))))

(provide 'kittymacs-exwm-tests)
;;; kittymacs-exwm-tests.el ends here
