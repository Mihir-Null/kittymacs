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
  (keymap-set smerge-mode-map "C-c v" smerge-basic-map)
  (kittymacs-define-minor-localleader 'smerge-mode "C" "conflicts" smerge-basic-map))
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
(declare-function diff-review-magit-mode "diff-review-magit" (&optional arg))
(declare-function diff-review-find-file "diff-review" (file &optional root base head))
(declare-function magit-gitdir "magit-git" (&optional directory common))
(defvar diff-review-file-command-map)

(declare-function forge-current-pullreq "forge-commands" ())
(declare-function eieio-oref "eieio-core" (obj slot))
(declare-function diff-review-branch "diff-review" (branch))

(defun kittymacs--forge-pullreq-number ()
  "The number of the pull request Forge has at point, or the current branch's."
  (when-let* (((require 'forge nil t))
              ((magit-toplevel))
              (pullreq (forge-current-pullreq)))
    (eieio-oref pullreq 'number)))

(defun kittymacs-diff-review-pull-request (number)
  "Fetch pull request NUMBER into the branch pr-NUMBER, and review it.
Interactively, the pull request at point in Forge, or the current
branch's; otherwise ask.  The review stays in this clone."
  (interactive (list (or (kittymacs--forge-pullreq-number)
                         (read-number "Pull request: "))))
  (let* ((default-directory (or (locate-dominating-file default-directory ".git")
                                (user-error "Not in a Git repository")))
         (branch (format "pr-%d" number)))
    (with-temp-buffer
      (unless (eq 0 (process-file "git" nil t nil "fetch" "origin"
                                  (format "+pull/%d/head:%s" number branch)))
        (user-error "Fetching pull request %d failed: %s" number (string-trim (buffer-string)))))
    (diff-review-branch branch)))

(defun kittymacs-diff-review-worktree ()
  "Review this worktree's uncommitted changes against its base.
The review file is review/NAME.worktree.json under the Git directory every
worktree shares, NAME being this worktree's directory, so it never meets a
branch's review/BRANCH.json."
  (interactive)
  (require 'magit)
  (let ((root (or (magit-toplevel) (user-error "Not in a Git repository"))))
    (diff-review-find-file
     (expand-file-name (format "review/%s.worktree.json"
                               (file-name-nondirectory (directory-file-name root)))
                       (magit-gitdir root t))
     root)))

(when (kittymacs-feature-p 'branch-review)
  (condition-case err
      (use-package diff-review
        :vc (:url "https://github.com/xiaoxinghu/diff-review"
             :rev "49cba292bb933e2a1a90f61145e29311636544ae")
        :defer t)
    (error
     (display-warning 'kittymacs
                      (format "diff-review was not installed: %s
Check that `git clone https://github.com/xiaoxinghu/diff-review' works from a terminal, and which git Emacs runs: %s"
                              (error-message-string err) (executable-find "git"))
                      :warning)))

  (when (locate-library "diff-review")
    (with-eval-after-load 'magit
      (diff-review-magit-mode 1))
    (with-eval-after-load 'diff-review
      (kittymacs-define-minor-localleader 'diff-review-file-mode "R" "review"
        diff-review-file-command-map))
    (keymap-set kittymacs-vc-map "v" (cons "review a branch" #'diff-review-branch))
    (keymap-set kittymacs-vc-map "V" (cons "review uncommitted changes" #'kittymacs-diff-review-worktree))
    (keymap-set kittymacs-vc-map "u" (cons "review a pull request here" #'kittymacs-diff-review-pull-request))))
(declare-function diff-review--review-buffer "diff-review" ())
(declare-function diff-review--git-at "diff-review" (directory &rest args))
(defvar diff-review--root)
(defvar diff-review--file-path)
(defvar diff-review--blob)

(defun kittymacs-diff-review--here (directory path)
  "PATH, which git printed on DIRECTORY's machine, as this Emacs reaches it."
  (let ((prefix (file-remote-p directory)))
    (if (and prefix (stringp path) (file-name-absolute-p path) (not (file-remote-p path)))
        (concat prefix path)
      path)))

(defun kittymacs-diff-review--there (arg)
  "ARG as git takes it: a remote file name without its TRAMP prefix."
  (if (and (stringp arg) (file-remote-p arg)) (file-local-name arg) arg))

(defun kittymacs-diff-review--toplevel (toplevel directory)
  "Call TOPLEVEL on DIRECTORY, and name its answer from here."
  (kittymacs-diff-review--here directory (funcall toplevel directory)))

(defun kittymacs-diff-review--common-dir (common-dir root)
  "Call COMMON-DIR on ROOT, and name its answer from here."
  (kittymacs-diff-review--here root (funcall common-dir root)))

(defun kittymacs-diff-review--worktrees (worktrees root)
  "Call WORKTREES on ROOT, and name each worktree's path from here."
  (mapcar (lambda (worktree)
            (plist-put worktree :path (kittymacs-diff-review--here root (plist-get worktree :path))))
          (funcall worktrees root)))

(defun kittymacs-diff-review--git-at (git-at directory &rest args)
  "Call GIT-AT in DIRECTORY with ARGS, each file name as git takes it."
  (apply git-at directory (mapcar #'kittymacs-diff-review--there args)))

(defun kittymacs-diff-review--git-maybe (args)
  "ARGS, each file name as git takes it."
  (mapcar #'kittymacs-diff-review--there args))

(defun kittymacs-diff-review--buffer-blob (buffer-blob)
  "Call BUFFER-BLOB, or for a remote file hash its text with git there."
  (let ((root (with-current-buffer (or (diff-review--review-buffer) (current-buffer))
                diff-review--root)))
    (if (or diff-review--blob (not (and root (file-remote-p root))))
        (funcall buffer-blob)
      (let ((default-directory root)
            (temp (make-nearby-temp-file "diff-review-blob")))
        (unwind-protect
            (progn
              (save-restriction
                (widen)
                (write-region (point-min) (point-max) temp nil 'silent))
              (diff-review--git-at root "hash-object" "-w" "--path" diff-review--file-path temp))
          (delete-file temp))))))

(defcustom kittymacs-diff-review-tramp-method "ssh"
  "The TRAMP method `kittymacs-diff-review-at' reaches another machine with."
  :type 'string
  :group 'kittymacs)

(defun kittymacs-diff-review--this-host-p (host)
  "Whether HOST names this machine, compared by the short name."
  (let ((short (lambda (name) (car (split-string name "\\.")))))
    (equal (funcall short host) (funcall short (system-name)))))

(defun kittymacs-diff-review--path (host directory)
  "DIRECTORY as this Emacs reaches it.
DIRECTORY itself when HOST is empty or this machine, or DIRECTORY exists
here; otherwise a TRAMP path on HOST."
  (if (or (null host) (string-empty-p host) (kittymacs-diff-review--this-host-p host)
          (file-directory-p directory))
      directory
    (format "/%s:%s:%s" kittymacs-diff-review-tramp-method host directory)))

(defun kittymacs-diff-review-at (host directory branch)
  "Review BRANCH in diff-review, from DIRECTORY on HOST.
Over TRAMP when HOST is another machine, so the review file stays in
that machine's Git directory; locally when HOST is empty or this
machine, or DIRECTORY exists here."
  (interactive (list (read-string "Host: " (system-name))
                     (read-string "Directory on that host: ")
                     (read-string "Branch: ")))
  (unless (fboundp 'diff-review-branch)
    (user-error "diff-review is not installed: turn on the branch-review feature"))
  (let ((default-directory (file-name-as-directory (kittymacs-diff-review--path host directory))))
    (diff-review-branch branch)))

(when (kittymacs-feature-p 'branch-review)
  (with-eval-after-load 'diff-review
    (advice-add 'diff-review--toplevel :around #'kittymacs-diff-review--toplevel)
    (advice-add 'diff-review--common-dir :around #'kittymacs-diff-review--common-dir)
    (advice-add 'diff-review--worktrees :around #'kittymacs-diff-review--worktrees)
    (advice-add 'diff-review--git-at :around #'kittymacs-diff-review--git-at)
    (advice-add 'diff-review--git-maybe :filter-args #'kittymacs-diff-review--git-maybe)
    (advice-add 'diff-review--buffer-blob :around #'kittymacs-diff-review--buffer-blob)))
(when (kittymacs-feature-p 'branch-review)
  (with-eval-after-load 'meow
    (add-to-list 'meow-mode-state-list '(diff-review-mode . motion))
    (add-to-list 'meow-mode-state-list '(diff-review-sidebar-mode . motion))))
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
  "L" (and (kittymacs-feature-p 'git-links) (cons "store Org link" #'orgit-store-link))
  "v" (and (kittymacs-feature-p 'branch-review) (locate-library "diff-review")
           (cons "review commits" #'diff-review-magit-commits)))

(with-eval-after-load 'magit-blame
  (kittymacs-define-minor-localleader 'magit-blame-mode "B" "blame"
    "n" (cons "next chunk" #'magit-blame-next-chunk)
    "p" (cons "previous chunk" #'magit-blame-previous-chunk)
    "N" (cons "same commit's next" #'magit-blame-next-chunk-same-commit)
    "P" (cons "same commit's previous" #'magit-blame-previous-chunk-same-commit)
    "s" (cons "show commit" #'magit-show-commit)
    "b" (cons "blame further back" #'magit-blame-addition)
    "c" (cons "cycle style" #'magit-blame-cycle-style)
    "q" (cons "stop blaming" #'magit-blame-quit)))

(provide 'kittymacs-vc)
;;; kittymacs-vc.el ends here
