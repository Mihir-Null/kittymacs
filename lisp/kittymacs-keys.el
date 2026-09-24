;;; kittymacs-keys.el --- The leader tree -*- lexical-binding: t; -*-
;; Generated from literate/42-keys.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)
(setopt which-key-idle-delay 0.45
        which-key-idle-secondary-delay 0.05
        which-key-show-early-on-C-h t
        which-key-side-window-location 'top
        which-key-side-window-max-height 0.5)
(which-key-mode 1)
(defun kittymacs-new-buffer-frame ()
  "Create an empty buffer in a new frame."
  (interactive)
  (kittymacs-new-buffer t))

(defvar-keymap kittymacs-buffer-map
  :doc "Buffers."
  "b" (cons "switch" #'consult-buffer)
  "B" (cons "switch in other frame" #'consult-buffer-other-frame)
  "p" (cons "project buffer" #'consult-project-buffer)
  "k" (cons "kill this" #'kill-current-buffer)
  "K" (cons "kill some" #'kill-buffer)
  "n" (cons "new" #'kittymacs-new-buffer)
  "N" (cons "new in frame" #'kittymacs-new-buffer-frame)
  "s" (cons "save" #'save-buffer)
  "r" (cons "revert" #'revert-buffer-quick)
  "R" (cons "rename file" #'rename-visited-file)
  "i" (cons "imenu" #'consult-imenu)
  "j" (cons "jump to heading" #'kittymacs-jump-in-buffer)
  "m" (cons "mark ring" #'consult-mark)
  "M" (cons "global mark ring" #'consult-global-mark)
  "a" (cons "ibuffer" #'ibuffer)
  "x" (cons "scratch" #'scratch-buffer)
  "u" (cons "undo tree" #'vundo)
  "[" (cons "previous" #'previous-buffer)
  "]" (cons "next" #'next-buffer))

(defvar-keymap kittymacs-file-map
  :doc "Files."
  "f" (cons "find" #'find-file)
  "F" (cons "find in other frame" #'find-file-other-frame)
  "s" (cons "save" #'save-buffer)
  "S" (cons "save all" #'save-some-buffers)
  "r" (cons "recent" #'consult-recent-file)
  "b" (cons "bookmarks" #'consult-bookmark)
  "B" (cons "set bookmark" #'bookmark-set)
  "d" (cons "directory" #'dired-jump)
  "D" (cons "switch directory" #'consult-dir)
  "R" (cons "rename" #'rename-visited-file)
  "y" (cons "copy file name" #'kittymacs-copy-file-name)
  "t" (cons "reveal in file tree" #'treemacs-find-file)
  "o" (cons "show in file manager" #'kittymacs-reveal-in-file-manager))

(defvar-keymap kittymacs-search-map
  :doc "Search."
  "s" (cons "lines" #'consult-line)
  "S" (cons "lines in all buffers" #'consult-line-multi)
  "." (cons "symbol at point" #'kittymacs-search-symbol-at-point)
  "d" (cons "ripgrep" #'consult-ripgrep)
  "D" (cons "ripgrep buffer" #'deadgrep)
  "r" (cons "replace (visual)" #'vr/query-replace)
  "c" (cons "edit occurrences" #'iedit-mode)
  "i" (cons "imenu" #'consult-imenu)
  "o" (cons "outline" #'consult-outline)
  "h" (cons "org heading" #'consult-org-heading)
  "a" (cons "org agenda" #'consult-org-agenda)
  "k" (cons "kill ring" #'consult-yank-pop)
  "m" (cons "mark ring" #'consult-mark)
  "t" (cons "todo keywords" #'hl-todo-occur)
  "p" (cons "spelling" #'consult-flyspell)
  "l" (cons "last completion" #'vertico-repeat))
(defvar-keymap kittymacs-project-map
  :doc "Project commands: Emacs's `project-prefix-map' plus a few more."
  :parent project-prefix-map
  "p" (cons "open in a workspace" #'tabspaces-open-or-create-project-and-workspace)
  "b" (cons "project buffer" #'consult-project-buffer)
  "m" (cons "bookmark" #'consult-bookmark)
  "G" (cons "Magit status" #'magit-project-status)
  "t" (cons "projects directory" #'kittymacs-projects-directory)
  "R" (cons "remember projects under" #'project-remember-projects-under)
  "C" (cons "recompile" #'recompile))

(defvar-keymap kittymacs-jump-map
  :doc "Jump with on-screen hints."
  "j" (cons "to character" #'avy-goto-char-timer)
  "l" (cons "to line" #'avy-goto-line)
  "w" (cons "to word" #'avy-goto-word-1)
  "s" (cons "to symbol" #'avy-goto-symbol-1)
  "e" (cons "to end of line" #'avy-goto-end-of-line)
  "i" (cons "in this line" #'avy-goto-char-in-line))

(defvar-keymap kittymacs-vc-map
  :doc "Version control."
  "s" (cons "status" #'kittymacs-magit-status)
  "d" (cons "diff" #'magit-diff)
  "l" (cons "log" #'magit-log)
  "L" (cons "log this file" #'magit-log-buffer-file)
  "b" (cons "blame" #'magit-blame)
  "c" (cons "commit" #'magit-commit)
  "f" (cons "file actions" #'magit-file-dispatch)
  "F" (cons "fetch" #'magit-fetch)
  "p" (cons "push" #'magit-push)
  "P" (cons "pull" #'magit-pull)
  "z" (cons "stash" #'magit-stash)
  "r" (cons "reflog" #'magit-reflog-current)
  "i" (cons "init" #'magit-init)
  "C" (cons "clone" #'magit-clone)
  "q" (cons "quick commit (vc)" #'vc-next-action)
  "?" (cons "all commands" #'magit-dispatch))

(defvar-keymap kittymacs-window-map
  :doc "Windows and frames."
  "n" (cons "new frame" #'make-frame-command)
  "k" (cons "close frame" #'delete-frame)
  "K" (cons "close other frames" #'delete-other-frames)
  "w" (cons "jump to window" #'ace-window)
  "o" (cons "other window" #'other-window)
  "s" (cons "swap windows" #'ace-swap-window)
  "d" (cons "close window" #'delete-window)
  "m" (cons "only this window" #'delete-other-windows)
  "h" (cons "split below" #'split-window-below)
  "v" (cons "split right" #'split-window-right)
  "=" (cons "balance" #'balance-windows)
  "t" (cons "window to frame" #'tear-off-window)
  "u" (cons "undo layout" #'winner-undo)
  "U" (cons "redo layout" #'winner-redo)
  "f" (cons "fullscreen" #'toggle-frame-fullscreen)
  "M" (cons "maximize" #'toggle-frame-maximized))

(defvar-keymap kittymacs-workspace-map
  :doc "Workspaces (tabs with their own buffers)."
  "TAB" (cons "switch" #'kittymacs-tab-dwim)
  "s" (cons "switch or create" #'tabspaces-switch-or-create-workspace)
  "o" (cons "open project" #'tabspaces-open-or-create-project-and-workspace)
  "n" (cons "new tab" #'tab-new)
  "b" (cons "workspace buffer" #'tabspaces-switch-to-buffer)
  "r" (cons "remove buffer" #'tabspaces-remove-current-buffer)
  "R" (cons "remove some buffer" #'tabspaces-remove-selected-buffer)
  "c" (cons "clear buffers" #'tabspaces-clear-buffers)
  "d" (cons "close workspace" #'tabspaces-close-workspace)
  "k" (cons "kill buffers and close" #'tabspaces-kill-buffers-close-workspace)
  "]" (cons "next tab" #'tab-next)
  "[" (cons "previous tab" #'tab-previous))
(defvar-keymap kittymacs-cape-map
  :doc "Complete with one particular source."
  "p" (cons "everything (capf)" #'completion-at-point)
  "d" (cons "words in buffers" #'cape-dabbrev)
  "f" (cons "file name" #'cape-file)
  "k" (cons "language keyword" #'cape-keyword)
  "l" (cons "whole line" #'cape-line)
  "a" (cons "abbrev" #'cape-abbrev)
  "w" (cons "dictionary word" #'cape-dict)
  "e" (cons "Emacs Lisp symbol" #'cape-elisp-symbol))

(defvar-keymap kittymacs-code-map
  :doc "Change code."
  "c" (cons "comment" #'comment-dwim)
  "l" (cons "comment line" #'comment-line)
  "d" (cons "duplicate" #'duplicate-dwim)
  "s" (cons "surround" #'embrace-commander)
  "f" (cons "indent region" #'indent-region)
  "w" (cons "clean whitespace" #'whitespace-cleanup)
  "m" (cons "editing menu" #'casual-editkit-main-tmenu)
  "p" (cons "complete with" kittymacs-cape-map))

(defvar-keymap kittymacs-eval-map
  :doc "Evaluate Lisp."
  "e" (cons "last sexp" #'eval-last-sexp)
  "d" (cons "defun" #'eval-defun)
  "b" (cons "buffer" #'eval-buffer)
  "r" (cons "region" #'eval-region)
  "x" (cons "expression" #'eval-expression)
  "i" (cons "ielm" #'ielm)
  "l" (cons "load file" #'load-file))

(defvar-keymap kittymacs-lsp-map
  :doc "Language server and code intelligence."
  "e" (cons "start or manage" #'eglot)
  "q" (cons "shut down" #'eglot-shutdown)
  "=" (cons "reconnect" #'eglot-reconnect)
  "a" (cons "code actions" #'eglot-code-actions)
  "R" (cons "rename" #'eglot-rename)
  "f" (cons "format buffer" #'eglot-format-buffer)
  "F" (cons "format region" #'eglot-format)
  "d" (cons "definition" #'xref-find-definitions)
  "r" (cons "references" #'xref-find-references)
  "D" (cons "declaration" #'eglot-find-declaration)
  "i" (cons "implementation" #'eglot-find-implementation)
  "t" (cons "type definition" #'eglot-find-typeDefinition)
  "h" (cons "documentation" #'eldoc-doc-buffer))

(defvar-keymap kittymacs-diagnostics-map
  :doc "Diagnostics (Flymake)."
  "n" (cons "next" #'flymake-goto-next-error)
  "p" (cons "previous" #'flymake-goto-prev-error)
  "d" (cons "list buffer" #'flymake-show-buffer-diagnostics)
  "D" (cons "list project" #'flymake-show-project-diagnostics)
  "c" (cons "choose" #'consult-flymake)
  "s" (cons "start check" #'flymake-start)
  "P" (cons "package lint" #'package-lint-current-buffer))

(defun kittymacs-insert-date ()
  "Insert today's date as YYYY-MM-DD."
  (interactive)
  (insert (format-time-string "%Y-%m-%d")))

(defvar-keymap kittymacs-insert-map
  :doc "Insert."
  "s" (cons "snippet" #'yas-insert-snippet)
  "S" (cons "new snippet" #'yas-new-snippet)
  "y" (cons "from kill ring" #'consult-yank-from-kill-ring)
  "r" (cons "register" #'consult-register)
  "R" (cons "store register" #'consult-register-store)
  "c" (cons "character" #'insert-char)
  "e" (cons "emoji" #'emoji-insert)
  "d" (cons "date" #'kittymacs-insert-date))
(defvar-keymap kittymacs-notes-map
  :doc "Linked notes in the current graph."
  "f" (cons "find node" #'kittymacs-org-roam-find)
  "i" (cons "insert ID link" #'kittymacs-org-roam-insert)
  "c" (cons "capture (show destination)" #'kittymacs-org-roam-capture)
  "b" (cons "backlinks panel" #'kittymacs-org-roam-backlinks)
  "s" (cons "sync graph" #'kittymacs-org-roam-sync))

(defvar-keymap kittymacs-open-map
  :doc "Open applications."
  "e" (cons "terminal" #'kittymacs-terminal-open)
  "E" (cons "pick a terminal" #'consult-ghostel)
  "p" (cons "project terminal" #'kittymacs-terminal-project)
  "m" (cons "MSYS2 terminal (Windows)" #'kittymacs-terminal-msys2)
  "t" (cons "file tree" #'treemacs-select-window)
  "s" (cons "eshell (project)" #'kittymacs-eshell-project)
  "S" (cons "eshell" #'eshell)
  "a" (cons "agenda dashboard" #'kittymacs-org-dashboard)
  "A" (cons "agenda" #'org-agenda)
  "c" (cons "capture" #'org-capture)
  "i" (cons "org inbox" #'kittymacs-org-inbox)
  "d" (cons "dired" #'dired)
  "h" (cons "home" #'dashboard-open))

(defvar-keymap kittymacs-toggle-map
  :doc "Toggles."
  "t" (cons "light/dark theme" #'kittymacs-toggle-theme)
  "T" (cons "choose theme" #'load-theme)
  "n" (cons "line numbers" #'display-line-numbers-mode)
  "h" (cons "highlight line" #'hl-line-mode)
  "H" (cons "hide mode line" #'hide-mode-line-mode)
  "w" (cons "writeroom" #'writeroom-mode)
  "v" (cons "visual lines" #'visual-line-mode)
  "l" (cons "truncate lines" #'toggle-truncate-lines)
  "s" (cons "spell check" #'flyspell-mode)
  "F" (cons "flymake" #'flymake-mode)
  "r" (cons "colour names" #'rainbow-mode)
  "R" (cons "rainbow identifiers" #'rainbow-identifiers-mode)
  "f" (cons "frames-only mode" #'frames-only-mode)
  "d" (cons "file tree sidebar" #'treemacs)
  "o" (cons "outline sidebar" #'imenu-list-smart-toggle)
  "g" (cons "git gutter" #'diff-hl-mode)
  "D" (cons "dim other windows" #'dimmer-mode)
  "k" (cons "show keys (keycast)" #'keycast-header-line-mode)
  "K" (cons "log keys" #'keycast-log-mode)
  "m" (cons "menu bar" #'menu-bar-mode)
  "p" (cons "structural editing" #'puni-mode)
  "z" (cons "zone out" #'zone))

(defvar-keymap kittymacs-config-map
  :doc "This configuration."
  "c" (cons "reading guide" #'kittymacs-literate-open)
  "f" (cons "find chapter" #'kittymacs-find-config-file)
  "s" (cons "search config" #'kittymacs-search-config)
  "t" (cons "tangle" #'kittymacs-literate-tangle)
  "k" (cons "check tangle" #'kittymacs-literate-check)
  "p" (cons "private.el" #'kittymacs-open-private-file)
  "u" (cons "custom.el" #'kittymacs-open-custom-file)
  "a" (cons "architecture" #'kittymacs-open-architecture)
  "r" (cons "restart Emacs" #'restart-emacs))

(defvar-keymap kittymacs-quit-map
  :doc "Quit."
  "q" (cons "save and quit" #'save-buffers-kill-emacs)
  "Q" (cons "quit without saving" #'kill-emacs)
  "r" (cons "restart" #'restart-emacs)
  "f" (cons "close frame" #'delete-frame))

(defvar-keymap kittymacs-user-map
  :doc "Your own keys. Add them here or in private.el.")
(defvar-keymap kittymacs-help-map
  :doc "Help, documentation and tutorials."
  "h" (cons "home" #'dashboard-open)
  "?" (cons "cheat sheet" #'kittymacs-dashboard-open-cheatsheet)
  "k" (cons "key" #'helpful-key)
  "f" (cons "function" #'helpful-callable)
  "v" (cons "variable" #'helpful-variable)
  "o" (cons "symbol" #'helpful-symbol)
  "c" (cons "command" #'helpful-command)
  "." (cons "at point" #'helpful-at-point)
  "m" (cons "mode" #'describe-mode)
  "b" (cons "bindings here" #'embark-bindings)
  "B" (cons "all bindings" #'describe-bindings)
  "l" (cons "leader" #'kittymacs-describe-leader)
  "F" (cons "face" #'describe-face)
  "w" (cons "where is" #'where-is)
  "e" (cons "messages" #'view-echo-area-messages)
  "L" (cons "lossage" #'view-lossage)
  "i" (cons "info" #'info)
  "s" (cons "search manuals" #'kittymacs-search-manuals)
  "S" (cons "find source" #'find-function)
  "V" (cons "find variable" #'find-variable)
  "K" (cons "find key" #'find-function-on-key)
  "t" (cons "meow tutor" #'meow-tutor)
  "C" (cons "meow cheatsheet" #'meow-cheatsheet))
(keymap-set kittymacs-leader-map "SPC" (cons "M-x" #'execute-extended-command))
(keymap-set kittymacs-leader-map "/" (cons "describe leader" #'kittymacs-describe-leader))
(keymap-set kittymacs-leader-map "?" (cons "search commands" #'apropos-command))
(keymap-set kittymacs-leader-map ";" (cons "comment line" #'comment-line))
(keymap-set kittymacs-leader-map "d" (cons "directory" #'dired-jump))
(keymap-set kittymacs-leader-map "x" (cons "scratch" #'scratch-buffer))
(keymap-set kittymacs-leader-map "k" (cons "kill ring" #'consult-yank-from-kill-ring))
(keymap-set kittymacs-leader-map "[" (cons "previous buffer" #'previous-buffer))
(keymap-set kittymacs-leader-map "]" (cons "next buffer" #'next-buffer))
(keymap-set kittymacs-leader-map "{" (cons "previous tab" #'tab-bar-switch-to-prev-tab))
(keymap-set kittymacs-leader-map "}" (cons "next tab" #'tab-bar-switch-to-next-tab))
(keymap-set kittymacs-leader-map "TAB" (cons "switch tab" #'kittymacs-tab-dwim))

(keymap-set kittymacs-leader-map "b" (cons "buffers" kittymacs-buffer-map))
(keymap-set kittymacs-leader-map "f" (cons "files" kittymacs-file-map))
(keymap-set kittymacs-leader-map "s" (cons "search" kittymacs-search-map))
(keymap-set kittymacs-leader-map "j" (cons "jump" kittymacs-jump-map))
(keymap-set kittymacs-leader-map "p" (cons "project" kittymacs-project-map))
(keymap-set kittymacs-leader-map "v" (cons "version control" kittymacs-vc-map))
(keymap-set kittymacs-leader-map "w" (cons "windows" kittymacs-window-map))
(keymap-set kittymacs-leader-map "W" (cons "workspaces" kittymacs-workspace-map))
(keymap-set kittymacs-leader-map "c" (cons "code" kittymacs-code-map))
(keymap-set kittymacs-leader-map "e" (cons "eval" kittymacs-eval-map))
(keymap-set kittymacs-leader-map "l" (cons "language server" kittymacs-lsp-map))
(keymap-set kittymacs-leader-map "F" (cons "diagnostics" kittymacs-diagnostics-map))
(keymap-set kittymacs-leader-map "i" (cons "insert" kittymacs-insert-map))
(keymap-set kittymacs-leader-map "n" (cons "notes" kittymacs-notes-map))
(keymap-set kittymacs-leader-map "o" (cons "open" kittymacs-open-map))
(keymap-set kittymacs-leader-map "t" (cons "toggle" kittymacs-toggle-map))
(keymap-set kittymacs-leader-map "C" (cons "config" kittymacs-config-map))
(keymap-set kittymacs-leader-map "q" (cons "quit" kittymacs-quit-map))
(keymap-set kittymacs-leader-map "h" (cons "help" kittymacs-help-map))
(keymap-set kittymacs-leader-map "u" (cons "user" kittymacs-user-map))

;; The same tree without Meow: C-c C-SPC works in Insert state and in
;; buffers where Meow is off.
(keymap-global-set "C-c C-SPC" kittymacs-leader-map)

(provide 'kittymacs-keys)
;;; kittymacs-keys.el ends here
