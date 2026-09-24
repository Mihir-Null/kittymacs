;;; kittymacs-help.el --- Help, Info and menus -*- lexical-binding: t; -*-
;; Generated from literate/62-help.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(setopt use-file-dialog nil
        use-dialog-box nil
        confirm-nonexistent-file-or-buffer nil
        help-window-select t
        help-at-pt-timer-delay 0.1
        help-at-pt-display-when-idle '(flymake-diagnostic))
(menu-bar-mode -1)
(use-package helpful
  :ensure t
  :bind (([remap display-local-help] . helpful-at-point)
         ([remap describe-function] . helpful-callable)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-symbol] . helpful-symbol)
         ([remap describe-key] . helpful-key)
         ([remap describe-command] . helpful-command)
         ("C-h C-l" . find-library)
         ("C-h C-c" . finder-commentary)))

(use-package elisp-demos
  :ensure t
  :after helpful
  :config
  (advice-add 'helpful-update :after #'elisp-demos-advice-helpful-update))

(use-package info-colors
  :ensure t
  :hook (Info-selection . info-colors-fontify-node))
(use-package transient
  :ensure nil
  :defer t
  :custom
  (transient-levels-file (expand-file-name "transient/levels.el" kittymacs-cache-dir))
  (transient-values-file (expand-file-name "transient/values.el" kittymacs-cache-dir))
  (transient-history-file (expand-file-name "transient/history.el" kittymacs-cache-dir))
  (transient-detect-key-conflicts t)
  (transient-force-fixed-pitch t)
  (transient-display-buffer-action '(display-buffer-in-side-window
                                     (side . top)
                                     (dedicated . t)
                                     (inhibit-same-window . t)
                                     (window-parameters (no-other-window . t)))))
(use-package keycast
  :ensure t
  :commands (keycast-header-line-mode keycast-log-mode keycast-tab-bar-mode)
  :config
  (dolist (input '(self-insert-command org-self-insert-command))
    (add-to-list 'keycast-substitute-alist `(,input "." "Typing...")))
  (dolist (event '(mouse-event-p mouse-movement-p mwheel-scroll))
    (add-to-list 'keycast-substitute-alist `(,event nil))))
(use-package casual
  :ensure t
  :defer t)

(with-eval-after-load 'calc (keymap-set calc-mode-map "C-o" #'casual-calc-tmenu))
(with-eval-after-load 'isearch (keymap-set isearch-mode-map "C-o" #'casual-isearch-tmenu))
(with-eval-after-load 're-builder (keymap-set reb-mode-map "C-o" #'casual-re-builder-tmenu))
(with-eval-after-load 'bookmark (keymap-set bookmark-bmenu-mode-map "C-o" #'casual-bookmarks-tmenu))
(with-eval-after-load 'ibuffer (keymap-set ibuffer-mode-map "C-o" #'casual-ibuffer-tmenu))
(with-eval-after-load 'dired (keymap-set dired-mode-map "C-o" #'casual-dired-tmenu))
(with-eval-after-load 'info (keymap-set Info-mode-map "C-o" #'casual-info-tmenu))
(with-eval-after-load 'compile (keymap-set compilation-mode-map "C-o" #'casual-compile-tmenu))

(kittymacs-define-localleader 'ibuffer-mode
  "?" (cons "menu" #'casual-ibuffer-tmenu))

(kittymacs-define-localleader 'compilation-mode
  "?" (cons "menu" #'casual-compile-tmenu))
(kittymacs-define-localleader 'Info-mode
  "n" (cons "next node" #'Info-next)
  "p" (cons "previous node" #'Info-prev)
  "u" (cons "up" #'Info-up)
  "t" (cons "top" #'Info-top-node)
  "d" (cons "directory" #'Info-directory)
  "g" (cons "go to node" #'Info-goto-node)
  "i" (cons "index" #'Info-index)
  "s" (cons "search" #'Info-search)
  "m" (cons "menu" #'Info-menu)
  "l" (cons "back" #'Info-history-back)
  "r" (cons "forward" #'Info-history-forward)
  "?" (cons "menu" #'casual-info-tmenu))

(kittymacs-define-localleader 'help-mode
  "l" (cons "back" #'help-go-back)
  "r" (cons "forward" #'help-go-forward)
  "s" (cons "source" #'help-view-source)
  "i" (cons "info" #'help-goto-info)
  "?" (cons "menu" #'casual-help-tmenu))

(with-eval-after-load 'helpful
  (kittymacs-define-localleader 'helpful-mode
    "u" (cons "update" #'helpful-update)
    "s" (cons "source" #'helpful-visit-reference)))

(provide 'kittymacs-help)
;;; kittymacs-help.el ends here
