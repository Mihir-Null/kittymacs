;;; kittymacs-org-node.el --- Linked notes across registered roots -*- lexical-binding: t; -*-
;; Generated from literate/71-org-node.org; edit the Org source, then tangle.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'kittymacs-leader)

(use-package org-mem :ensure t :defer t)
(use-package org-node :ensure t :defer t)

(defvar kittymacs-org-directory)
(defvar org-note-abort)
(defvar org-capture-templates)
(defvar org-mem-do-look-everywhere)
(defvar org-mem-watch-dirs)
(defvar org-mem-updater-mode)
(defvar kittymacs-org-roam-excluded-directories)
(declare-function org-mem-await "org-mem")
(declare-function org-mem-all-entries "org-mem")
(declare-function org-mem-all-links "org-mem")
(declare-function org-mem-entry-file "org-mem")
(declare-function org-mem-entry-id "org-mem")
(declare-function org-mem-entry-lnum "org-mem")
(declare-function org-mem-entry-properties-local "org-mem")
(declare-function org-mem-entry-roam-aliases "org-mem")
(declare-function org-mem-entry-tags "org-mem")
(declare-function org-mem-entry-title-maybe "org-mem")
(declare-function org-mem-id-links-to-id "org-mem")
(declare-function org-mem-link-entry "org-mem")
(declare-function org-mem-link-file "org-mem")
(declare-function org-mem-link-target "org-mem")
(declare-function org-mem-link-type "org-mem")
(declare-function org-mem-reset "org-mem")
(declare-function org-mem-updater-mode "org-mem-updater")
(declare-function org-mem-updater-update "org-mem-updater")
(declare-function org-node-goto "org-node")
(declare-function org-node-p "org-node")
(declare-function org-capture "org-capture")
(declare-function org-capture-get "org-capture")
(declare-function org-entry-get-with-inheritance "org")
(declare-function org-id-get-create "org-id")
(declare-function org-link-make-string "ol")

