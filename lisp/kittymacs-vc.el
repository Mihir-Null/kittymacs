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
        diff-font-lock-syntax nil
        ediff-window-setup-function #'ediff-setup-windows-plain)

(with-eval-after-load 'smerge-mode
  (keymap-set smerge-mode-map "C-c v" smerge-basic-map))
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
  (git-commit-summary-max-length 50))
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

(keymap-set kittymacs-vc-map "s" (cons "status" #'kittymacs-magit-status))
(keymap-set kittymacs-vc-map "d" (cons "diff" #'magit-diff))
(keymap-set kittymacs-vc-map "l" (cons "log" #'magit-log))
(keymap-set kittymacs-vc-map "L" (cons "log this file" #'magit-log-buffer-file))
(keymap-set kittymacs-vc-map "b" (cons "blame" #'magit-blame))
(keymap-set kittymacs-vc-map "c" (cons "commit" #'magit-commit))
(keymap-set kittymacs-vc-map "f" (cons "file actions" #'magit-file-dispatch))
(keymap-set kittymacs-vc-map "F" (cons "fetch" #'magit-fetch))
(keymap-set kittymacs-vc-map "p" (cons "push" #'magit-push))
(keymap-set kittymacs-vc-map "P" (cons "pull" #'magit-pull))
(keymap-set kittymacs-vc-map "z" (cons "stash" #'magit-stash))
(keymap-set kittymacs-vc-map "r" (cons "reflog" #'magit-reflog-current))
(keymap-set kittymacs-vc-map "i" (cons "init" #'magit-init))
(keymap-set kittymacs-vc-map "C" (cons "clone" #'magit-clone))
(keymap-set kittymacs-vc-map "q" (cons "quick commit (vc)" #'vc-next-action))
(keymap-set kittymacs-vc-map "?" (cons "all commands" #'magit-dispatch))

(keymap-set kittymacs-project-map "G" (cons "Magit status" #'magit-project-status))
(defun kittymacs--git-commit-setup ()
  "Prepare a commit message buffer for writing."
  (setq fill-column 80)
  (setq-local comment-auto-fill-only-comments nil)
  (kittymacs--flyspell-text)
  ;; Meow's states are minor modes, but only `meow--switch-state' also moves
  ;; the cursor and the mode line with them.
  (when (fboundp 'meow--switch-state)
    (meow--switch-state 'insert)))

;; Never touch `git-commit-setup-hook' -- or its alias `git-commit-mode-hook'
;; -- before git-commit.el has declared them.  See the prose above.
(with-eval-after-load 'git-commit
  (add-hook 'git-commit-setup-hook #'kittymacs--git-commit-setup))
(use-package diff-hl
  :ensure t
  :hook ((prog-mode text-mode) . diff-hl-mode)
  :custom
  (diff-hl-side 'left)
  (diff-hl-update-async t)
  :config
  (unless (display-graphic-p) (diff-hl-margin-mode 1))
  (with-eval-after-load 'magit
    (add-hook 'magit-pre-refresh-hook #'diff-hl-magit-pre-refresh)
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))

(keymap-set kittymacs-toggle-map "g" (cons "git gutter" #'diff-hl-mode))
(declare-function forge-current-pullreq "forge-pullreq" (&optional demand))
(declare-function forge-get-url "forge-commands" (obj))

(defun kittymacs-pr-review ()
  "Review a pull request with pr-review.
The one at point in Forge, or else the current branch's; otherwise ask."
  (interactive)
  (if-let* ((pullreq (and (require 'forge nil t)
                          (magit-toplevel)
                          (forge-current-pullreq))))
      (pr-review (forge-get-url pullreq))
    (call-interactively #'pr-review)))

(when (kittymacs-feature-p 'pull-requests)
  (use-package forge
    :ensure t
    :after magit
    :custom
    (forge-database-file (expand-file-name "forge-database.sqlite" kittymacs-cache-dir)))

  (use-package pr-review
    :ensure t
    :defer t
    :custom
    (pr-review-ghub-auth-name 'forge))

  (use-package orgit-forge
    :ensure t
    :defer t)

  (keymap-set kittymacs-vc-map "g" (cons "forge menu" #'forge-dispatch))
  (keymap-set kittymacs-vc-map "R" (cons "review a pull request" #'kittymacs-pr-review))
  (keymap-set kittymacs-vc-map "N" (cons "notifications" #'pr-review-notification)))
(declare-function pr-review-context-comment "pr-review-action" ())
(declare-function pr-review-context-action "pr-review-action" ())
(declare-function pr-review-context-edit "pr-review-action" ())
(declare-function pr-review-refresh "pr-review" (&optional clear-pending-reviews))
(declare-function pr-review-view-file "pr-review-action" (head-or-base filepath &optional line))
(declare-function pr-review-goto-file "pr-review-action" (filepath))
(declare-function pr-review-ediff-file "pr-review-action" (filepath))
(declare-function pr-review-open-in-external-browser "pr-review-action" ())

(when (kittymacs-feature-p 'pull-requests)
  (with-eval-after-load 'meow
    (add-to-list 'meow-mode-state-list '(pr-review-mode . motion))
    (add-to-list 'meow-mode-state-list '(pr-review-listview-mode . motion))
    (add-to-list 'meow-mode-state-list '(pr-review-input-mode . insert)))

  (kittymacs-define-localleader 'pr-review-mode
    "c" (cons "comment or reply" #'pr-review-context-comment)
    "s" (cons "resolve or submit" #'pr-review-context-action)
    "e" (cons "edit" #'pr-review-context-edit)
    "g" (cons "refresh" #'pr-review-refresh)
    "v" (cons "view whole file" #'pr-review-view-file)
    "f" (cons "go to file" #'pr-review-goto-file)
    "d" (cons "Ediff file" #'pr-review-ediff-file)
    "o" (cons "open in browser" #'pr-review-open-in-external-browser)))
(when (kittymacs-feature-p 'git-extras)
  (use-package git-modes
    :ensure t
    :defer t)

  (use-package magit-todos
    :ensure t
    :after magit
    :config
    (magit-todos-mode 1))

  (keymap-set kittymacs-vc-map "t" (cons "TODOs" #'magit-todos-list)))
(when (kittymacs-feature-p 'git-links)
  (use-package git-link
    :ensure t
    :defer t
    :custom
    (git-link-use-commit t))

  (use-package orgit
    :ensure t
    :defer t)

  (keymap-set kittymacs-vc-map "o" (cons "copy link to line" #'git-link)))
(when (kittymacs-feature-p 'structural-diffs)
  (use-package difftastic
    :ensure t
    :defer t)

  (with-eval-after-load 'magit
    (difftastic-bindings-mode 1))

  (with-eval-after-load 'meow
    (add-to-list 'meow-mode-state-list '(difftastic-mode . motion)))

  (keymap-set kittymacs-vc-map "D" (cons "diff file by syntax" #'difftastic-magit-diff-buffer-file)))
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
  "?" (cons "all commands" #'magit-dispatch)
  "L" (and (kittymacs-feature-p 'git-links) (cons "store Org link" #'orgit-store-link)))

(provide 'kittymacs-vc)
;;; kittymacs-vc.el ends here
