;;; kittymacs-navigation.el --- Projects, places, search and workspaces -*- lexical-binding: t; -*-
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
(keymap-set kittymacs-jump-map "i" (cons "in this line" #'avy-goto-char-in-line))
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
  :config
  (when (executable-find "rg")
    (setopt xref-search-program 'ripgrep))
  (project-forget-zombie-projects))
(use-package visual-regexp
  :ensure t
  :commands (vr/query-replace vr/replace))

(keymap-set kittymacs-search-map "r" (cons "replace (visual)" #'vr/query-replace))
(setopt tab-bar-tab-hints t
        tab-bar-new-tab-choice "*scratch*"
        tab-bar-new-tab-to 'rightmost
        tab-bar-close-last-tab-choice 'tab-bar-mode-disable
        tab-bar-new-button-show nil
        tab-bar-close-button-show nil
        tab-bar-auto-width nil)

(defun kittymacs-tab-dwim ()
  "Create a tab if there is one, switch if there are two, else choose one."
  (interactive)
  (let ((tabs (mapcar (lambda (tab) (alist-get 'name tab)) (tab-bar--tabs-recent))))
    (cond ((null tabs) (tab-new))
          ((= (length tabs) 1) (tab-next))
          (t (tab-bar-switch-to-tab (completing-read "Select tab: " tabs nil t))))))

(keymap-set kittymacs-leader-map "{" (cons "previous tab" #'tab-bar-switch-to-prev-tab))
(keymap-set kittymacs-leader-map "}" (cons "next tab" #'tab-bar-switch-to-next-tab))
(keymap-set kittymacs-leader-map "TAB" (cons "switch tab" #'kittymacs-tab-dwim))

(keymap-set kittymacs-workspace-map "TAB" (cons "switch" #'kittymacs-tab-dwim))
(keymap-set kittymacs-workspace-map "n" (cons "new tab" #'tab-new))
(keymap-set kittymacs-workspace-map "]" (cons "next tab" #'tab-next))
(keymap-set kittymacs-workspace-map "[" (cons "previous tab" #'tab-previous))

(defvar kittymacs-consult-source-workspace
  (list :name "Workspace Buffers"
        :narrow ?w
        :history 'buffer-name-history
        :category 'buffer
        :state #'consult--buffer-state
        :default t
        :items (lambda () (consult--buffer-query
                           :predicate #'tabspaces--local-buffer-p
                           :sort 'visibility
                           :as #'buffer-name)))
  "Consult source listing only this workspace's buffers.")

(defun kittymacs--consult-tabspaces ()
  "Show workspace buffers first while tabspaces is on."
  (if tabspaces-mode
      (progn
        (plist-put consult-source-buffer :hidden t)
        (plist-put consult-source-buffer :default nil)
        (add-to-list 'consult-buffer-sources 'kittymacs-consult-source-workspace))
    (plist-put consult-source-buffer :hidden nil)
    (plist-put consult-source-buffer :default t)
    (setq consult-buffer-sources (remove 'kittymacs-consult-source-workspace consult-buffer-sources))))

(use-package tabspaces
  :ensure t
  :demand t
  :custom
  (tabspaces-use-filtered-buffers-as-default t)
  (tabspaces-default-tab "Home")
  :config
  (kittymacs-after-init #'tabspaces-mode 95)
  (with-eval-after-load 'consult
    (add-hook 'tabspaces-mode-hook #'kittymacs--consult-tabspaces)
    (kittymacs--consult-tabspaces)))

;; Loaded by the `use-package' above; these quiet the byte compiler.
(declare-function tabspaces-switch-to-buffer "tabspaces")
(declare-function tabspaces-remove-current-buffer "tabspaces")
(declare-function tabspaces-remove-selected-buffer "tabspaces")
(declare-function tabspaces-clear-buffers "tabspaces")
(declare-function tabspaces-close-workspace "tabspaces")
(declare-function tabspaces-kill-buffers-close-workspace "tabspaces")

(keymap-set kittymacs-project-map "p" (cons "open in a workspace" #'tabspaces-open-or-create-project-and-workspace))

(keymap-set kittymacs-workspace-map "s" (cons "switch or create" #'tabspaces-switch-or-create-workspace))
(keymap-set kittymacs-workspace-map "o" (cons "open project" #'tabspaces-open-or-create-project-and-workspace))
(keymap-set kittymacs-workspace-map "b" (cons "workspace buffer" #'tabspaces-switch-to-buffer))
(keymap-set kittymacs-workspace-map "r" (cons "remove buffer" #'tabspaces-remove-current-buffer))
(keymap-set kittymacs-workspace-map "R" (cons "remove some buffer" #'tabspaces-remove-selected-buffer))
(keymap-set kittymacs-workspace-map "c" (cons "clear buffers" #'tabspaces-clear-buffers))
(keymap-set kittymacs-workspace-map "d" (cons "close workspace" #'tabspaces-close-workspace))
(keymap-set kittymacs-workspace-map "k" (cons "kill buffers and close" #'tabspaces-kill-buffers-close-workspace))

(provide 'kittymacs-navigation)
;;; kittymacs-navigation.el ends here