(defgroup kittymacs-org-node nil "Personal and project notes." :group 'kittymacs)

(defcustom kittymacs-org-node-directory
  (or (bound-and-true-p kittymacs-org-roam-directory) kittymacs-org-directory)
  "Personal notes root."
  :type 'directory)

(defcustom kittymacs-org-node-projects nil
  "Persistent project declarations of the form (ROOT :notes DIR :capture FILE :exclude NAMES)."
  :type '(repeat sexp))

(defcustom kittymacs-org-node-project nil
  "Register the current .dir-locals.el directory as a project."
  :type 'boolean :safe #'booleanp)

(defun kittymacs--org-node-relative-p (path)
  "Whether PATH is local, relative and contains no parent traversal."
  (and (stringp path) (not (string-empty-p path))
       (not (file-name-absolute-p path)) (not (file-remote-p path))
       (not (string-prefix-p "~" path))
       (not (member ".." (split-string path "[/\\\\]" t)))))

(defcustom kittymacs-org-node-project-directory "."
  "Notes directory within a directory-local project."
  :type 'string :safe #'kittymacs--org-node-relative-p)

(defcustom kittymacs-org-node-capture-file "inbox.org"
  "Capture destination relative to the notes directory."
  :type 'string :safe #'kittymacs--org-node-relative-p)

(defcustom kittymacs-org-node-excluded-directories
  (or (bound-and-true-p kittymacs-org-roam-excluded-directories)
      '(".git" ".cache" "cache" "caches"))
  "Directory basenames excluded from the personal or opted-in project root."
  :type '(repeat string) :safe #'list-of-strings-p)

(defvar kittymacs--org-node-discovered nil)
(defvar kittymacs--org-node-index-roots nil)

(defun kittymacs--org-node-below-p (file root)
  "Whether FILE is ROOT or lies beneath it."
  (or (equal (directory-file-name file) (directory-file-name root))
      (file-in-directory-p file root)))

(defun kittymacs--org-node-root (base &rest options)
  "Normalize the notes and capture paths for BASE and OPTIONS."
  (when (file-remote-p base)
    (user-error "Linked notes require a local root: %s" base))
  (let* ((base (file-name-as-directory (file-truename base)))
         (subdir (or (plist-get options :notes) "."))
         (capture (or (plist-get options :capture) "inbox.org")))
    (unless (and (kittymacs--org-node-relative-p subdir)
                 (kittymacs--org-node-relative-p capture)
                 (string-suffix-p ".org" capture t))
      (user-error "Invalid notes or capture path for %s" base))
    (let* ((notes (file-name-as-directory (file-truename (expand-file-name subdir base))))
           (file (file-truename (expand-file-name capture notes))))
      (unless (and (kittymacs--org-node-below-p notes base) (file-in-directory-p file notes))
        (user-error "Notes or capture escapes its root: %s" file))
      (list base :notes notes :capture file :exclude (plist-get options :exclude)))))

(defun kittymacs--org-node-register ()
  "Remember a project whose directory locals explicitly opt in."
  (when (and (not (file-remote-p default-directory))
             (or (alist-get 'kittymacs-org-node-project dir-local-variables-alist)
                 (alist-get 'kittymacs-org-roam-project dir-local-variables-alist)))
    (when-let* ((source (dir-locals-find-file (or buffer-file-name default-directory)))
                (base (if (consp source) (car source) source)))
      (setf (alist-get (file-name-as-directory (file-truename base))
                      kittymacs--org-node-discovered nil nil #'equal)
            (list :notes kittymacs-org-node-project-directory
                  :capture kittymacs-org-node-capture-file
                  :exclude (or (and (local-variable-p 'kittymacs-org-roam-excluded-directories)
                                    kittymacs-org-roam-excluded-directories)
                               kittymacs-org-node-excluded-directories))))))

(add-hook 'hack-local-variables-hook #'kittymacs--org-node-register)

(defun kittymacs--org-node-roots ()
  "Return registered project roots, most specific first, then the personal root."
  (let ((seen (make-hash-table :test #'equal)) projects)
    (dolist (spec (append kittymacs--org-node-discovered kittymacs-org-node-projects))
      (let ((root (apply #'kittymacs--org-node-root spec)))
        (unless (gethash (car root) seen)
          (puthash (car root) t seen)
          (push root projects))))
    (append (sort projects (lambda (left right) (> (length (car left)) (length (car right)))))
            (list (kittymacs--org-node-root
                   kittymacs-org-node-directory
                   :capture (default-value 'kittymacs-org-node-capture-file)
                   :exclude (default-value 'kittymacs-org-node-excluded-directories))))))

(defun kittymacs--org-node-scope (roots)
  "Choose the active scope among ROOTS."
  (let ((file (or buffer-file-name default-directory)))
    (or (and (not (file-remote-p file))
             (seq-find (lambda (root) (kittymacs--org-node-below-p file (car root))) roots))
        (car (last roots)))))

(defun kittymacs--org-node-file-in-root-p (file root)
  "Whether FILE is inside ROOT's notes directory and passes its exclusions."
  (let ((notes (plist-get (cdr root) :notes)))
    (and (file-in-directory-p file notes)
         (not (seq-intersection
               (butlast (split-string (file-relative-name file notes) "/" t))
               (plist-get (cdr root) :exclude) #'string-equal)))))

(defun kittymacs--org-node-owner (file)
  "Return FILE's most specific registered root, if it allows FILE."
  (when-let* ((root (seq-find (lambda (scope) (kittymacs--org-node-below-p file (car scope)))
                             kittymacs--org-node-index-roots)))
    (when (kittymacs--org-node-file-in-root-p file root) root)))

(defun kittymacs--org-node-scan-files (scan &rest arguments)
  "Filter Org Mem's SCAN result before it parses files."
  (let ((files (apply scan arguments)))
    (if kittymacs--org-node-index-roots
        (seq-filter (lambda (file) (kittymacs--org-node-owner (car file))) files)
      files)))

(defun kittymacs--org-node-prepare (&optional refresh)
  "Load the backend lazily and refresh changed files when REFRESH is set."
  (require 'org)
  (require 'org-id)
  (require 'org-node)
  (require 'org-mem-updater)
  (kittymacs--org-node-register)
  (let* ((roots (kittymacs--org-node-roots))
         (directories (seq-filter #'file-directory-p
                                  (mapcar (lambda (r) (plist-get (cdr r) :notes)) roots)))
         (changed (not (equal roots kittymacs--org-node-index-roots))))
    (setq kittymacs--org-node-index-roots roots)
    (when directories
      (advice-add 'org-mem--truenames-and-attrs :around #'kittymacs--org-node-scan-files)
      (setq org-mem-do-look-everywhere nil org-mem-watch-dirs (delete-dups directories))
      (cond ((not org-mem-updater-mode) (org-mem-updater-mode 1))
            (changed (org-mem-reset t))
            (refresh (org-mem-updater-update t)))
      (unless (org-mem-await "Indexing linked notes..." 30)
        (user-error "Linked notes are still indexing; try again when the scan finishes")))
    roots))

(defun kittymacs--org-node-open-id (&rest _)
  "Index opted-in roots before visiting an ID link."
  (kittymacs--org-node-prepare))

(with-eval-after-load 'org-id
  (advice-add 'org-id-open :before #'kittymacs--org-node-open-id))

(defun kittymacs--org-node-indexed-entries ()
  "Return entries belonging to registered notes roots."
  (seq-filter (lambda (entry) (kittymacs--org-node-owner (org-mem-entry-file entry)))
              (org-mem-all-entries)))

(defun kittymacs--org-node-entries (scope &optional tag)
  "Return ID notes in SCOPE (nil means all), optionally limited to TAG."
  (seq-filter (lambda (entry)
                (and (org-node-p entry)
                     (or (not scope) (equal scope (kittymacs--org-node-owner (org-mem-entry-file entry))))
                     (or (not tag) (member tag (org-mem-entry-tags entry)))))
              (kittymacs--org-node-indexed-entries)))

(defun kittymacs--org-node-title (entry)
  "Return ENTRY's display title."
  (or (org-mem-entry-title-maybe entry) (file-name-base (org-mem-entry-file entry))))

(defun kittymacs--org-node-read (scope &optional tag)
  "Read a note from SCOPE or all roots, optionally limited to TAG."
  (let ((candidates (make-hash-table :test #'equal)))
    (dolist (entry (kittymacs--org-node-entries scope tag))
      (let ((where (format "%s:%d" (abbreviate-file-name (org-mem-entry-file entry))
                           (org-mem-entry-lnum entry)))
            (tags (mapconcat (lambda (item) (concat " #" item)) (org-mem-entry-tags entry))))
        (dolist (title (cons (kittymacs--org-node-title entry) (org-mem-entry-roam-aliases entry)))
          (puthash (format "%s%s  [%s]" title tags where) entry candidates))))
    (when (hash-table-empty-p candidates)
      (user-error "No linked notes in this scope"))
    (gethash (completing-read (format "Note (%s): " (if scope (car scope) "all roots"))
                              candidates nil t)
             candidates)))

(defun kittymacs-org-node-find (&optional all)
  "Visit a note in the active root, or across registered roots with ALL."
  (interactive "P")
  (let ((roots (kittymacs--org-node-prepare)))
    (org-node-goto (kittymacs--org-node-read (unless all (kittymacs--org-node-scope roots))) t)))

(defun kittymacs-org-node-find-all ()
  "Visit a note from any registered root."
  (interactive)
  (kittymacs-org-node-find t))

(defun kittymacs--org-node-link (entry)
  "Return an Org link to ENTRY."
  (org-link-make-string
   (if-let* ((id (org-mem-entry-id entry))) (concat "id:" id)
     (format "file:%s::%d" (org-mem-entry-file entry) (org-mem-entry-lnum entry)))
   (kittymacs--org-node-title entry)))

(defun kittymacs-org-node-insert (&optional all)
  "Insert a scoped ID link, or select across roots with ALL."
  (interactive "P")
  (unless (derived-mode-p 'org-mode) (user-error "Insert an ID link from an Org buffer"))
  (let* ((roots (kittymacs--org-node-prepare))
         (entry (kittymacs--org-node-read (unless all (kittymacs--org-node-scope roots)))))
    (if (use-region-p)
        (let ((text (buffer-substring-no-properties (region-beginning) (region-end))))
          (delete-region (region-beginning) (region-end))
          (insert (org-link-make-string (concat "id:" (org-mem-entry-id entry)) text)))
      (insert (kittymacs--org-node-link entry)))))

(defun kittymacs--org-node-capture-id ()
  "Give the captured note an Org ID before finalizing."
  (unless org-note-abort
    (save-excursion
      (goto-char (org-capture-get :begin-marker 'local))
      (org-id-get-create))))

(defun kittymacs-org-node-capture ()
  "Capture a new ID note into the active root."
  (interactive)
  (require 'org-capture)
  (kittymacs--org-node-register)
  (let* ((scope (kittymacs--org-node-scope (kittymacs--org-node-roots)))
         (file (plist-get (cdr scope) :capture))
         (org-capture-templates
          `(("k" "Linked note" entry (file ,file) "* %?\n"
             :prepare-finalize kittymacs--org-node-capture-id))))
    (unless (kittymacs--org-node-file-in-root-p file scope)
      (user-error "Capture file is excluded from notes: %s" file))
    (make-directory (file-name-directory file) t)
    (message "Capturing linked note in %s" (abbreviate-file-name file))
    (org-capture nil "k")))

(defun kittymacs-org-node-sync ()
  "Refresh the shared index and show the current roots."
  (interactive)
  (message "Linked notes roots: %s" (mapconcat #'car (kittymacs--org-node-prepare t) ", ")))

(defun kittymacs--org-node-tags (scope)
  "List tags of notes in SCOPE."
  (sort (delete-dups (mapcan (lambda (entry) (copy-sequence (org-mem-entry-tags entry)))
                             (kittymacs--org-node-entries scope)))
        #'string-lessp))

(defun kittymacs-org-node-find-by-tag ()
  "Visit a note by tag in the active root."
  (interactive)
  (let* ((scope (kittymacs--org-node-scope (kittymacs--org-node-prepare)))
         (tags (or (kittymacs--org-node-tags scope) (user-error "No tags in this scope")))
         (tag (completing-read "Tag: " tags nil t)))
    (org-node-goto (kittymacs--org-node-read scope tag) t)))

(defun kittymacs--org-node-report (buffer-name title groups)
  "Write an Org BUFFER-NAME with TITLE and GROUPS of notes."
  (with-current-buffer (get-buffer-create buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "#+title: " title "\n")
      (dolist (group groups)
        (insert "\n* " (car group) "\n")
        (dolist (entry (delete-dups (cdr group)))
          (insert "- " (kittymacs--org-node-link entry) "\n"))))
    (org-mode)
    (read-only-mode 1)
    (goto-char (point-min))
    (current-buffer)))

(defun kittymacs-org-node-tag-index ()
  "Show the active root's tags and linked notes."
  (interactive)
  (let ((scope (kittymacs--org-node-scope (kittymacs--org-node-prepare))))
    (pop-to-buffer
     (kittymacs--org-node-report
      "*Kittymacs Tags*" (concat "Tags in " (car scope))
      (mapcar (lambda (tag) (cons tag (kittymacs--org-node-entries scope tag)))
              (kittymacs--org-node-tags scope))))))

(defun kittymacs-org-node-backlinks ()
  "Show local and cross-root backlinks to the current or selected note."
  (interactive)
  (let* ((scope (kittymacs--org-node-scope (kittymacs--org-node-prepare)))
         (id (or (and (derived-mode-p 'org-mode) (org-entry-get-with-inheritance "ID"))
                 (org-mem-entry-id (kittymacs--org-node-read scope))))
         local other)
    (dolist (link (org-mem-id-links-to-id id))
      (when-let* ((owner (kittymacs--org-node-owner (org-mem-link-file link)))
                  (entry (org-mem-link-entry link)))
        (if (equal owner scope) (push entry local) (push entry other))))
    (display-buffer-in-side-window
     (kittymacs--org-node-report "*Kittymacs Backlinks*" (concat "Backlinks to " id)
                                (list (cons "Within this root" local) (cons "From other roots" other)))
     '((side . right) (window-width . 0.33)))))

(defun kittymacs--org-node-audit (roots)
  "Return graph problems in ROOTS."
  (let ((ids (make-hash-table :test #'equal))
        (entries (kittymacs--org-node-indexed-entries))
        issues)
    (dolist (root roots)
      (let ((directory (plist-get (cdr root) :notes))
            (capture (plist-get (cdr root) :capture)))
        (unless (file-directory-p directory) (push (format "Missing root: %s" directory) issues))
        (unless (kittymacs--org-node-file-in-root-p capture root)
          (push (format "Excluded capture destination: %s" capture) issues))))
    (dolist (entry entries)
      (when-let* ((id (org-mem-entry-id entry)))
        (push (format "%s:%d" (org-mem-entry-file entry) (org-mem-entry-lnum entry)) (gethash id ids))))
    (maphash (lambda (id locations)
               (when (cdr locations)
                 (push (format "Duplicate ID %s: %s" id (string-join (sort locations #'string-lessp) ", "))
                       issues))) ids)
    (dolist (link (org-mem-all-links))
      (let ((type (org-mem-link-type link))
            (target (org-mem-link-target link))
            (file (org-mem-link-file link)))
        (when (kittymacs--org-node-owner file)
          (cond ((and (equal type "id")
                      (not (or (gethash target ids) (gethash (car (split-string target "::")) ids))))
                 (push (format "Unresolved ID %s in %s" target file) issues))
                ((equal type "roam") (push (format "Review Roam link %s in %s" target file) issues))))))
    (dolist (entry entries)
      (let ((properties (org-mem-entry-properties-local entry))
            (location (format "%s:%d" (org-mem-entry-file entry) (org-mem-entry-lnum entry))))
        (when (or (assoc "ROAM_ALIASES" properties) (assoc "ROAM_REFS" properties))
          (push (format "Roam metadata in %s" location) issues))
        (dolist (property '("BLOCKER" "TRIGGER"))
          (when-let* ((rule (cdr (assoc property properties))) ((stringp rule)))
            (let ((start 0))
              (while (string-match "\\_<ids(\\([^)]*\\))" rule start)
                (setq start (match-end 0))
                (dolist (argument (split-string (match-string 1 rule) "[[:space:]\",]+" t))
                  (let ((id (string-remove-prefix "id:" argument)))
                    (unless (gethash id ids)
                      (push (format "Unresolved %s target %s in %s" property id location)
                            issues))))))))))
    (sort (delete-dups issues) #'string-lessp)))

(defun kittymacs-org-node-audit ()
  "Show registered roots, capture paths and graph findings."
  (interactive)
  (let* ((roots (kittymacs--org-node-prepare t))
         (issues (kittymacs--org-node-audit roots)))
    (with-current-buffer (get-buffer-create "*Kittymacs Graph Audit*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (root roots)
          (insert (format "%s\n  Notes: %s\n  Capture: %s\n" (car root)
                          (plist-get (cdr root) :notes) (plist-get (cdr root) :capture))))
        (insert "\n" (if issues (string-join issues "\n") "No graph issues found.") "\n"))
      (special-mode)
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

(keymap-set kittymacs-notes-map "f" (cons "find note in scope" #'kittymacs-org-node-find))
(keymap-set kittymacs-notes-map "F" (cons "find across roots" #'kittymacs-org-node-find-all))
(keymap-set kittymacs-notes-map "i" (cons "insert ID link" #'kittymacs-org-node-insert))
(keymap-set kittymacs-notes-map "c" (cons "capture linked note" #'kittymacs-org-node-capture))
(keymap-set kittymacs-notes-map "b" (cons "backlinks" #'kittymacs-org-node-backlinks))
(keymap-set kittymacs-notes-map "s" (cons "refresh graph" #'kittymacs-org-node-sync))
(keymap-set kittymacs-notes-map "t" (cons "find by tag" #'kittymacs-org-node-find-by-tag))
(keymap-set kittymacs-notes-map "T" (cons "tag index" #'kittymacs-org-node-tag-index))
(keymap-set kittymacs-notes-map "a" (cons "audit graph" #'kittymacs-org-node-audit))

(provide 'kittymacs-org-node)
;;; kittymacs-org-node.el ends here
