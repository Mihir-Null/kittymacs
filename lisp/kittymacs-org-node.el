;;; kittymacs-org-node.el --- One graph of linked notes -*- lexical-binding: t; -*-
;; Generated from literate/71-org-node.org; edit the Org source, then tangle.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'kittymacs-leader)

;; Defined by the defaults and platform chapters, which init.el loads first.
(defvar kittymacs-cache-dir)
(defvar kittymacs-org-directory)

(use-package org-node
  :ensure t
  :demand t)

(defgroup kittymacs-org-node nil
  "Linked notes in one graph, across your notes folder and your projects."
  :group 'kittymacs)

(defcustom kittymacs-org-node-directory kittymacs-org-directory
  "Your notes folder, the graph's first folder.
The chapter reads it while it loads, so set it with `setopt' in private.el."
  :type 'directory
  :group 'kittymacs-org-node)

(defcustom kittymacs-org-node-excluded-directories nil
  "Folders, relative to a graph folder, whose files are never notes.
The global value applies to `kittymacs-org-node-directory'; a project
sets its own in its .dir-locals.el."
  :type '(repeat string)
  :safe #'list-of-strings-p
  :group 'kittymacs-org-node)

(defvar kittymacs--org-node-base-exclude (default-toplevel-value 'org-mem-exclude)
  "`org-mem-exclude' before this chapter added the folders' exclusions.")

(defun kittymacs--org-node-root (directory)
  "Return DIRECTORY as an absolute directory name with links resolved."
  (file-name-as-directory (file-truename (expand-file-name directory))))

(defun kittymacs--org-node-unreadable-p (root)
  "Whether org-mem skips every file under ROOT.
It skips any path with a folder whose name starts with . or _."
  (string-match-p "/[._]" (directory-file-name root)))
(defcustom kittymacs-org-node-project nil
  "Non-nil in a directory's .dir-locals.el to add that directory to the graph."
  :type 'boolean
  :safe #'booleanp
  :group 'kittymacs-org-node)

(defcustom kittymacs-org-node-projects-file
  (expand-file-name "org-node-projects" kittymacs-cache-dir)
  "File in which the graph remembers its project folders between sessions."
  :type 'file
  :group 'kittymacs-org-node)

(defvar kittymacs--org-node-projects nil
  "The graph's project folders, as (ROOT . EXCLUSIONS) pairs.")

(defvar kittymacs--org-node-unreadable-reported nil
  "Project roots that org-mem cannot read and this session has reported.")

(defun kittymacs--org-node-load-projects ()
  "Read the graph's project folders from `kittymacs-org-node-projects-file'."
  (setq kittymacs--org-node-projects
        (when (file-readable-p kittymacs-org-node-projects-file)
          (with-temp-buffer
            (insert-file-contents kittymacs-org-node-projects-file)
            (ignore-errors (read (current-buffer)))))))

(defun kittymacs--org-node-save-projects ()
  "Write the graph's project folders to `kittymacs-org-node-projects-file'."
  (make-directory (file-name-directory kittymacs-org-node-projects-file) t)
  (with-temp-file kittymacs-org-node-projects-file
    (insert ";; Project folders of the notes graph; see literate/71-org-node.org.\n")
    (let ((print-length nil) (print-level nil))
      (pp kittymacs--org-node-projects (current-buffer)))))

(defun kittymacs--org-node-folders ()
  "Return the graph's folders that exist, as (ROOT . EXCLUSIONS) pairs."
  (seq-filter (lambda (folder) (file-directory-p (car folder)))
              (cons (cons (kittymacs--org-node-root kittymacs-org-node-directory)
                          (default-value 'kittymacs-org-node-excluded-directories))
                    kittymacs--org-node-projects)))

(defun kittymacs--org-node-project-root ()
  "Return the real directory whose .dir-locals.el set `kittymacs-org-node-project'.
Only a buffer visiting a file counts."
  (when (and buffer-file-name
             (alist-get 'kittymacs-org-node-project dir-local-variables-alist))
    (let ((found (dir-locals-find-file buffer-file-name)))
      (kittymacs--org-node-root (if (consp found) (car found) found)))))

(defun kittymacs--org-node-register ()
  "Add the project that this buffer's .dir-locals.el declares to the graph."
  (when-let* ((root (kittymacs--org-node-project-root)))
    (let ((excluded (alist-get 'kittymacs-org-node-excluded-directories
                               dir-local-variables-alist)))
      (cond
       ((kittymacs--org-node-unreadable-p root)
        (unless (member root kittymacs--org-node-unreadable-reported)
          (push root kittymacs--org-node-unreadable-reported)
          (message "org-node cannot read %s: a folder in its path starts with . or _"
                   (abbreviate-file-name root))))
       ((not (equal (assoc root kittymacs--org-node-projects) (cons root excluded)))
        (setf (alist-get root kittymacs--org-node-projects nil nil #'equal) excluded)
        (kittymacs--org-node-save-projects)
        (kittymacs--org-node-start)
        (message "Notes graph includes %s; indexing it" (abbreviate-file-name root)))))))

(defun kittymacs-org-node-forget-project (root)
  "Take the project folder ROOT out of the notes graph."
  (interactive
   (list (completing-read "Forget project: "
                          (or (mapcar #'car kittymacs--org-node-projects)
                              (user-error "The graph has no project folders"))
                          nil t)))
  (setq kittymacs--org-node-projects (assoc-delete-all root kittymacs--org-node-projects))
  (kittymacs--org-node-save-projects)
  (kittymacs--org-node-start))
(defun kittymacs--org-node-apply ()
  "Point org-mem at the graph's folders and their exclusions; return the folders."
  (let ((folders (kittymacs--org-node-folders)))
    (setq org-mem-watch-dirs (mapcar #'car folders)
          org-mem-exclude
          (append kittymacs--org-node-base-exclude
                  (cl-loop for (root . excluded) in folders
                           append (mapcar (lambda (directory)
                                            (file-name-as-directory
                                             (expand-file-name directory root)))
                                          excluded))))
    folders))

(defun kittymacs--org-node-start ()
  "Index the graph's folders, or stop indexing when none exists.
Return non-nil when the index is on."
  (if (kittymacs--org-node-apply)
      (progn
        (if (and org-node-cache-mode org-mem-updater-mode)
            (org-mem-reset)
          (org-node-cache-mode)
          (org-mem-updater-mode))
        t)
    (when org-mem-updater-mode (org-mem-updater-mode 0))
    (when org-node-cache-mode (org-node-cache-mode 0))
    nil))

(defun kittymacs--org-node-ensure ()
  "Make sure the graph is indexed, or explain why it cannot be."
  (unless (or (and org-node-cache-mode org-mem-updater-mode)
              (kittymacs--org-node-start))
    (user-error "No notes folder yet: create %s, or open a project whose .dir-locals.el sets kittymacs-org-node-project"
                (abbreviate-file-name kittymacs-org-node-directory))))

(defun kittymacs-org-node-rescan ()
  "Read every file of the graph again, then report what the index holds."
  (interactive)
  (kittymacs--org-node-ensure)
  (call-interactively #'org-mem-reset))
(setopt org-mem-do-look-everywhere nil
        org-node-file-directory-ask (kittymacs--org-node-root kittymacs-org-node-directory))

(defun kittymacs-org-node-find ()
  "Visit a note of the graph, or create one in your notes folder."
  (interactive)
  (kittymacs--org-node-ensure)
  (org-node-find))

(defun kittymacs-org-node-insert ()
  "Insert an ID link to a note of the graph at point.
The active region's text is the prompt's input and the link's description."
  (interactive "*")
  (kittymacs--org-node-ensure)
  (org-node-insert-link*))

(defun kittymacs--org-node-folder (file)
  "Return the graph folder holding FILE, the deepest if folders nest, or nil."
  (let ((file (file-truename file)))
    (car (sort (seq-filter (lambda (root) (file-in-directory-p file root))
                           org-mem-watch-dirs)
               (lambda (a b) (> (length a) (length b)))))))

(defun kittymacs-org-node-new (title directory)
  "Create a note called TITLE in DIRECTORY.
Interactively, DIRECTORY defaults to the graph folder of this buffer's file."
  (interactive
   (progn
     (kittymacs--org-node-ensure)
     (let ((default (or (kittymacs--org-node-folder (or buffer-file-name default-directory))
                        (kittymacs--org-node-root kittymacs-org-node-directory))))
       (list (read-string "New note title: ")
             (read-directory-name "In folder: " default default t)))))
  (when (string-blank-p title)
    (user-error "A note needs a title"))
  (unless (file-writable-p directory)
    (user-error "Cannot create a note in %s: it is read-only" directory))
  (let ((org-node-file-directory-ask (file-name-as-directory directory)))
    (org-node-create title (org-id-new))))
(defun kittymacs-org-node-backlinks ()
  "Show or hide the notes that link to the note at point, in a side panel."
  (interactive)
  (kittymacs--org-node-ensure)
  (require 'org-node-context)
  (cond
   ((derived-mode-p 'org-mode)
    (unless (org-entry-get-with-inheritance "ID")
      (user-error "No note here: neither this heading nor its file has an ID")))
   ((not (get-buffer org-node-context-main-buffer))
    (user-error "SPC n b shows the backlinks of the note at point; open a note first")))
  (org-node-context-toggle))

(with-eval-after-load 'org-node-context
  (add-to-list 'display-buffer-alist
               `(,(concat "\\`" (regexp-quote org-node-context-main-buffer) "\\'")
                 (display-buffer-in-side-window)
                 (side . right)
                 (window-width . 0.33))))
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(org-node-context-mode . motion)))
(kittymacs-define-localleader 'org-node-context-mode
  "g" (cons "refresh backlinks" #'org-node-context-refresh-this-buffer)
  "l" (cons "previous note" #'org-node-context-history-go-back)
  "r" (cons "next note" #'org-node-context-history-go-forward)
  "s" (cons "rescan graph" #'kittymacs-org-node-rescan)
  "f" (cons "find node" #'kittymacs-org-node-find))
(defun kittymacs--org-node-affix (node title)
  "Return TITLE followed by NODE's tags, each behind a #, for the prompt."
  (list title ""
        (if-let* ((tags (org-mem-entry-tags node)))
            (propertize (concat "  " (mapconcat (lambda (tag) (concat "#" tag)) tags " "))
                        'face 'org-tag)
          "")))

(setopt org-node-affixation-fn #'kittymacs--org-node-affix
        org-node-alter-candidates t)
(defun kittymacs--org-node-tag-counts ()
  "Return the graph's tags as (TAG . NOTES) pairs, sorted by tag."
  (let ((counts (make-hash-table :test #'equal))
        pairs)
    (dolist (node (org-node-all-filtered-nodes))
      (dolist (tag (org-mem-entry-tags node))
        (cl-incf (gethash tag counts 0))))
    (maphash (lambda (tag notes) (push (cons tag notes) pairs)) counts)
    (sort pairs (lambda (a b) (string< (car a) (car b))))))

(defun kittymacs--org-node-read-tag ()
  "Read a tag of the graph; the list says how many notes carry each."
  (let ((counts (or (kittymacs--org-node-tag-counts)
                    (user-error "No tags in the graph; SPC n s reads it again"))))
    (completing-read
     "Tag: "
     (lambda (string predicate action)
       (if (eq action 'metadata)
           `(metadata
             (annotation-function
              . ,(lambda (tag)
                   (let ((notes (alist-get tag counts nil nil #'equal)))
                     (format "  %d note%s" notes (if (= notes 1) "" "s"))))))
         (complete-with-action action counts string predicate)))
     nil t)))

(defun kittymacs-org-node-find-by-tag ()
  "Find a note of the graph by choosing one of the graph's tags first."
  (interactive)
  (kittymacs--org-node-ensure)
  (org-node-cache-ensure t)
  (let* ((tag (kittymacs--org-node-read-tag))
         (input (org-node-read-candidate
                 (format "Note tagged %s: " tag) nil
                 (lambda (_candidate node) (member tag (org-mem-entry-tags node)))
                 t)))
    (org-node-goto (gethash input org-node--candidate<>entry))))

(defun kittymacs--org-node-tagged-notes ()
  "Return the graph's tags with the notes listed under each.
The value is a list of (TAG . NOTES), sorted by tag; a note is a list
\(ID TITLE FILE LEVEL), file notes first.  A file note is listed under
its file tags, a heading note only under tags its file note lacks."
  (let ((nodes (sort (org-node-all-filtered-nodes)
                     (lambda (a b)
                       (let ((file-a (org-mem-entry-file a)) (file-b (org-mem-entry-file b)))
                         (if (equal file-a file-b)
                             (< (org-mem-entry-pos a) (org-mem-entry-pos b))
                           (string< file-a file-b))))))
        (file-tags (make-hash-table :test #'equal))
        groups)
    (dolist (node nodes)
      (when (zerop (org-mem-entry-level node))
        (dolist (tag (org-mem-entry-tags node))
          (puthash (cons (org-mem-entry-file node) tag) t file-tags))))
    (dolist (node nodes)
      (let ((file (org-mem-entry-file node))
            (level (org-mem-entry-level node)))
        (dolist (tag (org-mem-entry-tags node))
          (unless (and (> level 0) (gethash (cons file tag) file-tags))
            (push (list (org-mem-entry-id node) (org-mem-entry-title node) file level)
                  (alist-get tag groups nil nil #'equal))))))
    (sort (mapcar (lambda (group)
                    ;; File notes first; `sort' is stable, so the rest keep
                    ;; the order of their files and positions.
                    (cons (car group)
                          (sort (nreverse (cdr group))
                                (lambda (a b) (and (zerop (nth 3 a)) (> (nth 3 b) 0))))))
                  groups)
          (lambda (a b) (string< (car a) (car b))))))

(defun kittymacs--org-node-display-file (file)
  "Return FILE relative to the parent of its graph folder, to show it."
  (if-let* ((folder (kittymacs--org-node-folder file)))
      (file-relative-name file (file-name-directory (directory-file-name folder)))
    (abbreviate-file-name file)))

(defun kittymacs-org-node-tag-index ()
  "List the graph's tags in an Org buffer, each with links to its notes."
  (interactive)
  (kittymacs--org-node-ensure)
  (org-node-cache-ensure t)
  (let ((groups (or (kittymacs--org-node-tagged-notes)
                    (user-error "No tags in the graph; SPC n s reads it again")))
        (buffer (get-buffer-create "*org-node tags*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (org-mode)
        (insert "#+title: Tags in the notes graph\n\n")
        (pcase-dolist (`(,tag . ,notes) groups)
          (insert (format "* %s (%d)\n" tag (length notes)))
          (pcase-dolist (`(,id ,title ,file ,_) notes)
            (insert "- " (org-link-make-string (concat "id:" id) title)
                    " · " (kittymacs--org-node-display-file file) "\n")))
        (set-buffer-modified-p nil)
        (goto-char (point-min))))
    (pop-to-buffer buffer)))
(add-hook 'hack-local-variables-hook #'kittymacs--org-node-register)
(kittymacs--org-node-load-projects)
(kittymacs--org-node-start)

(provide 'kittymacs-org-node)
;;; kittymacs-org-node.el ends here
