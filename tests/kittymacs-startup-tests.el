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

(defun kittymacs-startup-test--nix-keyed ()
  "The list in nix/packages.nix, as (FEATURE . PACKAGES), in the file's order."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "nix/packages.nix" kittymacs-startup-test-root))
    (re-search-forward "with epkgs;[[:space:]]*{")
    (let ((end (save-excursion (re-search-forward "^[[:space:]]*};")))
          keyed)
      (while (re-search-forward "^[[:space:]]*\\([[:alnum:]_'-]+\\) = \\[\\([^]]*\\)\\];" end t)
        (push (cons (intern (match-string 1))
                    (mapcar #'intern (split-string (match-string 2))))
              keyed))
      (nreverse keyed))))

(defun kittymacs-startup-test--nix-list ()
  "The package names in nix/packages.nix's list."
  (seq-mapcat #'cdr (kittymacs-startup-test--nix-keyed)))

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

(defvar kittymacs-catalogue)

(ert-deftest kittymacs-startup-nix-list-has-the-catalogue-keys ()
  "Each key holds its catalogue entry's packages, less Git's and the archive-only ones."
  (load (expand-file-name "lisp/kittymacs-catalogue.el" kittymacs-startup-test-root) nil t)
  (let ((keyed (kittymacs-startup-test--nix-keyed)))
    (should (equal (sort (mapcar #'car (copy-sequence keyed)) #'string<)
                   (sort (mapcar #'car (copy-sequence kittymacs-catalogue)) #'string<)))
    (pcase-dolist (`(,feature . ,plist) kittymacs-catalogue)
      (should (equal (cons feature
                           (seq-difference (seq-difference (plist-get plist :packages)
                                                           (plist-get plist :vc))
                                           kittymacs-startup-test-archive-only))
                     (assq feature keyed))))))

(defvar kittymacs--archives-refreshed)
(defvar kittymacs-features--failed)

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

(ert-deftest kittymacs-startup-ensure-leaves-alone-what-the-installer-failed-on ()
  "One warning per package, not one from the installer and one from `:ensure'."
  (kittymacs-startup-test--load-defun 'kittymacs-ensure-package)
  (let ((kittymacs--archives-refreshed nil)
        (kittymacs-features--failed '(broken))
        (ensured nil))
    (cl-letf (((symbol-function 'use-package-as-symbol) #'identity)
              ((symbol-function 'package-installed-p) #'ignore)
              ((symbol-function 'package-refresh-contents) #'ignore)
              ((symbol-function 'use-package-ensure-elpa)
               (lambda (name &rest _) (push name ensured))))
      (kittymacs-ensure-package 'broken '(t) nil)
      (should-not ensured)
      (should-not kittymacs--archives-refreshed)
      (kittymacs-ensure-package 'other '(t) nil)
      (should (equal ensured '(other))))))

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

(defvar kittymacs-host-directories nil)

(defmacro kittymacs-startup-test-with-host-files (directories &rest body)
  "Run BODY with the loaders defined and a temporary DIRECTORIES bound to two folders."
  (declare (indent 1))
  `(let* ((root (make-temp-file "kittymacs-host-" t))
          (,directories (list (expand-file-name "system/" root)
                              (expand-file-name "user/" root)))
          (kittymacs-host-directories ,directories)
          (debug-on-error nil)
          (kittymacs-startup-test--loaded nil))
     (kittymacs-startup-test--load-defun 'kittymacs-load-user-file)
     (kittymacs-startup-test--load-defun 'kittymacs-load-host-files)
     (mapc (lambda (directory) (make-directory directory t)) ,directories)
     (unwind-protect (progn ,@body)
       (delete-directory root t))))

(defvar kittymacs-startup-test--loaded nil
  "The host files a test has loaded, newest first.")

(defun kittymacs-startup-test--host-file (directory name &optional body)
  "Write NAME in DIRECTORY, a file that records its name, then runs BODY."
  (with-temp-file (expand-file-name name directory)
    (insert ";;; -*- lexical-binding: t; -*-\n"
            (format "(push %S kittymacs-startup-test--loaded)\n" name)
            (or body ""))))

(ert-deftest kittymacs-startup-host-files-load-in-order ()
  "Each directory in turn, by name, so a user's files follow the system's."
  (kittymacs-startup-test-with-host-files directories
    (kittymacs-startup-test--host-file (cadr directories) "10-user.el")
    (kittymacs-startup-test--host-file (car directories) "90-system.el")
    (kittymacs-startup-test--host-file (car directories) "20-system.el")
    (kittymacs-load-host-files)
    (should (equal (reverse kittymacs-startup-test--loaded)
                   '("20-system.el" "90-system.el" "10-user.el")))))

(ert-deftest kittymacs-startup-host-files-skip-what-is-not-configuration ()
  "Editors leave lock and auto-save files beside the ones they edit."
  (kittymacs-startup-test-with-host-files directories
    (let ((directory (car directories)))
      (kittymacs-startup-test--host-file directory "10-real.el")
      (dolist (name '(".#10-real.el" "#10-real.el#" "#10-real.el" "10-real.el~" "notes.txt"))
        (with-temp-file (expand-file-name name directory)
          (insert "(error \"This must not load\")\n")))
      (kittymacs-startup-test-with-warnings warnings
        (kittymacs-load-host-files)
        (should-not warnings))
      (should (equal kittymacs-startup-test--loaded '("10-real.el"))))))

(ert-deftest kittymacs-startup-host-directories-may-be-missing ()
  "Almost no machine has both directories."
  (kittymacs-startup-test-with-host-files directories
    (let ((kittymacs-host-directories (list "/no/such/kittymacs/directory/" (car directories))))
      (kittymacs-startup-test--host-file (car directories) "10-real.el")
      (kittymacs-startup-test-with-warnings warnings
        (kittymacs-load-host-files)
        (should-not warnings))
      (should (equal kittymacs-startup-test--loaded '("10-real.el"))))))

(ert-deftest kittymacs-startup-a-broken-file-warns-and-the-rest-still-load ()
  "A mistake in one file must not cost the editor needed to fix it."
  (kittymacs-startup-test-with-host-files directories
    (let ((directory (car directories)))
      (kittymacs-startup-test--host-file directory "10-first.el")
      (kittymacs-startup-test--host-file directory "20-broken.el" "(error \"Boom\")\n")
      (with-temp-file (expand-file-name "30-unbalanced.el" directory)
        (insert ";;; -*- lexical-binding: t; -*-\n(setq unbalanced 1"))
      (kittymacs-startup-test--host-file directory "40-last.el")
      (kittymacs-startup-test-with-warnings warnings
        (kittymacs-load-host-files)
        (should (= (length warnings) 2))
        (should (seq-some (lambda (w) (string-match-p "20-broken.el did not finish loading: Boom" w))
                          warnings))
        (should (seq-some (lambda (w) (string-match-p "30-unbalanced.el did not finish" w))
                          warnings)))
      (should (member "40-last.el" kittymacs-startup-test--loaded)))))

(ert-deftest kittymacs-startup-loads-outside-files-in-the-documented-order ()
  "Host files, then private.el, while options can still affect the modules."
  (let* ((text (with-temp-buffer
                 (insert-file-contents (expand-file-name "init.el" kittymacs-startup-test-root))
                 (buffer-string)))
         (position (lambda (form)
                     (or (string-search form text)
                         (ert-fail (list "init.el no longer has" form)))))
         (order (mapcar position
                        '("(require 'kittymacs-defaults)"
                          "(require 'kittymacs-platform)"
                          "(kittymacs-load-host-files)"
                          "(kittymacs-load-user-file private)"
                          "(kittymacs-features-resolve)"
                          "(kittymacs-features-install)"
                          "(kittymacs-platform-apply)"
                          "(kittymacs-require-module 'kittymacs-basics)"
                          "(kittymacs-require-module 'kittymacs-ui)"))))
    (should (equal order (sort (copy-sequence order) #'<)))))

(defun kittymacs-startup-test--backend-tools ()
  "The default of `kittymacs-backend-tools', read from the generated module."
  (eval (nth 2 (seq-find (lambda (form)
                           (and (eq (car-safe form) 'defcustom)
                                (eq (cadr form) 'kittymacs-backend-tools)))
                         (kittymacs-startup-test--forms
                          (expand-file-name "lisp/kittymacs-remote.el" kittymacs-startup-test-root))))
        t))

(defun kittymacs-startup-test--nix-matches (regexp &optional after)
  "Return the first group of each match of REGEXP in nix/tools.nix.
With AFTER, only those between that string and the next closing bracket."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "nix/tools.nix" kittymacs-startup-test-root))
    (when after (search-forward after))
    (let ((end (and after (save-excursion (search-forward "]"))))
          matches)
      (while (re-search-forward regexp end t)
        (push (match-string 1) matches))
      (nreverse matches))))

(ert-deftest kittymacs-startup-the-doctors-agree-on-what-they-share ()
  "`SPC o B' looks for what a backend installs, named as `nix run .#doctor' names it.
The lists differ on purpose: the Nix chapter's \"The apps\" says why."
  (let ((option (kittymacs-startup-test--backend-tools))
        (commands (kittymacs-startup-test--nix-matches
                   "(tool \\(?:null\\|\"[^\"]+\"\\) \"\\([^\"]+\\)\""))
        (installed (kittymacs-startup-test--nix-matches
                    "\"\\([^\"]+\\)\"" "lib.elem entry.command [")))
    (should installed)
    (should-not (seq-difference installed commands))
    (should-not (seq-difference installed option))
    (should (equal (seq-difference option commands)
                   '("inotifywait" "nix" "claude-agent-acp")))))
