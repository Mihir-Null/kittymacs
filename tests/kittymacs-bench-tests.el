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
      (when (string-match-p "\\`module-\\|\\`elisp-\\|\\`prose-\\|\\`declared-"
                            (symbol-name (car entry)))
        (should (memq (car entry) known))))))

;;; kittymacs-bench-tests.el ends here
