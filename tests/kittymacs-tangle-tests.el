;;; kittymacs-tangle-tests.el --- Regression tests for the literate builder -*- lexical-binding: t; -*-
;; emacs -Q --batch -l tests/kittymacs-tangle-tests.el -f ert-run-tests-batch-and-exit
(require 'ert)
(require 'cl-lib)
(defvar kittymacs-tangle-library-only t)
(load (expand-file-name "../tools/tangle.el" (file-name-directory load-file-name)) nil t)

(defun kittymacs-tangle-test-write (root relative text)
  (let ((file (expand-file-name relative root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

(defmacro kittymacs-tangle-test-fixture (&rest body)
  (declare (indent 0))
  `(let ((root (make-temp-file "kittymacs-tangle-test-" t)))
     (unwind-protect
         (progn
           (kittymacs-tangle-test-write root "literate/manifest.json"
             "{\"sources\":[\"test.org\"],\"outputs\":[\"init.el\"]}")
           (kittymacs-tangle-test-write root "literate/test.org"
             "#+begin_src emacs-lisp :tangle ../init.el :mkdirp yes\n(setq fixture-value 42)\n#+end_src\n")
           ,@body)
       (when (file-in-directory-p root temporary-file-directory)
         (delete-directory root t)))))

(ert-deftest kittymacs-tangle-roundtrip-and-no-op ()
  (kittymacs-tangle-test-fixture
    (should (equal (kittymacs-tangle-build root t) '("init.el")))
    (let* ((file (expand-file-name "init.el" root))
           (before (file-attribute-modification-time (file-attributes file))))
      (should-not (kittymacs-tangle-build root))
      (should-not (kittymacs-tangle-build root t))
      (should (equal before (file-attribute-modification-time (file-attributes file)))))))

(ert-deftest kittymacs-tangle-check-preserves-manual-edit ()
  (kittymacs-tangle-test-fixture
    (kittymacs-tangle-build root t)
    (kittymacs-tangle-test-write root "init.el" "(setq fixture-value 'manual)\n")
    (should-error (kittymacs-tangle-build root))
    (should (equal (kittymacs-tangle--read (expand-file-name "init.el" root))
                   "(setq fixture-value 'manual)\n"))))

(ert-deftest kittymacs-tangle-source-edit-requires-explicit-write ()
  (kittymacs-tangle-test-fixture
    (kittymacs-tangle-build root t)
    (kittymacs-tangle-test-write root "literate/test.org"
      "#+begin_src emacs-lisp :tangle ../init.el\n(setq fixture-value 43)\n#+end_src\n")
    (should-error (kittymacs-tangle-build root))
    (should (string-match-p "42" (kittymacs-tangle--read (expand-file-name "init.el" root))))
    (should (equal (kittymacs-tangle-build root t) '("init.el")))
    (should-not (kittymacs-tangle-build root))))

(ert-deftest kittymacs-tangle-rejects-private-and-traversal-targets ()
  (kittymacs-tangle-test-fixture
    (dolist (target '("lisp/private.el" "../outside.el" "var/etc/custom.el"))
      (kittymacs-tangle-test-write root "literate/manifest.json"
        (json-serialize `(:sources ["test.org"] :outputs [,target])))
      (should-error (kittymacs-tangle-build root t)))
    (should-not (file-exists-p (expand-file-name "init.el" root)))))

(ert-deftest kittymacs-tangle-rejects-undeclared-output ()
  (kittymacs-tangle-test-fixture
    (kittymacs-tangle-test-write root "literate/test.org"
      "#+begin_src emacs-lisp :tangle ../early-init.el\n(setq fixture-value 42)\n#+end_src\n")
    (should-error (kittymacs-tangle-build root t))
    (should-not (file-exists-p (expand-file-name "early-init.el" root)))))

(ert-deftest kittymacs-tangle-validates-all-files-before-writing ()
  (kittymacs-tangle-test-fixture
    (kittymacs-tangle-test-write root "init.el" "(setq fixture-value 'original)\n")
    (kittymacs-tangle-test-write root "literate/manifest.json"
      "{\"sources\":[\"test.org\"],\"outputs\":[\"init.el\",\"early-init.el\"]}")
    (kittymacs-tangle-test-write root "literate/test.org"
      (concat "#+begin_src emacs-lisp :tangle ../init.el\n(setq fixture-value 'new)\n#+end_src\n"
              "#+begin_src emacs-lisp :tangle ../early-init.el\n(setq broken\n#+end_src\n"))
    (should-error (kittymacs-tangle-build root t))
    (should (equal (kittymacs-tangle--read (expand-file-name "init.el" root))
                   "(setq fixture-value 'original)\n"))
    (should-not (file-exists-p (expand-file-name "early-init.el" root)))))

(ert-deftest kittymacs-tangle-preserves-fragments-strings-and-does-not-evaluate ()
  (kittymacs-tangle-test-fixture
    (let ((kittymacs-tangle-evaluated nil))
      (kittymacs-tangle-test-write root "literate/test.org"
        (concat "#+PROPERTY: header-args:emacs-lisp :tangle ../init.el :padline no :eval never\n"
                "#+begin_src emacs-lisp\n(setq kittymacs-tangle-evaluated\n#+end_src\n"
                "#+begin_src emacs-lisp\n  \"first\n    second\")\n#+end_src\n"))
      (kittymacs-tangle-build root t)
      (should-not kittymacs-tangle-evaluated)
      (should (equal (kittymacs-tangle--read (expand-file-name "init.el" root))
                     "(setq kittymacs-tangle-evaluated\n  \"first\n    second\")\n")))))

(ert-deftest kittymacs-tangle-rejects-overlapping-chapter-outputs ()
  (kittymacs-tangle-test-fixture
    (kittymacs-tangle-test-write root "init.el" "(setq fixture-value 'original)\n")
    (kittymacs-tangle-test-write root "literate/manifest.json"
      "{\"sources\":[\"test.org\",\"other.org\"],\"outputs\":[\"init.el\"]}")
    (kittymacs-tangle-test-write root "literate/other.org"
      "#+begin_src emacs-lisp :tangle ../init.el\n(setq other-value 1)\n#+end_src\n")
    (should-error (kittymacs-tangle-build root t))
    (should (equal (kittymacs-tangle--read (expand-file-name "init.el" root))
                   "(setq fixture-value 'original)\n"))))
