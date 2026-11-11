;;; kittymacs-shell.el --- Eshell and the login environment -*- lexical-binding: t; -*-
;; Generated from literate/35-shells.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(declare-function consult-history "consult" (&optional history))
;; Eshell's, bound with `let' in `kittymacs-eshell-project'.
(defvar eshell-buffer-name)
;; early-init.el's, read after the login shell's PATH is imported.
(defvar kittymacs-launcher-path)

(setopt comint-pager "cat")
(remove-hook 'kill-buffer-query-functions #'process-kill-buffer-query-function)
(defun kittymacs--restore-launcher-path ()
  "Put back the directories `early-init.el' found and the shell import dropped.
They go at the end of `exec-path' and of the PATH that subprocesses see."
  (dolist (directory (reverse (bound-and-true-p kittymacs-launcher-path)))
    (unless (member directory exec-path)
      (setq exec-path (append exec-path (list directory)))
      (setenv "PATH" (concat (getenv "PATH") path-separator directory)))))

(when (kittymacs-feature-p 'shell-path)
  (use-package exec-path-from-shell
    :ensure t
    :custom
    (exec-path-from-shell-variables '("PATH" "MANPATH" "LANG" "NIX_PATH" "NIX_PROFILES"))
    (exec-path-from-shell-arguments (and (eq system-type 'darwin) '("-l")))
    :config
    (when (or window-system (daemonp))
      (exec-path-from-shell-initialize)
      (kittymacs--restore-launcher-path))))
(use-package envrc
  :ensure t
  :commands (envrc-allow envrc-deny envrc-reload envrc-show-log)
  :custom
  (envrc-async 1)
  :init
  (kittymacs-after-init #'envrc-global-mode 90))

(keymap-set kittymacs-project-map "E" (cons "direnv" (define-keymap
                                                       "a" (cons "allow .envrc" #'envrc-allow)
                                                       "d" (cons "deny .envrc" #'envrc-deny)
                                                       "r" (cons "reload" #'envrc-reload)
                                                       "l" (cons "log" #'envrc-show-log))))
(defcustom kittymacs-eshell-dir (expand-file-name "eshell/" kittymacs-etc-dir)
  "Directory for Eshell history, aliases and the directory ring."
  :type 'directory
  :group 'kittymacs)

(setopt eshell-directory-name kittymacs-eshell-dir
        eshell-history-file-name (expand-file-name "history" kittymacs-eshell-dir)
        eshell-last-dir-ring-file-name (expand-file-name "lastdir" kittymacs-eshell-dir)
        eshell-aliases-file (expand-file-name "alias" kittymacs-eshell-dir)
        eshell-buffer-maximum-lines 20000
        eshell-scroll-to-bottom-on-input 'all
        eshell-scroll-to-bottom-on-output 'all
        eshell-cmpl-ignore-case t
        eshell-history-size 10000
        eshell-hist-ignoredups t
        eshell-glob-case-insensitive t
        eshell-error-if-no-glob t
        eshell-destroy-buffer-when-process-dies t
        eshell-banner-message ""
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

(when (kittymacs-feature-p 'eshell-highlight)
  (use-package eshell-syntax-highlighting
    :ensure t
    :after eshell
    :config
    (eshell-syntax-highlighting-global-mode 1)))

(keymap-set kittymacs-open-map "s" (cons "eshell (project)" #'kittymacs-eshell-project))
(keymap-set kittymacs-open-map "S" (cons "eshell" #'eshell))
(defcustom kittymacs-gui-programs '("xdg-open" "xterm" "xclock" "xmessage")
  "Programs that open a window and may have no desktop entry.
In a graphical frame, a shell command you run that starts one of these,
or a program a desktop entry starts outside a terminal, starts detached
instead of making Emacs wait for it."
  :type '(repeat string)
  :group 'kittymacs)

(defvar kittymacs--shell-command-from-user nil
  "Non-nil while a command the user ran calls `shell-command' for them.")

(defun kittymacs--command-program (command)
  "Return the program the shell COMMAND starts, or nil if its words do not parse.
Leading `env' and NAME=VALUE words are skipped."
  (let ((words (condition-case nil (split-string-and-unquote command) (error nil))))
    (while (and words (or (equal (car words) "env")
                          (string-match-p "\\`[A-Za-z_][A-Za-z0-9_]*=" (car words))))
      (pop words))
    (car words)))

