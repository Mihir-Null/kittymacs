;;; kittymacs-literate.el --- Edit and build the literate source -*- lexical-binding: t; -*-
;; Generated from literate/80-maintenance.org; edit the Org source, then tangle.
;;; Commentary:
;; Development addition: keep authoring explicit and startup independent of Org.
;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-features)
(require 'kittymacs-leader)

(autoload 'kittymacs-onboard "kittymacs-onboard"
  "Choose what kittymacs installs, and write it to `private.el'." t)

(defun kittymacs-onboard-hint ()
  "Say where this machine started and where to choose, if it has chosen nothing."
  (unless (or noninteractive (daemonp)
              kittymacs-profile kittymacs-features kittymacs-features-excluded)
    (message "kittymacs: nothing chosen yet, so this is the %s profile.  SPC C o chooses, or `just onboard' in a terminal."
             (kittymacs-features-profile))))

(add-hook 'emacs-startup-hook #'kittymacs-onboard-hint 90)

(defun kittymacs-literate-open (&rest _)
  "Open the literate configuration's reading guide."
  (interactive)
  (find-file (expand-file-name "literate/index.org" user-emacs-directory)))
(defun kittymacs-find-config-file ()
  "Open one of the literate chapters."
  (interactive)
  (let ((default-directory (expand-file-name "literate/" user-emacs-directory)))
    (call-interactively #'find-file)))

(defun kittymacs-search-config ()
  "Search the configuration sources with ripgrep."
  (interactive)
  (consult-ripgrep (expand-file-name "literate/" user-emacs-directory)))

(defun kittymacs-open-private-file ()
  "Open private.el, creating it from the example if needed."
  (interactive)
  (let ((private (expand-file-name "private.el" kittymacs-lisp-dir))
        (example (expand-file-name "private.example.el" kittymacs-lisp-dir)))
    (when (and (not (file-exists-p private)) (file-exists-p example))
      (copy-file example private))
    (find-file private)))

(defun kittymacs-open-custom-file ()
  "Open the file where Customize saves settings."
  (interactive)
  (find-file custom-file))

(defun kittymacs-open-architecture ()
  "Open ARCHITECTURE.md, the design record."
  (interactive)
  (find-file (expand-file-name "ARCHITECTURE.md" user-emacs-directory)))
(defun kittymacs-literate--build (write)
  "Run the isolated literate builder; WRITE selects generation over checking."
  (let ((source-dir (expand-file-name "literate/" user-emacs-directory))
        (output (get-buffer-create "*kittymacs literate build*")))
    (dolist (buffer (buffer-list))
      (when-let* ((file (buffer-file-name buffer)))
        (when (and (file-in-directory-p file source-dir)
                   (buffer-modified-p buffer))
          (user-error "Save %s before building the literate configuration" file))))
    (with-current-buffer output
      (let ((inhibit-read-only t)) (erase-buffer)))
    (let ((status
           (call-process (expand-file-name invocation-name invocation-directory)
                         nil (list output t) nil
                         "-Q" "--batch" "-l"
                         (expand-file-name "tools/tangle.el" user-emacs-directory)
                         "--" (if write "--write" "--check"))))
      (display-buffer output)
      (unless (equal status 0)
        (user-error "Literate build failed; see %s" (buffer-name output)))
      (message (if write
                   "Lisp regenerated. Restart Emacs to apply configuration changes."
                 "Literate sources and deployed Lisp agree.")))))
(defun kittymacs-literate-tangle ()
  "Regenerate deployed Lisp from saved literate sources."
  (interactive)
  (kittymacs-literate--build t))
(defun kittymacs-literate-check ()
  "Check that deployed Lisp matches saved literate sources without writing it."
  (interactive)
  (kittymacs-literate--build nil))

(declare-function org-babel-get-src-block-info "ob-core" (&optional no-eval datum))
(declare-function org-element-map "org-element" (data types fun &optional info first-match no-recursion with-affiliated))
(declare-function org-element-parse-buffer "org-element" (&optional granularity visible-only))
(declare-function org-element-property "org-element" (property element &optional dflt force-undefer))
(declare-function org-fold-show-context "org-fold" (&optional key))

(defun kittymacs-literate--source-lines (target line)
  "Return labeled positions for generated LINE in blocks that tangle to TARGET."
  (org-element-map (org-element-parse-buffer) 'src-block
    (lambda (block)
      (save-excursion
        (goto-char (org-element-property :post-affiliated block))
        (let* ((params (nth 2 (org-babel-get-src-block-info 'light)))
               (destination (alist-get :tangle params))
               (end (org-element-property :end block))
               matches)
          (when (equal target destination)
            (forward-line 1)
            (while (and (< (point) end) (not (looking-at-p "[ \t]*#\\+end_src")))
              (let* ((text (string-trim (buffer-substring-no-properties
                                         (line-beginning-position) (line-end-position))))
                     (text (if (or (string-prefix-p ",*" text) (string-prefix-p ",#+" text))
                               (substring text 1)
                             text)))
                (when (equal text line)
                  (push (cons (format "Line %d: %s" (line-number-at-pos) text)
                              (point))
                        matches)))
              (forward-line 1)))
          (nreverse matches))))))

(defun kittymacs-literate-jump-to-source ()
  "Find this generated line in its source chapter.
Offer a choice for duplicate lines, and open the chapter when the line
has changed or was assembled by tangling."
  (interactive)
  (let* ((file (or buffer-file-name (user-error "This buffer has no file")))
         (root (or (locate-dominating-file file "tools/tangle.el")
                   (user-error "This file is outside a Kittymacs checkout")))
         (target (concat "../" (file-relative-name file root)))
         (line (string-trim (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position))))
         (chapter (save-excursion
                    (save-restriction
                      (widen)
                      (goto-char (point-min))
                      (when (re-search-forward
                             "Generated from \\(literate/[0-9][0-9]-[-[:alnum:]_]+\\.org\\)"
                             (line-end-position 6) t)
                        (expand-file-name (match-string-no-properties 1) root))))))
    (unless (and chapter (file-readable-p chapter))
      (user-error "No source chapter recorded in this file"))
    (require 'org)
    (require 'org-element)
    (let* ((buffer (find-file-noselect chapter))
           (candidates (unless (string-empty-p line)
                         (with-current-buffer buffer
                           (save-restriction
                             (widen)
                             (apply #'append (kittymacs-literate--source-lines target line))))))
           (position (pcase candidates
                       ('nil nil)
                       (`((,_ . ,only)) only)
                       (_ (cdr (assoc (completing-read "Source line: " candidates nil t)
                                      candidates))))))
      (pop-to-buffer buffer)
      (widen)
      (goto-char (or position (point-min)))
      (if position
          (org-fold-show-context 'lineage)
        (message "No matching block line; opened %s" (file-name-nondirectory chapter))))))

(keymap-set kittymacs-config-map "c" (cons "reading guide" #'kittymacs-literate-open))
(keymap-set kittymacs-config-map "f" (cons "find chapter" #'kittymacs-find-config-file))
(keymap-set kittymacs-config-map "s" (cons "search config" #'kittymacs-search-config))
(keymap-set kittymacs-config-map "t" (cons "tangle" #'kittymacs-literate-tangle))
(keymap-set kittymacs-config-map "k" (cons "check tangle" #'kittymacs-literate-check))
(keymap-set kittymacs-config-map "j" (cons "jump to source" #'kittymacs-literate-jump-to-source))
(keymap-set kittymacs-config-map "p" (cons "private.el" #'kittymacs-open-private-file))
(keymap-set kittymacs-config-map "o" (cons "onboarding" #'kittymacs-onboard))
(keymap-set kittymacs-config-map "u" (cons "custom.el" #'kittymacs-open-custom-file))
(keymap-set kittymacs-config-map "a" (cons "architecture" #'kittymacs-open-architecture))

(provide 'kittymacs-literate)
;;; kittymacs-literate.el ends here
