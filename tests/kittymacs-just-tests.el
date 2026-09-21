;;; kittymacs-just-tests.el --- Justfile recipe runner -*- lexical-binding: t; -*-
;; Run: EMACS_DOTS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-just-tests.el -f ert-run-tests-batch-and-exit
;; Loads kittymacs-programming.el with package installation disabled; `just' itself
;; is never run, so these pass on a machine that does not have it.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'package)
(when-let* ((directory (getenv "EMACS_DOTS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path
             (expand-file-name "../lisp"
                               (file-name-directory (or load-file-name buffer-file-name))))
(require 'use-package)
;; The runner is the subject; nothing here should reach the package archives.
(setq use-package-ensure-function #'ignore)
(require 'kittymacs-programming)

(defmacro kittymacs-just-test-with-project (&rest body)
  "Run BODY with `default-directory' inside a throwaway project holding a justfile.
The justfile sits at the root; BODY starts one directory below it, so a
test that passes has walked up to find it."
  (declare (indent 0))
  `(let ((root (file-name-as-directory (make-temp-file "kittymacs-just" t))))
     (unwind-protect
         (let ((nested (expand-file-name "src/" root)))
           (write-region "default:\n\techo hi\n" nil (expand-file-name "justfile" root))
           (make-directory nested)
           (let ((default-directory nested)) ,@body))
       (delete-directory root t))))

(defun kittymacs-just-test-parent ()
  "The directory above `default-directory', resolved for comparison."
  (file-name-as-directory (file-truename (expand-file-name ".." default-directory))))

(ert-deftest kittymacs-just-root-walks-up-to-the-justfile ()
  (kittymacs-just-test-with-project
    (should (equal (file-name-as-directory (file-truename (kittymacs-just-root)))
                   (kittymacs-just-test-parent)))))

(ert-deftest kittymacs-just-root-is-nil-without-a-justfile ()
  (let ((default-directory (file-name-as-directory (make-temp-file "kittymacs-nojust" t))))
    (unwind-protect (should-not (kittymacs-just-root))
      (delete-directory default-directory t))))

(ert-deftest kittymacs-just-recipes-splits-the-summary ()
  (kittymacs-just-test-with-project
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (insert "tangle  check\nbuild switch\n") 0)))
      (should (equal (kittymacs-just-recipes (kittymacs-just-root))
                     '("tangle" "check" "build" "switch"))))))

(ert-deftest kittymacs-just-recipes-survives-a-missing-program ()
  (kittymacs-just-test-with-project
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (error "No such file or directory"))))
      (should-not (kittymacs-just-recipes (kittymacs-just-root))))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 1)))
      (should-not (kittymacs-just-recipes (kittymacs-just-root))))))

(ert-deftest kittymacs-just-compiles-in-the-justfile-directory ()
  (kittymacs-just-test-with-project
    (let (ran directory)
      (cl-letf (((symbol-function 'compile)
                 (lambda (command &rest _)
                   (setq ran command directory default-directory))))
        (kittymacs-just "build"))
      (should (equal ran "just build"))
      (should (equal (file-name-as-directory (file-truename directory))
                     (kittymacs-just-test-parent))))))

(ert-deftest kittymacs-just-honours-the-program-setting ()
  (kittymacs-just-test-with-project
    (let ((kittymacs-just-program "/usr/bin/just") ran)
      (cl-letf (((symbol-function 'compile) (lambda (command &rest _) (setq ran command))))
        (kittymacs-just "check"))
      (should (equal ran "/usr/bin/just check")))))

(ert-deftest kittymacs-just-uses-a-terminal-when-asked ()
  (kittymacs-just-test-with-project
    (let (terminal-command compiled)
      (cl-letf (((symbol-function 'ghostel-compile)
                 (lambda (command &rest _) (setq terminal-command command)))
                ((symbol-function 'compile)
                 (lambda (command &rest _) (setq compiled command))))
        (kittymacs-just "switch" t))
      (should (equal terminal-command "just switch"))
      (should-not compiled))))

(ert-deftest kittymacs-just-refuses-outside-a-project ()
  (let ((default-directory (file-name-as-directory (make-temp-file "kittymacs-nojust" t))))
    (unwind-protect
        (should-error (kittymacs-just "build") :type 'user-error)
      (delete-directory default-directory t))))

(ert-deftest kittymacs-just-is-on-the-project-prefix-map ()
  (require 'project)
  (should (eq (lookup-key project-prefix-map "j") #'kittymacs-just))
  (should (member '(kittymacs-just "Just recipe") project-switch-commands)))

(provide 'kittymacs-just-tests)
;;; kittymacs-just-tests.el ends here