(defun kittymacs--desktop-entry-program (file)
  "Return the program the desktop entry FILE starts in a window of its own.
Nil for an entry that runs in a terminal, stays out of menus, or is not
an application."
  (with-temp-buffer
    (ignore-errors (insert-file-contents file))
    (goto-char (point-min))
    (when (re-search-forward "^\\[Desktop Entry\\][ \t]*$" nil t)
      (let ((end (save-excursion
                   (if (re-search-forward "^\\[" nil t) (match-beginning 0) (point-max))))
            fields)
        (while (re-search-forward "^\\([A-Za-z]+\\)[ \t]*=[ \t]*\\(.*\\)$" end t)
          (push (cons (match-string 1) (match-string 2)) fields))
        (and (equal (cdr (assoc "Type" fields)) "Application")
             (not (equal (cdr (assoc "Terminal" fields)) "true"))
             (not (equal (cdr (assoc "Hidden" fields)) "true"))
             (not (equal (cdr (assoc "NoDisplay" fields)) "true"))
             (cdr (assoc "Exec" fields))
             (kittymacs--command-program (cdr (assoc "Exec" fields))))))))

(defun kittymacs--desktop-entry-programs ()
  "Return the programs that desktop entries start in a window of their own."
  (let ((directories (cons (or (getenv "XDG_DATA_HOME") "~/.local/share")
                           (split-string (or (getenv "XDG_DATA_DIRS")
                                             "/usr/local/share:/usr/share")
                                         path-separator t)))
        programs)
    (dolist (directory directories)
      (let ((applications (expand-file-name "applications" directory)))
        (when (file-directory-p applications)
          (dolist (file (ignore-errors
                          (directory-files-recursively applications "\\.desktop\\'")))
            (when-let* ((program (kittymacs--desktop-entry-program file)))
              (push program programs))))))
    programs))

(defun kittymacs--program-file (program)
  "Return the file PROGRAM runs, with every link resolved, or nil."
  (when-let* ((file (if (file-name-absolute-p program) program (executable-find program))))
    (file-truename file)))

(defun kittymacs-gui-program-p (program)
  "Return non-nil if PROGRAM opens a window of its own.
It does when its name is in `kittymacs-gui-programs', or when a desktop
entry that does not run in a terminal starts it, by name or by file."
  (let ((name (file-name-nondirectory program))
        (file (kittymacs--program-file program)))
    (or (member name kittymacs-gui-programs)
        (seq-some (lambda (entry)
                    (or (equal (file-name-nondirectory entry) name)
                        (and file (equal (kittymacs--program-file entry) file))))
                  (kittymacs--desktop-entry-programs)))))

(defun kittymacs--shell-command-detach-p (command output-buffer from-user)
  "Return non-nil if `shell-command' should start COMMAND detached.
FROM-USER is non-nil when the user ran the command; OUTPUT-BUFFER is
`shell-command's own argument, non-nil when the output is wanted here."
  (and from-user
       (display-graphic-p)
       (not output-buffer)
       (not (file-remote-p default-directory))
       (not (string-match-p "&[ \t]*\\'" command))
       (when-let* ((program (kittymacs--command-program command)))
         (kittymacs-gui-program-p program))))

(declare-function kittymacs-exwm-launch "kittymacs-exwm" (command))

(defun kittymacs--shell-command-detach (original command &rest arguments)
  "Call ORIGINAL with COMMAND and ARGUMENTS, unless COMMAND is a graphical program.
A graphical program that the user asked for in a graphical frame starts
detached instead, through `kittymacs-exwm-launch' when it is defined."
  (if (not (kittymacs--shell-command-detach-p
            command (car arguments)
            (or kittymacs--shell-command-from-user (called-interactively-p 'any))))
      (apply original command arguments)
    (if (fboundp 'kittymacs-exwm-launch)
        (kittymacs-exwm-launch command)
      (let ((process-connection-type nil))
        (set-process-query-on-exit-flag (start-process-shell-command command nil command) nil)))
    (message "Started %s without waiting for it, because it opens a window"
             (kittymacs--command-program command))
    nil))

(defun kittymacs--shell-command-note-user (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS, telling `shell-command' whether the user ran it."
  (let ((kittymacs--shell-command-from-user (called-interactively-p 'any)))
    (apply original arguments)))

(advice-add 'shell-command :around #'kittymacs--shell-command-detach)
(dolist (command '(dired-do-shell-command dired-smart-shell-command))
  (advice-add command :around #'kittymacs--shell-command-note-user))
(with-eval-after-load 'meow
  (dolist (entry '((eshell-mode . insert) (shell-mode . insert) (term-mode . insert)))
    (add-to-list 'meow-mode-state-list entry)))

(kittymacs-define-localleader 'eshell-mode
  "c" (cons "clear" #'kittymacs-eshell-clear)
  "h" (cons "history" #'consult-history)
  "d" (and (kittymacs-feature-p 'directory-switch) (cons "directory" #'consult-dir))
  "p" (cons "previous prompt" #'eshell-previous-prompt)
  "n" (cons "next prompt" #'eshell-next-prompt)
  "i" (cons "insert" #'meow-insert)
  "?" (and (kittymacs-feature-p 'command-menus) (cons "menu" #'casual-eshell-tmenu)))

(provide 'kittymacs-shell)
;;; kittymacs-shell.el ends here
