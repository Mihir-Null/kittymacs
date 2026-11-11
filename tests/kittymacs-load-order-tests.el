;;; kittymacs-load-order-tests.el --- Early modules work before later ones load -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-load-order-tests.el -f ert-run-tests-batch-and-exit
;;
;; Loads, under the full profile and in init.el's order, the modules up to and
;; including the look, so `doom-look' is on and the remote chapter has not
;; loaded.  A package's first install from Git visits files at that point in a
;; real start, because the version-control chapter comes before the remote one.

;;; Code:
(require 'ert)
(require 'package)

(defconst kittymacs-load-order-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-load-order-" t))
      native-comp-jit-compilation nil)
(load (expand-file-name "early-init.el" kittymacs-load-order-test-root) nil t)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(dolist (fn '(package-install package-vc-install package-refresh-contents))
  (advice-add fn :override
              (lambda (&rest _) (error "Package installation forbidden in load-order tests"))))
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-load-order-test-root))
(require 'use-package)

(setq kittymacs-profile 'full)
(require 'kittymacs-defaults)
(require 'kittymacs-platform)
(require 'kittymacs-basics)
(require 'kittymacs-ui)

(ert-deftest kittymacs-load-order-a-file-opens-before-the-remote-chapter ()
  "doom-modeline's version update runs on every visit, behind the look's guard.
The guard's predicate once lived in the remote chapter, so a file visited
before that chapter loaded signalled `void-function', and a first install
of diff-review stopped half done."
  (should (kittymacs-feature-p 'doom-look))
  (should-not (featurep 'kittymacs-remote))
  (should (featurep 'doom-modeline-env))
  (should (advice-member-p #'kittymacs-remote-buffer-p 'doom-modeline-update-env))
  (let ((file (make-temp-file "kittymacs-load-order-" nil ".txt" "text\n")))
    (unwind-protect
        (kill-buffer (find-file-noselect file))
      (delete-file file)))
  (with-temp-buffer
    (doom-modeline-update-env)))

;;; kittymacs-load-order-tests.el ends here
