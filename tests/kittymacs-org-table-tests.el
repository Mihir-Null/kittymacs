;;; kittymacs-org-table-tests.el --- Org table cells that wrap -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-org-table-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages: the table forms are taken from lisp/kittymacs-org.el
;; without running the rest of it, and Org is Emacs's own.

;;; Code:
(require 'ert)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-table)

(defconst kittymacs-org-table-test-module
  (expand-file-name "../lisp/kittymacs-org.el"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun kittymacs-org-table-test--load ()
  "Evaluate the table definitions of the Org module, and nothing else."
  (with-temp-buffer
    (insert-file-contents kittymacs-org-table-test-module)
    (condition-case nil
        (while t
          (let ((form (read (current-buffer))))
            (when (and (memq (car-safe form) '(defun defcustom defconst))
                       (string-match-p "org-table" (symbol-name (cadr form))))
              (eval form t))))
      (end-of-file nil))))

(kittymacs-org-table-test--load)

(defun kittymacs-org-table-test--wrap (text)
  "TEXT, an Org buffer's contents, after wrapping every table in it."
  (with-temp-buffer
    (org-mode)
    (insert text)
    (kittymacs-org-table-wrap-all)
    (buffer-string)))

(defconst kittymacs-org-table-test-table
  (concat "| Candidate | Source | Verdict |\n"
          "|-\n"
          "| <10> | <16> | <12> |\n"
          "|-\n"
          "| ~cargo fmt~ and nixfmt formatters | community: ~rust-lang/rustfmt~ | Designed (formatter hooks) |\n"
          "|-\n"
          "| gh | commercial (GitHub) | adopt |\n"))

(ert-deftest kittymacs-org-table-wraps-long-cells-to-their-cookies ()
  (should (equal (kittymacs-org-table-test--wrap kittymacs-org-table-test-table)
                 (concat "| Candidate   | Source              | Verdict    |\n"
                         "|-------------+---------------------+------------|\n"
                         "| <10>        | <16>                | <12>       |\n"
                         "|-------------+---------------------+------------|\n"
                         "| ~cargo fmt~ | community:          | Designed   |\n"
                         "| and nixfmt  | ~rust-lang/rustfmt~ | (formatter |\n"
                         "| formatters  |                     | hooks)     |\n"
                         "|-------------+---------------------+------------|\n"
                         "| gh          | commercial          | adopt      |\n"
                         "|             | (GitHub)            |            |\n"))))

(ert-deftest kittymacs-org-table-wrapping-twice-changes-nothing ()
  (let ((once (kittymacs-org-table-test--wrap kittymacs-org-table-test-table)))
    (should (equal (kittymacs-org-table-test--wrap once) once))))

(ert-deftest kittymacs-org-table-cookie-row-in-the-header-is-kept-once ()
  (let* ((text "| <6> | <6> |\n| Name | Note |\n|-\n| a b c d e f | x |\n")
         (once (kittymacs-org-table-test--wrap text)))
    (should (= (with-temp-buffer (insert once) (how-many "<6>" (point-min) (point-max))) 2))
    (should (equal (kittymacs-org-table-test--wrap once) once))))

(ert-deftest kittymacs-org-table-edited-continuation-row-reflows ()
  (with-temp-buffer
    (org-mode)
    (insert (kittymacs-org-table-test--wrap kittymacs-org-table-test-table))
    (goto-char (point-min))
    (search-forward "(GitHub)")
    (insert " with a longer edit")
    (kittymacs-org-table-wrap-all)
    (should (string-match-p (concat "| gh +| commercial +| adopt +|\n"
                                    "| +| (GitHub) with a +| +|\n"
                                    "| +| longer edit +| +|\n")
                            (buffer-string)))))

(ert-deftest kittymacs-org-table-keeps-every-character ()
  (dolist (text '("a=1 and ~/src" "x ~ y = z" "(~code span~), then =a b= done"))
    (should (equal (string-join (kittymacs--org-table-words text) " ") text))))

(ert-deftest kittymacs-org-table-never-splits-links-or-code ()
  (should (equal (kittymacs--org-table-fill
                  "see [[https://orgmode.org][the org manual]] and ~a long span~" 8)
                 '("see" "[[https://orgmode.org][the org manual]]" "and" "~a long span~"))))

(ert-deftest kittymacs-org-table-leaves-tables-that-have-not-opted-in ()
  (dolist (text '(;; no cookie row
                  "| a | a very long cell that must stay on one line |\n|-\n| b | c |\n"
                  ;; cookies but no hline: every row would merge into one
                  "| <4> | <4> |\n| a long one | b |\n| c | d |\n"
                  ;; formulas name rows by number
                  "| <4> | <4> |\n|-\n| a long one | 1 |\n#+TBLFM: $2=1\n"))
    (should (equal (kittymacs-org-table-test--wrap text) text))))

(ert-deftest kittymacs-org-table-unchanged-table-is-not-rewritten ()
  (with-temp-buffer
    (org-mode)
    (insert (kittymacs-org-table-test--wrap kittymacs-org-table-test-table))
    (set-buffer-modified-p nil)
    (kittymacs-org-table-wrap-all)
    (should-not (buffer-modified-p))))

(ert-deftest kittymacs-org-table-point-keeps-its-row-and-column ()
  (with-temp-buffer
    (org-mode)
    (insert "Before.\n\n" kittymacs-org-table-test-table "\nAfter.\n")
    (goto-char (point-min))
    (search-forward "| gh")
    (kittymacs-org-table-wrap-all)
    (should (looking-back "| gh" (line-beginning-position))))
  (with-temp-buffer
    (org-mode)
    (insert "Before.\n\n" kittymacs-org-table-test-table "\nAfter.\n")
    (goto-char (point-min))
    (search-forward "| commerc")
    (kittymacs-org-table-wrap-all)
    (should (looking-at "ial +| adopt"))
    (goto-char (point-max))
    (forward-line -1)
    (let ((after (point)))
      (kittymacs-org-table-wrap-all)
      (should (= (point) after)))))

(ert-deftest kittymacs-org-table-wraps-on-save-by-default ()
  (let ((file (make-temp-file "kittymacs-table-" nil ".org")))
    (unwind-protect
        (with-current-buffer (find-file-noselect file)
          (add-hook 'org-mode-hook #'kittymacs--org-table-wrap-setup)
          (unwind-protect
              (progn
                (org-mode)
                (insert kittymacs-org-table-test-table)
                (save-buffer)
                (should (string-match-p "| and nixfmt +|" (buffer-string)))
                (kill-buffer))
            (remove-hook 'org-mode-hook #'kittymacs--org-table-wrap-setup)))
      (delete-file file))))

;;; kittymacs-org-table-tests.el ends here
