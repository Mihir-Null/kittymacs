;;; kittymacs-doc-tests.el --- The pages follow the conventions -*- lexical-binding: t; -*-
;; emacs -Q --batch -l tests/kittymacs-doc-tests.el -f ert-run-tests-batch-and-exit
;; (`just doc-test' does exactly this.)
;;
;; The mechanical half of literate/conventions.org: every page has an ID, a
;; title and one kind tag; every tag is in the vocabulary; IDs are unique;
;; every link resolves; the index lists every chapter; every chapter ends
;; with a Check.  Needs only the Org that ships with Emacs.
(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-element)

(defconst kittymacs-doc-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))

(defconst kittymacs-doc-tags
  '(;; kind: exactly one per page, in #+FILETAGS
    ("meta" . kind) ("core" . kind) ("keys" . kind) ("interface" . kind)
    ("apps" . kind) ("notes" . kind) ("code" . kind) ("nix" . kind)
    ;; system: on the page or on a heading
    ("macos" . system) ("windows" . system) ("linux" . system)
    ("android" . system) ("wsl" . system)
    ;; heading: on headings only
    ("concept" . heading) ("decision" . heading) ("meow" . heading))
  "The tag vocabulary; literate/conventions.org explains each tag.")

(defun kittymacs-doc-tag-type (tag)
  "Return TAG's type in the vocabulary: kind, system or heading; nil if unknown."
  (alist-get tag kittymacs-doc-tags nil nil #'equal))

(defun kittymacs-doc-pages ()
  "Return every page: the Org files in literate/."
  (directory-files (expand-file-name "literate" kittymacs-doc-root) t "\\.org\\'"))

(defun kittymacs-doc-chapter-p (file)
  "Non-nil when FILE is a chapter: literate/NN-name.org."
  (string-match-p "\\`[0-9][0-9]-.*\\.org\\'" (file-name-nondirectory file)))

(defmacro kittymacs-doc-with-page (file &rest body)
  "Run BODY in an Org buffer visiting FILE's text."
  (declare (indent 1))
  `(with-temp-buffer
     (insert-file-contents ,file)
     (let ((org-mode-hook nil)
           (default-directory (file-name-directory ,file)))
       (org-mode)
       ,@body)))

(defun kittymacs-doc-headings ()
  "Return (TITLE TAGS ID LEVEL) for every heading in this buffer."
  (org-element-map (org-element-parse-buffer 'headline) 'headline
    (lambda (h)
      (list (org-element-property :raw-value h)
            (mapcar #'substring-no-properties (org-element-property :tags h))
            (org-element-property :ID h)
            (org-element-property :level h)))))

(defun kittymacs-doc-file-tags ()
  "Return this buffer's #+FILETAGS as a list."
  (split-string (or (cadr (assoc "FILETAGS" (org-collect-keywords '("FILETAGS")))) "")
                ":" t "[ \t]+"))

(defun kittymacs-doc-file-id ()
  "Return the ID in this buffer's file-level property drawer, or nil."
  (save-excursion
    (goto-char (point-min))
    (org-entry-get nil "ID")))

(defun kittymacs-doc-all-ids ()
  "Return an alist of (ID . FILE) over every page and heading."
  (let (ids)
    (dolist (file (kittymacs-doc-pages) (nreverse ids))
      (kittymacs-doc-with-page file
        (when-let* ((id (kittymacs-doc-file-id))) (push (cons id file) ids))
        (dolist (h (kittymacs-doc-headings))
          (when (nth 2 h) (push (cons (nth 2 h) file) ids)))))))

(defun kittymacs-doc-links (type)
  "Return the paths of this buffer's links of TYPE."
  (org-element-map (org-element-parse-buffer) 'link
    (lambda (link)
      (when (equal (org-element-property :type link) type)
        (org-element-property :path link)))))

(defun kittymacs-doc-heading-titles (file)
  "Return the heading titles of FILE."
  (kittymacs-doc-with-page file (mapcar #'car (kittymacs-doc-headings))))

(ert-deftest kittymacs-doc-every-page-has-id-title-and-one-kind ()
  (dolist (file (kittymacs-doc-pages))
    (kittymacs-doc-with-page file
      (should (cons file (kittymacs-doc-file-id)))
      (should (cons file (assoc "TITLE" (org-collect-keywords '("TITLE")))))
      (let ((kinds (seq-filter (lambda (tag) (eq (kittymacs-doc-tag-type tag) 'kind))
                               (kittymacs-doc-file-tags))))
        (should (equal (list file 1) (list file (length kinds))))))))

(ert-deftest kittymacs-doc-tags-are-from-the-vocabulary ()
  (dolist (file (kittymacs-doc-pages))
    (kittymacs-doc-with-page file
      (dolist (tag (kittymacs-doc-file-tags))
        (should (equal (list file tag t)
                       (list file tag (and (memq (kittymacs-doc-tag-type tag) '(kind system)) t)))))
      (dolist (h (kittymacs-doc-headings))
        (dolist (tag (nth 1 h))
          (should (equal (list file (car h) tag t)
                         (list file (car h) tag
                               (and (memq (kittymacs-doc-tag-type tag) '(system heading)) t)))))))))

(ert-deftest kittymacs-doc-tagged-headings-have-ids ()
  "Org-roam lists, and finds by tag, only headings that have an ID."
  (dolist (file (kittymacs-doc-pages))
    (kittymacs-doc-with-page file
      (dolist (h (kittymacs-doc-headings))
        (when (nth 1 h)
          (should (equal (list file (car h) t) (list file (car h) (and (nth 2 h) t)))))))))

(ert-deftest kittymacs-doc-ids-are-unique ()
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (entry (kittymacs-doc-all-ids))
      (should-not (when-let* ((other (gethash (car entry) seen)))
                    (list (car entry) other (cdr entry))))
      (puthash (car entry) (cdr entry) seen))))

(ert-deftest kittymacs-doc-id-links-resolve ()
  (let ((ids (kittymacs-doc-all-ids)))
    (dolist (file (kittymacs-doc-pages))
      (kittymacs-doc-with-page file
        (dolist (id (kittymacs-doc-links "id"))
          (should (equal (list file id t) (list file id (and (assoc id ids) t)))))))))

(ert-deftest kittymacs-doc-file-and-heading-links-resolve ()
  (dolist (file (kittymacs-doc-pages))
    (kittymacs-doc-with-page file
      (let ((titles (mapcar #'car (kittymacs-doc-headings))))
        (dolist (path (kittymacs-doc-links "file"))
          (let* ((parts (split-string path "::"))
                 (target (expand-file-name (car parts)))
                 (search (cadr parts)))
            (should (equal (list file path t) (list file path (file-exists-p target))))
            (when (and search (string-prefix-p "*" search) (string-suffix-p ".org" target))
              (should (equal (list file path t)
                             (list file path (and (member (substring search 1)
                                                          (kittymacs-doc-heading-titles target))
                                                  t)))))))
        (dolist (search (kittymacs-doc-links "fuzzy"))
          (when (string-prefix-p "*" search)
            (should (equal (list file search t)
                           (list file search (and (member (substring search 1) titles) t))))))))))

(ert-deftest kittymacs-doc-index-lists-every-chapter ()
  (let ((listed (kittymacs-doc-with-page (expand-file-name "literate/index.org" kittymacs-doc-root)
                  (kittymacs-doc-links "id"))))
    (dolist (file (seq-filter #'kittymacs-doc-chapter-p (kittymacs-doc-pages)))
      (kittymacs-doc-with-page file
        (should (equal (list file t) (list file (and (member (kittymacs-doc-file-id) listed) t))))))))

(ert-deftest kittymacs-doc-chapters-end-with-check ()
  (dolist (file (seq-filter #'kittymacs-doc-chapter-p (kittymacs-doc-pages)))
    (kittymacs-doc-with-page file
      (let ((top (seq-filter (lambda (h) (= (nth 3 h) 1)) (kittymacs-doc-headings))))
        (should (equal (list file "Check") (list file (car (car (last top))))))))))

(provide 'kittymacs-doc-tests)
;;; kittymacs-doc-tests.el ends here
