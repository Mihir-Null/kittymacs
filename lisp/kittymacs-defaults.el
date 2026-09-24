;;; kittymacs-defaults.el --- Sane defaults -*- lexical-binding: t; -*-
;; Generated from literate/25-defaults.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:
(defgroup kittymacs nil
  "Options of the kittymacs Emacs configuration."
  :group 'emacs
  :prefix "kittymacs-")
;; The three directories are defined in early-init.el (see the startup chapter);
;; these defaults only apply when a module is loaded on its own.
(defvar kittymacs-var-dir (expand-file-name "var/" user-emacs-directory))
(defvar kittymacs-cache-dir (expand-file-name "cache/" kittymacs-var-dir))
(defvar kittymacs-etc-dir (expand-file-name "etc/" kittymacs-var-dir))

(dolist (directory (list kittymacs-var-dir kittymacs-cache-dir kittymacs-etc-dir))
  (make-directory directory t))

(setopt custom-file (expand-file-name "custom.el" kittymacs-etc-dir))
(setopt require-final-newline t
        large-file-warning-threshold 100000000
        confirm-kill-processes nil
        find-file-visit-truename t
        view-read-only t)

(let ((backups (expand-file-name "backup/" kittymacs-cache-dir))
      (auto-saves (expand-file-name "auto-save/" kittymacs-cache-dir)))
  (make-directory backups t)
  (make-directory auto-saves t)
  (setopt backup-directory-alist `(("." . ,backups))
          auto-save-file-name-transforms `((".*" ,auto-saves t))
          auto-save-list-file-prefix (expand-file-name ".saves-" auto-saves)))
(setopt backup-by-copying t
        version-control t
        delete-old-versions t
        kept-new-versions 10
        kept-old-versions 0
        vc-make-backup-files t
        create-lockfiles nil)
(auto-save-visited-mode 1)

