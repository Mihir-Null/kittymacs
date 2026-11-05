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
    (should-not (seq-difference (plist-get plist :vc) (plist-get plist :packages)))
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

(defun kittymacs-catalogue-test--vc-declared (form)
  "Names of the `use-package' declarations with `:vc' anywhere in FORM."
  (when (consp form)
    (append (and (eq (car form) 'use-package)
                 (memq :vc (cddr form))
                 (list (cadr form)))
            (let (names)
              (while (consp form)
                (setq names (append names (kittymacs-catalogue-test--vc-declared (car form)))
                      form (cdr form)))
              names))))

(ert-deftest kittymacs-catalogue-says-which-packages-come-from-git ()
  "The installer leaves these to their declarations, so it must know them all."
  (let ((declared (seq-mapcat
                   (lambda (file)
                     (seq-mapcat #'kittymacs-catalogue-test--vc-declared
                                 (kittymacs-bench--forms file)))
                   (directory-files (expand-file-name "lisp" kittymacs-catalogue-test-root)
                                    t "\\`kittymacs-.*\\.el\\'")))
        (listed (apply #'append (mapcar #'cdr (kittymacs-catalogue-test--property :vc)))))
    (should declared)
    (should-not (seq-difference declared listed))
    (should-not (seq-difference listed declared))))

;;; The gates

(defun kittymacs-catalogue-test--init-gates ()
  "Return (FEATURE . MODULE) for each chapter init.el loads behind a feature."
  (let (gates)
    (dolist (form (kittymacs-bench--forms
                   (expand-file-name "init.el" kittymacs-catalogue-test-root)))
      (pcase form
        (`(when (kittymacs-feature-p ',feature) (kittymacs-require-module ',module))
         (push (cons feature module) gates))))
    gates))

(defun kittymacs-catalogue-test--declarations-and-gates (form gates)
  "Return (PACKAGE . CONDITIONS) for each `use-package' in FORM.
CONDITIONS are those of the `when' forms around it, starting from GATES."
  (when (consp form)
    (pcase form
      (`(use-package ,(and name (pred symbolp)) . ,_) (list (cons name gates)))
      (`(when ,condition . ,body)
       (seq-mapcat (lambda (inner)
                     (kittymacs-catalogue-test--declarations-and-gates
                      inner (cons condition gates)))
                   body))
      (_ (let (found)
           (while (consp form)
             (setq found (append found (kittymacs-catalogue-test--declarations-and-gates
                                        (car form) gates))
                   form (cdr form)))
           found)))))

(defun kittymacs-catalogue-test--asks-for-p (conditions feature)
  "Return non-nil if one of CONDITIONS asks whether FEATURE is on."
  (seq-some (lambda (condition)
              (or (and (eq feature 'terminal) (eq condition 'kittymacs-terminal-ghostel))
                  (string-search (format "%S" `(kittymacs-feature-p ',feature))
                                 (format "%S" condition))))
            conditions))

(defun kittymacs-catalogue-test--ungated (entries init-gates declarations)
  "Return (FEATURE PACKAGE) for each package of ENTRIES its feature cannot stop.
INIT-GATES are the chapters init.el gates, and DECLARATIONS come from
`kittymacs-catalogue-test--declarations-and-gates', with each module's name."
  (let (ungated)
    (pcase-dolist (`(,feature . ,plist) entries)
      (unless (or (eq (plist-get plist :profile) 'minimal)
                  (equal (assq feature init-gates) (cons feature (plist-get plist :module))))
        (dolist (package (plist-get plist :packages))
          (unless (kittymacs-catalogue-test--asks-for-p
                   (alist-get package declarations) feature)
            (push (list feature package) ungated)))))
    ungated))

(ert-deftest kittymacs-catalogue-ungated-finds-a-package-no-gate-stops ()
  (let* ((entries '((plain :profile full :module m :packages (a))
                    (gated :profile full :module m :packages (b))
                    (wrong :profile full :module m :packages (c))
                    (floor :profile minimal :module m :packages (d))
                    (whole :profile full :module n :packages (e))))
         (declarations
          (kittymacs-catalogue-test--declarations-and-gates
           '(progn (use-package a :ensure t)
                   (when (kittymacs-feature-p 'gated) (use-package b :ensure t))
                   (when (kittymacs-feature-p 'gated) (use-package c :ensure t))
                   (use-package d :ensure t)
                   (use-package e :ensure t))
           nil)))
    (should (equal (sort (kittymacs-catalogue-test--ungated
                          entries '((whole . n)) declarations)
                         (lambda (x y) (string< (car x) (car y))))
                   '((plain a) (wrong c))))))

(ert-deftest kittymacs-catalogue-every-optional-package-sits-behind-its-feature ()
  "A package added to a mixed module without a gate would install for everyone."
  (let ((declarations
         (seq-mapcat (lambda (file)
                       (seq-mapcat (lambda (form)
                                     (kittymacs-catalogue-test--declarations-and-gates form nil))
                                   (kittymacs-bench--forms file)))
                     (directory-files (expand-file-name "lisp" kittymacs-catalogue-test-root)
                                      t "\\`kittymacs-.*\\.el\\'"))))
    (should (> (length declarations) 50))
    (should-not (kittymacs-catalogue-test--ungated
                 kittymacs-catalogue (kittymacs-catalogue-test--init-gates) declarations))))

(ert-deftest kittymacs-catalogue-init-gates-each-chapter-on-its-own-feature ()
  (let ((gates (kittymacs-catalogue-test--init-gates)))
    (should (>= (length gates) 8))
    (pcase-dolist (`(,feature . ,module) gates)
      (should (equal (list feature module)
                     (list feature (plist-get (alist-get feature kittymacs-catalogue) :module)))))))

(ert-deftest kittymacs-catalogue-gates-name-features-that-exist ()
  (let (asked)
    (dolist (file (cons (expand-file-name "init.el" kittymacs-catalogue-test-root)
                        (directory-files (expand-file-name "lisp" kittymacs-catalogue-test-root)
                                         t "\\`kittymacs-.*\\.el\\'")))
      (with-temp-buffer
        (insert-file-contents file)
        (while (re-search-forward "(kittymacs-feature-p '\\([a-z-]+\\))" nil t)
          (push (intern (match-string 1)) asked))))
    (should (> (length asked) 30))
    (should-not (seq-remove (lambda (name) (assq name kittymacs-catalogue))
                            (seq-uniq asked)))))

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
