;;; kittymacs-shell.el --- Eshell and Tramp -*- lexical-binding: t; -*-
;; Generated from literate/35-shells.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(declare-function consult-history "consult" (&optional history))

(setopt comint-pager "cat")
(setopt kill-buffer-query-functions
        (delq #'process-kill-buffer-query-function kill-buffer-query-functions))
(use-package exec-path-from-shell
  :ensure t
  :if (not (memq system-type '(windows-nt android)))
  :custom
  (exec-path-from-shell-arguments (and (eq system-type 'darwin) '("-l")))
  :config
  (when (or window-system (daemonp))
    (exec-path-from-shell-initialize)))
(defvar kittymacs-eshell-dir (expand-file-name "eshell/" kittymacs-etc-dir)
  "Directory for Eshell history, aliases and the directory ring.")

(setopt eshell-directory-name kittymacs-eshell-dir
        eshell-history-file-name (expand-file-name "history" kittymacs-eshell-dir)
        eshell-last-dir-ring-file-name (expand-file-name "lastdir" kittymacs-eshell-dir)
        eshell-aliases-file (expand-file-name "alias" kittymacs-eshell-dir)
        eshell-buffer-maximum-lines 20000
        eshell-scroll-to-bottom-on-input 'all
        eshell-scroll-to-bottom-on-output 'all
        eshell-list-files-after-cd nil
        eshell-cmpl-ignore-case t
        eshell-cmpl-cycle-completions t
        eshell-history-size 10000
        eshell-hist-ignoredups t
        eshell-glob-case-insensitive t
        eshell-error-if-no-glob t
        eshell-destroy-buffer-when-process-dies t
        eshell-banner-message ""
        eshell-highlight-prompt t
        eshell-prompt-regexp "^λ ")

(with-eval-after-load 'em-term
  (dolist (command '("htop" "top" "less" "more" "vim" "nano" "ssh" "tail"))
    (add-to-list 'eshell-visual-commands command))
  (add-to-list 'eshell-visual-subcommands '("git" "log" "diff" "show")))

(defun kittymacs--eshell-git-branch ()
  "Return the current Git branch for the prompt, or nil."
  (when (and (not (file-remote-p default-directory))
             (locate-dominating-file default-directory ".git"))
    (car (vc-git-branches))))

(defun kittymacs-eshell-prompt ()
  "A two-line prompt: directory and branch, then λ."
  (let ((branch (kittymacs--eshell-git-branch)))
    (concat "\n"
            (propertize (abbreviate-file-name (eshell/pwd)) 'face 'font-lock-constant-face)
            (when branch (propertize (format " (%s)" branch) 'face 'font-lock-comment-face))
            "\n"
            (propertize "λ" 'face 'font-lock-keyword-face)
            (propertize " " 'face 'default))))
(setopt eshell-prompt-function #'kittymacs-eshell-prompt)
(defvar kittymacs-eshell-aliases
  '(("g" "git --no-pager $*")
    ("gs" "magit-status")
    ("gd" "git diff --color $*")
    ("gl" "git log --oneline -20")
    ("l" "ls $*")
    ("la" "ls -la $*")
    ("ll" "ls -lah $*")
    ("d" "dired $1")
    ("ff" "find-file $1")
    ("e" "find-file $1")
    ("fr" "consult-recent-file")
    ("bb" "consult-buffer")
    ("pp" "project-switch-project")
    ("up" "eshell-up $1")
    ("q" "exit")
    ("x" "exit"))
  "Eshell aliases defined in Lisp.")

(with-eval-after-load 'em-alias
  (advice-add #'eshell-write-aliases-list :override #'ignore)
  (setq eshell-command-aliases-list (append eshell-command-aliases-list kittymacs-eshell-aliases)))

(defun eshell/z (&optional regexp)
  "Change to a previously visited directory chosen with completion.
With REGEXP, go to the most recent directory matching it."
  (let ((dirs (delete-dups (mapcar #'abbreviate-file-name (ring-elements eshell-last-dir-ring)))))
    (eshell/cd (if regexp
                   (eshell-find-previous-directory regexp)
                 (completing-read "Directory: " dirs nil t)))))

(defun kittymacs-eshell-clear ()
  "Clear the Eshell buffer."
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (eshell-send-input)))

(defun kittymacs-eshell-project ()
  "Open an Eshell for the current project, or for this directory."
  (interactive)
  (require 'eshell)
  (let* ((root (if-let* ((project (project-current))) (project-root project) default-directory))
         (name (file-name-nondirectory (directory-file-name root)))
         (eshell-buffer-name (format "*eshell: %s*" name))
         (default-directory root))
    (eshell)))

(defun kittymacs--eshell-setup ()
  "Per-buffer Eshell settings."
  (keymap-local-set "C-l" #'kittymacs-eshell-clear)
  (setq-local imenu-generic-expression '(("Prompt" "^λ \\(.*\\)" 1)))
  (hl-line-mode -1)
  (visual-line-mode 1))
(add-hook 'eshell-mode-hook #'kittymacs--eshell-setup)

(use-package eshell-syntax-highlighting
  :ensure t
  :after eshell
  :config
  (eshell-syntax-highlighting-global-mode 1))

(use-package eshell-up
  :ensure t
  :commands eshell-up
  :config
  (defalias 'eshell/up #'eshell-up))

(use-package esh-help
  :ensure t
  :after eshell
  :config
  (setup-esh-help-eldoc))

(use-package pcmpl-args :ensure t :after eshell)
(use-package pcomplete-extension :ensure t :after eshell)
(setopt tramp-persistency-file-name (expand-file-name "tramp" kittymacs-cache-dir)
        tramp-default-method "ssh"
        tramp-copy-size-limit nil
        tramp-use-ssh-controlmaster-options nil)
(with-eval-after-load 'meow
  (dolist (entry '((eshell-mode . insert) (shell-mode . insert) (term-mode . insert)))
    (add-to-list 'meow-mode-state-list entry)))

(kittymacs-define-localleader 'eshell-mode
  "c" (cons "clear" #'kittymacs-eshell-clear)
  "h" (cons "history" #'consult-history)
  "d" (cons "directory" #'consult-dir)
  "p" (cons "previous prompt" #'eshell-previous-prompt)
  "n" (cons "next prompt" #'eshell-next-prompt)
  "i" (cons "insert" #'meow-insert)
  "?" (cons "menu" #'casual-eshell-tmenu))

(provide 'kittymacs-shell)
;;; kittymacs-shell.el ends here