(setopt savehist-file (expand-file-name "savehist" kittymacs-cache-dir))
(savehist-mode 1)
(global-so-long-mode 1)
(setopt multisession-directory (expand-file-name "multisession/" kittymacs-cache-dir))
(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 80
              tab-always-indent 'complete)
(setopt completion-cycle-threshold 3
        sentence-end-double-space nil
        global-mark-ring-max 8
        mark-ring-max 8)
(prefer-coding-system 'utf-8)
(global-subword-mode 1)
(global-visual-line-mode 1)
(use-package ws-butler
  :ensure t
  :hook ((text-mode prog-mode) . ws-butler-mode))
(setopt use-short-answers t
        use-file-dialog nil
        use-dialog-box nil
        ring-bell-function #'ignore
        display-line-numbers-type 'visual
        display-line-numbers-width-start t)
(blink-cursor-mode -1)
;; Builds without a window system (some CI Emacsen) have no fringe.el.
(when (fboundp 'fringe-mode)
  (fringe-mode '(1 . 0)))

(setopt scroll-step 1
        scroll-margin 3
        scroll-conservatively 101
        scroll-up-aggressively 0.01
        scroll-down-aggressively 0.01
        auto-window-vscroll nil
        hscroll-step 1
        hscroll-margin 1
        mouse-wheel-progressive-speed nil
        mouse-wheel-scroll-amount '(1 ((shift) . 2))
        mouse-autoselect-window t)
(context-menu-mode 1)

(setopt uniquify-buffer-name-style 'reverse
        uniquify-separator " • "
        uniquify-ignore-buffers-re "^\\*")

(setopt auto-revert-verbose nil
        auto-revert-interval 0.5
        revert-without-query '(".*")
        global-auto-revert-non-file-buffers t)
(global-auto-revert-mode 1)

;; A buffer that is not visiting a file still picks a major mode by its name.
;; This has to be a named function, not a lambda: `get-buffer-create' copies
;; the default into the new buffer's `major-mode' without calling it, and
;; everything that inspects a mode -- `derived-mode-p', `symbol-name', the
;; `derived-mode-parent' property -- expects to find a symbol there.
(defun kittymacs-guess-major-mode ()
  "Choose a major mode for this buffer, by file name or by buffer name."
  (if buffer-file-name
      (fundamental-mode)
    (let ((buffer-file-name (buffer-name)))
      (set-auto-mode))))
(setq-default major-mode #'kittymacs-guess-major-mode)
(fset 'undo-auto-amalgamate #'ignore)
(setopt undo-limit 67108864
        undo-strong-limit 100663296
        undo-outer-limit 1006632960)

(use-package vundo
  :ensure t
  :commands vundo
  :custom
  (vundo-glyph-alist vundo-unicode-symbols)
  (vundo-compact-display t)
  :config
  (with-eval-after-load 'meow
    (add-to-list 'meow-mode-state-list '(vundo-mode . motion))))
(winner-mode 1)
(windmove-default-keybindings)
(setopt window-divider-default-right-width 10
        window-divider-default-bottom-width 10)
(window-divider-mode 1)

(use-package ace-window
  :ensure t
  :commands (ace-window ace-swap-window aw-flip-window))

(use-package popper
  :ensure t
  :bind (("M-`" . popper-toggle)
         ("C-`" . popper-cycle)
         ("C-M-`" . popper-toggle-type))
  :custom
  (popper-window-height 20)
  (popper-group-function #'popper-group-by-directory)
  (popper-reference-buffers
   '("\\*Messages\\*"
     "Output\\*$"
     "\\*Async Shell Command\\*"
     help-mode
     compilation-mode))
  :init
  (popper-mode 1)
  (popper-echo-mode 1))
(defvar kittymacs-scratch-file (expand-file-name "scratch" kittymacs-cache-dir)
  "Where the *scratch* buffer's text is kept between sessions.")

(defun kittymacs--bury-scratch ()
  "Bury *scratch* instead of killing it."
  (if (eq (current-buffer) (get-buffer "*scratch*"))
      (progn (bury-buffer) nil)
    t))

(defun kittymacs--save-scratch ()
  "Save the text of *scratch* to `kittymacs-scratch-file'."
  (with-current-buffer (get-buffer-create "*scratch*")
    (write-region (point-min) (point-max) kittymacs-scratch-file nil 'quiet)))

(defun kittymacs--restore-scratch ()
  "Restore *scratch* from `kittymacs-scratch-file' when it exists."
  (when (file-exists-p kittymacs-scratch-file)
    (with-current-buffer (get-buffer-create "*scratch*")
      (erase-buffer)
      (insert-file-contents kittymacs-scratch-file))))

(add-hook 'kill-buffer-query-functions #'kittymacs--bury-scratch)
(add-hook 'after-init-hook #'kittymacs--restore-scratch)
(add-hook 'kill-emacs-hook #'kittymacs--save-scratch)
(run-with-idle-timer 300 t #'kittymacs--save-scratch)
(when (or window-system (daemonp))
  (require 'server)
  (setopt server-client-instructions nil)
  (unless (server-running-p)
    (server-start)))
(setopt switch-to-prev-buffer-skip-regexp "\\`[ *]")
(defun kittymacs-new-buffer (&optional frame)
  "Create an empty buffer; with FRAME (prefix argument), show it in a new frame."
  (interactive "P")
  (let ((buffer (generate-new-buffer "untitled")))
    (with-current-buffer buffer
      (funcall (default-value 'major-mode)))
    (if frame
        (display-buffer buffer '(display-buffer-pop-up-frame))
      (switch-to-buffer buffer))))

(defun kittymacs-copy-file-name ()
  "Show this buffer's file name and copy it to the kill ring."
  (interactive)
  (if-let* ((name (buffer-file-name)))
      (let ((short (abbreviate-file-name name)))
        (message "%s" short)
        (kill-new short))
    (user-error "This buffer is not visiting a file")))

(use-package rainbow-mode
  :ensure t
  :commands rainbow-mode)

(provide 'kittymacs-defaults)
;;; kittymacs-defaults.el ends here
