;;; kittymacs-org-roam.el --- Scoped linked notes -*- lexical-binding: t; -*-
;; Generated from literate/71-org-roam.org; edit the Org source, then tangle.
;;; Code:
(require 'cl-lib)
(require 'kittymacs-leader)
(require 'org)
(require 'org-id)
(require 'org-capture)

(defgroup kittymacs-org-roam nil
  "Scoped linked notes." :group 'org)
(defcustom kittymacs-org-roam-directory kittymacs-org-directory
  "Personal graph root.  Prebind with `setq' in private.el."
  :type 'directory :group 'kittymacs-org-roam)
(defcustom kittymacs-org-roam-excluded-directories
  '("legacy" ".git" "secrets" "cache" "caches" ".cache" "var")
  "Directory components excluded from graph indexing and capture."
  :type '(repeat string) :group 'kittymacs-org-roam)

(require 'json)

(defcustom kittymacs-org-roam-python-executable nil
  "Absolute native Windows Python, or nil to discover python.exe on exec-path.
Requires sys.platform == win32 and os.path.ALLOW_MISSING.  Configure this
in private.el if Python is not on PATH; never use a project interpreter."
  :type '(choice (const nil) file) :group 'kittymacs-org-roam)
(defcustom kittymacs-org-roam-path-timeout 5
  "Maximum seconds for one native physical-path request."
  :type 'number :group 'kittymacs-org-roam)

;; Fixed code; request paths are JSON data, never executable arguments.
(defconst kittymacs--org-roam-python-code
  "import json, os, stat, sys
sys.stdin.reconfigure(encoding='utf-8')
def resolve(path):
    if not isinstance(path, str) or not os.path.isabs(path):
        raise ValueError('Expected an absolute local path')
    if os.path.splitdrive(path)[0].startswith('\\\\'):
        raise ValueError('UNC paths are not supported by this local graph backend')
    result = os.path.realpath(path, strict=os.path.ALLOW_MISSING)
    if os.path.splitdrive(result)[0].startswith('\\\\'):
        raise ValueError('Resolved UNC paths are not supported')
    ancestor = result
    while True:
        try:
            info = os.stat(ancestor)
            break
        except FileNotFoundError:
            parent = os.path.dirname(ancestor)
            if parent == ancestor:
                raise
            ancestor = parent
    if ancestor != result and not stat.S_ISDIR(info.st_mode):
        raise NotADirectoryError('Nearest existing ancestor is not a directory: ' + ancestor)
    return result.replace('\\\\', '/')
for line in sys.stdin:
    try:
        if sys.platform != 'win32' or not hasattr(os.path, 'ALLOW_MISSING'):
            raise RuntimeError('Native Windows CPython with os.path.ALLOW_MISSING is required')
        request = json.loads(line)
        if not isinstance(request, list) or not all(isinstance(p, str) for p in request):
            raise ValueError('Expected a JSON array of absolute paths')
        response = {'paths': [resolve(p) for p in request]}
    except Exception as error:
        response = {'error': type(error).__name__ + ': ' + str(error)}
    print(json.dumps(response, ensure_ascii=True), flush=True)
")
(defvar kittymacs--org-roam-path-context nil
  "Dynamically owned [process stdout stderr busy] for one graph operation.")

(defun kittymacs--org-roam-operation (function &rest args)
  "Run FUNCTION with ARGS, owning any lazy native helper until return.
Nested synchronous calls reuse the child, but each path is resolved anew."
  (if kittymacs--org-roam-path-context
      (apply function args)
    (let ((kittymacs--org-roam-path-context (vector nil nil nil nil)))
      (unwind-protect (apply function args)
        (when-let* ((child (aref kittymacs--org-roam-path-context 0)))
          (when (process-live-p child) (delete-process child)))
        (dolist (index '(1 2))
          (when-let* ((buffer (aref kittymacs--org-roam-path-context index)))
            (when (buffer-live-p buffer)
              (when-let* ((pipe (get-buffer-process buffer)))
                (when (process-live-p pipe) (delete-process pipe)))
              (kill-buffer buffer))))))))

(defun kittymacs--org-roam-python-start ()
  "Start the operation's isolated interpreter, failing only on graph use."
  (let* ((default-directory temporary-file-directory)
         ;; Relative exec-path entries can name project code; ignore them.
         (exec-path (seq-filter (lambda (p) (and p (file-name-absolute-p p)
                                                 (not (file-remote-p p))))
                                exec-path))
         (program (or kittymacs-org-roam-python-executable
                      (executable-find "python.exe"))))
    (unless (and program (file-name-absolute-p program)
                 (not (file-remote-p program))
                 (not (string-prefix-p "//" program))
                 (file-executable-p program))
      (user-error "Org-roam physical paths require native Python; set kittymacs-org-roam-python-executable to an absolute CPython with os.path.ALLOW_MISSING"))
    (let ((out (generate-new-buffer " *org-roam-paths*"))
          (err (generate-new-buffer " *org-roam-path-errors*")))
      (aset kittymacs--org-roam-path-context 1 out)
      (aset kittymacs--org-roam-path-context 2 err)
      (condition-case failure
          (aset kittymacs--org-roam-path-context 0
                (make-process :name "org-roam-paths" :buffer out :stderr err
                              :command (list program "-I" "-S" "-B" "-u" "-c"
                                             kittymacs--org-roam-python-code)
                              :connection-type 'pipe :coding 'utf-8-unix
                              :noquery t :sentinel #'ignore))
        (error (user-error "Org-roam physical-path Python could not start: %s"
                           (error-message-string failure)))))))

(defun kittymacs--org-roam-native-paths (paths)
  "Resolve absolute PATHS using the owned JSON pipe; no response is cached."
  (unless kittymacs--org-roam-path-context
    (error "Physical resolver needs an operation context"))
  (when (aref kittymacs--org-roam-path-context 3)
    (user-error "Org-roam physical-path request reentered while awaiting Python"))
  (unless (aref kittymacs--org-roam-path-context 0)
    (kittymacs--org-roam-python-start))
  (let ((child (aref kittymacs--org-roam-path-context 0))
        (output (aref kittymacs--org-roam-path-context 1))
        (deadline (+ (float-time) kittymacs-org-roam-path-timeout))
        complete)
    (aset kittymacs--org-roam-path-context 3 t)
    (unwind-protect
        (condition-case failure
            (progn
              (unless (process-live-p child) (error "Python exited before the request"))
              (process-send-string child (concat (json-serialize (vconcat paths)) "\n"))
              (with-current-buffer output
                (while (not (save-excursion (goto-char (point-min)) (search-forward "\n" nil t)))
                  (when (> (buffer-size) 1048576) (error "Oversized Python response"))
                  (unless (process-live-p child) (error "Python exited without a complete response"))
                  (when (> (float-time) deadline) (error "Python response timed out"))
                  (accept-process-output child 0.01))
                (let* ((end (save-excursion (goto-char (point-min)) (search-forward "\n")))
                       (response (json-parse-string (buffer-substring-no-properties (point-min) end)
                                                    :object-type 'alist :array-type 'list))
                       (resolved (alist-get 'paths response)))
                  (delete-region (point-min) end)
                  (when (alist-get 'error response)
                    (error "%s" (alist-get 'error response)))
                  (unless (and (= (buffer-size) 0)
                               (equal (mapcar #'car response) '(paths))
                               (listp resolved) (= (length paths) (length resolved))
                               (cl-every (lambda (p) (and (stringp p)
                                                         (file-name-absolute-p p)
                                                         (not (file-remote-p p))
                                                         (not (string-prefix-p "//" p))))
                                         resolved))
                    (error "Invalid Python path response"))
                  (setq complete t)
                  resolved)))
          (error
           (when (process-live-p child) (delete-process child))
           (user-error "Org-roam physical-path resolution failed: %s%s"
                       (error-message-string failure)
                       (with-current-buffer (aref kittymacs--org-roam-path-context 2)
                         (if (= (buffer-size) 0) ""
                           (concat "; " (buffer-substring-no-properties
                                         (point-min) (min (point-max) 2049))))))))
      (unless complete
        (when (process-live-p child) (delete-process child)))
      (aset kittymacs--org-roam-path-context 3 nil))))

(defun kittymacs--org-roam-path (path)
  "Return fresh physical PATH, folded only on a case-insensitive filesystem."
  (when (or (file-remote-p path) (string-prefix-p "//" path))
    (user-error "Org-roam supports local graph paths only"))
  (kittymacs--org-roam-operation
   (lambda ()
     (let ((true (if (eq system-type 'windows-nt)
                     (car (kittymacs--org-roam-native-paths (list (expand-file-name path))))
                   (file-truename (expand-file-name path)))))
       (if (file-name-case-insensitive-p true) (downcase true) true)))))

(defun kittymacs--org-roam-root (root)
  "Return the physical directory identity of ROOT."
  (file-name-as-directory (kittymacs--org-roam-path root)))

(defun kittymacs-org-roam-db-path (root)
  "Return the external cache database path for canonical ROOT."
  (expand-file-name
   (concat (secure-hash 'sha256 (kittymacs--org-roam-root root)) ".sqlite")
   (expand-file-name "org-roam/" kittymacs-cache-dir)))

;; Defvar preserves private.el prebindings, including upstream options.
(defvar org-roam-directory kittymacs-org-roam-directory)
(defvar org-roam-db-location
  (unless (eq system-type 'windows-nt)
    (kittymacs-org-roam-db-path org-roam-directory)))
(defvar kittymacs--org-roam-capture-scope nil)
(defvar-local kittymacs--org-roam-panel-scope nil)
(put 'kittymacs--org-roam-panel-scope 'permanent-local t)

(defun kittymacs--org-roam-capability (&rest _)
  "Refuse graph operations without native SQLite, before opening a backend."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (user-error "Org-roam requires an Emacs build with native SQLite support")))

(defun kittymacs--org-roam-scope ()
  "Return the physical upstream root and external database pair."
  (kittymacs--org-roam-capability)
  (let* ((root (kittymacs--org-roam-root org-roam-directory))
         (db (expand-file-name
              (or (if (and (local-variable-p 'org-roam-directory)
                           (not (local-variable-p 'org-roam-db-location)))
                      nil org-roam-db-location)
                  (kittymacs-org-roam-db-path root))))
         (physical-db (kittymacs--org-roam-path db)))
    (unless (file-directory-p root)
      (user-error "Org-roam root does not exist: %s" root))
    (when (or (equal (directory-file-name root) physical-db)
              (file-in-directory-p physical-db root))
      (user-error "Org-roam database must be outside the graph; use kittymacs-org-roam-db-path"))
    (cons root db)))

(defun kittymacs--org-roam-call (scope function)
  "Call FUNCTION in this buffer with SCOPE also bound for temporary buffers.
Binding in a buffer with local graph variables only binds those locals;
Org-roam's parser uses temporary buffers, which need the default binding."
  (let ((origin (current-buffer)))
    (with-temp-buffer
      (let ((org-roam-directory (car scope))
            (org-roam-db-location (cdr scope)))
        (with-current-buffer origin
          (let ((org-roam-directory (car scope))
                (org-roam-db-location (cdr scope)))
            (funcall function)))))))

(defun kittymacs--org-roam-set-scope (scope)
  "Apply SCOPE to this buffer, including subsequent save operations."
  (setq-local org-roam-directory (car scope)
              org-roam-db-location (cdr scope))
  (when (derived-mode-p 'org-mode)
    (add-hook 'after-save-hook #'kittymacs--org-roam-save nil t)))

(defun kittymacs--org-roam-excluded-p (path root)
  "Whether PATH has an excluded component relative to ROOT."
  (let ((components (split-string (file-relative-name path root) "[/\\]" t))
        (excluded kittymacs-org-roam-excluded-directories))
    (when (file-name-case-insensitive-p path)
      (setq components (mapcar #'downcase components)
            excluded (mapcar #'downcase excluded)))
    (seq-intersection components excluded #'equal)))

(defun kittymacs--org-roam-allowed-p (file)
  "Whether FILE is physically in this graph with no lexical or physical exclusion."
  (when file
    (let ((root (kittymacs--org-roam-root org-roam-directory))
          (physical (kittymacs--org-roam-path file)))
      (and (file-in-directory-p physical root)
           (not (kittymacs--org-roam-excluded-p (expand-file-name file) org-roam-directory))
           (not (kittymacs--org-roam-excluded-p physical root))))))

(defun kittymacs--org-roam-list-files (&rest _)
  "Walk allowed physical directories before upstream reads note contents.
Visit each physical directory once; exclude escape links before descending.
Missing link targets contribute no files; resolution errors abort the scan."
  (let* ((org-roam-directory (kittymacs--org-roam-root org-roam-directory))
         (pending (list org-roam-directory))
         (seen (make-hash-table :test #'equal))
         files)
    (while pending
      (let ((dir (pop pending)))
        (unless (gethash dir seen)
          (puthash dir t seen)
          (dolist (entry (directory-files dir t directory-files-no-dot-files-regexp))
            (when (kittymacs--org-roam-allowed-p entry)
              (let ((physical (kittymacs--org-roam-path entry)))
                (cond
                 ((file-directory-p physical)
                  (push (file-name-as-directory physical) pending))
                 ((and (file-regular-p physical) (file-readable-p physical)
                       (org-roam-file-p entry))
                  (push physical files)))))))))
    (delete-dups files)))

(defun kittymacs--org-roam-update-file (original &optional file &rest args)
  "Validate and canonicalize FILE before ORIGINAL hashes or reads it."
  (let* ((file (or file (buffer-file-name (buffer-base-buffer))))
         (scope (kittymacs--org-roam-scope)))
    (kittymacs--org-roam-call
     scope
     (lambda ()
       (unless (kittymacs--org-roam-allowed-p file)
         (user-error "Org-roam refuses to index excluded or escaped file: %s" file))
       (let* ((physical (kittymacs--org-roam-path file))
              (visited (or (find-buffer-visiting file)
                           (find-buffer-visiting physical)))
              (find-file-hook nil)
              (find-file-existing-other-name t)
              (auto-mode-alist nil)
              (buffer (or visited (find-file-noselect physical))))
         (unwind-protect
             (with-current-buffer buffer
               ;; Visiting restores native case. Bind the physical DB spelling
               ;; before upstream selects this buffer and records its filename.
               (let ((buffer-file-name physical))
                 (apply original physical args)))
           (unless visited (kill-buffer buffer))))))))

(defun kittymacs--org-roam-file-filter (original &optional file)
  "Limit ORIGINAL membership check for FILE to safe graph paths."
  (let ((path (or file (buffer-file-name (or (buffer-base-buffer) (current-buffer)))))
        (org-roam-directory (kittymacs--org-roam-root org-roam-directory)))
    (and (kittymacs--org-roam-allowed-p path)
         ;; Upstream only folds the drive letter in its prefix comparison.
         (funcall original (kittymacs--org-roam-path path)))))

(defun kittymacs--org-roam-save ()
  "Update this buffer's graph after a save without starting a global scan."
  (when (and (sqlite-available-p) (org-roam-file-p))
    (kittymacs--org-roam-call (kittymacs--org-roam-scope)
                             #'org-roam-db-update-file)))

(defun kittymacs--org-roam-visit-scope ()
  "Restore file scope from directory locals, or an already open graph.
Use upstream connections to recognize known roots; there is no graph registry."
  (when (and buffer-file-name (derived-mode-p 'org-mode))
    (let* ((roots (cons (kittymacs--org-roam-root kittymacs-org-roam-directory)
                        (hash-table-keys org-roam-db--connection)))
           (root (if (local-variable-p 'org-roam-directory)
                     (kittymacs--org-roam-root org-roam-directory)
                   (car (sort (seq-filter
                               (lambda (dir) (file-in-directory-p (kittymacs--org-roam-path buffer-file-name) dir))
                               roots)
                              (lambda (a b) (> (length a) (length b))))))))
      (when root
        (kittymacs--org-roam-set-scope
         (cons root (if (local-variable-p 'org-roam-db-location)
                        org-roam-db-location
                      (if-let* ((connection (gethash root org-roam-db--connection)))
                          (oref connection file)
                        (if (equal root (kittymacs--org-roam-root (default-value 'org-roam-directory)))
                            (default-value 'org-roam-db-location)
                          (kittymacs-org-roam-db-path root))))))))))

(defun kittymacs--org-roam-capture-prepared (&rest _)
  "Save originating scope in both the capture properties and target buffer."
  (when kittymacs--org-roam-capture-scope
    (org-capture-put :kittymacs-org-roam-scope kittymacs--org-roam-capture-scope)
    (kittymacs--org-roam-set-scope kittymacs--org-roam-capture-scope)))

(defun kittymacs--org-roam-capture-mode ()
  "Give the indirect capture buffer the scope saved on its target."
  (when-let* ((scope (org-capture-get :kittymacs-org-roam-scope)))
    (kittymacs--org-roam-set-scope scope)))

(defun kittymacs--org-roam-finalize (original &rest args)
  "Run ORIGINAL with ARGS in the graph saved by the capture."
  (if-let* ((scope (org-capture-get :kittymacs-org-roam-scope)))
      (kittymacs--org-roam-call
       scope (lambda ()
               (let ((kittymacs--org-roam-capture-scope scope))
                 (apply original args))))
    (apply original args)))

(defun kittymacs--org-roam-writable-target-p (file)
  "Whether physical FILE or its nearest existing directory permits creation."
  (let* ((file (kittymacs--org-roam-path file))
         (existing file))
    (while (not (file-exists-p existing))
      (let ((parent (file-name-directory (directory-file-name existing))))
        (when (equal parent existing)
          (user-error "No existing capture ancestor: %s" file))
        (setq existing parent)))
    (and (or (equal existing file) (file-directory-p existing))
         (file-writable-p existing))))

(defun kittymacs--org-roam-capture-target (original path)
  "Validate ORIGINAL's resolved PATH before Org writes capture headers."
  (let ((file (funcall original path)))
    (when kittymacs--org-roam-capture-scope
      (unless (and (kittymacs--org-roam-allowed-p file)
                   (kittymacs--org-roam-writable-target-p file))
        (user-error "Org-roam capture destination is excluded, outside the graph, or read-only: %s" file))
      (setq file (kittymacs--org-roam-path file))
      (make-directory (file-name-directory file) t))
    file))

(defun kittymacs--org-roam-panel-restore ()
  "Restore the graph before sections query the DB on every panel render."
  (when kittymacs--org-roam-panel-scope
    (kittymacs--org-roam-set-scope kittymacs--org-roam-panel-scope)))

(defun kittymacs--org-roam-db-canonical (original &rest args)
  "Validate physical root and DB placement before every upstream DB access."
  (kittymacs--org-roam-call
   (kittymacs--org-roam-scope) (lambda () (apply original args))))

(defun kittymacs--org-roam-id-destination (location)
  "Restore graph scope on an already open ID destination LOCATION."
  (when-let* ((buffer (cond ((markerp location) (marker-buffer location))
                           ((consp location) (find-buffer-visiting (car location))))))
    (with-current-buffer buffer (kittymacs--org-roam-visit-if-available)))
  location)

(defun kittymacs--org-roam-id-available (original &rest args)
  "Let Org's own ID index handle lookups when graph scope is unavailable.
Only the optional graph preflight is tolerant; errors from ORIGINAL after
successful validation remain visible."
  (when (condition-case nil (kittymacs--org-roam-scope)
          (user-error nil))
    (apply original args)))

(defun kittymacs--org-roam-visit-if-available ()
  "Restore known graph scope without making ordinary Org editing require Python."
  (condition-case nil
      (kittymacs--org-roam-operation #'kittymacs--org-roam-visit-scope)
    (user-error nil)))

(use-package org-roam
  :ensure t
  :demand t
  :config
  (advice-add 'org-roam-db :around #'kittymacs--org-roam-db-canonical)
  (advice-add 'org-roam-db-sync :around #'kittymacs--org-roam-db-canonical)
  (advice-add 'org-roam-list-files :override #'kittymacs--org-roam-list-files)
  (advice-add 'org-roam-db-update-file :around #'kittymacs--org-roam-update-file)
  ;; Outer ownership covers direct upstream use as well as scoped commands.
  (dolist (function '(org-roam-db org-roam-db-sync org-roam-db-update-file
                      org-roam-list-files org-roam-file-p org-roam-id-find
                      org-capture-finalize))
    (advice-add function :around #'kittymacs--org-roam-operation))
  (advice-add 'org-id-find :filter-return #'kittymacs--org-roam-id-destination)
  (advice-add 'org-roam-file-p :around #'kittymacs--org-roam-file-filter)
  (advice-add 'org-roam-id-find :around #'kittymacs--org-roam-id-available)
  (advice-add 'org-roam-capture--prepare-buffer :after #'kittymacs--org-roam-capture-prepared)
  (advice-add 'org-roam-capture--target-truepath :around #'kittymacs--org-roam-capture-target)
  (advice-add 'org-capture-finalize :around #'kittymacs--org-roam-finalize)
  (add-hook 'org-capture-mode-hook #'kittymacs--org-roam-capture-mode)
  (add-hook 'org-roam-mode-hook #'kittymacs--org-roam-panel-restore)
  (add-hook 'find-file-hook #'kittymacs--org-roam-visit-if-available)
  (add-hook 'kill-emacs-hook #'org-roam-db--close-all))

(defun kittymacs--org-roam-read (scope &optional require-match)
  "Read a node in SCOPE, optionally REQUIRE-MATCH."
  (kittymacs--org-roam-call
   scope (lambda ()
           (org-roam-node-read nil nil nil require-match
                               (format "Node (%s): " (car scope))))))

(defun kittymacs--org-roam-project-p (scope)
  "Whether SCOPE is different from the personal graph."
  (not (equal (car scope) (kittymacs--org-roam-root kittymacs-org-roam-directory))))

(defun kittymacs--org-roam-capture-node (scope node &optional props)
  "Start capture of NODE in SCOPE with finalization PROPS."
  (unless (file-writable-p (car scope))
    (user-error "Org-roam capture root is read-only: %s" (car scope)))
  (message "Org-roam capture destination: %s" (car scope))
  (kittymacs--org-roam-call
   scope (lambda ()
           (let ((kittymacs--org-roam-capture-scope scope))
             (org-roam-capture- :node node :props props)))))

(defun kittymacs-org-roam-find ()
  "Find a node in this graph; project graphs require an existing node."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (origin (current-buffer))
         (node (kittymacs--org-roam-read scope (kittymacs--org-roam-project-p scope))))
    (with-current-buffer origin
      (if (org-roam-node-file node)
          (let ((buffer (find-file-noselect (org-roam-node-file node))))
            (with-current-buffer buffer (kittymacs--org-roam-set-scope scope))
            (org-roam-node-open node nil t))
        (kittymacs--org-roam-capture-node scope node '(:finalize find-file))))))

(defun kittymacs-org-roam-insert ()
  "Insert an ID link in the originating buffer, scoped to its graph."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (origin (point-marker))
         (region (when (use-region-p) (cons (copy-marker (region-beginning))
                                          (copy-marker (region-end)))))
         (node (kittymacs--org-roam-read scope (kittymacs--org-roam-project-p scope))))
    (unwind-protect
        (with-current-buffer (marker-buffer origin)
          (goto-char origin)
          (if (org-roam-node-id node)
              (progn
                (when region (delete-region (car region) (cdr region)))
                (insert (org-link-make-string (concat "id:" (org-roam-node-id node))
                                              (org-roam-node-title node)))
                (run-hook-with-args 'org-roam-post-node-insert-hook
                                    (org-roam-node-id node) (org-roam-node-title node)))
            (kittymacs--org-roam-capture-node
             scope node (append (list :finalize 'insert-link
                                      :link-description (org-roam-node-title node))
                                (when region (list :region region))))))
      (set-marker origin nil)
      (deactivate-mark))))

(defun kittymacs-org-roam-capture ()
  "Explicitly capture in this graph, showing its destination."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (origin (current-buffer))
         (node (kittymacs--org-roam-read scope)))
    (with-current-buffer origin
      (kittymacs--org-roam-capture-node scope node '(:finalize find-file)))))

(defun kittymacs-org-roam-backlinks ()
  "Show graph-local backlinks in a side panel in the current frame."
  (interactive)
  (let* ((scope (kittymacs--org-roam-scope))
         (node (or (and (derived-mode-p 'org-mode) (org-roam-node-at-point))
                   (kittymacs--org-roam-read scope t)))
         (buffer (get-buffer-create
                  (format "*org-roam: %s*" (substring (secure-hash 'sha256 (car scope)) 0 12)))))
    (with-current-buffer buffer
      (setq-local kittymacs--org-roam-panel-scope scope
                  org-roam-buffer-current-directory (car scope)
                  org-roam-buffer-current-node node)
      (org-roam-buffer-render-contents))
    (display-buffer-in-side-window buffer '((side . right) (window-width . 0.33)))))

(defun kittymacs-org-roam-sync ()
  "Synchronize this graph and add its IDs to Org's independent global index."
  (interactive)
  (kittymacs--org-roam-call
   (kittymacs--org-roam-scope)
   (lambda ()
     (org-roam-db-sync)
     ;; Adding locations is deliberately separate from database ownership.
     (dolist (row (org-roam-db-query [:select [id file] :from nodes]))
       (org-id-add-location (car row) (cadr row)))
     (org-id-locations-save))))

(dolist (function '(kittymacs-org-roam-db-path kittymacs--org-roam-scope
                    kittymacs--org-roam-capture-target
                    kittymacs-org-roam-find kittymacs-org-roam-insert
                    kittymacs-org-roam-capture kittymacs-org-roam-backlinks
                    kittymacs-org-roam-sync))
  (advice-add function :around #'kittymacs--org-roam-operation))

(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(org-roam-mode . motion)))
(kittymacs-define-localleader 'org-roam-mode
  "g" (cons "refresh backlinks" #'org-roam-buffer-refresh)
  "s" (cons "sync graph" #'kittymacs-org-roam-sync)
  "f" (cons "find node" #'kittymacs-org-roam-find))

(provide 'kittymacs-org-roam)
;;; kittymacs-org-roam.el ends here
