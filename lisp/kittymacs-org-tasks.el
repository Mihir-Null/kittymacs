;;; kittymacs-org-tasks.el --- Project tasks and Edna dependencies -*- lexical-binding: t; -*-
;; Generated from literate/83-org-tasks.org; edit the Org source, then tangle.

(require 'cl-lib)
(require 'project)
(require 'tabulated-list)
(require 'kittymacs-leader)
(declare-function kittymacs--org-files-here "kittymacs-org-extras")
(declare-function org-agenda-files "org" (&optional unrestricted archives))
(declare-function org-back-to-heading "org" (&optional invisible-ok))
(declare-function org-beginning-of-dblock "org")
(declare-function org-edna-mode "org-edna" (&optional arg))
(declare-function org-entry-blocked-p "org")
(declare-function org-entry-get "org" (pom property &optional inherit literal-nil))
(declare-function org-entry-put "org" (pom property value))
(declare-function org-fold-show-context "org-fold" (&optional key))
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))
(declare-function org-get-todo-state "org")
(declare-function org-id-find "org-id" (id &optional markerp))
(declare-function org-id-get-create "org-id" (&optional force))
(declare-function org-kanban/initialize-here "org-kanban")
(declare-function org-kanban/prev "org-kanban")
(declare-function org-kanban/next "org-kanban")
(declare-function org-ql-select "org-ql" (buffers-or-files query &rest args))
(declare-function org-todo "org" (&optional arg))
(declare-function org-update-dblock "org")
(defvar org-not-done-keywords)
(defvar org-todo-keywords-1)
(defvar org-edna-use-inheritance)
(defvar meow-mode-state-list)

(defcustom kittymacs-org-task-files nil
  "Org task files for this project, relative to its root.
When unset, search the Org files known to the project."
  :type '(repeat file)
  :safe (lambda (files)
          (and (proper-list-p files)
               (seq-every-p (lambda (file)
                              (and (stringp file)
                                   (not (file-name-absolute-p file))
                                   (not (member ".." (split-string file "/")))))
                            files)))
  :group 'kittymacs)

(defvar kittymacs-org-tasks--missing-ids nil
  "Unresolved IDs from an Edna lookup in the current task check.")

(defun kittymacs-org-tasks--require-ids (original &rest ids)
  "Call Edna finder ORIGINAL with IDS and report unresolved targets."
  (let* ((markers (apply original ids))
         (missing (cl-loop for id in ids for marker in markers
                           unless (and (markerp marker) (marker-buffer marker))
                           collect id)))
    (when missing
      (setq kittymacs-org-tasks--missing-ids missing)
      (user-error "Unresolved Org task IDs: %s" (string-join missing ", ")))
    markers))

(use-package org-edna
  :ensure t
  :after org
  :demand t
  :config
  (advice-add 'org-edna-finder/ids :around #'kittymacs-org-tasks--require-ids)
  (org-edna-mode 1))

(defun kittymacs-org-tasks--files (&optional include-agenda)
  "Return project Org files, adding agenda files when INCLUDE-AGENDA is non-nil."
  (let ((files (if kittymacs-org-task-files
                   (let ((root (if-let* ((project (project-current)))
                                   (project-root project)
                                 default-directory)))
                     (mapcar (lambda (file) (expand-file-name file root))
                             kittymacs-org-task-files))
                 (condition-case nil (kittymacs--org-files-here) (user-error nil)))))
    (delete-dups (append (seq-filter #'file-regular-p files)
                         (when include-agenda (org-agenda-files t))))))

(defun kittymacs-org-tasks--markers (files)
  "Return markers to unfinished Org tasks in FILES."
  (require 'org-ql)
  (org-ql-select files '(todo) :action #'point-marker))

(defun kittymacs-org-tasks--at (marker function)
  "Run FUNCTION at the widened heading indicated by MARKER."
  (unless (and (markerp marker) (marker-buffer marker))
    (user-error "This task disappeared; refresh the view"))
  (with-current-buffer (marker-buffer marker)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char marker)
        (org-back-to-heading t)
        (funcall function)))))

(defun kittymacs-org-tasks--label (marker)
  "Return a task title with file and line for MARKER."
  (kittymacs-org-tasks--at
   marker (lambda () (format "%s — %s:%d"
                             (org-get-heading t t)
                             (abbreviate-file-name buffer-file-name)
                             (line-number-at-pos)))))

(defun kittymacs-org-tasks--id-clause (id)
  "Format ID as an Edna finder with a string argument."
  (let ((print-escape-newlines t))
    (format "ids(%S)" id)))

(defun kittymacs-org-tasks--ids (rule)
  "Extract explicit IDs mentioned in Edna finder calls in RULE."
  (let ((start 0) ids)
    (while (string-match "\\_<ids(\\([^)]*\\))" (or rule "") start)
      (setq start (match-end 0))
      (dolist (arg (split-string (match-string 1 rule) "[[:space:]\"]+" t))
        (push (string-remove-prefix "id:" arg) ids)))
    ids))

(defun kittymacs-org-tasks--reaches-p (origin goal)
  "Return non-nil if ORIGIN reaches GOAL through explicit Edna IDs."
  (let ((pending (list origin)) seen found)
    (while (and pending (not found))
      (let ((marker (pop pending)))
        (cond
         ((equal marker goal) (setq found t))
         ((not (member marker seen))
          (push marker seen)
          (dolist (id (kittymacs-org-tasks--at
                       marker (lambda ()
                                (kittymacs-org-tasks--ids
                                 (org-entry-get nil "BLOCKER" org-edna-use-inheritance)))))
            (when-let* ((target (org-id-find id 'marker)))
              (push target pending)))))))
    found))

(defun kittymacs-org-tasks--append-rule (property clause)
  "Append CLAUSE to the effective PROPERTY on the current heading."
  (let ((existing (org-entry-get nil property org-edna-use-inheritance)))
    (unless (member clause (split-string (or existing "") "  +" t))
      (org-entry-put nil property
                     (string-join (delq nil (list existing clause)) "  ")))))

(defun kittymacs-org-tasks--relate (dependent prerequisite trigger)
  "Make DEPENDENT wait for PREREQUISITE and optionally set its TRIGGER."
  (when (kittymacs-org-tasks--reaches-p prerequisite dependent)
    (user-error "This link would create a task dependency cycle"))
  (dolist (marker (list dependent prerequisite))
    (kittymacs-org-tasks--at
     marker (lambda ()
              (unless (and buffer-file-name (not buffer-read-only))
                (user-error "Task needs a writable Org file"))
              (unless (member (org-get-todo-state) org-not-done-keywords)
                (user-error "Choose an unfinished task")))))
  (let* ((prerequisite-id (kittymacs-org-tasks--at prerequisite #'org-id-get-create))
         (dependent-id (kittymacs-org-tasks--at dependent #'org-id-get-create))
         (blocker (concat (kittymacs-org-tasks--id-clause prerequisite-id) " !done?")))
    (kittymacs-org-tasks--at dependent
                            (lambda () (kittymacs-org-tasks--append-rule "BLOCKER" blocker)))
    (when trigger
      (kittymacs-org-tasks--at
       prerequisite
       (lambda ()
         (kittymacs-org-tasks--append-rule
          "TRIGGER" (format "%s todo!(%S)" (kittymacs-org-tasks--id-clause dependent-id)
                            trigger)))))))

(defun kittymacs-org-tasks--pick-and-relate (include-agenda promote)
  "Read a prerequisite, optionally from INCLUDE-AGENDA, and PROMOTE on completion."
  (org-back-to-heading t)
  (let* ((dependent (point-marker))
         (files (or (kittymacs-org-tasks--files include-agenda)
                    (user-error "No Org task files here")))
         (candidates (cl-loop for marker in (kittymacs-org-tasks--markers files)
                              unless (equal marker dependent)
                              collect (cons (kittymacs-org-tasks--label marker) marker)))
         (prerequisite (if candidates
                           (cdr (assoc (completing-read "Prerequisite: " candidates nil t)
                                       candidates))
                         (user-error "No other unfinished task found")))
         (state (when promote (completing-read "Promote dependent to: "
                                              org-not-done-keywords nil t))))
    (unless (yes-or-no-p
             (format "%s waits for %s%s? "
                     (kittymacs-org-tasks--label dependent)
                     (kittymacs-org-tasks--label prerequisite)
                     (if state (format ", then moves to %s" state) "")))
      (user-error "Canceled"))
    (kittymacs-org-tasks--relate dependent prerequisite state)))

(defun kittymacs-org-tasks-link (include-agenda)
  "Add a prerequisite for this heading, searching agenda files with INCLUDE-AGENDA."
  (interactive "P")
  (kittymacs-org-tasks--pick-and-relate include-agenda nil))

(defun kittymacs-org-tasks-link-and-promote (include-agenda)
  "Add a prerequisite and a promotion trigger.
With INCLUDE-AGENDA, search configured agenda files as well."
  (interactive "P")
  (kittymacs-org-tasks--pick-and-relate include-agenda t))
(defvar-local kittymacs-org-tasks--view-files nil)
(defvar-local kittymacs-org-tasks--view-blocked nil)

(defun kittymacs-org-tasks--status ()
  "Return the live blocking status of the current heading, or nil."
  (let (kittymacs-org-tasks--missing-ids)
    (when (org-entry-blocked-p)
      (if kittymacs-org-tasks--missing-ids
          (concat "Missing: " (string-join kittymacs-org-tasks--missing-ids ", "))
        "Blocked"))))

(defun kittymacs-org-tasks--rows ()
  "Return project task rows with current blocking status."
  (let ((blocked-only kittymacs-org-tasks--view-blocked))
    (cl-loop for marker in (kittymacs-org-tasks--markers kittymacs-org-tasks--view-files)
             for row = (kittymacs-org-tasks--at
                        marker
                        (lambda ()
                          (let ((status (kittymacs-org-tasks--status)))
                            (when (or status (not blocked-only))
                              (list marker (vector (org-get-todo-state) (or status "")
                                                   (kittymacs-org-tasks--label marker)))))))
             when row collect row)))

(defun kittymacs-org-tasks-visit ()
  "Visit the task listed on the current line."
  (interactive)
  (let ((marker (tabulated-list-get-id)))
    (unless (and (markerp marker) (marker-buffer marker))
      (user-error "No live task on this line"))
    (pop-to-buffer (marker-buffer marker))
    (goto-char marker)
    (org-fold-show-context)))

(defun kittymacs-org-tasks-change-state ()
  "Prompt for an Org TODO transition and refresh the task list."
  (interactive)
  (kittymacs-org-tasks--at
   (tabulated-list-get-id)
   (lambda () (org-todo (completing-read "Task state: " org-todo-keywords-1 nil t))))
  (revert-buffer))

(define-derived-mode kittymacs-org-tasks-mode tabulated-list-mode "Org Tasks"
  "Project task view with live Org dependency status."
  (setq tabulated-list-format [("State" 10 t) ("Dependency" 24 t) ("Task" 0 t)]
        tabulated-list-entries #'kittymacs-org-tasks--rows)
  (tabulated-list-init-header)
  (keymap-local-set "RET" #'kittymacs-org-tasks-visit)
  (keymap-local-set "t" #'kittymacs-org-tasks-change-state))

(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(kittymacs-org-tasks-mode . motion)))

(kittymacs-define-localleader 'kittymacs-org-tasks-mode
  "o" (cons "visit task" #'kittymacs-org-tasks-visit)
  "t" (cons "change task state" #'kittymacs-org-tasks-change-state))

(defun kittymacs-org-tasks-view (&optional blocked include-agenda)
  "Open a task view, optionally restricted to BLOCKED.
Pass INCLUDE-AGENDA for the configured agenda scope."
  (interactive)
  (let* ((files (or (if include-agenda (org-agenda-files t)
                     (kittymacs-org-tasks--files))
                    (user-error "No Org task files here")))
         (buffer (get-buffer-create (if blocked "*Blocked Org Tasks*" "*Project Org Tasks*"))))
    (with-current-buffer buffer
      (kittymacs-org-tasks-mode)
      (setq-local kittymacs-org-tasks--view-files files
                  kittymacs-org-tasks--view-blocked blocked)
      (tabulated-list-print))
    (pop-to-buffer buffer)))

(defun kittymacs-org-tasks-blocked (&optional agenda)
  "Show blocked project tasks, or use the configured AGENDA with a prefix."
  (interactive "P")
  (kittymacs-org-tasks-view t (or agenda (derived-mode-p 'org-agenda-mode))))
(defun kittymacs-org-tasks-board-move (direction)
  "Move a task on the Kanban board in DIRECTION, then refresh from its heading."
  (interactive (list (intern (completing-read "Move: " '("left" "right") nil t))))
  (require 'org-kanban)
  (let ((start (save-excursion
                 (org-beginning-of-dblock)
                 (unless (looking-at-p "[ \t]*#\\+begin:[ \t]+kanban\\_>")
                   (user-error "Point must be in an Org Kanban block"))
                 (point-marker))))
    (unwind-protect
        (unwind-protect (if (eq direction 'left) (org-kanban/prev) (org-kanban/next))
          (save-excursion
            (goto-char start)
            (org-update-dblock)))
      (set-marker start nil))))

(defvar-keymap kittymacs-org-tasks-map
  :doc "Org task views and relationship editing."
  "l" (cons "add prerequisite" #'kittymacs-org-tasks-link)
  "T" (cons "add prerequisite and trigger" #'kittymacs-org-tasks-link-and-promote)
  "p" (cons "project tasks" #'kittymacs-org-tasks-view)
  "b" (cons "blocked tasks" #'kittymacs-org-tasks-blocked))

(when (kittymacs-feature-p 'org-kanban)
  (use-package org-kanban
    :ensure t
    :commands (org-kanban/initialize-here org-kanban/prev org-kanban/next))
  (keymap-set kittymacs-org-tasks-map "k" (cons "insert board" #'org-kanban/initialize-here))
  (keymap-set kittymacs-org-tasks-map "m" (cons "move board task" #'kittymacs-org-tasks-board-move))
  (keymap-set kittymacs-org-tasks-map "R" (cons "refresh board" #'org-update-dblock)))

(when-let* ((map (alist-get 'org-mode kittymacs-localleader-alist)))
  (keymap-set map "D" (cons "task dependencies" kittymacs-org-tasks-map)))
(when-let* ((map (alist-get 'org-agenda-mode kittymacs-localleader-alist)))
  (keymap-set map "D" (cons "blocked agenda tasks" #'kittymacs-org-tasks-blocked)))
(kittymacs-refresh-localleaders)

(provide 'kittymacs-org-tasks)
;;; kittymacs-org-tasks.el ends here
