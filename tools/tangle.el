;;; tangle.el --- Build kittymacs from Org without loading the config -*- lexical-binding: t; -*-
;; Run from any directory: emacs -Q --batch -l /path/to/tools/tangle.el -- --check
;; Replace --check with --write to regenerate the deployed Lisp files.
(require 'cl-lib)
(require 'json)
(require 'org)
(require 'ob-tangle)

(defconst kittymacs-tangle-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defvar kittymacs-tangle-library-only nil)

(defun kittymacs-tangle--read (file)
  "Read FILE as text with normalized line endings."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun kittymacs-tangle--manifest (root)
  "Read and validate the explicit source/output manifest under ROOT."
  (let ((manifest
         (with-temp-buffer
           (insert-file-contents (expand-file-name "literate/manifest.json" root))
           (json-parse-buffer :object-type 'alist :array-type 'list))))
    (dolist (source (alist-get 'sources manifest))
      (unless (and (stringp source)
                   (equal source (file-name-nondirectory source))
                   (string-suffix-p ".org" source))
        (error "Invalid literate source: %S" source)))
    (let ((outputs (alist-get 'outputs manifest)))
      (unless (= (length outputs) (length (delete-dups (copy-sequence outputs))))
        (error "Duplicate tangled output"))
      (dolist (output outputs)
        (unless (and (stringp output)
                     (not (file-name-absolute-p output))
                     (not (member ".." (split-string output "/")))
                     (or (member output '("early-init.el" "init.el"))
                         (and (string-match-p
                               "\\`lisp/[[:alnum:]_.-]+\\.el\\'" output)
                              (not (string-suffix-p "/private.el" output)))))
          (error "Output is outside generated configuration paths: %S" output))))
    manifest))

(defun kittymacs-tangle--validate-org (file outputs)
  "Check that FILE tangles only Emacs Lisp to declared OUTPUTS."
  (with-current-buffer (find-file-noselect file)
    (org-babel-map-src-blocks nil
      (let* ((info (org-babel-get-src-block-info 'light))
             (target (cdr (assq :tangle (nth 2 info)))))
        (unless (or (null target) (equal target "no"))
          (unless (and (equal (car info) "emacs-lisp")
                       (stringp target)
                       (member target (mapcar (lambda (p) (concat "../" p)) outputs)))
            (error "Undeclared tangle target in %s: %S" file target)))))))

(defun kittymacs-tangle-build (root &optional write)
  "Tangle ROOT in temporary storage; check outputs or WRITE changed files.
No personal startup, package installation, or source-block evaluation is run."
  (let* ((root (file-name-as-directory (expand-file-name root)))
         (manifest (kittymacs-tangle--manifest root))
         (sources (alist-get 'sources manifest))
         (outputs (alist-get 'outputs manifest))
         (stage (make-temp-file "kittymacs-tangle-" t))
         ;; Chapters and outputs are UTF-8 with LF line endings on every
         ;; platform; never let the host locale guess and double-encode.
         (coding-system-for-read 'utf-8)
         (coding-system-for-write 'utf-8-unix)
         (org-confirm-babel-evaluate t)
         (org-src-preserve-indentation t)
         (enable-local-variables nil)
         (enable-local-eval nil)
         (org-babel-pre-tangle-hook nil)
         (org-babel-post-tangle-hook nil)
         generated changed)
    (unwind-protect
        (progn
          (make-directory (expand-file-name "literate" stage))
          (dolist (source sources)
            (let ((copy (expand-file-name (concat "literate/" source) stage)))
              (copy-file (expand-file-name (concat "literate/" source) root) copy)
              (kittymacs-tangle--validate-org copy outputs)
              (setq generated (append (org-babel-tangle-file copy) generated))))
          (unless (= (length generated)
                     (length (delete-dups (copy-sequence generated))))
            (error "An output is tangled by more than one chapter"))
          (unless (equal (sort (delete-dups
                               (mapcar (lambda (p) (file-relative-name p stage)) generated))
                              #'string<)
                         (sort (copy-sequence outputs) #'string<))
            (error "Tangled file set differs from literate/manifest.json"))
          ;; Validate every result before touching any deployed file.
          (dolist (output outputs)
            (let ((file (expand-file-name output stage)))
              (with-temp-buffer
                (insert-file-contents file)
                (let ((emacs-lisp-mode-hook nil) (prog-mode-hook nil)) (emacs-lisp-mode))
                (check-parens))
              (let ((deployed (expand-file-name output root)))
                (unless (and (file-exists-p deployed)
                             (equal (kittymacs-tangle--read file)
                                    (kittymacs-tangle--read deployed)))
                  (push output changed)))))
          (setq changed (nreverse changed))
          (cond
           (write
            (dolist (output changed)
              (let ((destination (expand-file-name output root)))
                (make-directory (file-name-directory destination) t)
                (copy-file (expand-file-name output stage) destination t)))
            (message "LITERATE WRITE: %d files updated; %d outputs validated"
                     (length changed) (length outputs)))
           (changed (error "Literate output drift; run --write: %s"
                           (mapconcat #'identity changed ", ")))
           (t (message "LITERATE CHECK PASS: %d generated files match" (length outputs))))
          changed)
      (dolist (buffer (buffer-list))
        (when-let* ((file (buffer-file-name buffer)))
          (when (file-in-directory-p file stage)
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer))))
      (when (file-in-directory-p stage temporary-file-directory)
        (delete-directory stage t)))))

(when (and noninteractive (not kittymacs-tangle-library-only))
  (let ((args (delete "--" command-line-args-left)))
    (setq command-line-args-left nil)
    (unless (or (null args) (equal args '("--check")) (equal args '("--write")))
      (error "Usage: emacs -Q --batch -l tools/tangle.el -- --check|--write"))
    (kittymacs-tangle-build kittymacs-tangle-root (equal args '("--write")))))
