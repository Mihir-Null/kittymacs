;;; kittymacs-catalogue-tests.el --- The catalogue tells the truth about the code -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-catalogue-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages: the modules are read, not loaded.  Everything later decides
;; from this list what to install, so these tests hold it to the declarations.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'seq)

(defconst kittymacs-catalogue-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defvar kittymacs-bench-library-only t)
(load (expand-file-name "tools/bench.el" kittymacs-catalogue-test-root) nil t)
(load (expand-file-name "lisp/kittymacs-catalogue.el" kittymacs-catalogue-test-root) nil t)

(defconst kittymacs-catalogue-test-minimal-limit 15
  "The most packages the minimal profile may declare, dependencies aside.")

(defun kittymacs-catalogue-test--property (property)
  "Return the value of PROPERTY for every feature, as (FEATURE . VALUE)."
  (mapcar (lambda (entry) (cons (car entry) (plist-get (cdr entry) property)))
          kittymacs-catalogue))

(defun kittymacs-catalogue-test--declared-by-module ()
  "Return (MODULE . PACKAGES) for every module that declares a package."
  (let (result)
    (dolist (file (directory-files (expand-file-name "lisp" kittymacs-catalogue-test-root)
                                   t "\\`kittymacs-.*\\.el\\'"))
      (when-let* ((names (seq-mapcat #'kittymacs-bench--declared
                                     (kittymacs-bench--forms file))))
        (push (cons (intern (file-name-base file)) names) result)))
    result))

(ert-deftest kittymacs-catalogue-lists-every-declared-package ()
  (let ((declared (apply #'append (mapcar #'cdr (kittymacs-catalogue-test--declared-by-module))))
        (listed (apply #'append (mapcar #'cdr (kittymacs-catalogue-test--property :packages)))))
    (should (> (length declared) 50))
    (should-not (seq-difference declared listed))
    (should-not (seq-difference listed declared))))

(ert-deftest kittymacs-catalogue-gives-each-package-one-feature ()
  (let ((listed (apply #'append (mapcar #'cdr (kittymacs-catalogue-test--property :packages)))))
    (should (equal (length listed) (length (seq-uniq listed))))))

(ert-deftest kittymacs-catalogue-names-the-module-that-declares-each-package ()
  (let ((declared (kittymacs-catalogue-test--declared-by-module)))
    (pcase-dolist (`(,feature . ,plist) kittymacs-catalogue)
      (let ((module (plist-get plist :module)))
        (should (equal (list feature t)
                       (list feature (and (assq module declared) t))))
        (dolist (package (plist-get plist :packages))
          (should (equal (list feature package t)
                         (list feature package
                               (and (memq package (alist-get module declared)) t)))))))))

(ert-deftest kittymacs-catalogue-entries-are-complete ()
  (should (equal (length kittymacs-catalogue)
                 (length (seq-uniq (mapcar #'car kittymacs-catalogue)))))
  (pcase-dolist (`(,feature . ,plist) kittymacs-catalogue)
    (should (equal (list feature t)
                   (list feature (and (memq (plist-get plist :profile) '(minimal full optional)) t))))
    (should (plist-get plist :group))
    (should (plist-get plist :packages))
    (dolist (property '(:summary :example))
      (let ((text (plist-get plist property)))
        (should (equal (list feature property t)
                       (list feature property
                             (and (stringp text) (string-suffix-p "." text) t))))))))

(ert-deftest kittymacs-catalogue-deps-exist-and-stay-within-the-profile ()
  "A feature must not need something its own profile leaves out."
  (let ((rank '((minimal . 0) (full . 1) (optional . 2))))
    (pcase-dolist (`(,feature . ,plist) kittymacs-catalogue)
      (dolist (dep (plist-get plist :deps))
        (let ((target (alist-get dep kittymacs-catalogue)))
          (should (equal (list feature dep t) (list feature dep (and target t))))
          (should (equal (list feature dep t)
                         (list feature dep
                               (<= (alist-get (plist-get target :profile) rank)
                                   (alist-get (plist-get plist :profile) rank))))))))))

(ert-deftest kittymacs-catalogue-deps-have-no-cycles ()
  (let (visit)
    (setq visit (lambda (feature path)
                  (should-not (memq feature path))
                  (dolist (dep (plist-get (alist-get feature kittymacs-catalogue) :deps))
                    (funcall visit dep (cons feature path)))))
    (dolist (entry kittymacs-catalogue)
      (funcall visit (car entry) nil))))

(ert-deftest kittymacs-catalogue-keeps-the-minimal-profile-small ()
  (let ((packages (seq-mapcat (lambda (entry)
                                (when (eq (plist-get (cdr entry) :profile) 'minimal)
                                  (plist-get (cdr entry) :packages)))
                              kittymacs-catalogue)))
    (should (memq 'meow packages))
    (should (<= (length packages) kittymacs-catalogue-test-minimal-limit))))

(ert-deftest kittymacs-catalogue-loads-without-anything-else ()
  "Onboarding reads this under `emacs -Q', before any package exists."
  (let ((forms (kittymacs-bench--forms
                (expand-file-name "lisp/kittymacs-catalogue.el" kittymacs-catalogue-test-root))))
    (should (equal (mapcar #'car forms) '(defconst provide)))))

(ert-deftest kittymacs-catalogue-json-holds-the-same-features ()
  (let* ((file (expand-file-name "nix/features.json" kittymacs-catalogue-test-root))
         (json (with-temp-buffer
                 (insert-file-contents file)
                 (json-parse-buffer :object-type 'alist :array-type 'list))))
    (should (equal (mapcar #'car json) (mapcar #'car kittymacs-catalogue)))
    (pcase-dolist (`(,feature . ,plist) kittymacs-catalogue)
      (let ((entry (alist-get feature json)))
        (should (equal (alist-get 'packages entry)
                       (mapcar #'symbol-name (plist-get plist :packages))))
        (should (equal (alist-get 'profile entry)
                       (symbol-name (plist-get plist :profile))))))))

;;; kittymacs-catalogue-tests.el ends here
