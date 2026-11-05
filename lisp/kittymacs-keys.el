;;; kittymacs-keys.el --- The keys no feature owns -*- lexical-binding: t; -*-
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

(keymap-set kittymacs-buffer-map "k" (cons "kill this" #'kill-current-buffer))
(keymap-set kittymacs-buffer-map "K" (cons "kill some" #'kill-buffer))
(keymap-set kittymacs-buffer-map "n" (cons "new" #'kittymacs-new-buffer))
(keymap-set kittymacs-buffer-map "N" (cons "new in frame" #'kittymacs-new-buffer-frame))
(keymap-set kittymacs-buffer-map "s" (cons "save" #'save-buffer))
(keymap-set kittymacs-buffer-map "r" (cons "revert" #'revert-buffer-quick))
(keymap-set kittymacs-buffer-map "R" (cons "rename file" #'rename-visited-file))
(keymap-set kittymacs-buffer-map "a" (cons "ibuffer" #'ibuffer))
(keymap-set kittymacs-buffer-map "x" (cons "scratch" #'scratch-buffer))
(keymap-set kittymacs-buffer-map "[" (cons "previous" #'previous-buffer))
(keymap-set kittymacs-buffer-map "]" (cons "next" #'next-buffer))

(keymap-set kittymacs-file-map "f" (cons "find" #'find-file))
(keymap-set kittymacs-file-map "F" (cons "find in other frame" #'find-file-other-frame))
(keymap-set kittymacs-file-map "s" (cons "save" #'save-buffer))
(keymap-set kittymacs-file-map "S" (cons "save all" #'save-some-buffers))
(keymap-set kittymacs-file-map "B" (cons "set bookmark" #'bookmark-set))
(keymap-set kittymacs-file-map "R" (cons "rename" #'rename-visited-file))
(keymap-set kittymacs-file-map "y" (cons "copy file name" #'kittymacs-copy-file-name))
(keymap-set kittymacs-file-map "o" (cons "show in file manager" #'kittymacs-reveal-in-file-manager))
(keymap-set kittymacs-window-map "n" (cons "new frame" #'make-frame-command))
(keymap-set kittymacs-window-map "k" (cons "close frame" #'delete-frame))
(keymap-set kittymacs-window-map "K" (cons "close other frames" #'delete-other-frames))
(keymap-set kittymacs-window-map "o" (cons "other window" #'other-window))
(keymap-set kittymacs-window-map "d" (cons "close window" #'delete-window))
(keymap-set kittymacs-window-map "m" (cons "only this window" #'delete-other-windows))
(keymap-set kittymacs-window-map "h" (cons "split below" #'split-window-below))
(keymap-set kittymacs-window-map "v" (cons "split right" #'split-window-right))
(keymap-set kittymacs-window-map "=" (cons "balance" #'balance-windows))
(keymap-set kittymacs-window-map "t" (cons "window to frame" #'tear-off-window))
(keymap-set kittymacs-window-map "u" (cons "undo layout" #'winner-undo))
(keymap-set kittymacs-window-map "U" (cons "redo layout" #'winner-redo))
(keymap-set kittymacs-window-map "f" (cons "fullscreen" #'toggle-frame-fullscreen))
(keymap-set kittymacs-window-map "M" (cons "maximize" #'toggle-frame-maximized))
(keymap-set kittymacs-code-map "c" (cons "comment" #'comment-dwim))
(keymap-set kittymacs-code-map "l" (cons "comment line" #'comment-line))
(keymap-set kittymacs-code-map "d" (cons "duplicate" #'duplicate-dwim))
(keymap-set kittymacs-code-map "f" (cons "indent region" #'indent-region))
(keymap-set kittymacs-code-map "w" (cons "clean whitespace" #'whitespace-cleanup))

(keymap-set kittymacs-eval-map "e" (cons "last sexp" #'eval-last-sexp))
(keymap-set kittymacs-eval-map "d" (cons "defun" #'eval-defun))
(keymap-set kittymacs-eval-map "b" (cons "buffer" #'eval-buffer))
(keymap-set kittymacs-eval-map "r" (cons "region" #'eval-region))
(keymap-set kittymacs-eval-map "x" (cons "expression" #'eval-expression))
(keymap-set kittymacs-eval-map "i" (cons "ielm" #'ielm))
(keymap-set kittymacs-eval-map "l" (cons "load file" #'load-file))

(defun kittymacs-insert-date ()
  "Insert today's date as YYYY-MM-DD."
  (interactive)
  (insert (format-time-string "%Y-%m-%d")))

(keymap-set kittymacs-insert-map "c" (cons "character" #'insert-char))
(keymap-set kittymacs-insert-map "e" (cons "emoji" #'emoji-insert))
(keymap-set kittymacs-insert-map "d" (cons "date" #'kittymacs-insert-date))
(keymap-set kittymacs-toggle-map "n" (cons "line numbers" #'display-line-numbers-mode))
(keymap-set kittymacs-toggle-map "h" (cons "highlight line" #'hl-line-mode))
(keymap-set kittymacs-toggle-map "v" (cons "visual lines" #'visual-line-mode))
(keymap-set kittymacs-toggle-map "l" (cons "truncate lines" #'toggle-truncate-lines))
(keymap-set kittymacs-toggle-map "s" (cons "spell check" #'flyspell-mode))
(keymap-set kittymacs-toggle-map "m" (cons "menu bar" #'menu-bar-mode))
(keymap-set kittymacs-toggle-map "z" (cons "zone out" #'zone))

(keymap-set kittymacs-quit-map "q" (cons "save and quit" #'save-buffers-kill-emacs))
(keymap-set kittymacs-quit-map "Q" (cons "quit without saving" #'kill-emacs))
(keymap-set kittymacs-quit-map "r" (cons "restart" #'restart-emacs))
(keymap-set kittymacs-quit-map "f" (cons "close frame" #'delete-frame))
(keymap-set kittymacs-leader-map "SPC" (cons "M-x" #'execute-extended-command))
(keymap-set kittymacs-leader-map "/" (cons "describe leader" #'kittymacs-describe-leader))
(keymap-set kittymacs-leader-map "?" (cons "search commands" #'apropos-command))
(keymap-set kittymacs-leader-map ";" (cons "comment line" #'comment-line))
(keymap-set kittymacs-leader-map "x" (cons "scratch" #'scratch-buffer))
(keymap-set kittymacs-leader-map "[" (cons "previous buffer" #'previous-buffer))
(keymap-set kittymacs-leader-map "]" (cons "next buffer" #'next-buffer))

;; The same tree without Meow: C-c C-SPC works in Insert state and in
;; buffers where Meow is off.
(keymap-global-set "C-c C-SPC" kittymacs-leader-map)

(provide 'kittymacs-keys)
;;; kittymacs-keys.el ends here
