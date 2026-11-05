;;; kittymacs-defaults.el --- Sane defaults -*- lexical-binding: t; -*-
;; Generated from literate/25-defaults.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:
(defgroup kittymacs nil
  "Options of the kittymacs Emacs configuration."
  :group 'emacs
  :prefix "kittymacs-")
;; The directories are defined in early-init.el (see the startup chapter);
;; these defaults only apply when a module is loaded on its own.
(defvar kittymacs-lisp-dir (expand-file-name "lisp/" user-emacs-directory))
(defvar kittymacs-var-dir (expand-file-name "var/" user-emacs-directory))
(defvar kittymacs-cache-dir (expand-file-name "cache/" kittymacs-var-dir))
(defvar kittymacs-etc-dir (expand-file-name "etc/" kittymacs-var-dir))

(dolist (directory (list kittymacs-var-dir kittymacs-cache-dir kittymacs-etc-dir))
  (make-directory directory t))

(setopt custom-file (expand-file-name "custom.el" kittymacs-etc-dir))
(setopt read-process-output-max (* 1024 1024)
        fast-but-imprecise-scrolling t
        redisplay-skip-fontification-on-input t
        highlight-nonselected-windows nil)
(setq process-adaptive-read-buffering nil
      inhibit-compacting-font-caches t
      bidi-inhibit-bpa t)
(setq-default bidi-paragraph-direction 'left-to-right)
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
(setopt auto-save-visited-interval 15)
(auto-save-visited-mode 1)

(setopt savehist-file (expand-file-name "savehist" kittymacs-cache-dir))
(savehist-mode 1)
(global-so-long-mode 1)
(setopt multisession-directory (expand-file-name "multisession/" kittymacs-cache-dir))
(setopt indent-tabs-mode nil
        tab-width 4
        fill-column 80
        tab-always-indent 'complete
        completion-cycle-threshold 3
        sentence-end-double-space nil
        global-mark-ring-max 8
        mark-ring-max 8)
(prefer-coding-system 'utf-8)
(global-subword-mode 1)
(global-visual-line-mode 1)
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
        auto-revert-interval 5
        auto-revert-avoid-polling t
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
(setopt major-mode #'kittymacs-guess-major-mode)
(fset 'undo-auto-amalgamate #'ignore)
(setopt undo-limit 16777216
        undo-strong-limit 25165824
        undo-outer-limit 134217728)
(winner-mode 1)
(windmove-default-keybindings)
(setopt window-divider-default-right-width 10
        window-divider-default-bottom-width 10)
(window-divider-mode 1)
(defcustom kittymacs-scratch-file (expand-file-name "scratch" kittymacs-cache-dir)
  "Where the *scratch* buffer's text is kept between sessions."
  :type 'file
  :group 'kittymacs)

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
  (when (file-readable-p kittymacs-scratch-file)
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

(provide 'kittymacs-defaults)
;;; kittymacs-defaults.el ends here
