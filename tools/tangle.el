;;; tangle.el --- Build kittymacs from Org without loading the config -*- lexical-binding: t; -*-
;; Run from any directory: emacs -Q --batch -l /path/to/tools/tangle.el -- --check
;; Replace --check with --write to regenerate the deployed files.
;; (`just tangle' and `just tangle-check' do exactly this.)
;;
;; The chapters are the files in literate/ whose names start with two digits
;; and a dash (10-startup.org); the outputs are whatever their :tangle headers
;; name.  There is no list to keep in step: adding a chapter file is enough.
;; Two kinds of output exist: Emacs Lisp (the startup files and lisp/) and
;; Nix (flake.nix and nix/).  See literate/80-maintenance.org.
(require 'cl-lib)
(require 'org)
(require 'ob-tangle)

(defconst kittymacs-tangle-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defvar kittymacs-tangle-library-only nil)

(defconst kittymacs-tangle-chapter-regexp "\\`[0-9][0-9]-.*\\.org\\'"
  "Names of the chapter files in literate/; index.org and the rest are prose only.")

(defun kittymacs-tangle--read (file)
  "Read FILE as text with normalized line endings."
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defun kittymacs-tangle--output-language (output)
  "Return the source language OUTPUT, relative to the root, must be written in.
Return nil when OUTPUT may not be generated at all.  Emacs Lisp may go to
early-init.el, init.el and files directly in lisp/, but never lisp/private.el,
which belongs to the user.  Nix may go to flake.nix and to nix/, at most one
directory deep (nix/tools.nix, nix/example/flake.nix)."
  (and (not (file-name-absolute-p output))
       (not (member ".." (split-string output "/")))
       (cond ((or (member output '("early-init.el" "init.el"))
                  (and (string-match-p "\\`lisp/[[:alnum:]_.-]+\\.el\\'" output)
                       (not (equal output "lisp/private.el"))))
              "emacs-lisp")
             ((or (equal output "flake.nix")
                  (string-match-p "\\`nix/\\([[:alnum:]_.-]+/\\)?[[:alnum:]_.-]+\\.nix\\'" output))
              "nix"))))

(defun kittymacs-tangle--outputs (file)
  "Return the outputs chapter FILE tangles to, relative to the root.
Every tangled block must name a target with `../' in front of an allowed
output, since chapters live one level down in literate/, and be written in
that output's language."
  (let (outputs)
    (with-current-buffer (find-file-noselect file)
      (org-babel-map-src-blocks nil
        (let* ((info (org-babel-get-src-block-info 'light))
               (target (cdr (assq :tangle (nth 2 info))))
               (output (and (stringp target)
                            (string-prefix-p "../" target)
                            (substring target 3))))
          (unless (or (null target) (equal target "no"))
            (unless (and output
                         (equal (car info) (kittymacs-tangle--output-language output)))
              (error "Tangle target outside the generated configuration in %s: %S"
                     (file-name-nondirectory file) target))
            (cl-pushnew output outputs :test #'equal)))))
    outputs))

(defun kittymacs-tangle--orphans (root outputs)
  "Return the generated-looking files under ROOT that no chapter generates.
They are lisp/kittymacs-*.el and the .nix files under nix/, left over from
a chapter that was deleted or retargeted: startup would still load the
module, and the flake would still import the Nix file."
  (let ((lisp (expand-file-name "lisp" root))
        (nix (expand-file-name "nix" root)))
    (seq-remove
     (lambda (file) (member file outputs))
     (append
      (when (file-directory-p lisp)
        (mapcar (lambda (name) (concat "lisp/" name))
                (directory-files lisp nil "\\`kittymacs-.*\\.el\\'")))
      (when (file-directory-p nix)
        (mapcar (lambda (file) (file-relative-name file root))
                (directory-files-recursively nix "\\.nix\\'")))))))

(defun kittymacs-tangle-build (root &optional write)
  "Tangle ROOT in temporary storage; check outputs or WRITE changed files.
No personal startup, package installation, or source-block evaluation is run."
  (let* ((root (file-name-as-directory (expand-file-name root)))
         (sources (directory-files (expand-file-name "literate" root) nil
                                   kittymacs-tangle-chapter-regexp))
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
         outputs changed)
    (unwind-protect
        (progn
          (make-directory (expand-file-name "literate" stage))
          ;; Read every chapter's targets before tangling any of them.
          (dolist (source sources)
            (let ((copy (expand-file-name (concat "literate/" source) stage)))
              (copy-file (expand-file-name (concat "literate/" source) root) copy)
              (dolist (output (kittymacs-tangle--outputs copy))
                (when (member output outputs)
                  (error "%s is tangled by more than one chapter" output))
                (push output outputs))))
          (setq outputs (sort outputs #'string<))
          (when-let* ((orphans (kittymacs-tangle--orphans root outputs)))
            (error "No chapter generates %s; delete it or restore its chapter"
                   (mapconcat #'identity orphans ", ")))
          (dolist (source sources)
            (org-babel-tangle-file (expand-file-name (concat "literate/" source) stage)))
          ;; Validate every result before touching any deployed file.
          (dolist (output outputs)
            (let ((file (expand-file-name output stage)))
              ;; Lisp must at least balance; Nix is checked by `just lint'
              ;; and `just eval', which need Nix.
              (when (string-suffix-p ".el" output)
                (with-temp-buffer
                  (insert-file-contents file)
                  (let ((emacs-lisp-mode-hook nil) (prog-mode-hook nil)) (emacs-lisp-mode))
                  (check-parens)))
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
