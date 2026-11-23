;;; kittymacs-hyperbole-book-tests.el --- The book's Hyperbole buttons work -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-hyperbole-book-tests.el -f ert-run-tests-batch-and-exit
;;
;; literate/conventions.org, "Hyperbole in the book", lets a page hold key
;; series in braces and action buttons in angle brackets, and keeps a
;; Koutline map.  The doc tests read them as text; these open every page with
;; Hyperbole on and ask Hyperbole itself what each one is.  Every test skips
;; without Hyperbole: `just test' runs them so, and `just test-packages' with
;; KITTYMACS_TEST_PACKAGES, where Hyperbole is installed and its absence fails.  HOME and the Org
;; directory are temporary, so the reader's HyWiki is a throwaway one.

;;; Code:
(require 'ert)
(require 'package)
(require 'seq)
(require 'cl-lib)

;; Spell the checkout without "~" before HOME moves, as the Hyperbole tests do.
(setq default-directory (expand-file-name default-directory))
;; Windows' runners name the temporary directory in 8.3 form (RUNNER~1),
;; while a visited file's name is the long one: use the long one throughout.
(setq temporary-file-directory
      (file-name-as-directory (file-truename temporary-file-directory)))
(defconst kittymacs-book-test-root
  (expand-file-name
   (file-name-directory
    (directory-file-name
     (file-name-directory (or load-file-name buffer-file-name))))))

(setenv "HOME" (make-temp-file "kittymacs-book-home-" t))
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-book-test-root))
(require 'use-package)

(defvar kittymacs-profile)
(defvar kittymacs-org-directory)
(defvar hywiki-directory)
(defvar hyperb:user-email)
(setq kittymacs-profile 'full
      kittymacs-org-directory (expand-file-name "org/" (getenv "HOME")))
(require 'kittymacs-features)
(let ((use-package-ensure-function #'ignore))
  (require 'kittymacs-hyperbole))

(defun kittymacs-book-test--literate (name)
  "Return the path of NAME in literate/."
  (expand-file-name name (expand-file-name "literate" kittymacs-book-test-root)))

(defun kittymacs-book-test--start ()
  "Skip without Hyperbole; otherwise turn it on.
`just test-packages' runs under the full profile, which installs Hyperbole,
so there a missing Hyperbole fails instead."
  (unless (locate-library "hyperbole")
    (when (and (equal (getenv "KITTYMACS_TEST_PROFILE") "full")
               (getenv "KITTYMACS_TEST_PACKAGES"))
      (error "Hyperbole is not installed in %s" (getenv "KITTYMACS_TEST_PACKAGES")))
    (ert-skip "Hyperbole is not installed"))
  (kittymacs-hyperbole-enable)
  (require 'org))

(defun kittymacs-book-test--categ ()
  "Return the implicit button type Hyperbole sees at point, or nil."
  (when-let* ((button (ignore-errors (hbut:at-p))))
    (hattr:get button 'categ)))

(defmacro kittymacs-book-test--with-page (file &rest body)
  "Run BODY in an Org buffer visiting FILE, at its start."
  (declare (indent 1))
  `(let ((buffer (find-file-noselect ,file)))
     (unwind-protect
         (with-current-buffer buffer
           (save-excursion (goto-char (point-min)) ,@body))
       (kill-buffer buffer))))

(defun kittymacs-book-test--in-markup-p ()
  "Non-nil if point is in verbatim, code, a block or a comment."
  (memq (org-element-type (org-element-context))
        '(verbatim code src-block example-block fixed-width comment comment-block
                   table-cell)))

(defun kittymacs-book-test--action-head (text)
  "Return the symbol an action button's TEXT names, without any $."
  (let ((name (car (split-string (substring text 1 -1) "[ ]" t))))
    (intern (string-remove-prefix "$" name))))

(ert-deftest kittymacs-book-key-series-and-action-buttons-are-buttons ()
  "Every key series in braces is a key series to Hyperbole, and every action
button naming something this Emacs has is an action button.  A button naming
a module this test has not loaded is left to the lint test."
  (kittymacs-book-test--start)
  (let ((keys 0) (actions 0) wrong)
    (dolist (file (directory-files (kittymacs-book-test--literate "") t "\\.org\\'"))
      (kittymacs-book-test--with-page file
        (while (re-search-forward
                "{\\(?:SPC\\|[CMs]-\\)[^{}\n]*}\\|<\\$?[a-z][a-z0-9-]*\\(?: [^<>\n]*\\)?>" nil t)
          (let ((text (match-string 0))
                (start (match-beginning 0)))
            (save-excursion
              (goto-char (1+ start))
              (unless (kittymacs-book-test--in-markup-p)
                (if (eq (aref text 0) ?{)
                    (progn
                      (setq keys (1+ keys))
                      (unless (eq (kittymacs-book-test--categ) 'ibtypes::kbd-key)
                        (push (list (file-name-nondirectory file) text) wrong)))
                  (let ((head (kittymacs-book-test--action-head text)))
                    (when (or (fboundp head) (boundp head))
                      (setq actions (1+ actions))
                      (unless (eq (kittymacs-book-test--categ) 'ibtypes::action)
                        (push (list (file-name-nondirectory file) text) wrong)))))))))))
    (should (> keys 100))
    (should (> actions 30))
    (should-not (reverse wrong))))

(ert-deftest kittymacs-book-map-is-a-koutline-of-the-pages ()
  (kittymacs-book-test--start)
  (let ((buffer (find-file-noselect (kittymacs-book-test--literate "book.kotl"))))
    (unwind-protect
        (with-current-buffer buffer
          (should (derived-mode-p 'kotl-mode))
          ;; One cell to open with, seven parts, a cell per page, and a meta part.
          (kotl-mode:goto-cell "2a")
          (should (string-search "10-startup.org" (kcell-view:contents)))
          (dolist (file (directory-files (kittymacs-book-test--literate "") nil "\\.org\\'"))
            (goto-char (point-min))
            (should (search-forward (format "\"%s\"" file) nil t))
            (backward-char 3)
            (should (equal (list file 'ibtypes::pathname)
                           (list file (kittymacs-book-test--categ)))))
          ;; A reference to a cell, and a key series, are buttons too.
          (goto-char (point-min))
          (search-forward "<@ 6>")
          (backward-char 2)
          (should (eq (kittymacs-book-test--categ) 'ibtypes::klink))
          (goto-char (point-min))
          (search-forward "{C-c C-v}")
          (backward-char 3)
          (should (eq (kittymacs-book-test--categ) 'ibtypes::kbd-key)))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))))

(ert-deftest kittymacs-book-vocabulary-lends-its-words-and-keeps-yours ()
  (kittymacs-book-test--start)
  (let ((hywiki-directory (file-name-as-directory (make-temp-file "kittymacs-hywiki-" t)))
        (vocabulary (kittymacs-book-test--literate "vocabulary.org")))
    ;; A page the reader wrote, under a word the vocabulary also has.
    (with-temp-file (expand-file-name "WikiWord.org" hywiki-directory) (insert "Mine.\n"))
    (hywiki-make-referent-hasht)
    (kittymacs-book-test--with-page vocabulary
      (search-forward "<kittymacs-hywiki-adopt>")
      (backward-char 3)
      (should (eq (kittymacs-book-test--categ) 'ibtypes::action))
      (let ((added (kittymacs-hywiki-adopt vocabulary)))
        (should (member "KittymacsTangle" added))
        (should-not (member "WikiWord" added))))
    (should (equal (car (hywiki-get-referent "WikiWord")) 'page))
    (let ((referent (hywiki-get-referent "KittymacsTangle")))
      (should (eq (car referent) 'org-id))
      (should (equal (org-id-find-id-file (cdr referent)) vocabulary)))
    ;; Adopting again adds nothing and changes nothing.
    (should-not (kittymacs-hywiki-adopt vocabulary))))

(ert-deftest kittymacs-book-words-are-valid-and-unique ()
  "Each :HYWIKI: word is a HyWikiWord, and no two headings share one."
  (kittymacs-book-test--start)
  (let (words)
    (kittymacs-book-test--with-page (kittymacs-book-test--literate "vocabulary.org")
      (org-map-entries (lambda () (push (org-entry-get nil "HYWIKI") words)) "HYWIKI={.}"))
    (should (> (length words) 10))
    (should (equal (length words) (length (delete-dups (copy-sequence words)))))
    (dolist (word words)
      (should (equal (list word t) (list word (and (hywiki-word-is-p word) t)))))))

(provide 'kittymacs-hyperbole-book-tests)
;;; kittymacs-hyperbole-book-tests.el ends here
