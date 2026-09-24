;;; kittymacs-completion.el --- Minibuffer and in-buffer completion -*- lexical-binding: t; -*-
;; Generated from literate/60-completion.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(use-package vertico
  :ensure t
  :demand t
  :bind (:map vertico-map
         ("<escape>" . minibuffer-keyboard-quit)
         ("M-RET" . vertico-exit))
  :custom
  (vertico-cycle t)
  (vertico-resize nil)
  :config
  (vertico-mode 1)
  (defun kittymacs-vertico-directories-first (files)
    "Sort FILES by history, length and name, then put directories first."
    (let ((sorted (vertico-sort-history-length-alpha files)))
      (nconc (seq-filter (lambda (file) (string-suffix-p "/" file)) sorted)
             (seq-remove (lambda (file) (string-suffix-p "/" file)) sorted))))
  (setopt vertico-multiform-categories '((file (vertico-sort-function . kittymacs-vertico-directories-first))))
  (vertico-multiform-mode 1))

(use-package vertico-directory
  :ensure nil
  :after vertico
  :bind (:map vertico-map
         ("DEL" . vertico-directory-delete-char)
         ("M-DEL" . vertico-directory-delete-word))
  :hook (rfn-eshadow-update-overlay . vertico-directory-tidy))

(use-package vertico-repeat
  :ensure nil
  :after vertico
  :hook (minibuffer-setup . vertico-repeat-save)
  :commands (vertico-repeat vertico-repeat-last))

(use-package vertico-buffer
  :ensure nil
  :after vertico
  :custom
  (vertico-buffer-display-action '(display-buffer-in-side-window
                                   (window-height . 12)
                                   (side . top)))
  :config
  (vertico-buffer-mode 1))
(defun kittymacs--crm-indicator (args)
  "Prefix a `completing-read-multiple' prompt with [CRM]."
  (cons (concat "[CRM] " (car args)) (cdr args)))
