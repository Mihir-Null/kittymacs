;;; kittymacs-msys2-tests.el --- The MSYS2 fallback, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-msys2-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages.  A temporary directory stands for the MSYS2 root, and
;; `system-type' is a plain variable, so the Windows branch runs here too.
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(defvar kittymacs-cache-dir temporary-file-directory)
(require 'kittymacs-catalogue)
(require 'kittymacs-platform)

(defvar kittymacs-msys2-root)
(defvar ghostel-shell)
(defvar ghostel-environment)
(defvar ghostel-buffer-name)

(defun kittymacs-msys2-test--program (root path)
  "Create an executable at PATH under ROOT."
  (let ((file (expand-file-name path root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "#!/bin/sh\n"))
    (set-file-modes file #o755)))

(defmacro kittymacs-msys2-test-with-root (&rest body)
  "Run BODY with a stand-in root, and a clean `exec-path', collecting warnings."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "kittymacs-msys2-" t)))
          (exec-path (list "/git/usr/bin/"))
          (process-environment (cons "DICPATH" (copy-sequence process-environment)))
          (warnings nil))
     (setenv "MSYS2_ROOT" root)
     (unwind-protect
         (cl-letf (((symbol-function 'display-warning)
                    (lambda (type text &rest _) (push (cons type text) warnings))))
           (load "kittymacs-msys2" nil t)
           (setq warnings nil)
           (setq kittymacs-msys2-root root)
           ,@body)
       (delete-directory root t)
       (setq features (delq 'kittymacs-msys2 features)))))

(ert-deftest kittymacs-msys2-the-catalogue-keeps-it-off-and-on-windows-only ()
  (let ((entry (alist-get 'msys2-fallback kittymacs-catalogue)))
    (should (eq (plist-get entry :profile) 'optional))
    (should-not (memq 'windows-nt (plist-get entry :not-on)))
    (dolist (system '(gnu/linux darwin android))
      (should (memq system (plist-get entry :not-on))))))

(ert-deftest kittymacs-msys2-warns-with-the-reason-and-the-use ()
  (kittymacs-msys2-test-with-root
    (kittymacs-msys2-apply)
    (should (= (length warnings) 1))
    (should (equal (caar warnings) '(kittymacs msys2-fallback)))
    (should (string-match-p "fallback" (cdar warnings)))
    (should (string-match-p "WSL2 backend" (cdar warnings)))
    (should (string-match-p "Windows-side files" (cdar warnings)))
    (should-not (string-match-p "No MSYS2 at" (cdar warnings)))))

(ert-deftest kittymacs-msys2-warns-when-the-root-holds-nothing ()
  (kittymacs-msys2-test-with-root
    (setq kittymacs-msys2-root (expand-file-name "not-here/" root))
    (kittymacs-msys2-apply)
    (should (string-match-p "No MSYS2 at" (cdar warnings)))))

(ert-deftest kittymacs-msys2-its-programs-come-after-every-other ()
  (kittymacs-msys2-test-with-root
    (kittymacs-msys2-apply)
    (should (equal exec-path (list "/git/usr/bin/"
                                   (expand-file-name "ucrt64/bin" root)
                                   (expand-file-name "usr/bin" root))))))

(ert-deftest kittymacs-msys2-the-spell-checker-finds-its-hunspell ()
  (kittymacs-msys2-test-with-root
    (kittymacs-msys2-test--program root "ucrt64/bin/hunspell")
    (make-directory (expand-file-name "ucrt64/share/hunspell" root) t)
    (let ((system-type 'windows-nt))
      (should-not (kittymacs-spell-checker))
      (kittymacs-msys2-apply)
      (should (equal (kittymacs-spell-checker)
                     (expand-file-name "ucrt64/bin/hunspell" root)))
      (should (equal (getenv "DICPATH") (expand-file-name "ucrt64/share/hunspell" root))))))

(ert-deftest kittymacs-msys2-keeps-a-dicpath-you-set ()
  (kittymacs-msys2-test-with-root
    (make-directory (expand-file-name "ucrt64/share/hunspell" root) t)
    (setenv "DICPATH" "/mine")
    (kittymacs-msys2-apply)
    (should (equal (getenv "DICPATH") "/mine"))))

(ert-deftest kittymacs-msys2-the-terminal-names-what-is-missing ()
  (kittymacs-msys2-test-with-root
    (let ((system-type 'windows-nt))
      (should (string-match-p "kittymacs-msys2-root"
                              (cadr (should-error (kittymacs-terminal-msys2)
                                                  :type 'user-error)))))
    (let ((system-type 'gnu/linux))
      (should-error (kittymacs-terminal-msys2) :type 'user-error))))

(ert-deftest kittymacs-msys2-the-terminal-opens-a-ucrt64-login-shell ()
  (kittymacs-msys2-test-with-root
    (kittymacs-msys2-test--program root "usr/bin/bash.exe")
    (let ((system-type 'windows-nt)
          (ghostel-environment '("KEPT=1"))
          seen)
      (cl-letf (((symbol-function 'ghostel)
                 (lambda (_) (setq seen (list ghostel-shell ghostel-environment ghostel-buffer-name)))))
        (kittymacs-terminal-msys2))
      (should (equal (car seen) (list (expand-file-name "usr/bin/bash.exe" root) "--login" "-i")))
      (should (member "MSYSTEM=UCRT64" (cadr seen)))
      (should (member "CHERE_INVOKING=1" (cadr seen)))
      (should (member "KEPT=1" (cadr seen))))))

;;; kittymacs-msys2-tests.el ends here
