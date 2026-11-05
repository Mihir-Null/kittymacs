;;; kittymacs-theme-tests.el --- The look works without doom -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-theme-tests.el -f ert-run-tests-batch-and-exit
;;
;; Does what a gate on the `doom-look' feature will do: activates every package
;; but that feature's, then evaluates lisp/kittymacs-ui.el without its
;; declarations.  The verifier covers the same module with them.

;;; Code:
(require 'ert)
(require 'package)
(require 'seq)

(defconst kittymacs-theme-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(load (expand-file-name "lisp/kittymacs-catalogue.el" kittymacs-theme-test-root) nil t)

(defconst kittymacs-theme-test-doom
  (plist-get (alist-get 'doom-look kittymacs-catalogue) :packages)
  "The packages the module has to work without.")

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-theme-" t))
      native-comp-jit-compilation nil)
(load (expand-file-name "early-init.el" kittymacs-theme-test-root) nil t)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(setq package-load-list
      (append (mapcar (lambda (name) (list name nil)) kittymacs-theme-test-doom) '(all)))
(package-initialize)
(dolist (fn '(package-install package-refresh-contents))
  (advice-add fn :override
              (lambda (&rest _) (error "Package installation forbidden in theme tests"))))
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-theme-test-root))
(require 'use-package)

(defconst kittymacs-theme-test-module
  (expand-file-name "lisp/kittymacs-ui.el" kittymacs-theme-test-root))

(defun kittymacs-theme-test--load ()
  "Evaluate the appearance module, leaving out the doom declarations."
  (let ((load-file-name kittymacs-theme-test-module))
    (with-temp-buffer
      (insert-file-contents kittymacs-theme-test-module)
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (unless (and (eq (car-safe form) 'use-package)
                           (memq (cadr form) kittymacs-theme-test-doom))
                (eval form t))))
        (end-of-file nil)))))

(kittymacs-theme-test--load)

(ert-deftest kittymacs-theme-module-loads-without-doom ()
  (should (= 2 (length kittymacs-theme-test-doom)))
  (should (featurep 'kittymacs-ui))
  (dolist (feature (append kittymacs-theme-test-doom '(doom-themes-ext-org)))
    (should-not (featurep feature)))
  (should-not (fboundp 'doom-modeline-mode)))

(ert-deftest kittymacs-theme-starts-on-the-built-in-theme ()
  (should (eq kittymacs-theme 'doom-sonokai))
  (should (equal custom-enabled-themes '(modus-vivendi))))

(ert-deftest kittymacs-theme-toggles-between-the-built-in-themes ()
  (kittymacs-load-theme (kittymacs--default-theme))
  (kittymacs-toggle-theme)
  (should (equal custom-enabled-themes '(modus-operandi)))
  (kittymacs-toggle-theme)
  (should (equal custom-enabled-themes '(modus-vivendi))))

(ert-deftest kittymacs-theme-keeps-a-choice-that-does-not-need-doom ()
  (let ((kittymacs-theme 'modus-vivendi-tinted)
        (kittymacs-light-theme 'modus-operandi-tinted))
    (should (eq (kittymacs--default-theme) 'modus-vivendi-tinted))
    (should (eq (kittymacs--other-theme) 'modus-operandi-tinted))))

(ert-deftest kittymacs-theme-module-leaves-org-unloaded ()
  (should-not (featurep 'org)))

;;; kittymacs-theme-tests.el ends here
