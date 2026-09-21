;;; kittymacs-vc.el --- Magit and version control -*- lexical-binding: t; -*-
;; Generated from literate/66-vc.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-leader)
(require 'kittymacs-platform)

(declare-function meow--switch-state "meow-util" (state &optional no-hook))
(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function magit-status-setup-buffer "magit-status" (&optional directory))
(declare-function project-root "project" (project))

(setopt vc-follow-symlinks t
        vc-handled-backends '(Git)
        vc-log-short-style '(file)
        vc-git-diff-switches "--patch-with-stat"
        vc-git-print-log-follow t
        vc-git-revision-complete-only-branches t
        vc-annotate-display-mode 'scale
        diff-refine 'navigation
        diff-font-lock-prettify t
        diff-font-lock-syntax 'hunk-also
        ediff-window-setup-function #'ediff-setup-windows-plain)

(with-eval-after-load 'smerge-mode
  (setopt smerge-command-prefix (kbd "C-c v")))
(defun kittymacs-magit-display-buffer (buffer)
  "Show Magit BUFFER in a frame under frames-only mode, otherwise traditionally."
  (if (and (bound-and-true-p frames-only-mode) (display-graphic-p))
      (display-buffer buffer
                      '((display-buffer-reuse-window
                         display-buffer-pop-up-frame
                         display-buffer-use-some-window)
                        (reusable-frames . t)))
    (magit-display-buffer-traditional buffer)))

(use-package magit
  :ensure t
  :commands (magit-status magit-log magit-diff magit-commit magit-blame magit-dispatch magit-file-dispatch)
  :custom
  (magit-display-buffer-function #'kittymacs-magit-display-buffer)
  (magit-diff-refine-hunk t)
  (magit-log-margin '(t "%Y-%m-%d %H:%M " magit-log-margin-width nil 18))
  (magit-section-initial-visibility-alist '((stashes . hide) (untracked . hide) (unpushed . hide)))
  (magit-no-message '("Turning on magit-auto-revert-mode..."))
  (git-commit-summary-max-length 50)
  :config
  (add-hook 'after-save-hook #'magit-after-save-refresh-status t))
(defun kittymacs--repository-root (directory)
  "Return the top level of the Git repository containing DIRECTORY, or nil."
  (when (and directory (file-directory-p directory))
    (let ((default-directory directory))
      (magit-toplevel))))

(defun kittymacs-magit-status ()
  "Open Magit for this buffer's repository, or for the current project.
Falls back to `magit-status', which asks, when neither is a repository."
  (interactive)
  (require 'magit)
  (if-let* ((root (or (kittymacs--repository-root default-directory)
                      (and (project-current)
                           (kittymacs--repository-root
                            (project-root (project-current)))))))
      (magit-status-setup-buffer root)
    (call-interactively #'magit-status)))
(defun kittymacs-git-commit-setup ()
  "Prepare a commit message buffer for writing."
  (setq fill-column 80)
  (setq-local comment-auto-fill-only-comments nil)
  (kittymacs-flyspell-text)
  ;; Meow's states are minor modes, but only `meow--switch-state' also moves
  ;; the cursor and the mode line with them.
  (when (fboundp 'meow--switch-state)
    (meow--switch-state 'insert)))

;; Never touch `git-commit-setup-hook' -- or its alias `git-commit-mode-hook'
;; -- before git-commit.el has declared them.  See the prose above.
(with-eval-after-load 'git-commit
  (add-hook 'git-commit-setup-hook #'kittymacs-git-commit-setup))
(use-package diff-hl
  :ensure t
  :hook ((prog-mode text-mode) . diff-hl-mode)
  :custom
  (diff-hl-side 'left)
  (diff-hl-update-async t)
  :config
  (diff-hl-flydiff-mode 1)
  (unless (display-graphic-p) (diff-hl-margin-mode 1))
  (with-eval-after-load 'magit
    (add-hook 'magit-pre-refresh-hook #'diff-hl-magit-pre-refresh)
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(magit-mode . motion)))

(kittymacs-define-localleader 'magit-mode
  "s" (cons "stage" #'magit-stage)
  "u" (cons "unstage" #'magit-unstage)
  "c" (cons "commit" #'magit-commit)
  "p" (cons "push" #'magit-push)
  "F" (cons "pull" #'magit-pull)
  "f" (cons "fetch" #'magit-fetch)
  "b" (cons "branch" #'magit-branch)
  "m" (cons "merge" #'magit-merge)
  "r" (cons "rebase" #'magit-rebase)
  "z" (cons "stash" #'magit-stash)
  "l" (cons "log" #'magit-log)
  "d" (cons "diff" #'magit-diff)
  "x" (cons "discard" #'magit-discard)
  "g" (cons "refresh" #'magit-refresh)
  "?" (cons "all commands" #'magit-dispatch))

(provide 'kittymacs-vc)
;;; kittymacs-vc.el ends here
