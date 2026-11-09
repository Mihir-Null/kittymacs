;;; kittymacs-bench-tests.el --- The measuring harness's arithmetic -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-bench-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages and starts no Emacs.  A claim that a change is faster
;; rests on these numbers, so what produces them is tested here.

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

(ert-deftest kittymacs-bench-size-counts-this-checkout ()
  (let ((size (kittymacs-bench-size)))
    (should (> (alist-get 'elisp-lines size) 0))
    (should (> (alist-get 'elisp-conses size) (alist-get 'elisp-lines size)))
    (should (> (alist-get 'declared-packages size) 0))
    (should (> (alist-get 'prose-lines size) 0))))

(ert-deftest kittymacs-bench-org-lines-are-the-chapters-alone ()
  "The prose count holds them, and the two Markdown pages on top."
  (let ((size (kittymacs-bench-size)))
    (should (> (alist-get 'org-lines size) 0))
    (should (= (alist-get 'prose-lines size)
               (+ (alist-get 'org-lines size)
                  (kittymacs-bench--line-count (kittymacs-bench--path "ARCHITECTURE.md"))
                  (kittymacs-bench--line-count (kittymacs-bench--path "README.md")))))))

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

;;; kittymacs-bench-tests.el ends here
