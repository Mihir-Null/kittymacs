;;; kittymacs-navigation.el --- Projects, places, search and workspaces -*- lexical-binding: t; -*-
;; Generated from literate/68-navigation.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(setopt save-place-file (expand-file-name "saved-places" kittymacs-cache-dir)
        save-place-forget-unreadable-files nil)
(save-place-mode 1)

(setopt recentf-save-file (expand-file-name "recentf" kittymacs-cache-dir)
        recentf-max-saved-items 500)
(recentf-mode 1)

(setopt bookmark-default-file (expand-file-name "bookmarks" kittymacs-cache-dir))

(use-package goto-last-change
  :ensure t
  :bind (("C-\"" . goto-last-change)))

(dolist (hook '(compilation-mode-hook eshell-mode-hook shell-mode-hook text-mode-hook))
  (add-hook hook #'goto-address-mode))
(add-hook 'prog-mode-hook #'goto-address-prog-mode)

(use-package imenu-list
  :ensure t
  :commands (imenu-list-smart-toggle imenu-list-minor-mode)
  :custom
  (imenu-list-position 'right)
  (imenu-list-auto-resize t)
  (imenu-list-focus-after-activation t)
  :config
  ;; Register its side-window placement so frames-only mode never gives it a frame.
  (when (fboundp 'imenu-list-install-display-buffer)
    (imenu-list-install-display-buffer)))

(defun kittymacs-jump-in-buffer ()
  "Jump to a heading or definition in this buffer with completion."
  (interactive)
  (if (derived-mode-p 'org-mode)
      (call-interactively #'consult-org-heading)
    (call-interactively #'consult-outline)))
(use-package avy
  :ensure t
  :commands (avy-goto-char-timer avy-goto-line avy-goto-word-1 avy-goto-symbol-1
             avy-goto-end-of-line avy-goto-char-in-line)
  :custom
  (avy-timeout-seconds 0.4)
  (avy-all-windows t)
  (avy-style 'at-full))
(defun kittymacs-projects-directory ()
  "Open the directory where projects live."
  (interactive)
  (dired kittymacs-project-directory))

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
(use-package deadgrep :ensure t :commands deadgrep)
(use-package visual-regexp
  :ensure t
  :commands (vr/query-replace vr/replace))
(use-package visual-regexp-steroids
  :ensure t
  :after visual-regexp)
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
  (tabspaces-mode 1)
  (with-eval-after-load 'consult
    (add-hook 'tabspaces-mode-hook #'kittymacs--consult-tabspaces)
    (kittymacs--consult-tabspaces)))

(provide 'kittymacs-navigation)
;;; kittymacs-navigation.el ends here
