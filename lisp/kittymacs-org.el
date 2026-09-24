;;; kittymacs-org.el --- Notes, tasks and the agenda -*- lexical-binding: t; -*-
;; Generated from literate/70-org.org; edit the Org source, then tangle.

;; Defaults distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-platform)
(require 'kittymacs-defaults)
(require 'kittymacs-leader)
(make-directory kittymacs-org-directory t)
(setopt org-directory kittymacs-org-directory
        org-default-notes-file (expand-file-name "inbox.org" kittymacs-org-directory)
        org-agenda-files (list kittymacs-org-directory)
        org-archive-location (expand-file-name "archive.org::datetree/" kittymacs-org-directory)
        org-id-locations-file (expand-file-name "org-id-locations" kittymacs-cache-dir)
        org-id-method 'ts
        org-id-link-to-org-use-id 'create-if-interactive)

(setopt org-capture-templates
        `(("t" "Inbox TODO" entry (file ,org-default-notes-file) "* TODO %?\n  %U\n")
          ("n" "Inbox note" entry (file ,org-default-notes-file) "* %?\n  %U\n")))

(defun kittymacs-org-inbox ()
  "Open the Org inbox file."
  (interactive)
  (find-file org-default-notes-file))
(setopt org-hide-emphasis-markers t
        org-hide-leading-stars t
        org-startup-indented t
        org-adapt-indentation t
        org-pretty-entities t
        org-ellipsis "…"
        org-tags-column 0
        org-auto-align-tags nil
        org-cycle-separator-lines 0
        org-fontify-quote-and-verse-blocks t
        org-image-actual-width 500
        org-startup-folded 'nofold
        org-catch-invisible-edits 'show-and-error
        org-insert-heading-respect-content t
        org-M-RET-may-split-line '((default . nil))
        org-yank-adjusted-subtrees t
        org-return-follows-link t
        org-special-ctrl-a/e t
        org-read-date-prefer-future 'time
        org-list-allow-alphabetical t
        org-list-demote-modify-bullet '(("+" . "-") ("-" . "+") ("*" . "+"))
        org-footnote-section nil
        org-footnote-auto-adjust t
        org-imenu-depth 8
        org-src-fontify-natively t
        org-src-tab-acts-natively t
        org-src-preserve-indentation t
        org-src-window-setup 'other-window
        org-confirm-babel-evaluate t)

(with-eval-after-load 'org
  (add-to-list 'org-modules 'org-habit t)
  (add-to-list 'org-modules 'org-tempo t)
  (defun kittymacs--org-no-angle-pairs ()
    "Do not auto-pair < in Org: it starts structure templates like <s."
    (setq-local electric-pair-inhibit-predicate
                (let ((inherited electric-pair-inhibit-predicate))
                  (lambda (char) (or (char-equal char ?<) (funcall inherited char))))))
  (add-hook 'org-mode-hook #'kittymacs--org-no-angle-pairs))
(setopt org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w@/!)" "|" "DONE(d)" "CANCELED(c@)"))
        org-use-fast-todo-selection 'expert
        org-enforce-todo-dependencies t
        org-enforce-todo-checkbox-dependencies t
        org-log-done 'time
        org-log-into-drawer t
        org-log-redeadline nil
        org-log-reschedule nil)

(setopt org-agenda-start-with-log-mode '(closed clock)
        org-agenda-tags-column 0
        org-agenda-block-separator " "
        org-agenda-skip-scheduled-if-done t
        org-agenda-skip-timestamp-if-done t
        org-agenda-todo-ignore-scheduled 'future
        org-agenda-todo-ignore-deadlines 'far
        org-agenda-time-grid '((daily today require-timed)
                               (800 1000 1200 1400 1600 1800 2000)
                               " ┄┄┄┄┄ " "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄")
        org-agenda-current-time-string "–––––––––––––– Now"
        org-agenda-prefix-format '((agenda . " %-18c%?-10t ")
                                   (todo . " ")
                                   (tags . " ")
                                   (search . " %i %-12:c"))
        calendar-week-start-day 1
        org-agenda-custom-commands
        '(("d" "Dashboard"
           ((agenda "" ((org-agenda-span 'day)))
            (tags-todo "DEADLINE<\"<+5d>\"" ((org-agenda-overriding-header "Due soon")))
            (todo "NEXT" ((org-agenda-overriding-header "Next actions")))))
          ("n" "Next actions" ((todo "NEXT")))))

(setopt org-refile-targets '((nil :maxlevel . 9) (org-agenda-files :maxlevel . 8))
        org-refile-use-cache t
        org-refile-use-outline-path 'file
        org-outline-path-complete-in-steps nil
        org-refile-allow-creating-parent-nodes 'confirm)

(defun kittymacs-org-dashboard ()
  "Open the agenda dashboard: today, due soon and next actions."
  (interactive)
  (org-agenda nil "d"))

(defun kittymacs-org-archive-done ()
  "Archive every DONE or CANCELED entry in this file."
  (interactive)
  (dolist (match '("/DONE" "/CANCELED"))
    (org-map-entries (lambda ()
                       (org-archive-subtree)
                       (setq org-map-continue-from (outline-previous-heading)))
                     match 'file)))

(defun kittymacs--org-agenda-refresh ()
  "Refresh an open agenda after a capture."
  (when-let* ((buffer (get-buffer "*Org Agenda*")))
    (with-current-buffer buffer (org-agenda-redo))))
(add-hook 'org-capture-after-finalize-hook #'kittymacs--org-agenda-refresh)
(setopt org-export-with-smart-quotes t
        org-export-with-broken-links t
        org-html-postamble nil
        org-odt-preferred-output-format "docx"
        org-table-export-default-format "orgtbl-to-csv"
        org-file-apps '(("\\.docx\\'" . default)
                        ("\\.x?html?\\'" . default)
                        ("\\.pdf\\'" . emacs)
                        (auto-mode . emacs)))

(use-package org-contrib
  :ensure t
  :after org
  :config
  (require 'ox-extra)
  (ox-extras-activate '(ignore-headlines)))

(defun kittymacs-org-block-wrap ()
  "Wrap the region, or insert at point, an Org block of a chosen type."
  (interactive)
  (let* ((choices '(("s" . "src") ("e" . "example") ("q" . "quote") ("c" . "comment")
                    ("E" . "src emacs-lisp") ("v" . "verse") ("C" . "center")))
         (key (key-description
               (vector (read-key (concat (propertize "Block type: " 'face 'minibuffer-prompt)
                                         (mapconcat (lambda (choice)
                                                      (concat (propertize (car choice) 'face 'font-lock-type-face)
                                                              ": " (cdr choice)))
                                                    choices ", "))))))
         (type (cdr (assoc key choices))))
    (when type
      (if (region-active-p)
          (let ((start (region-beginning)) (end (region-end)))
            (goto-char end) (insert "#+end_" (car (split-string type)) "\n")
            (goto-char start) (insert "#+begin_" type "\n"))
        (insert "#+begin_" type "\n")
        (save-excursion (insert "#+end_" (car (split-string type))))))))
(use-package org-modern
  :ensure t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda)))

(use-package org-appear
  :ensure t
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t)
  (org-appear-autoentities t))
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(org-agenda-mode . motion)))
(with-eval-after-load 'org
  (modify-syntax-entry ?@ "_" org-mode-syntax-table))

(kittymacs-define-localleader 'org-mode
  "a" (cons "agenda" #'kittymacs-org-dashboard)
  "c" (cons "capture" #'org-capture)
  "t" (cons "todo state" #'org-todo)
  "s" (cons "schedule" #'org-schedule)
  "d" (cons "deadline" #'org-deadline)
  "T" (cons "tags" #'org-set-tags-command)
  "," (cons "priority" #'org-priority)
  "r" (cons "refile" #'org-refile)
  "A" (cons "archive subtree" #'org-archive-subtree)
  "n" (cons "narrow / widen" #'org-toggle-narrow-to-subtree)
  "j" (cons "jump to heading" #'consult-org-heading)
  "l" (cons "insert link" #'org-insert-link)
  "L" (cons "store link" #'org-store-link)
  "o" (cons "open at point" #'org-open-at-point)
  "x" (cons "toggle checkbox" #'org-toggle-checkbox)
  "p" (cons "set property" #'org-set-property)
  "." (cons "time stamp" #'org-time-stamp)
  "b" (cons "run source block" #'org-babel-execute-src-block)
  "'" (cons "edit source block" #'org-edit-special)
  "w" (cons "wrap in block" #'kittymacs-org-block-wrap)
  "e" (cons "export" #'org-export-dispatch)
  "i" (cons "insert heading" #'org-insert-heading-respect-content)
  "?" (cons "menu" #'casual-org-tmenu))

(kittymacs-define-localleader 'org-agenda-mode
  "t" (cons "todo state" #'org-agenda-todo)
  "s" (cons "schedule" #'org-agenda-schedule)
  "d" (cons "deadline" #'org-agenda-deadline)
  "r" (cons "refile" #'org-agenda-refile)
  "g" (cons "refresh" #'org-agenda-redo)
  "v" (cons "view" #'org-agenda-view-mode-dispatch)
  "f" (cons "filter by tag" #'org-agenda-filter-by-tag)
  "q" (cons "quit" #'org-agenda-quit)
  "?" (cons "menu" #'casual-agenda-tmenu))

(provide 'kittymacs-org)
;;; kittymacs-org.el ends here
