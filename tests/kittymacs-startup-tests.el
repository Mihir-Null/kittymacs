;;; kittymacs-startup-tests.el --- Startup guards, and the Nix package list -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-startup-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages: the declarations are read, not loaded, and the one
;; function under test is taken from init.el without running the rest of it.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst kittymacs-startup-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defconst kittymacs-startup-test-archive-only '(copilot consult-ghostel)
  "Packages declared with `:ensure t' that nix/packages.nix leaves out.
The Nix chapter's \"The Emacs packages\" says why each one.")

(defun kittymacs-startup-test--forms (file)
  "Every top-level form in FILE, read but not evaluated."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun kittymacs-startup-test--ensured (form)
  "Names of the `use-package' declarations with `:ensure t' anywhere in FORM."
  (when (consp form)
    (append (and (eq (car form) 'use-package)
                 (symbolp (cadr form))
                 (eq (cadr (memq :ensure (cddr form))) t)
                 (list (cadr form)))
            (let (names)
              (while (consp form)
                (setq names (append names (kittymacs-startup-test--ensured (car form)))
                      form (cdr form)))
              names))))

(defun kittymacs-startup-test--declared ()
  "Every package a generated module declares with `:ensure t'."
  (seq-uniq
   (seq-mapcat (lambda (file)
                 (seq-mapcat #'kittymacs-startup-test--ensured
                             (kittymacs-startup-test--forms file)))
               (directory-files (expand-file-name "lisp" kittymacs-startup-test-root)
                                t "\\`kittymacs-.*\\.el\\'"))))

(defun kittymacs-startup-test--nix-list ()
  "The package names in nix/packages.nix's list."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "nix/packages.nix" kittymacs-startup-test-root))
    (re-search-forward "with epkgs;[[:space:]]*\\[")
    (let ((end (save-excursion (search-forward "]")))
          names)
      (while (re-search-forward "^[[:space:]]*\\([[:alnum:]_'-]+\\)[[:space:]]*$" end t)
        (push (intern (match-string 1)) names))
      names)))

(ert-deftest kittymacs-startup-nix-list-matches-declarations ()
  "nix/packages.nix lists exactly the declared packages, less the archive-only ones."
  (let ((declared (kittymacs-startup-test--declared))
        (nix (kittymacs-startup-test--nix-list)))
    (should (> (length declared) 50))
    (dolist (package kittymacs-startup-test-archive-only)
      (should (memq package declared)))
    (should-not (seq-difference
                 (seq-difference declared kittymacs-startup-test-archive-only) nix))
    (should-not (seq-difference nix declared))
    (should-not (seq-intersection nix kittymacs-startup-test-archive-only))))

(defvar kittymacs--archives-refreshed)

(defun kittymacs-startup-test--load-defun (name)
  "Define NAME from its `defun' in init.el, and nothing else from that file."
  (let ((form (seq-find (lambda (form)
                          (and (eq (car-safe form) 'defun) (eq (cadr form) name)))
                        (kittymacs-startup-test--forms
                         (expand-file-name "init.el" kittymacs-startup-test-root)))))
    (should form)
    (eval form t)))

(defmacro kittymacs-startup-test-with-warnings (var &rest body)
  "Run BODY with an empty `after-init-hook', collecting warning texts in VAR."
  (declare (indent 1))
  `(let ((after-init-hook nil)
         (,var nil))
     (cl-letf (((symbol-function 'display-warning)
                (lambda (_type message &rest _) (push message ,var))))
       ,@body)))

(ert-deftest kittymacs-startup-after-init-guards ()
  "A missing or failing after-init function warns; a working one runs, in depth order."
  (kittymacs-startup-test--load-defun 'kittymacs-after-init)
  (let ((debug-on-error nil)
        (calls nil))
    (defalias 'kittymacs-startup-test--works (lambda () (push 'works calls)))
    (defalias 'kittymacs-startup-test--early (lambda () (push 'early calls)))
    (defalias 'kittymacs-startup-test--fails (lambda () (error "Boom")))
    (fmakunbound 'kittymacs-startup-test--missing)
    (kittymacs-startup-test-with-warnings warnings
      (kittymacs-after-init #'kittymacs-startup-test--works 90)
      (kittymacs-after-init #'kittymacs-startup-test--missing 90)
      (kittymacs-after-init #'kittymacs-startup-test--fails 90)
      (kittymacs-after-init #'kittymacs-startup-test--early 10)
      (run-hooks 'after-init-hook)
      (should (equal (reverse calls) '(early works)))
      (should (= (length warnings) 2))
      (should (seq-some (lambda (w) (string-match-p "--missing is not defined" w)) warnings))
      (should (seq-some (lambda (w) (string-match-p "--fails failed after init: Boom" w)) warnings)))))

(ert-deftest kittymacs-startup-ensure-refreshes-once-before-first-install ()
  "The index is refreshed once, before the first install, and never when all is installed."
  (kittymacs-startup-test--load-defun 'kittymacs-ensure-package)
  (let ((kittymacs--archives-refreshed nil)
        (installed '(present))
        (events nil))
    (cl-letf (((symbol-function 'use-package-as-symbol) #'identity)
              ((symbol-function 'package-installed-p) (lambda (p) (memq p installed)))
              ((symbol-function 'package-refresh-contents) (lambda () (push 'refresh events)))
              ((symbol-function 'use-package-ensure-elpa)
               (lambda (name &rest _) (push name installed) (push (list 'ensure name) events))))
      (kittymacs-ensure-package 'present '(t) nil)
      (should-not (memq 'refresh events))
      (kittymacs-ensure-package 'first '(t) nil)
      (kittymacs-ensure-package 'second '((second . "melpa")) nil)
      (should (equal (reverse events)
                     '((ensure present) refresh (ensure first) (ensure second)))))))

(ert-deftest kittymacs-startup-ensure-survives-offline ()
  "A refresh that fails warns once and the install still goes ahead."
  (kittymacs-startup-test--load-defun 'kittymacs-ensure-package)
  (let ((kittymacs--archives-refreshed nil)
        (debug-on-error nil)
        (refreshes 0)
        (ensured nil))
    (cl-letf (((symbol-function 'use-package-as-symbol) #'identity)
              ((symbol-function 'package-installed-p) #'ignore)
              ((symbol-function 'package-refresh-contents)
               (lambda () (cl-incf refreshes) (error "Offline")))
              ((symbol-function 'use-package-ensure-elpa)
               (lambda (name &rest _) (push name ensured))))
      (kittymacs-startup-test-with-warnings warnings
        (kittymacs-ensure-package 'one '(t) nil)
        (kittymacs-ensure-package 'two '(t) nil)
        (should (= refreshes 1))
        (should (equal ensured '(two one)))
        (should (= (length warnings) 1))
        (should (string-match-p "Could not refresh.*Offline" (car warnings)))))))

;;; kittymacs-startup-tests.el ends here
