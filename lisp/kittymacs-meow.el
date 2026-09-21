;;; kittymacs-meow.el --- Selection-first editing -*- lexical-binding: t; -*-
;; Generated from literate/40-editing.org; edit the Org source, then tangle.

;; Grammar adapted from Colin McLear's cpm-setup-meow.el (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-leader)
(defun kittymacs-meow-setup ()
  "Install the QWERTY selection grammar and the Motion-state basics."
  ;; Motion state: application buffers keep their own keys; only j/k move.
  (meow-motion-define-key
   '("j" . meow-next)
   '("k" . meow-prev))
  (meow-normal-define-key
   ;; Numbered expansion hints and counts.
   '("0" . meow-expand-0)
   '("9" . meow-expand-9)
   '("8" . meow-expand-8)
   '("7" . meow-expand-7)
   '("6" . meow-expand-6)
   '("5" . meow-expand-5)
   '("4" . meow-expand-4)
   '("3" . meow-expand-3)
   '("2" . meow-expand-2)
   '("1" . meow-expand-1)
   '("-" . negative-argument)
   ;; Move; the shifted key extends the selection instead.
   '("h" . meow-left)
   '("H" . meow-left-expand)
   '("j" . meow-next)
   '("J" . meow-next-expand)
   '("k" . meow-prev)
   '("K" . meow-prev-expand)
   '("l" . meow-right)
   '("L" . meow-right-expand)
   '("b" . meow-back-word)
   '("B" . meow-back-symbol)
   '("e" . meow-next-word)
   '("E" . meow-next-symbol)
   '("g" . beginning-of-buffer)
   '("G" . end-of-buffer)
   ;; Select a thing: word, symbol, line, block, or by character.
   '("w" . meow-mark-word)
   '("W" . meow-mark-symbol)
   '("x" . meow-line)
   '("o" . meow-block)
   '("O" . meow-to-block)
   '("f" . meow-find)
   '("t" . meow-till)
   '("n" . meow-search)
   '("v" . meow-visit)
   '(";" . meow-reverse)
   '(":" . meow-goto-line)
   '("," . meow-inner-of-thing)
   '("." . meow-bounds-of-thing)
   '("[" . meow-beginning-of-thing)
   '("]" . meow-end-of-thing)
   ;; Act on the selection.
   '("a" . meow-append)
   '("A" . meow-open-below)
   '("i" . meow-insert)
   '("I" . meow-open-above)
   '("c" . meow-change)
   '("d" . meow-delete)
   '("D" . meow-backward-delete)
   '("s" . meow-kill)
   '("r" . meow-replace)
   '("R" . overwrite-mode)
   '("m" . meow-join)
   '("p" . meow-yank)
   '("y" . meow-clipboard-save)
   '("u" . meow-undo)
   '("U" . meow-undo-in-selection)
   '("z" . meow-pop-selection)
   '("q" . meow-quit)
   '("'" . repeat)
   '("&" . meow-query-replace-regexp)
   '("%" . meow-query-replace)
   ;; Grab: keep a second selection in sync (see meow-tutor).
   '("=" . meow-grab)
   '("X" . meow-swap-grab)
   '("Y" . meow-sync-grab)
   '("<escape>" . meow-cancel-selection)))
(use-package meow
  :ensure t
  :custom
  (meow-use-cursor-position-hack t)
  (meow-use-clipboard t)
  (meow-goto-line-function #'consult-goto-line)
  :config
  (meow-thing-register 'angle '(regexp "<" ">") '(regexp "<" ">"))
  (add-to-list 'meow-char-thing-table '(?< . angle))
  (dolist (entry '((eshell-mode . insert)
                   (shell-mode . insert)
                   (term-mode . insert)))
    (add-to-list 'meow-mode-state-list entry))
  (with-eval-after-load 'org
    ;; Treat @ as part of symbols/words during Meow movement in Org.
    (modify-syntax-entry ?@ "_" org-mode-syntax-table))
  (kittymacs-meow-setup)
  (meow-global-mode 1)
  (kittymacs-leader-enable))
(use-package meow-tree-sitter
  :ensure t
  :after meow
  :config
  (meow-tree-sitter-register-defaults))
(provide 'kittymacs-meow)
;;; kittymacs-meow.el ends here
