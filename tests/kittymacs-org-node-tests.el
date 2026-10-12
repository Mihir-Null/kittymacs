;;; kittymacs-org-node-tests.el --- One graph of linked notes -*- lexical-binding: t; -*-
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
;; Startup with no notes folder and no remembered project.
(setq kittymacs-cache-dir (make-temp-file "node-startup-" t)
      kittymacs-org-directory (expand-file-name "absent" kittymacs-cache-dir))
(require 'kittymacs-org-node)
(defconst kittymacs-node-test-startup
  (list org-mem-watch-dirs org-node-cache-mode org-mem-updater-mode
        (and (memq #'kittymacs--org-node-register hack-local-variables-hook) t))
  "The index's folders and modes, and whether projects can register, as
the chapter left them when it loaded.")
;; ERT visits this file to report where a failed test is, and the checkout's
;; .dir-locals.el would add the checkout to the graph; each fixture binds
;; the hook instead.
(remove-hook 'hack-local-variables-hook #'kittymacs--org-node-register)

(defconst kittymacs-node-test-temp-root
  (or (seq-find (lambda (directory)
                  (and (file-directory-p directory)
                       (file-writable-p directory)
                       (not (kittymacs--org-node-unreadable-p (file-truename directory)))))
                (list temporary-file-directory "/tmp/"
                      (expand-file-name "../var/" (file-name-directory load-file-name))))
      (error "No temporary folder org-mem can read"))
  "Where fixtures live: a folder none of whose parents starts with . or _.
org-mem never reads such a path, and GitHub's Linux runners keep their
temporary files in /home/runner/work/_temp/.")

(defmacro kittymacs-node-test (&rest body)
  "Run BODY with a fresh notes folder, project folder and remembered list."
  (declare (indent 0))
  `(let* ((base (file-name-as-directory
                 (file-truename (let ((temporary-file-directory kittymacs-node-test-temp-root))
                                  (make-temp-file "kittymacs-node-" t)))))
          (hack-local-variables-hook (list #'kittymacs--org-node-register))
          (personal (expand-file-name "notes/" base))
          (project (expand-file-name "src/proj/" base))
          (kittymacs-cache-dir (expand-file-name "cache/" base))
          (kittymacs-org-node-directory personal)
          (kittymacs-org-node-excluded-directories nil)
          (kittymacs-org-node-projects-file (expand-file-name "org-node-projects" kittymacs-cache-dir))
          (kittymacs--org-node-projects nil)
          (kittymacs--org-node-unreadable-reported nil)
          (org-node-file-directory-ask personal)
          (org-mem-watch-dirs nil)
          (org-mem-exclude kittymacs--org-node-base-exclude)
          (org-id-locations-file (expand-file-name "ids" base))
          (org-id-locations (make-hash-table :test #'equal))
          (org-id-extra-files nil)
          (org-agenda-files nil))
     (make-directory personal t)
     (make-directory project t)
     (unwind-protect (save-window-excursion ,@body)
       (dolist (buffer (buffer-list))
         (when (or (and (buffer-file-name buffer)
                        (file-in-directory-p (buffer-file-name buffer) base))
                   (member (buffer-name buffer) '("*org-node context*" "*org-node tags*")))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (when org-mem-updater-mode (org-mem-updater-mode 0))
       (when org-node-cache-mode (org-node-cache-mode 0))
       (delete-directory base t))))

(defun kittymacs-node-test-note (root name id title &optional body)
  "Write a note with ID and TITLE to NAME under ROOT; return its file."
  (let ((file (expand-file-name name root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert (format ":PROPERTIES:\n:ID: %s\n:END:\n#+title: %s\n\n%s\n" id title (or body ""))))
    file))

(defun kittymacs-node-test-dir-locals (directory variables)
  "Write a .dir-locals.el in DIRECTORY that sets VARIABLES in every mode."
  (with-temp-file (expand-file-name ".dir-locals.el" directory)
    (prin1 `((nil . ,variables)) (current-buffer))))

(defmacro kittymacs-node-test-scanned (&rest body)
  "Run BODY, which starts a full read of the graph, and wait until it is recorded.
`org-mem-await' returns once the parsing processes exit, but their results
are recorded later, by the process sentinel; org-mem runs
`org-mem-post-full-scan-functions' once they are, after org-node has
built its candidates."
  (declare (indent 0))
  `(let* ((done nil)
          (note (lambda (&rest _) (setq done t))))
     (add-hook 'org-mem-post-full-scan-functions note 95)
     (unwind-protect
         (progn ,@body
                (let ((deadline (+ (float-time) 60)))
                  (while (and (not done) (< (float-time) deadline))
                    (accept-process-output nil 0.05)))
                (should done))
       (remove-hook 'org-mem-post-full-scan-functions note))))

(defun kittymacs-node-test-index ()
  "Start the index on the graph's folders and wait until it has read them."
  (kittymacs-node-test-scanned
    (should (kittymacs--org-node-start))
    ;; Take over any read already under way, so the one awaited is this one.
    (org-mem-reset t)))

(defun kittymacs-node-test-ids ()
  "Return the IDs the index holds, sorted."
  (sort (mapcar #'org-mem-entry-id (org-mem-all-id-nodes)) #'string<))

(defun kittymacs-node-test-candidate (prefix)
  "Return a stub `completing-read' answering the candidate that starts with PREFIX."
  (lambda (_prompt table pred &rest _)
    (or (seq-find (lambda (candidate) (string-prefix-p prefix candidate))
                  (all-completions "" table pred))
        (error "No candidate starts with %S" prefix))))

(ert-deftest kittymacs-node-startup-without-a-folder-indexes-nothing ()
  "With no folder, startup creates nothing, and every SPC n command explains."
  (should (featurep 'kittymacs-org-node))
  (should-not (file-exists-p kittymacs-org-directory))
  (should (equal kittymacs-node-test-startup '(nil nil nil t)))
  (with-temp-buffer
    (org-mode)
    (dolist (command '(kittymacs-org-node-find kittymacs-org-node-insert
                       kittymacs-org-node-new kittymacs-org-node-backlinks
                       kittymacs-org-node-rescan kittymacs-org-node-find-by-tag
                       kittymacs-org-node-tag-index))
      (should-error (call-interactively command) :type 'user-error)))
  (should-not (file-exists-p kittymacs-org-directory)))

(ert-deftest kittymacs-node-notes-folder-and-its-exclusions-are-read ()
  "Exclusions are folders relative to the root; upstream skips dot folders."
  (kittymacs-node-test
    (kittymacs-node-test-note personal "p.org" "p" "Personal")
    (kittymacs-node-test-note personal "archive/old.org" "old" "Old")
    (kittymacs-node-test-note personal "deep/archive/kept.org" "kept" "Kept")
    (kittymacs-node-test-note personal ".hidden/dot.org" "dot" "Dot")
    (setq kittymacs-org-node-excluded-directories '("archive"))
    (kittymacs-node-test-index)
    (should (equal org-mem-watch-dirs (list personal)))
    (should (member (expand-file-name "archive/" personal) org-mem-exclude))
    (should (equal (kittymacs-node-test-ids) '("kept" "p")))
    ;; org-mem hands every ID to Org's own index.
    (should (file-equal-p (gethash "p" org-id-locations) (expand-file-name "p.org" personal)))))

(ert-deftest kittymacs-node-project-flag-joins-and-is-remembered ()
  (kittymacs-node-test
    (kittymacs-node-test-dir-locals project '((kittymacs-org-node-project . t)
                                              (kittymacs-org-node-excluded-directories . ("secrets"))))
    (kittymacs-node-test-note personal "p.org" "p" "Personal")
    (let ((page (kittymacs-node-test-note project "wiki/a.org" "a" "Alpha" "[[id:p][Personal]]")))
      (kittymacs-node-test-note project "secrets/s.org" "s" "Secret")
      (kittymacs-node-test-index)
      (should (equal (kittymacs-node-test-ids) '("p")))
      (kittymacs-node-test-scanned (find-file-noselect page))
      (with-current-buffer (get-file-buffer page)
        (should (equal kittymacs--org-node-projects `((,project "secrets"))))
        (should (equal org-mem-watch-dirs (list personal project)))
        (should (equal (kittymacs-node-test-ids) '("a" "p")))
        ;; A second visit changes nothing.
        (let (starts)
          (cl-letf (((symbol-function 'kittymacs--org-node-start) (lambda () (push t starts))))
            (revert-buffer nil t))
          (should-not starts)))
      ;; The next session reads the project from the file.
      (setq kittymacs--org-node-projects nil)
      (kittymacs--org-node-load-projects)
      (should (equal kittymacs--org-node-projects `((,project "secrets"))))
      ;; Changed exclusions replace the remembered ones.
      (kill-buffer (get-file-buffer page))
      (kittymacs-node-test-dir-locals project '((kittymacs-org-node-project . t)))
      ;; Emacs re-reads a .dir-locals.el only when its modification time
      ;; changes, and Windows can give the rewrite the same time stamp.
      (setq dir-locals-directory-cache nil)
      (find-file-noselect page)
      (should (equal kittymacs--org-node-projects `((,project))))
      (should-not (member (expand-file-name "secrets/" project) org-mem-exclude))
      (kittymacs-org-node-forget-project project)
      (should-not kittymacs--org-node-projects)
      (should (equal org-mem-watch-dirs (list personal))))))

(ert-deftest kittymacs-node-project-under-a-dot-folder-is-reported-not-added ()
  (kittymacs-node-test
    (let ((hidden (expand-file-name ".config/proj/" base)))
      (kittymacs-node-test-dir-locals (progn (make-directory hidden t) hidden)
                                      '((kittymacs-org-node-project . t)))
      (find-file-noselect (kittymacs-node-test-note hidden "a.org" "a" "Alpha"))
      (should-not kittymacs--org-node-projects)
      (should (equal kittymacs--org-node-unreadable-reported (list hidden)))
      (should-not (file-exists-p kittymacs-org-node-projects-file)))))

(ert-deftest kittymacs-node-links-and-backlinks-cross-folders ()
  (kittymacs-node-test
    (setq kittymacs--org-node-projects `((,project)))
    (kittymacs-node-test-note personal "p.org" "p" "Personal" "[[id:a][Alpha]]")
    (let ((page (kittymacs-node-test-note project "a.org" "a" "Alpha" "[[id:p][Personal]]")))
      (kittymacs-node-test-index)
      (should (equal (mapcar (lambda (link) (org-mem-entry-id (org-mem-link-entry link)))
                             (org-mem-id-links-to-entry (org-mem-entry-by-id "a")))
                     '("p")))
      (should (equal (mapcar (lambda (link) (org-mem-entry-id (org-mem-link-entry link)))
                             (org-mem-id-links-to-entry (org-mem-entry-by-id "p")))
                     '("a")))
      ;; An id: link from the notes folder opens the project page.
      (should (file-equal-p (car (org-id-find "a")) page)))))

(ert-deftest kittymacs-node-new-notes-go-to-the-chosen-folder ()
  (kittymacs-node-test
    (setq kittymacs--org-node-projects `((,project)))
    (let ((page (kittymacs-node-test-note project "a.org" "a" "Alpha")))
      (kittymacs-node-test-index)
      ;; SPC n f with a new title creates the note in the notes folder.
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Brand new")))
        (kittymacs-org-node-find))
      (should (file-equal-p (file-name-directory buffer-file-name) personal))
      (should (string-search "#+title: Brand new" (buffer-string)))
      (should (org-entry-get (point-min) "ID"))
      ;; SPC n c offers the graph folder of the file it starts from.
      (with-current-buffer (find-file-noselect page)
        (should (equal (kittymacs--org-node-folder buffer-file-name) project)))
      (kittymacs-org-node-new "Project page" project)
      (should (file-equal-p (file-name-directory buffer-file-name) project))
      (cl-letf (((symbol-function 'file-writable-p) #'ignore))
        (should-error (kittymacs-org-node-new "Nope" project) :type 'user-error))
      (should-error (kittymacs-org-node-new "  " project) :type 'user-error))))

(ert-deftest kittymacs-node-insert-keeps-region-text ()
  (kittymacs-node-test
    (kittymacs-node-test-note personal "a.org" "a" "Alpha")
    (kittymacs-node-test-index)
    (with-current-buffer (find-file-noselect
                          (kittymacs-node-test-note personal "b.org" "b" "Beta"))
      (goto-char (point-max))
      (insert "see the first note")
      (let ((transient-mark-mode t)
            initial)
        (set-mark (- (point) (length "the first note")))
        (activate-mark)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt _table _pred _match init &rest _)
                     (setq initial init)
                     "Alpha")))
          (kittymacs-org-node-insert))
        (should (equal initial "the first note")))
      (should (string-search "see [[id:a][the first note]]" (buffer-string))))))

(ert-deftest kittymacs-node-backlinks-panel-is-a-side-window-in-motion-state ()
  (kittymacs-node-test
    (kittymacs-node-test-note personal "b.org" "b" "Beta" "[[id:a][Alpha]]")
    (let ((page (kittymacs-node-test-note personal "a.org" "a" "Alpha")))
      (kittymacs-node-test-index)
      (with-temp-buffer
        (should-error (kittymacs-org-node-backlinks) :type 'user-error))
      (with-current-buffer (find-file-noselect page)
        (goto-char (point-max))
        (switch-to-buffer (current-buffer))
        (kittymacs-org-node-backlinks)
        (let ((window (cl-find-if (lambda (w) (window-parameter w 'window-side)) (window-list))))
          (should window)
          (should (eq (window-parameter window 'window-side) 'right))
          (with-current-buffer (window-buffer window)
            (should (derived-mode-p 'org-node-context-mode))
            (should (string-search "Beta" (buffer-string)))
            (should (meow-motion-mode-p))))))
    (with-temp-buffer
      (org-mode)
      (insert "* No ID here\n")
      (should-error (kittymacs-org-node-backlinks) :type 'user-error))))

(defun kittymacs-node-test-tagged-graph (root)
  "Write three notes in ROOT: two tagged pages, and headings with tags of their own.
Mack's headings inherit its file tags; one adds decision.  Loop has no file
tags, and one heading carries decision and concept."
  (kittymacs-node-test-note
   root "mack.org" "mack" "Mack"
   (concat "#+filetags: :machine:nixos:\n"
           "* Services :decision:\n:PROPERTIES:\n:ID: mack-services\n:END:\n"
           "* Hardware\n:PROPERTIES:\n:ID: mack-hardware\n:END:"))
  (kittymacs-node-test-note root "flake.org" "flake" "Flake" "#+filetags: :nixos:")
  (kittymacs-node-test-note
   root "loop.org" "loop" "Loop"
   "* Why a loop :decision:concept:\n:PROPERTIES:\n:ID: loop-why\n:END:"))

(ert-deftest kittymacs-node-tags-follow-titles-in-prompt ()
  "Every tag is part of its candidate, so #tag narrows the prompt."
  (kittymacs-node-test
    (kittymacs-node-test-tagged-graph personal)
    (kittymacs-node-test-index)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt table pred &rest _)
                 (let* ((candidates (all-completions "" table pred))
                        (decisions (seq-filter (lambda (candidate)
                                                 (string-search "#decision" candidate))
                                               candidates))
                        (services (seq-find (lambda (candidate)
                                              (string-prefix-p "Services " candidate))
                                            candidates)))
                   (should (= (length decisions) 2))
                   (dolist (tag '("#decision" "#machine" "#nixos"))
                     (should (string-search tag services)))
                   (seq-find (lambda (candidate) (string-prefix-p "Why a loop " candidate))
                             decisions)))))
      (kittymacs-org-node-find))
    (should (equal (org-entry-get nil "ID") "loop-why"))
    ;; A link inserted from a tagged candidate still shows the title.
    (with-current-buffer (find-file-noselect (expand-file-name "flake.org" personal))
      (goto-char (point-max))
      (cl-letf (((symbol-function 'completing-read) (kittymacs-node-test-candidate "Services ")))
        (kittymacs-org-node-insert))
      (should (string-search "[[id:mack-services][Services]]" (buffer-string))))))

(ert-deftest kittymacs-node-find-by-tag-lists-tags-then-their-notes ()
  "SPC n t offers the graph's tags with their counts, then only those notes."
  (kittymacs-node-test
    (kittymacs-node-test-tagged-graph personal)
    (kittymacs-node-test-index)
    (let (prompts)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (prompt table pred &rest _)
                   (push prompt prompts)
                   (if (string-prefix-p "Tag" prompt)
                       (let ((annotate (completion-metadata-get
                                        (completion-metadata "" table pred)
                                        'annotation-function)))
                         (should (equal (all-completions "" table pred)
                                        '("concept" "decision" "machine" "nixos")))
                         (should (equal (funcall annotate "nixos") "  4 notes"))
                         (should (equal (funcall annotate "concept") "  1 note"))
                         "decision")
                     (let ((notes (sort (all-completions "" table pred) #'string<)))
                       (should (= (length notes) 2))
                       (should (string-prefix-p "Services " (nth 0 notes)))
                       (should (string-prefix-p "Why a loop " (nth 1 notes)))
                       (nth 1 notes))))))
        (kittymacs-org-node-find-by-tag))
      (should (= (length prompts) 2))
      (should (equal (org-entry-get nil "ID") "loop-why")))))

(ert-deftest kittymacs-node-tag-index-lists-pages-once-and-headings-by-own-tags ()
  "SPC n T lists a page under its file tags and a heading under the tags it adds."
  (kittymacs-node-test
    (kittymacs-node-test-tagged-graph personal)
    (kittymacs-node-test-index)
    (kittymacs-org-node-tag-index)
    (with-current-buffer "*org-node tags*"
      (let ((text (buffer-substring-no-properties (point-min) (point-max))))
        (dolist (expected
                 '("* concept (1)\n- [[id:loop-why][Why a loop]] · notes/loop.org\n"
                   "* decision (2)\n- [[id:loop-why][Why a loop]] · notes/loop.org\n- [[id:mack-services][Services]] · notes/mack.org\n"
                   "* machine (1)\n- [[id:mack][Mack]] · notes/mack.org\n"
                   "* nixos (2)\n- [[id:flake][Flake]] · notes/flake.org\n- [[id:mack][Mack]] · notes/mack.org\n"))
          (should (string-search expected text))))
      (goto-char (point-min))
      (search-forward "[[id:mack-services]")
      (org-open-at-point))
    (with-current-buffer (window-buffer)
      (should (equal (org-entry-get nil "ID") "mack-services")))))

;;; kittymacs-org-node-tests.el ends here
