;;; kittymacs-bench-tests.el --- The measuring harness's arithmetic -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-bench-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages and starts no Emacs.  The numbers decide later what a
;; change may cost, so what produces them is tested here.

;;; Code:
(require 'ert)

(defvar kittymacs-bench-library-only t)
(load (expand-file-name "../tools/bench.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest kittymacs-bench-host-files-are-what-init-would-load ()
  "A host file changes the measurement, so the report has to name it."
  (let ((root (make-temp-file "kittymacs-bench-host-" t)))
    (unwind-protect
        (let ((host (expand-file-name "10-host.el" root)))
          (should-not (kittymacs-bench--host-files (list root "/no/such/directory/")))
          (with-temp-file host (insert ";; A host.\n"))
          (with-temp-file (expand-file-name ".#10-host.el" root) (insert ""))
          (with-temp-file (expand-file-name "notes.txt" root) (insert ""))
          (should (equal (kittymacs-bench--host-files (list root "/no/such/directory/"))
                         (list host))))
      (delete-directory root t))))

(ert-deftest kittymacs-bench-host-directories-come-from-init ()
  (let ((process-environment (cons "XDG_CONFIG_HOME=/no/such/config" process-environment)))
    (should (listp (kittymacs-bench--host-files)))))

(ert-deftest kittymacs-bench-median-handles-odd-and-even-counts ()
  (should (= (kittymacs-bench--median '(3 1 2)) 2.0))
  (should (= (kittymacs-bench--median '(4 1 3 2)) 2.5))
  (should (= (kittymacs-bench--median '(7)) 7.0)))

(ert-deftest kittymacs-bench-median-leaves-its-argument-alone ()
  (let ((numbers (list 3 1 2)))
    (kittymacs-bench--median numbers)
    (should (equal numbers '(3 1 2)))))

(ert-deftest kittymacs-bench-p90-is-nearest-rank ()
  (should (= (kittymacs-bench--p90 (number-sequence 1 20)) 18.0))
  (should (= (kittymacs-bench--p90 (number-sequence 1 10)) 9.0))
  (should (= (kittymacs-bench--p90 '(5)) 5.0)))

(ert-deftest kittymacs-bench-conses-ignore-how-the-code-is-laid-out ()
  (should (= (kittymacs-bench--conses '(a (b c)))
             (kittymacs-bench--conses (car (read-from-string "(a\n\n  (b\n c))")))))
  (should (= (kittymacs-bench--conses 'a) 0))
  (should (= (kittymacs-bench--conses '(a b)) 2))
  (should (= (kittymacs-bench--conses '(a (b))) 3)))

(ert-deftest kittymacs-bench-declared-finds-every-way-to-install ()
  (should (equal (kittymacs-bench--declared '(use-package a :ensure t)) '(a)))
  (should (equal (kittymacs-bench--declared '(use-package a :vc (:url "u"))) '(a))))

(ert-deftest kittymacs-bench-declared-looks-inside-gates ()
  (should (equal (kittymacs-bench--declared
                  '(when gate (use-package a :ensure t) (use-package b :ensure t)))
                 '(a b))))

(ert-deftest kittymacs-bench-declared-skips-what-installs-nothing ()
  (should-not (kittymacs-bench--declared '(use-package a :ensure nil)))
  (should-not (kittymacs-bench--declared '(use-package a :defer t))))

(ert-deftest kittymacs-bench-closure-follows-requirements-once ()
  (let ((alist (list (list 'a (package-desc-create :name 'a :reqs '((b (1)) (emacs (31)))))
                     (list 'b (package-desc-create :name 'b :reqs '((a (1)))))
                     (list 'c (package-desc-create :name 'c)))))
    (should (equal (sort (kittymacs-bench--closure '(a) alist) #'string<) '(a b)))
    (should-not (kittymacs-bench--closure '(not-installed) alist))))

(ert-deftest kittymacs-bench-compare-reports-only-differences ()
  (should-not (kittymacs-bench--compare '((a . 1)) '((a . 1))))
  (should (equal (kittymacs-bench--compare '((a . 1)) '((a . 2))) '((a 1 2))))
  (should (equal (kittymacs-bench--compare nil '((a . 2))) '((a nil 2)))))

(ert-deftest kittymacs-bench-size-counts-this-checkout ()
  (let ((size (kittymacs-bench-size)))
    (should (> (alist-get 'elisp-lines size) 0))
    (should (> (alist-get 'elisp-conses size) (alist-get 'elisp-lines size)))
    (should (> (alist-get 'declared-packages size) 0))
    (should (> (alist-get 'prose-lines size) 0))
    (should (alist-get 'module-lines/init size))))

(ert-deftest kittymacs-bench-size-leaves-out-the-private-file ()
  (should-not (seq-some (lambda (file) (string-suffix-p "/private.el" file))
                        (kittymacs-bench--elisp-files))))

(ert-deftest kittymacs-bench-a-failed-run-is-noted-and-does-not-stop-the-rest ()
  (let ((kittymacs-bench--failures nil))
    (cl-letf (((symbol-function 'kittymacs-bench--run)
               (lambda (&rest _) (error "Exited with status 139"))))
      (should-not (kittymacs-bench--attempt '("-Q")))
      (should (equal kittymacs-bench--failures '("Exited with status 139")))
      (should-error (kittymacs-bench--measure '("-Q") 0)))))

(ert-deftest kittymacs-bench-keeps-the-reports-of-the-runs-that-worked ()
  (let ((kittymacs-bench--failures nil)
        (calls 0)
        (process-environment (cons "KITTYMACS_BENCH_RUNS=2" process-environment)))
    (cl-letf (((symbol-function 'kittymacs-bench--run)
               (lambda (&rest _)
                 (setq calls (1+ calls))
                 (if (= calls 4) (error "Died") '(:first-idle 1.0)))))
      (should (equal (kittymacs-bench--measure '("-Q") 0) '((:first-idle 1.0))))
      (should (equal kittymacs-bench--failures '("Died"))))))

(ert-deftest kittymacs-bench-output-tail-is-short-and-printable ()
  (should (equal (kittymacs-bench--output-tail "a\e[2Jb\n") "a [2Jb "))
  (should (= (length (kittymacs-bench--output-tail (make-string 1000 ?x))) 300)))

(ert-deftest kittymacs-bench-terminal-numbers-are-never-called-graphical ()
  "An Emacs without a toolkit ignores DISPLAY and starts in the terminal."
  (should (kittymacs-bench--display-mismatch-p nil '(:graphic nil)))
  (should-not (kittymacs-bench--display-mismatch-p nil '(:graphic t)))
  (should-not (kittymacs-bench--display-mismatch-p '("-nw") '(:graphic nil))))

(ert-deftest kittymacs-bench-samples-are-outside-the-checkout ()
  "Inside it, `.dir-locals.el' makes `emacs -Q' wait for an answer forever."
  (let ((directory (make-temp-file "kittymacs-bench-test-" t)))
    (unwind-protect
        (pcase-let ((`(,el . ,org) (kittymacs-bench--make-samples directory)))
          (should (file-exists-p el))
          (should (file-exists-p org))
          (should-not (file-in-directory-p el kittymacs-bench-root))
          (should-not (locate-dominating-file el ".dir-locals.el")))
      (delete-directory directory t))))

(ert-deftest kittymacs-bench-budgets-name-only-metrics-this-harness-reports ()
  (let ((known (mapcar #'car (kittymacs-bench-size))))
    (dolist (entry (kittymacs-bench--budgets))
      (when (string-match-p "\\`module-\\|\\`elisp-\\|\\`prose-\\|\\`declared-\\|\\`default-"
                            (symbol-name (car entry)))
        (should (memq (car entry) known))))))

;;; What the default profile loads

(ert-deftest kittymacs-bench-default-modules-stop-at-a-gate-that-is-off ()
  "A real start holds this list to the truth: see tests/verify-config.el."
  (let ((modules (kittymacs-bench-default-modules)))
    (dolist (module '(kittymacs-features kittymacs-leader kittymacs-ui kittymacs-org))
      (should (memq module modules)))
    (dolist (module '(kittymacs-onboard kittymacs-treemacs kittymacs-agents
                                        kittymacs-org-roam kittymacs-dashboard))
      (should-not (memq module modules)))))

(ert-deftest kittymacs-bench-default-loaded-is-less-than-everything ()
  "The point of the count: onboarding and the gated chapters do not add to it."
  (let ((size (kittymacs-bench-size)))
    (should (< (alist-get 'default-loaded-lines size) (alist-get 'elisp-lines size)))
    (should (< (alist-get 'default-loaded-conses size) (alist-get 'elisp-conses size)))
    (should (< (alist-get 'default-packages size) (alist-get 'declared-packages size)))))

(ert-deftest kittymacs-bench-modules-look-only-at-what-runs-as-it-loads ()
  (should (equal (kittymacs-bench--modules-in '(require 'kittymacs-leader) nil)
                 '(kittymacs-leader)))
  (should-not (kittymacs-bench--modules-in '(require 'seq) nil))
  (should-not (kittymacs-bench--modules-in
               '(defun later () (require 'kittymacs-leader)) nil))
  (should-not (kittymacs-bench--modules-in
               '(when (kittymacs-feature-p 'agents) (require 'kittymacs-agents)) '(meow)))
  (should (equal (kittymacs-bench--modules-in
                  '(when (kittymacs-feature-p 'agents) (kittymacs-require-module 'kittymacs-agents))
                  '(agents))
                 '(kittymacs-agents))))

;;; Holding the budgets to the merge base

(ert-deftest kittymacs-bench-a-reason-names-its-budgets ()
  (should (equal (kittymacs-bench--parse-reason "elisp-lines, module-lines/init: it had to grow")
                 '((elisp-lines module-lines/init) . "it had to grow")))
  (should-not (kittymacs-bench--parse-reason "elisp-lines:"))
  (should-not (kittymacs-bench--parse-reason "no colon here")))

(ert-deftest kittymacs-bench-rises-are-what-went-up-from-the-base ()
  (should (equal (kittymacs-bench--rises '((a . 1) (b . 5) (c . 2)) '((a . 2) (b . 4) (c . 2) (d . 9)))
                 '((a 1 2)))))

(ert-deftest kittymacs-bench-a-measured-count-replaces-the-recorded-one ()
  (should (equal (sort (kittymacs-bench--current '((a . 1) (b . 2)) '((a . 3)))
                       (lambda (x y) (string< (car x) (car y))))
                 '((a . 3) (b . 2)))))

(ert-deftest kittymacs-bench-a-module-may-go-and-a-budget-may-not ()
  (should (equal (kittymacs-bench--missing '((features . 1) (module-lines/gone . 2)) nil)
                 '(features))))

(defun kittymacs-bench-test--git (&rest arguments)
  "Run git with ARGUMENTS in `default-directory', as a throwaway author."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil
                          "-c" "user.name=Test" "-c" "user.email=test@example.invalid"
                          "-c" "commit.gpgsign=false" arguments))
      (error "git %S: %s" arguments (buffer-string)))))

(defun kittymacs-bench-test--check (budget-text message measured)
  "Commit BUDGET-TEXT with MESSAGE on a branch off a base, and run the check.
Return what the check returned, with MEASURED standing in for the count of code."
  (let* ((root (file-name-as-directory (make-temp-file "kittymacs-bench-git-" t)))
         (default-directory root)
         (kittymacs-bench-root root)
         (budgets (expand-file-name "tests/budgets.eld" root)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory budgets))
          (kittymacs-bench-test--git "init" "-q" "-b" "main")
          (with-temp-file budgets (insert "((a . 5) (b . 5) (recorded . 5))\n"))
          (kittymacs-bench-test--git "add" ".")
          (kittymacs-bench-test--git "commit" "-q" "-m" "Base")
          (kittymacs-bench-test--git "switch" "-q" "-c" "change")
          (with-temp-file budgets (insert budget-text))
          (kittymacs-bench-test--git "add" ".")
          (kittymacs-bench-test--git "commit" "-q" "--allow-empty" "-m" message)
          (cl-letf (((symbol-function 'kittymacs-bench-size) (lambda () measured))
                    ((symbol-function 'princ) #'ignore))
            (kittymacs-bench-check "main")))
      (delete-directory root t))))

(ert-deftest kittymacs-bench-check-fails-a-rise-with-no-reason ()
  (skip-unless (executable-find "git"))
  (should (kittymacs-bench-test--check "((a . 6) (b . 5) (recorded . 5))\n"
                                       "Grow\n\nBecause."
                                       '((a . 6) (b . 5)))))

(ert-deftest kittymacs-bench-check-passes-a-rise-with-a-reason-for-that-budget ()
  (skip-unless (executable-find "git"))
  (should-not (kittymacs-bench-test--check "((a . 6) (b . 5) (recorded . 5))\n"
                                           "Grow\n\nBudget-rise: a: it had to."
                                           '((a . 6) (b . 5)))))

(ert-deftest kittymacs-bench-check-fails-a-rise-with-a-reason-for-another-budget ()
  (skip-unless (executable-find "git"))
  (should (kittymacs-bench-test--check "((a . 6) (b . 5) (recorded . 5))\n"
                                       "Grow\n\nBudget-rise: b: it had to."
                                       '((a . 6) (b . 5)))))

(ert-deftest kittymacs-bench-check-passes-a-fall ()
  (skip-unless (executable-find "git"))
  (should-not (kittymacs-bench-test--check "((a . 4) (b . 5) (recorded . 3))\n"
                                           "Shrink"
                                           '((a . 4) (b . 5)))))

(ert-deftest kittymacs-bench-check-holds-a-count-only-a-start-can-measure ()
  "A count `just size' cannot see is held by the file, so a rise there needs a reason."
  (skip-unless (executable-find "git"))
  (should (kittymacs-bench-test--check "((a . 5) (b . 5) (recorded . 6))\n"
                                       "More"
                                       '((a . 5) (b . 5)))))

(ert-deftest kittymacs-bench-check-fails-a-file-that-disagrees-with-the-code ()
  "Otherwise a fall leaves room for a later rise, and a rise ambushes the next change."
  (skip-unless (executable-find "git"))
  (should (kittymacs-bench-test--check "((a . 5) (b . 5) (recorded . 5))\n"
                                       "Shrink, and forget to write it"
                                       '((a . 4) (b . 5)))))

(ert-deftest kittymacs-bench-check-fails-a-dropped-budget ()
  (skip-unless (executable-find "git"))
  (should (kittymacs-bench-test--check "((a . 5) (b . 5))\n"
                                       "Lose one"
                                       '((a . 5) (b . 5)))))

(ert-deftest kittymacs-bench-check-is-silent-about-a-flake-bump ()
  "A commit that touches nothing counted has nothing to state."
  (skip-unless (executable-find "git"))
  (should-not (kittymacs-bench-test--check "((a . 5) (b . 5) (recorded . 5))\n"
                                           "Bump flake.lock"
                                           '((a . 5) (b . 5)))))

;;; kittymacs-bench-tests.el ends here
