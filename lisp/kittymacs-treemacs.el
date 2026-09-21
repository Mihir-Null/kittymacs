;;; kittymacs-treemacs.el --- The project tree -*- lexical-binding: t; -*-
;; Generated from literate/65-treemacs.org; edit the Org source, then tangle.

;;; Commentary:
;; Treemacs as a project-scoped sidebar: one project at a time, following the
;; current buffer, with Git status, Nerd Font icons, per-workspace scoping and
;; Magit-aware refreshes.

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)
(require 'kittymacs-ui)
(use-package treemacs
  :ensure t
  :defer t
  :commands (treemacs treemacs-select-window treemacs-find-file
             treemacs-add-and-display-current-project-exclusively)
  :custom
  ;; State, not cache: the workspace layout is worth keeping between sessions.
  (treemacs-persist-file (expand-file-name "treemacs/persist" kittymacs-etc-dir))
  (treemacs-last-error-persist-file
   (expand-file-name "treemacs/persist-at-last-error" kittymacs-cache-dir))
  (treemacs-width 35)
  (treemacs-width-is-initially-locked t)
  (treemacs-position 'left)
  (treemacs-display-in-side-window t)
  (treemacs-is-never-other-window t)
  (treemacs-follow-after-init t)
  (treemacs-file-follow-delay 0.2)
  (treemacs-project-follow-cleanup t)
  (treemacs-collapse-dirs (if (executable-find "python3") 3 0))
  (treemacs-indent-guide-style 'line)
  (treemacs-show-hidden-files t)
  (treemacs-hide-dot-git-directory t)
  (treemacs-silent-refresh t)
  (treemacs-silent-filewatch t)
  (treemacs-sorting 'alphabetic-asc)
  (treemacs-eldoc-display 'simple)
  (treemacs-no-png-images (not (display-graphic-p)))
  :config
  ;; Watch the filesystem, mark the current file in the fringe, draw the
  ;; indent guides, and show the project you are in and only that project.
  (treemacs-filewatch-mode 1)
  (treemacs-follow-mode 1)
  (treemacs-project-follow-mode 1)
  (treemacs-indent-guide-mode 1)
  (treemacs-fringe-indicator-mode 'always)

  ;; Git status colours.  The extended variants colour directories as well as
  ;; files and parse the status asynchronously in Python; `deferred' renders
  ;; the tree first and colours it a moment later, which feels quicker on a
  ;; large repository.  Without Python 3, the simple variant colours files.
  (pcase (cons (and (executable-find "git") t)
               (and treemacs-python-executable t))
    ('(t . t) (treemacs-git-mode 'deferred))
    ('(t . nil) (treemacs-git-mode 'simple)))
  (when (fboundp 'treemacs-hide-gitignored-files-mode)
    (treemacs-hide-gitignored-files-mode nil))

  ;; The sidebar is a panel that serves the buffer beside it; dimming it as
  ;; an "inactive window" only makes the tree harder to read.
  (with-eval-after-load 'dimmer
    (add-to-list 'dimmer-buffer-exclusion-regexps "\\*Treemacs")))
(use-package treemacs-nerd-icons
  :ensure t
  :after treemacs
  :demand t
  :config
  (when (kittymacs-icons-available-p)
    (treemacs-load-theme "nerd-icons")))

(use-package treemacs-tab-bar
  :ensure t
  :after treemacs
  :demand t
  :config
  (treemacs-set-scope-type 'Tabs))

(use-package treemacs-magit
  :ensure t
  :after (treemacs magit)
  :demand t)
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(treemacs-mode . motion)))

(kittymacs-define-localleader 'treemacs-mode
  "f" (cons "new file" #'treemacs-create-file)
  "d" (cons "new directory" #'treemacs-create-dir)
  "r" (cons "rename" #'treemacs-rename-file)
  "D" (cons "delete" #'treemacs-delete-file)
  "y" (cons "copy" #'treemacs-copy-file)
  "m" (cons "move" #'treemacs-move-file)
  "p" (cons "copy path" #'treemacs-copy-absolute-path-at-point)
  "P" (cons "copy relative path" #'treemacs-copy-relative-path-at-point)
  "o" (cons "open elsewhere" #'treemacs-visit-node-ace)
  "x" (cons "open outside Emacs" #'treemacs-visit-node-in-external-application)
  "g" (cons "refresh" #'treemacs-refresh)
  "w" (cons "set width" #'treemacs-set-width)
  "h" (cons "show hidden files" #'treemacs-toggle-show-dotfiles)
  "b" (cons "bookmark" #'treemacs-add-bookmark)
  "!" (cons "shell command here" #'treemacs-run-shell-command-for-current-node)
  "a" (cons "add project" #'treemacs-add-project-to-workspace)
  "k" (cons "remove project" #'treemacs-remove-project-from-workspace)
  "u" (cons "parent directory" #'treemacs-root-up)
  "q" (cons "close the tree" #'treemacs-quit)
  "?" (cons "menu" #'treemacs-common-helpful-hydra))

(provide 'kittymacs-treemacs)
;;; kittymacs-treemacs.el ends here