(when (< emacs-major-version 31)
  (advice-add #'completing-read-multiple :filter-args #'kittymacs--crm-indicator))

(setopt resize-mini-windows t
        enable-recursive-minibuffers t
        minibuffer-prompt-properties '(read-only t cursor-intangible t face minibuffer-prompt)
        read-file-name-completion-ignore-case t
        read-buffer-completion-ignore-case t
        completion-ignore-case t)
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))
(use-package marginalia
  :ensure t
  :demand t
  :bind (:map minibuffer-local-map
         ("C-M-a" . marginalia-cycle))
  :custom
  (marginalia-align 'center)
  :config
  (marginalia-mode 1))
(use-package consult
  :ensure t
  :bind (("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop)
         ("M-g g" . consult-goto-line)
         ("M-g i" . consult-imenu))
  :hook (completion-list-mode . consult-preview-at-point-mode)
  :custom
  (consult-async-min-input 2)
  (consult-ripgrep-args
   "rg --null --line-buffered --color=never --max-columns=1000 --path-separator / --smart-case --no-heading --with-filename --line-number --search-zip")
  (register-preview-delay 0.5)
  (register-preview-function #'consult-register-format)
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref)
  :config
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   consult-source-bookmark consult-source-recent-file
   consult-source-project-recent-file consult-theme
   :preview-key '(:debounce 0.2 any))
  (advice-add #'register-preview :override #'consult-register-window))

(defun kittymacs-search-symbol-at-point ()
  "Search this buffer's lines for the symbol at point."
  (interactive)
  (consult-line (thing-at-point 'symbol)))

(defun kittymacs-search-manuals ()
  "Search the Emacs, Org and completion-stack manuals with Consult."
  (interactive)
  (consult-info "emacs" "efaq" "elisp" "org" "vertico" "consult" "marginalia"
                "orderless" "embark" "corfu" "cape"))

(use-package consult-dir
  :ensure t
  :bind (("C-x C-d" . consult-dir)
         :map vertico-map
         ("C-x C-d" . consult-dir)
         ("C-x C-j" . consult-dir-jump-file)))
(use-package embark
  :ensure t
  :bind (("C-." . embark-act)
         ("C->" . embark-act-all)
         ("M-." . embark-dwim)
         ("C-h B" . embark-bindings)
         :map minibuffer-local-completion-map
         ("C-S-o" . embark-act)
         :map completion-list-mode-map
         (";" . embark-act))
  :custom
  (prefix-help-command #'embark-prefix-help-command)
  (embark-prompter #'embark-keymap-prompter)
  :config
  (defun kittymacs-embark-which-key-indicator ()
    "Show Embark's action keymap with which-key."
    (lambda (&optional keymap targets prefix)
      (if (null keymap)
          (which-key-hide-popup)
        (which-key-show-keymap
         (if (eq (plist-get (car targets) :type) 'embark-become)
             "Become"
           (format "Act on %s '%s'%s"
                   (plist-get (car targets) :type)
                   (embark--truncate-target (plist-get (car targets) :target))
                   (if (cdr targets) "..." "")))))))
  (setopt embark-indicators '(kittymacs-embark-which-key-indicator
                              embark-highlight-indicator
                              embark-isearch-highlight-indicator))
  (defun kittymacs--embark-hide-which-key (function &rest args)
    "Hide the which-key popup before the completing-read prompter takes over."
    (which-key-hide-popup)
    (let ((embark-indicators (remq #'kittymacs-embark-which-key-indicator embark-indicators)))
      (apply function args)))
  (advice-add #'embark-completing-read-prompter :around #'kittymacs--embark-hide-which-key)
  (add-to-list 'display-buffer-alist
               '("\\`\\*Embark Collect \\(Live\\|Completions\\)\\*"
                 nil
                 (window-parameters (mode-line-format . none))))
  (defun kittymacs-embark-dired-here (file)
    "Open Dired in FILE's directory."
    (dired (file-name-directory file)))
  (defun kittymacs-embark-ripgrep-here (file)
    "Run ripgrep in FILE's directory."
    (let ((default-directory (file-name-directory file)))
      (consult-ripgrep)))
  (keymap-set embark-file-map "x" #'embark-open-externally)
  (keymap-set embark-file-map "D" #'kittymacs-embark-dired-here)
  (keymap-set embark-file-map "g" #'kittymacs-embark-ripgrep-here)
  (keymap-set embark-general-map "A" #'marginalia-cycle))

(use-package embark-consult
  :ensure t
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))
(use-package corfu
  :ensure t
  :demand t
  :bind (:map corfu-map
         ("C-j" . corfu-next)
         ("C-k" . corfu-previous)
         ("M-l" . corfu-show-location)
         ("M-SPC" . corfu-insert-separator)
         ("<escape>" . corfu-quit)
         ("RET" . corfu-send)
         ("TAB" . corfu-insert)
         ([tab] . corfu-insert))
  :custom
  (corfu-auto t)
  (corfu-cycle t)
  (corfu-count 10)
  (corfu-min-width 25)
  (corfu-max-width 100)
  (corfu-scroll-margin 5)
  (corfu-separator ?\s)
  (corfu-quit-no-match 'separator)
  (corfu-quit-at-boundary 'separator)
  (corfu-preview-current t)
  (corfu-preselect 'first)
  (corfu-popupinfo-delay 1)
  :config
  (global-corfu-mode 1)
  (corfu-history-mode 1)
  (corfu-popupinfo-mode 1)
  (defun kittymacs--corfu-in-minibuffer ()
    "Enable Corfu in minibuffers that offer completion at point, such as M-:."
    (when (where-is-internal #'completion-at-point (list (current-local-map)))
      (corfu-mode 1)))
  (add-hook 'minibuffer-setup-hook #'kittymacs--corfu-in-minibuffer)
  (defun kittymacs--corfu-in-shells ()
    "In Eshell, complete only on request, like an ordinary shell."
    (setq-local corfu-auto nil
                corfu-quit-no-match t
                corfu-quit-at-boundary t)
    (corfu-mode 1))
  (add-hook 'eshell-mode-hook #'kittymacs--corfu-in-shells))

(keymap-global-set "M-/" #'dabbrev-completion)
(keymap-global-set "C-M-/" #'dabbrev-expand)
(setopt text-mode-ispell-word-completion nil)

(use-package cape
  :ensure t
  :init
  (add-to-list 'completion-at-point-functions #'cape-file)
  (add-to-list 'completion-at-point-functions #'cape-keyword)
  :config
  (advice-add 'pcomplete-completions-at-point :around #'cape-wrap-silent))
(use-package flyspell-correct
  :ensure t
  :after flyspell
  :bind (:map flyspell-mode-map ("C-;" . flyspell-correct-wrapper)))

(use-package consult-flyspell
  :ensure t
  :commands consult-flyspell)
(defvar kittymacs-snippets-dir (expand-file-name "snippets/" kittymacs-etc-dir)
  "Directory of personal snippets, one subdirectory per major mode.")

(use-package yasnippet
  :ensure t
  :defer 1
  :bind (:map yas-minor-mode-map
         ("C-'" . yas-expand))
  :custom
  (yas-snippet-dirs (list kittymacs-snippets-dir))
  :config
  (make-directory kittymacs-snippets-dir t)
  (defun kittymacs--yas-not-in-org-src ()
    "Do not expand snippets inside Org source blocks."
    (setq-local yas-buffer-local-condition '(not (org-in-src-block-p t))))
  (add-hook 'org-mode-hook #'kittymacs--yas-not-in-org-src)
  (with-eval-after-load 'warnings
    (push '(yasnippet backquote-change) warning-suppress-types))
  (yas-global-mode 1))

(provide 'kittymacs-completion)
;;; kittymacs-completion.el ends here
