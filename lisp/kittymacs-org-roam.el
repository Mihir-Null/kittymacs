;;; kittymacs-org-roam.el --- Scoped linked notes -*- lexical-binding: t; -*-
;; Generated from literate/71-org-roam.org; edit the Org source, then tangle.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-id)
(require 'kittymacs-leader)

;; Defined by the defaults and platform chapters, which init.el loads first.
(defvar kittymacs-cache-dir)
(defvar kittymacs-org-directory)

(defgroup kittymacs-org-roam nil
  "Linked notes, one graph at a time."
  :group 'kittymacs)

(defcustom kittymacs-org-roam-directory kittymacs-org-directory
  "Root of the personal Org-roam graph.
The chapter reads it while it loads, so set it with `setopt' in private.el."
  :type 'directory
  :group 'kittymacs-org-roam)

(defun kittymacs--org-roam-root (directory)
  "Return DIRECTORY as an absolute directory name with links resolved."
  (file-name-as-directory (file-truename (expand-file-name directory))))

(defun kittymacs-org-roam-db-path (root)
  "Return the database file for the graph at ROOT, inside the user cache.
The name is a hash of ROOT's real path, lower-cased on a file system
that ignores case, so every spelling of one directory shares one file."
  (let ((identity (kittymacs--org-roam-root root)))
    (when (file-name-case-insensitive-p identity)
      (setq identity (downcase identity)))
    (expand-file-name (concat (secure-hash 'sha256 identity) ".sqlite")
                      (expand-file-name "org-roam/" kittymacs-cache-dir))))

(defvar org-roam-directory (kittymacs--org-roam-root kittymacs-org-roam-directory))
(defvar org-roam-db-location (kittymacs-org-roam-db-path org-roam-directory))
(defcustom kittymacs-org-roam-project nil
  "Non-nil in a directory's .dir-locals.el to make that directory a graph root."
  :type 'boolean
  :safe #'booleanp
  :group 'kittymacs-org-roam)

(defcustom kittymacs-org-roam-excluded-directories '(".git" ".cache" "cache" "caches")
  "Folder names whose contents are never notes, at any depth of a graph.
A project graph sets its own list in its .dir-locals.el."
  :type '(repeat string)
  :safe #'list-of-strings-p
  :group 'kittymacs-org-roam)

(defvar org-roam-file-exclude-regexp)

(defvar-local kittymacs--org-roam-graph nil
  "This buffer's graph as a list (ROOT DB EXCLUDE), or nil.")
(put 'kittymacs--org-roam-graph 'permanent-local t)

(defun kittymacs--org-roam-project-root ()
  "Return the directory whose .dir-locals.el set `kittymacs-org-roam-project'."
  (when (alist-get 'kittymacs-org-roam-project dir-local-variables-alist)
    (let ((found (dir-locals-find-file (or buffer-file-name default-directory))))
      (if (consp found) (car found) found))))

(defun kittymacs--org-roam-named-graph ()
  "Return the graph that this buffer's own variables name, or nil."
  (when-let* ((directory (or (kittymacs--org-roam-project-root)
                             (and (local-variable-p 'org-roam-directory)
                                  org-roam-directory))))
    (let ((root (kittymacs--org-roam-root directory)))
      (list root
            (if (local-variable-p 'org-roam-db-location)
                (expand-file-name org-roam-db-location)
              (kittymacs-org-roam-db-path root))
            (kittymacs--org-roam-exclusions kittymacs-org-roam-excluded-directories)))))

(defun kittymacs--org-roam-personal-graph ()
  "Return the personal graph, from the global values of its variables."
  (list (kittymacs--org-roam-root (default-value 'org-roam-directory))
        (expand-file-name (default-value 'org-roam-db-location))
        (kittymacs--org-roam-exclusions
         (default-value 'kittymacs-org-roam-excluded-directories))))

(defun kittymacs--org-roam-scope ()
  "Return the graph for a command in this buffer, or explain why there is none."
  (unless (sqlite-available-p)
    (user-error "Org-roam needs an Emacs built with SQLite support"))
  (let ((scope (or kittymacs--org-roam-graph
                   (kittymacs--org-roam-named-graph)
                   (kittymacs--org-roam-personal-graph))))
    (pcase-let ((`(,root ,db) scope))
      (unless (file-directory-p root)
        (user-error "Org-roam graph does not exist: %s" root))
      (when (file-in-directory-p db root)
        (user-error "Org-roam database %s is inside its graph; see kittymacs-org-roam-db-path"
                    db)))
    scope))

(defun kittymacs--org-roam-set-scope (scope)
  "Make SCOPE this buffer's graph, for these commands and for Org-roam's own."
  (pcase-let ((`(,root ,db ,exclude) scope))
    (setq-local kittymacs--org-roam-graph scope
                org-roam-directory root
                org-roam-db-location db
                org-roam-file-exclude-regexp exclude))
  (when (derived-mode-p 'org-mode)
    (add-hook 'after-save-hook #'kittymacs--org-roam-save nil t)))

(defun kittymacs--org-roam-restore ()
  "Give this buffer its graph again after its local variables were cleared."
  (when-let* ((scope (or (and (derived-mode-p 'org-mode)
                              (or (kittymacs--org-roam-named-graph)
                                  (and buffer-file-name
                                       (file-in-directory-p buffer-file-name
                                                            org-roam-directory)
                                       (kittymacs--org-roam-personal-graph))))
                         kittymacs--org-roam-graph)))
    (kittymacs--org-roam-set-scope scope)))
(defun kittymacs--org-roam-exclusions (directories)
  "Return Org-roam's exclusion regexps plus one matching any of DIRECTORIES.
The new regexp matches a whole folder name at any depth of a path that
is relative to the graph root, which is what `org-roam-file-p' tests."
  (append (ensure-list (default-toplevel-value 'org-roam-file-exclude-regexp))
          (and directories
               (list (concat "\\(?:\\`\\|/\\)" (regexp-opt directories) "/")))))
(defun kittymacs--org-roam-call (scope function)
  "Call FUNCTION with SCOPE in effect, also in buffers Org-roam opens itself."
  (let ((variables '(org-roam-directory org-roam-db-location org-roam-file-exclude-regexp))
        (origin (current-buffer)))
    (with-temp-buffer
      (cl-progv variables scope
        (with-current-buffer origin
          (cl-progv variables scope
            (funcall function)))))))

(defun kittymacs--org-roam-save ()
  "Update this note's entry in its graph's database, under its real file name."
  (let ((buffer-file-name (file-truename buffer-file-name)))
    (when (and (sqlite-available-p) (org-roam-file-p))
      (kittymacs--org-roam-call kittymacs--org-roam-graph #'org-roam-db-update-file))))

(defun kittymacs-org-roam-sync (&optional force)
  "Bring this graph's database up to date and record its IDs for Org.
With a prefix argument FORCE, delete the database and build it again."
  (interactive "P")
  (kittymacs--org-roam-call
   (kittymacs--org-roam-scope)
   (lambda ()
     (org-roam-db-sync force)
     (dolist (row (org-roam-db-query [:select [id file] :from nodes]))
       (org-id-add-location (car row) (cadr row)))
     (org-id-locations-save))))

(defun kittymacs--org-roam-lookup-p (&rest _)
  "Whether Org-roam can answer an ID lookup in this buffer's graph."
  (and (sqlite-available-p) (file-directory-p org-roam-directory)))
(defvar kittymacs--org-roam-capture-scope nil
  "The graph of the command now starting an Org-roam capture, or nil.
Only `kittymacs--org-roam-capture-node' binds it, while Org sets up the
capture; `kittymacs--org-roam-capture-mode' reads it.")

(defun kittymacs--org-roam-capture-mode ()
  "Give a capture started from a SPC n command the graph of that command.
Set it in the capture buffer and in the file buffer behind it, so the
save that finishes the capture updates that graph's database."
  (when kittymacs--org-roam-capture-scope
    (kittymacs--org-roam-set-scope kittymacs--org-roam-capture-scope)
    (with-current-buffer (buffer-base-buffer)
      (kittymacs--org-roam-set-scope kittymacs--org-roam-capture-scope))))

(defun kittymacs--org-roam-capture-node (scope node &optional props)
  "Capture NODE into the graph SCOPE, passing PROPS to Org-roam."
  (unless (file-writable-p (car scope))
    (user-error "Org-roam capture root is read-only: %s" (car scope)))
  (message "Org-roam capture destination: %s" (car scope))
  (kittymacs--org-roam-call
   scope (lambda ()
           (let ((kittymacs--org-roam-capture-scope scope))
             (org-roam-capture- :node node :props props)))))
(defun kittymacs--org-roam-read (scope &optional require-match initial)
  "Read a node of the graph SCOPE, starting from INITIAL input.
REQUIRE-MATCH allows only existing nodes."
  (kittymacs--org-roam-call
   scope (lambda ()
           (org-roam-node-read initial nil nil require-match
                               (format "Node (%s): " (car scope))))))

(defun kittymacs--org-roam-project-p (scope)
  "Whether SCOPE is a graph other than the personal one."
  (not (file-equal-p (car scope) (default-value 'org-roam-directory))))

(defun kittymacs-org-roam-find ()
  "Find a note in this graph; a project graph offers only existing notes."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (origin (current-buffer))
         (node (kittymacs--org-roam-read scope (kittymacs--org-roam-project-p scope))))
    (with-current-buffer origin
      (if (org-roam-node-file node)
          (progn
            (with-current-buffer (find-file-noselect (org-roam-node-file node))
              (kittymacs--org-roam-set-scope scope))
            (org-roam-node-open node nil t))
        (kittymacs--org-roam-capture-node scope node '(:finalize find-file))))))

(defun kittymacs-org-roam-insert ()
  "Insert an ID link to a note of this graph where the command started.
The active region's text is the prompt's input and the link's description."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (origin (point-marker))
         (region (when (use-region-p) (cons (copy-marker (region-beginning))
                                          (copy-marker (region-end)))))
         (text (when region
                 (org-link-display-format
                  (buffer-substring-no-properties (car region) (cdr region)))))
         (node (kittymacs--org-roam-read scope (kittymacs--org-roam-project-p scope) text))
         (description (or text (org-roam-node-formatted node))))
    (unwind-protect
        (with-current-buffer (marker-buffer origin)
          (goto-char origin)
          (if (org-roam-node-id node)
              (progn
                (when region (delete-region (car region) (cdr region)))
                (insert (org-link-make-string (concat "id:" (org-roam-node-id node))
                                              description))
                (run-hook-with-args 'org-roam-post-node-insert-hook
                                    (org-roam-node-id node) description))
            (kittymacs--org-roam-capture-node
             scope node (append (list :finalize 'insert-link
                                      :link-description description)
                                (when region (list :region region))))))
      (set-marker origin nil)
      (deactivate-mark))))

(defun kittymacs-org-roam-capture ()
  "Capture a note into this graph, showing where it will go."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (origin (current-buffer))
         (node (kittymacs--org-roam-read scope)))
    (with-current-buffer origin
      (kittymacs--org-roam-capture-node scope node '(:finalize find-file)))))

(defun kittymacs-org-roam-backlinks ()
  "Show the notes of this graph that link to a note, in a side panel."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (node (or (and (derived-mode-p 'org-mode) (org-roam-node-at-point))
                   (kittymacs--org-roam-read scope t)))
         (buffer (get-buffer-create
                  (format "*org-roam: %s*" (substring (secure-hash 'sha256 (car scope)) 0 12)))))
    (with-current-buffer buffer
      (setq-local kittymacs--org-roam-graph scope
                  org-roam-buffer-current-directory (car scope)
                  org-roam-buffer-current-node node)
      (org-roam-buffer-render-contents))
    (display-buffer-in-side-window buffer '((side . right) (window-width . 0.33)))))

(use-package org-roam
  :ensure t
  :demand t
  :config
  (add-hook 'hack-local-variables-hook #'kittymacs--org-roam-restore)
  (add-hook 'org-roam-mode-hook #'kittymacs--org-roam-restore)
  (add-hook 'org-capture-mode-hook #'kittymacs--org-roam-capture-mode)
  (add-hook 'kill-emacs-hook #'org-roam-db--close-all)
  (advice-add 'org-roam-id-find :before-while #'kittymacs--org-roam-lookup-p))

(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(org-roam-mode . motion)))
(kittymacs-define-localleader 'org-roam-mode
  "g" (cons "refresh backlinks" #'org-roam-buffer-refresh)
  "s" (cons "sync graph" #'kittymacs-org-roam-sync)
  "f" (cons "find node" #'kittymacs-org-roam-find))

(provide 'kittymacs-org-roam)
;;; kittymacs-org-roam.el ends here
