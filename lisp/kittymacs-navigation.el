;;; kittymacs-navigation.el --- Projects, places and search -*- lexical-binding: t; -*-
;; Generated from literate/68-navigation.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)
(require 'kittymacs-platform)
(setopt save-place-file (expand-file-name "saved-places" kittymacs-cache-dir)
        save-place-forget-unreadable-files nil)
(save-place-mode 1)

(setopt recentf-save-file (expand-file-name "recentf" kittymacs-cache-dir)
        recentf-max-saved-items 500)
(recentf-mode 1)

(setopt bookmark-default-file (expand-file-name "bookmarks" kittymacs-cache-dir))


(dolist (hook '(compilation-mode-hook eshell-mode-hook shell-mode-hook text-mode-hook))
  (add-hook hook #'goto-address-mode))
(add-hook 'prog-mode-hook #'goto-address-prog-mode)

(defun kittymacs-jump-in-buffer ()
  "Jump to a heading or definition in this buffer with completion."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'consult-org-heading)
    (call-interactively #'consult-outline)))

(keymap-set kittymacs-buffer-map "j" (cons "jump to heading" #'kittymacs-jump-in-buffer))
(when (kittymacs-feature-p 'jump)
  (use-package avy
    :ensure t
    :commands (avy-goto-char-timer avy-goto-line avy-goto-word-1 avy-goto-symbol-1
               avy-goto-end-of-line avy-goto-char-in-line)
    :custom
    (avy-timeout-seconds 0.4)
    (avy-all-windows t)
    (avy-style 'at-full))

  (keymap-set kittymacs-jump-map "j" (cons "to character" #'avy-goto-char-timer))
  (keymap-set kittymacs-jump-map "l" (cons "to line" #'avy-goto-line))
  (keymap-set kittymacs-jump-map "w" (cons "to word" #'avy-goto-word-1))
  (keymap-set kittymacs-jump-map "s" (cons "to symbol" #'avy-goto-symbol-1))
  (keymap-set kittymacs-jump-map "e" (cons "to end of line" #'avy-goto-end-of-line))
  (keymap-set kittymacs-jump-map "i" (cons "in this line" #'avy-goto-char-in-line)))
(defun kittymacs-projects-directory ()
  "Open the directory where projects live."
  (interactive)
  (dired kittymacs-project-directory))

(keymap-set kittymacs-project-map "t" (cons "projects directory" #'kittymacs-projects-directory))
(keymap-set kittymacs-project-map "R" (cons "remember projects under" #'project-remember-projects-under))

(use-package project
  :ensure nil
  :custom
  (project-list-file (expand-file-name "projects" kittymacs-cache-dir))
  (project-switch-commands '((project-find-file "Find file")
                             (project-find-regexp "Find regexp")
                             (project-find-dir "Find directory")
                             (project-vc-dir "VC-Dir")
                             (magit-project-status "Magit status" ?G)))
  (project-vc-extra-root-markers '(".dir-locals.el" ".project.el" "package.json" "requirements.txt" "autogen.sh"))
  (project-prune-zombie-projects '((list-first-read . project-prune-zombies-default)
                                   (prompt . project-prune-zombies-default)))
  :config
  (when (executable-find "rg")
    (setopt xref-search-program 'ripgrep)))
(when (kittymacs-feature-p 'visual-replace)
  (use-package visual-regexp
    :ensure t
    :commands (vr/query-replace vr/replace))

  (keymap-set kittymacs-search-map "r" (cons "replace (visual)" #'vr/query-replace)))
(setopt tab-bar-tab-hints t
        tab-bar-new-tab-choice "*scratch*"
        tab-bar-new-tab-to 'rightmost
        tab-bar-close-last-tab-choice 'tab-bar-mode-disable
        tab-bar-new-button-show nil
        tab-bar-close-button-show nil
        tab-bar-auto-width nil)

(provide 'kittymacs-navigation)
;;; kittymacs-navigation.el ends here
