;;; kittymacs-org-roam-tests.el --- Scoped graphs -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'package)
(setq native-comp-jit-compilation nil)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(dolist (fn '(package-install package-refresh-contents))
  (advice-add fn :override
              (lambda (&rest _) (error "Package installation forbidden in graph tests"))))
(add-to-list 'load-path (expand-file-name "../lisp" (file-name-directory load-file-name)))
(require 'use-package)
(require 'kittymacs-leader)
(require 'meow)
(meow-global-mode 1)
(defvar kittymacs-cache-dir)
(defvar kittymacs-org-directory)
(setq kittymacs-cache-dir (make-temp-file "roam-startup-" t)
      kittymacs-org-directory (expand-file-name "absent" kittymacs-cache-dir))
;; Startup must load even when native SQLite is unavailable.
(cl-letf (((symbol-function 'sqlite-available-p) (lambda () nil)))
  (require 'kittymacs-org-roam nil t))

(defmacro kittymacs-roam-test (&rest body)
  (declare (indent 0))
  `(let* ((frames-before (frame-list))
          (frame-before (selected-frame))
          ;; The real path, so paths built from it are the ones the graph uses.
          (base (file-name-as-directory
                 (file-truename (make-temp-file "kittymacs-roam-" t))))
          (personal (expand-file-name "personal/" base))
          (project (expand-file-name "worktree/" base))
          (kittymacs-cache-dir (expand-file-name "cache/" base))
          (kittymacs-org-roam-directory personal)
          (org-roam-directory personal)
          (org-roam-db-location (expand-file-name "personal.db" kittymacs-cache-dir))
          (org-id-locations-file (expand-file-name "ids" base))
          (org-id-locations (make-hash-table :test #'equal))
          (org-id-extra-files nil)
          (org-roam-db--connection (make-hash-table :test #'equal))
          (org-roam-list-files-commands nil)
          (org-agenda-files nil))
     (make-directory personal t)
     (make-directory project t)
     (make-directory kittymacs-cache-dir t)
     (unwind-protect (save-window-excursion ,@body)
       (when (frame-live-p frame-before) (select-frame frame-before))
       (dolist (frame (seq-difference (frame-list) frames-before))
         (when (frame-live-p frame) (delete-frame frame t)))
       (when (fboundp 'org-roam-db--close-all) (org-roam-db--close-all))
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (file-in-directory-p (buffer-file-name buffer) base))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (dolist (buffer (buffer-list))
         (when (or (string-prefix-p "*org-roam:" (buffer-name buffer))
                   (equal (buffer-name buffer) "*roam-test-switch*"))
           (kill-buffer buffer)))
       (delete-directory base t))))

(defun kittymacs-roam-test-symlink (target link)
  "Create a fixture symlink or explicitly skip on hosts that forbid it."
  (condition-case err (make-symbolic-link target link)
    (file-error (ert-skip (format "Host disallows symlinks: %s" err)))))

(defun kittymacs-roam-test-note (root name id title &optional body)
  (let ((file (expand-file-name name root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: %s\n\n%s\n" id title (or body ""))))
    file))

(defun kittymacs-roam-test-dir-locals (directory variables)
  "Write a .dir-locals.el in DIRECTORY that sets VARIABLES in every mode."
  (with-temp-file (expand-file-name ".dir-locals.el" directory)
    (prin1 `((nil . ,variables)) (current-buffer))))

(defmacro kittymacs-roam-test-project (&rest body)
  (declare (indent 0))
  `(with-temp-buffer
     (setq-local org-roam-directory project
                 org-roam-db-location (kittymacs-org-roam-db-path project))
     ,@body))

(ert-deftest kittymacs-roam-cache-physical-identity ()
  (should (fboundp 'kittymacs-org-roam-db-path))
  (kittymacs-roam-test
    (let ((alias (expand-file-name "alias" base)))
      (kittymacs-roam-test-symlink project alias)
      (should (equal (kittymacs-org-roam-db-path project)
                     (kittymacs-org-roam-db-path alias)))
      (should-not (equal (kittymacs-org-roam-db-path personal)
                         (kittymacs-org-roam-db-path project)))
      (should (file-in-directory-p (kittymacs-org-roam-db-path project)
                                  kittymacs-cache-dir)))))

(ert-deftest kittymacs-roam-startup-is-lazy-and-sqlite-is-required ()
  (should (featurep 'kittymacs-org-roam))
  (should-not (file-exists-p kittymacs-org-directory))
  (should-not (directory-files-recursively kittymacs-cache-dir "sqlite\\'"))
  (cl-letf (((symbol-function 'sqlite-available-p) (lambda () nil)))
    (dolist (command '(kittymacs-org-roam-find kittymacs-org-roam-insert
                      kittymacs-org-roam-capture kittymacs-org-roam-backlinks
                      kittymacs-org-roam-sync))
      (should-error (funcall command) :type 'user-error))))

(ert-deftest kittymacs-roam-real-databases-keep-graphs-apart ()
  (kittymacs-roam-test
    (kittymacs-roam-test-note personal "p.org" "p" "Personal")
    (kittymacs-roam-test-note project "a.org" "a" "Alpha" "[[id:b][Beta]] [[id:p][Personal]]")
    (kittymacs-roam-test-note project "b.org" "b" "Beta")
    (kittymacs-org-roam-sync)
    (should (equal (org-roam-db-query [:select id :from nodes]) '(("p"))))
    (kittymacs-roam-test-project
      (kittymacs-org-roam-sync)
      (should (equal (org-roam-db-query [:select id :from nodes :order-by id]) '(("a") ("b"))))
      (should (equal (org-roam-db-query [:select [source dest] :from links :order-by dest])
                     '(("a" "b") ("a" "p")))))))

(ert-deftest kittymacs-roam-default-exclusions-are-generic ()
  "The personal graph leaves out Git and cache folders, and nothing else."
  (should (equal (eval (car (get 'kittymacs-org-roam-excluded-directories 'standard-value)))
                 '(".git" ".cache" "cache" "caches")))
  (kittymacs-roam-test
    (kittymacs-roam-test-note personal "p.org" "p" "Personal")
    (dolist (dir '(".git" ".cache" "cache" "caches" "deep/cache"))
      (kittymacs-roam-test-note personal (concat dir "/excluded.org") dir dir))
    (dolist (dir '("legacy" "secrets" "var" "cached"))
      (kittymacs-roam-test-note personal (concat dir "/kept.org") dir dir))
    (kittymacs-org-roam-sync)
    (should (equal (org-roam-db-query [:select id :from nodes :order-by id])
                   '(("cached") ("legacy") ("p") ("secrets") ("var"))))))

(ert-deftest kittymacs-roam-project-flag-names-root-database-and-exclusions ()
  "The .dir-locals.el that EmptyNet ships makes its folder a graph of its own."
  (should (safe-local-variable-p 'kittymacs-org-roam-project t))
  (should (safe-local-variable-p 'kittymacs-org-roam-excluded-directories '("secrets")))
  (should-not (safe-local-variable-p 'kittymacs-org-roam-excluded-directories '(secrets)))
  (kittymacs-roam-test
    (kittymacs-roam-test-dir-locals
     project '((kittymacs-org-roam-project . t)
               (kittymacs-org-roam-excluded-directories . ("secrets" "tools" "web" ".github"))))
    (let ((file (kittymacs-roam-test-note project "a.org" "a" "Alpha"))
          (hidden (kittymacs-roam-test-note project "secrets/s.org" "s" "Secret")))
      ;; Only the project's list applies, so its cache folder is indexed.
      (kittymacs-roam-test-note project "cache/c.org" "c" "Cache")
      (kittymacs-roam-test-note project "notes/n.org" "n" "Nested")
      (with-current-buffer (find-file-noselect file)
        (should (equal org-roam-directory project))
        (should (equal org-roam-db-location (kittymacs-org-roam-db-path project)))
        (kittymacs-org-roam-sync)
        (should (equal (org-roam-db-query [:select id :from nodes :order-by id])
                       '(("a") ("c") ("n"))))
        ;; Org-roam's own sync, started in a project note, reads new notes
        ;; into the project's database too.
        (kittymacs-roam-test-note project "notes/m.org" "m" "Upstream")
        (org-roam-db-sync)
        (should (equal (org-roam-db-query [:select id :from nodes :order-by id])
                       '(("a") ("c") ("m") ("n")))))
      (with-current-buffer (find-file-noselect hidden)
        (should (equal org-roam-directory project))
        (should-not (org-roam-file-p)))
      (let ((default-directory project))
        (with-temp-buffer
          (hack-dir-local-variables-non-file-buffer)
          (should (equal (car (kittymacs--org-roam-scope)) project))))
      (should-not (file-exists-p (expand-file-name "personal.db" kittymacs-cache-dir))))))

(ert-deftest kittymacs-roam-project-find-and-insert-require-existing ()
  (kittymacs-roam-test
    (let ((file (kittymacs-roam-test-note project "a.org" "a" "Alpha")))
      (kittymacs-roam-test-project
        (kittymacs-org-roam-sync)
        (let ((origin (current-buffer)))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt table pred require-match &rest _)
                       (should require-match)
                       (should (member "Alpha" (all-completions "" table pred)))
                       (set-buffer (get-buffer-create "*roam-test-switch*"))
                       "Alpha")))
            (kittymacs-org-roam-insert)
            (with-current-buffer origin (should (equal (buffer-string) "[[id:a][Alpha]]")))
            (set-buffer origin)
            (kittymacs-org-roam-find)
            (set-buffer (window-buffer))
            (should (file-equal-p buffer-file-name file))
            (should (file-equal-p org-roam-directory project))))))))

(ert-deftest kittymacs-roam-insert-keeps-region-text ()
  "The selected text starts the prompt and becomes the link's description."
  (kittymacs-roam-test
    (kittymacs-roam-test-note personal "a.org" "a" "Alpha")
    (kittymacs-org-roam-sync)
    (with-temp-buffer
      (let ((transient-mark-mode t))
        (insert "see the first letter here")
        (set-mark 5)
        (goto-char 21)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt _table _pred _require-match initial &rest _)
                     (should (equal initial "the first letter"))
                     "Alpha")))
          (kittymacs-org-roam-insert))
        (should (equal (buffer-string) "see [[id:a][the first letter]] here"))))))

(ert-deftest kittymacs-roam-capture-finalizes-in-originating-graph ()
  (kittymacs-roam-test
    (kittymacs-roam-test-note personal "p.org" "p" "Personal")
    (kittymacs-org-roam-sync)
    (kittymacs-roam-test-project
      (let ((org-roam-capture-templates
             '(("d" "default" plain "%?" :target (file+head "new.org" "#+title: ${title}\n") :unnarrowed t))))
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Captured")))
          (kittymacs-org-roam-capture))
        (set-buffer (window-buffer))
        (should (buffer-base-buffer))
        (should (file-equal-p org-roam-directory project))
        (let ((capture (current-buffer)))
          (with-current-buffer (get-buffer-create "*roam-test-switch*")
            (setq-local org-roam-directory personal
                        org-roam-db-location (kittymacs-org-roam-db-path personal)))
          (switch-to-buffer "*roam-test-switch*")
          (switch-to-buffer capture)
          (insert "Captured body")
          (org-capture-finalize))
        (should (file-exists-p (expand-file-name "new.org" project)))
        (should-not (file-exists-p (expand-file-name "new.org" personal)))))
    (kittymacs-roam-test-project
      (should (equal (org-roam-db-query [:select title :from nodes]) '(("Captured")))))
    (should (equal (org-roam-db-query [:select id :from nodes]) '(("p"))))))

(ert-deftest kittymacs-roam-backlinks-refresh-keeps-scope-and-frame ()
  (kittymacs-roam-test
    (kittymacs-roam-test-note project "a.org" "a" "Alpha" "[[id:b][Beta]]")
    (kittymacs-roam-test-note project "b.org" "b" "Beta")
    (kittymacs-roam-test-project
      (kittymacs-org-roam-sync)
      (let ((frame (selected-frame)))
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Beta")))
          (kittymacs-org-roam-backlinks))
        ;; The side window is observable regardless of selection policy.
        (let ((panel (cl-loop for window in (window-list)
                              when (window-parameter window 'window-side)
                              return (window-buffer window))))
          (should panel)
          (with-current-buffer panel
            (should (derived-mode-p 'org-roam-mode))
            (org-roam-buffer-refresh)
            (should (equal org-roam-db-location (kittymacs-org-roam-db-path project)))
            (should (string-match-p "Alpha" (buffer-string)))
            (should (meow-motion-mode-p)))
          (should (eq frame (selected-frame))))))))

(ert-deftest kittymacs-roam-cross-graph-id-does-not-import ()
  (kittymacs-roam-test
    (kittymacs-roam-test-note personal "p.org" "p" "Personal")
    (kittymacs-roam-test-note project "a.org" "a" "Alpha" "[[id:p][Personal]]")
    (kittymacs-org-roam-sync)
    (kittymacs-roam-test-project
      (kittymacs-org-roam-sync)
      (let ((marker (org-id-find "p" t)))
        (should (markerp marker))
        (with-current-buffer (marker-buffer marker)
          (should (file-equal-p org-roam-directory personal))
          (should (equal (org-roam-db-query [:select id :from nodes]) '(("p")))))
        (set-marker marker nil))
      (should (equal (org-roam-db-query [:select id :from nodes]) '(("a")))))))

(ert-deftest kittymacs-roam-missing-root-fails-without-creating-it ()
  (kittymacs-roam-test
    (delete-directory project)
    (kittymacs-roam-test-project
      (should-error (kittymacs-org-roam-sync) :type 'user-error)
      (should-error (kittymacs-org-roam-capture) :type 'user-error)
      (should-not (file-exists-p project)))))

(ert-deftest kittymacs-roam-alias-uses-one-real-connection ()
  (kittymacs-roam-test
    (let ((alias (expand-file-name "alias/" base)))
      (kittymacs-roam-test-symlink project (directory-file-name alias))
      (kittymacs-roam-test-note project "a.org" "a" "Alpha")
      (kittymacs-roam-test-project
        (kittymacs-org-roam-sync)
        (setq-local org-roam-directory alias)
        (kittymacs-org-roam-sync)
        (should (= (hash-table-count org-roam-db--connection) 1))
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Alpha")))
          (kittymacs-org-roam-insert))
        (should (equal (buffer-string) "[[id:a][Alpha]]"))))))

(ert-deftest kittymacs-roam-read-only-root-browses-but-cannot-capture ()
  (kittymacs-roam-test
    (kittymacs-roam-test-note project "a.org" "a" "Alpha")
    (set-file-modes project #o555)
    (unwind-protect
        (progn
          (skip-unless (not (file-writable-p project)))
          (kittymacs-roam-test-project
            (kittymacs-org-roam-sync)
            (should (equal (org-roam-db-query [:select id :from nodes]) '(("a"))))
            (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "No write")))
              (should-error (kittymacs-org-roam-capture) :type 'user-error))
            (should (equal (directory-files project nil "\\.org\\'") '("a.org")))))
      (set-file-modes project #o755))))

(ert-deftest kittymacs-roam-explicit-dir-locals-pair-survives-panel-and-id-links ()
  "Directory locals that set both upstream variables still name a graph."
  (kittymacs-roam-test
    (let* ((external (expand-file-name "custom.sqlite" kittymacs-cache-dir))
           (file (kittymacs-roam-test-note project "a.org" "a" "Alpha"))
           ;; Upstream does not declare its variables safe; accept them here
           ;; as a user would at the prompt.
           (enable-local-variables :all))
      (kittymacs-roam-test-dir-locals
       project `((org-roam-directory . ,project) (org-roam-db-location . ,external)))
      (with-current-buffer (find-file-noselect file)
        (should (equal org-roam-directory project))
        (should (equal org-roam-db-location external))
        (kittymacs-org-roam-sync)
        (kittymacs-org-roam-backlinks)
        (let ((panel (cl-loop for window in (window-list)
                              when (window-parameter window 'window-side)
                              return (window-buffer window))))
          (with-current-buffer panel
            (org-roam-buffer-refresh)
            (should (equal org-roam-db-location external)))))
      (let ((marker (org-id-find "a" t)))
        (with-current-buffer (marker-buffer marker)
          (should (equal org-roam-directory project))
          (should (equal org-roam-db-location external))
          (should (equal (org-roam-db-query [:select id :from nodes]) '(("a")))))
        (set-marker marker nil))
      (should-not (file-exists-p (kittymacs-org-roam-db-path project))))))

(ert-deftest kittymacs-roam-personal-insert-capture-callback-retains-origin ()
  (kittymacs-roam-test
    (with-temp-buffer
      (org-mode)
      (let ((origin (current-buffer))
            (org-roam-capture-templates
             '(("d" "default" plain "%?" :target (file+head "new.org" "#+title: ${title}\n") :unnarrowed t))))
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "New personal")))
          (kittymacs-org-roam-insert))
        (with-current-buffer (window-buffer)
          (let ((capture (current-buffer)))
            (switch-to-buffer (get-buffer-create "*roam-test-switch*"))
            (setq-local org-roam-directory project
                        org-roam-db-location (kittymacs-org-roam-db-path project))
            (switch-to-buffer capture)
            (org-capture-finalize)))
        (with-current-buffer origin
          (should (string-match-p "\\[\\[id:.*\\]\\[New personal\\]\\]" (buffer-string))))
        (should (file-exists-p (expand-file-name "new.org" personal)))
        (should-not (file-exists-p (expand-file-name "new.org" project)))
        (should (equal (org-roam-db-query [:select title :from nodes]) '(("New personal"))))))))

(ert-deftest kittymacs-roam-case-insensitive-root-identity ()
  (kittymacs-roam-test
    (skip-unless (file-name-case-insensitive-p project))
    (should (equal (kittymacs-org-roam-db-path project)
                   (kittymacs-org-roam-db-path (upcase project))))))

(ert-deftest kittymacs-roam-panel-source-navigation-preserves-panel ()
  (kittymacs-roam-test
    (let ((file (kittymacs-roam-test-note project "a.org" "a" "Alpha")))
      (kittymacs-roam-test-project
        (kittymacs-org-roam-sync)
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Alpha")))
          (kittymacs-org-roam-backlinks))
        (let* ((window (cl-find-if (lambda (w) (window-parameter w 'window-side)) (window-list)))
               (panel (window-buffer window)))
          (select-window window)
          (org-roam-node-visit (org-roam-node-from-id "a"))
          (should (eq panel (window-buffer window)))
          (should-not (eq window (selected-window)))
          (should (file-equal-p buffer-file-name file))
          (select-window window)
          (org-roam-preview-visit file 1)
          (should (eq panel (window-buffer window)))
          (should-not (eq window (selected-window)))
          (should (file-equal-p buffer-file-name file)))))))

(ert-deftest kittymacs-roam-gui-source-obeys-frames-policy ()
  "Run after ordinary GUI startup with frames-only-mode enabled."
  (skip-unless (and (display-graphic-p) (bound-and-true-p frames-only-mode)))
  (kittymacs-roam-test
    (kittymacs-roam-test-dir-locals project '((kittymacs-org-roam-project . t)))
    (kittymacs-roam-test-note project "a.org" "a" "Alpha")
    (kittymacs-roam-test-note project "b.org" "b" "Beta")
    (kittymacs-roam-test-project
      (kittymacs-org-roam-sync)
      (let ((origin-frame (selected-frame)))
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Beta")))
          (kittymacs-org-roam-backlinks))
        (should (eq origin-frame (selected-frame)))
        (let ((window (cl-find-if (lambda (w) (window-parameter w 'window-side)) (window-list))))
          (select-window window)
          (should (meow-motion-mode-p))
          (org-roam-node-visit (org-roam-node-from-id "a"))
          (should-not (eq origin-frame (selected-frame)))
          (should (derived-mode-p 'org-mode))
          (should (file-equal-p org-roam-directory project))
          (should (eq (window-parameter window 'window-side) 'right)))))))

(ert-deftest kittymacs-roam-cross-graph-id-already-open-destination ()
  (kittymacs-roam-test
    (kittymacs-roam-test-dir-locals project '((kittymacs-org-roam-project . t)))
    (let* ((file (kittymacs-roam-test-note project "a.org" "a" "Alpha"))
           (buffer (find-file-noselect file)))
      (with-current-buffer buffer (kittymacs-org-roam-sync))
      (let ((marker (org-id-find "a" t)))
        (should (eq buffer (marker-buffer marker)))
        (with-current-buffer buffer
          (should (equal org-roam-directory project))
          (should (equal org-roam-db-location (kittymacs-org-roam-db-path project))))
        (set-marker marker nil)))))

(ert-deftest kittymacs-roam-capture-then-sync-keeps-one-physical-record ()
  "Capture save, ordinary DB/ID access and sync must agree on path identity."
  (kittymacs-roam-test
    (let ((org-roam-capture-templates
           '(("d" "default" plain "%?" :target (file+head "MixedCase.org" "#+title: ${title}\n") :unnarrowed t))))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Unique")))
        (kittymacs-org-roam-capture))
      (with-current-buffer (window-buffer) (org-capture-finalize))
      (should (equal (org-roam-db-query [:select title :from nodes]) '(("Unique"))))
      (let ((id (caar (org-roam-db-query [:select id :from nodes]))))
        (should (org-id-find id)))
      (should (= 1 (hash-table-count org-roam-db--connection)))
      (kittymacs-org-roam-sync)
      (should (equal (org-roam-db-query [:select title :from nodes]) '(("Unique"))))
      (should (= 1 (length (org-roam-db-query [:select file :from files]))))
      (should (= 1 (hash-table-count org-roam-db--connection)))
      (dolist (row (org-roam-db-query [:select file :from files]))
        (should (file-equal-p (car row) (expand-file-name "MixedCase.org" personal)))))))

(ert-deftest kittymacs-roam-id-preserves-established-destination-pair ()
  (kittymacs-roam-test
    (let* ((file (kittymacs-roam-test-note project "a.org" "a" "Alpha"))
           (buffer (find-file-noselect file))
           (external (expand-file-name "custom.sqlite" kittymacs-cache-dir)))
      (with-current-buffer buffer
        (setq-local org-roam-directory project org-roam-db-location external)
        (kittymacs-org-roam-sync))
      (let ((marker (org-id-find "a" t)))
        (should (eq buffer (marker-buffer marker)))
        (with-current-buffer buffer
          (should (file-equal-p org-roam-directory project))
          (should (equal org-roam-db-location external))
          (should (equal (org-roam-db-query [:select id :from nodes]) '(("a")))))
        (set-marker marker nil)))))

(ert-deftest kittymacs-roam-ordinary-id-with-missing-root ()
  "An absent optional graph must not intercept Org's own registered IDs."
  (kittymacs-roam-test
    (let ((file (kittymacs-roam-test-note base "ordinary/note.org"
                                         "ordinary" "Outside graph")))
      (delete-directory personal)
      (org-id-add-location "ordinary" file)
      (let ((marker (org-id-find "ordinary" t)))
        (should (markerp marker))
        (should (file-equal-p file (buffer-file-name (marker-buffer marker))))
        (should (= 1 (marker-position marker)))
        (set-marker marker nil))
      (should (file-equal-p file (car (org-id-find "ordinary"))))
      (should-error (kittymacs-org-roam-sync) :type 'user-error)
      (should-error (kittymacs-org-roam-capture) :type 'user-error)
      (should (= 0 (hash-table-count org-roam-db--connection)))
      (should-not (file-exists-p personal)))))

