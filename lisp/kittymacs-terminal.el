;;; kittymacs-terminal.el --- The terminal -*- lexical-binding: t; -*-
;; Generated from literate/34-terminal.org; edit the Org source, then tangle.

;;; Commentary:
;; ghostel (https://github.com/dakra/ghostel) is the terminal emulator.  This
;; module sets its options, loads the integrations it ships for Eshell, comint,
;; Org, bookmarks, desktop, input methods and Consult, and bridges its five
;; input modes to Meow's states.

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)
(require 'kittymacs-platform)

(declare-function meow-insert-exit "meow-command" ())
(declare-function ghostel-alt-screen-p "ghostel" ())
(declare-function ghostel-send-key "ghostel" (key-name &optional mods))
(declare-function ghostel-semi-char-mode "ghostel" ())
(declare-function ghostel-readonly-enter "ghostel" ())
(declare-function ghostel "ghostel" (&optional arg))
(declare-function ghostel-project "ghostel" (&optional arg))
(declare-function ghostel--download-module "ghostel-module-install"
                  (dir &optional version latest-release))
(declare-function ghostel-module-compile "ghostel-module-install" ())
(declare-function package-desc-version "package" (desc))
(declare-function package-version-join "package" (vlist))
;; Without these a `let' would bind them lexically, and neither program would see
;; the name, when the first terminal of a session is on another machine.
(defvar ghostel-buffer-name)
(defvar eshell-buffer-name)
;; The Eshell fallback below: `kittymacs-shell' is loaded before this module
;; by `init.el', but this module does not require it.
(declare-function kittymacs-eshell-project "kittymacs-shell" ())

(defgroup kittymacs-terminal nil
  "The integrated terminal."
  :group 'kittymacs)
(defcustom kittymacs-terminal-module-directory
  (expand-file-name "ghostel/" kittymacs-var-dir)
  "Directory holding ghostel's native module.
Kept outside `package-user-dir' so upgrading the package never deletes a
module file this Emacs has already loaded."
  :type 'directory)

(defun kittymacs-terminal-module-installed-p ()
  "Return non-nil when ghostel's native module has been downloaded or built.
Nil also when this Emacs was built without dynamic module support, which
is what the terminal needs."
  (and module-file-suffix
       (file-exists-p
        (expand-file-name (concat "ghostel-module" module-file-suffix)
                          kittymacs-terminal-module-directory))))

(defun kittymacs-terminal--package-version ()
  "Return the installed ghostel package's version, or nil."
  (when-let* ((desc (cadr (assq 'ghostel (bound-and-true-p package-alist)))))
    (package-version-join (package-desc-version desc))))

(defun kittymacs-terminal--module-version ()
  "Return the version recorded beside the native module, or nil."
  (let ((file (expand-file-name "ghostel-module.version"
                                kittymacs-terminal-module-directory)))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (string-trim (buffer-string))))))

(defun kittymacs-terminal-module-current-p ()
  "Return non-nil when the native module is from the installed ghostel release.
Also non-nil when ghostel did not come from package.el, which has no
version to compare."
  (and (kittymacs-terminal-module-installed-p)
       (let ((package (kittymacs-terminal--package-version)))
         (or (null package)
             (equal package (kittymacs-terminal--module-version))))))

(defun kittymacs-terminal-install-module ()
  "Install the native module of the installed ghostel release.
Download that release's module; when it has none for this machine,
compile it from the package's own source.  Return non-nil when the
module is ready now, nil while it compiles."
  (interactive)
  (require 'ghostel-module-install)
  (let ((version (kittymacs-terminal--package-version)))
    (if (and version
             (ghostel--download-module
              (file-name-as-directory kittymacs-terminal-module-directory) version))
        (progn
          (message "ghostel: module %s installed%s" version
                   (if (featurep 'ghostel-module) "; restart Emacs to load it" ""))
          t)
      (message "ghostel: no prebuilt module for %s; compiling it from source"
               (or version "this package"))
      (ghostel-module-compile)
      nil)))
(defcustom kittymacs-terminal-ghostel
  (kittymacs-feature-p 'terminal)
  "Whether ghostel provides the terminal.
It follows the `terminal' feature.  That is off on Android, whose port is
commonly built without the dynamic module support ghostel needs.
`kittymacs-terminal-open' falls back to Eshell whenever this is nil."
  :type 'boolean)
(when kittymacs-terminal-ghostel
  ;; Install ghostel and consult-ghostel only from MELPA Stable, whose tagged
  ;; releases have prebuilt native modules.  Not `:pin', which runs
  ;; `package-initialize' when this file loads.
  (setopt package-pinned-packages
          (append '((ghostel . "melpa-stable") (consult-ghostel . "melpa-stable"))
                  (bound-and-true-p package-pinned-packages)))
  (use-package ghostel
    :ensure t
    :defer t
    :commands (ghostel ghostel-project ghostel-other ghostel-list-buffers
               ghostel-create ghostel-exec ghostel-compile ghostel-recompile)
    :custom
    (ghostel-module-directory kittymacs-terminal-module-directory)
    (ghostel-kill-buffer-on-exit t)
    (ghostel-query-before-killing 'auto)
    (ghostel-max-scrollback (* 5 1024 1024))
    (ghostel-scroll-on-input t)
    (ghostel-enable-osc52 nil)
    (ghostel-detect-password-prompts t)
    :config
    ;; Ghostel runs $SHELL, which native Windows does not set; follow the shell
    ;; the platform chapter picked instead of ghostel's /bin/sh fallback.
    (when (and (eq system-type 'windows-nt) (not (getenv "SHELL")))
      (setopt ghostel-shell (or explicit-shell-file-name shell-file-name)))

    ;; A shell inside the terminal can call these Emacs commands by name:
    ;;   ghostel_cmd find-file README.md
    ;;   ghostel_cmd magit-status
    ;; Only the listed commands can be reached, and every argument is a string.
    (dolist (command '(("magit-status" magit-status)
                       ("find-file-other-frame" find-file-other-frame)
                       ("treemacs-find-file" treemacs-find-file)))
      (add-to-list 'ghostel-eval-cmds command))

    ;; Integrations that ship with ghostel and only make sense once it is here:
    ;; ghostel: links in Org, bookmarks that reopen a terminal where it was,
    ;; terminals that survive a desktop session, and Lisp input methods
    ;; (Hangul, Quail) composing into the terminal rather than the buffer.
    (require 'ghostel-org nil t)
    (require 'ghostel-bookmark nil t)
    (require 'ghostel-desktop nil t)
    (when (require 'ghostel-ime nil t)
      (add-hook 'ghostel-mode-hook #'ghostel-ime-mode))))
(defun kittymacs-terminal--freeze ()
  "Freeze the terminal when Meow leaves Insert state.
The buffer becomes read-only, so Meow's grammar can select its output."
  (when (and (derived-mode-p 'ghostel-mode) (not buffer-read-only))
    (ghostel-readonly-enter)))

(defun kittymacs-terminal--thaw ()
  "Give the keyboard back to the terminal when Meow enters Insert state."
  (when (and (derived-mode-p 'ghostel-mode) buffer-read-only)
    (ghostel-semi-char-mode)))

(defun kittymacs-terminal--meow-setup ()
  "Keep Meow's state and ghostel's input mode in step in this buffer."
  (add-hook 'meow-insert-exit-hook #'kittymacs-terminal--freeze nil t)
  (add-hook 'meow-insert-enter-hook #'kittymacs-terminal--thaw nil t))

(add-hook 'ghostel-mode-hook #'kittymacs-terminal--meow-setup)
(defcustom kittymacs-terminal-escape 'auto
  "Where the escape key goes in a terminal while Meow is in Insert state.
`auto'     to the program while it is drawing a full-screen interface
           (vim, less, htop, a TUI agent), and to Meow otherwise.
`terminal' always to the program.
`meow'     always to Meow, leaving Insert state."
  :type '(choice (const :tag "Full-screen programs only" auto)
                 (const :tag "Always the terminal" terminal)
                 (const :tag "Always Meow" meow)))

(defvar-local kittymacs-terminal--escape nil
  "This buffer's override of `kittymacs-terminal-escape', or nil to follow it.")

(defun kittymacs-terminal--escape-target ()
  "Return `terminal' or `meow': where the escape key should go here."
  (pcase (or kittymacs-terminal--escape kittymacs-terminal-escape)
    ('terminal 'terminal)
    ('meow 'meow)
    (_ (if (ghostel-alt-screen-p) 'terminal 'meow))))

(defun kittymacs-terminal-escape-dwim ()
  "Leave Meow's Insert state, or send escape to a full-screen program."
  (interactive)
  (if (and (derived-mode-p 'ghostel-mode)
           (eq (kittymacs-terminal--escape-target) 'terminal))
      (ghostel-send-key "escape")
    (call-interactively #'meow-insert-exit)))

(defun kittymacs-terminal-toggle-escape ()
  "Switch where the escape key goes in this terminal, and say where."
  (interactive)
  (unless (derived-mode-p 'ghostel-mode)
    (user-error "This is not a terminal buffer"))
  (setq kittymacs-terminal--escape
        (if (eq (kittymacs-terminal--escape-target) 'terminal) 'meow 'terminal))
  (message "Escape %s"
           (if (eq kittymacs-terminal--escape 'terminal)
               "now goes to the program in the terminal"
             "now leaves Insert state")))
(with-eval-after-load 'meow
  (dolist (entry '((ghostel-mode . insert)
                   (ghostel-compile-view-mode . motion)))
    (add-to-list 'meow-mode-state-list entry))
  (keymap-set meow-insert-state-keymap "<escape>" #'kittymacs-terminal-escape-dwim))
(defun kittymacs-terminal--without-module (error)
  "Re-signal ERROR, or explain that the native module is missing."
  (if (kittymacs-terminal-module-installed-p)
      (signal (car error) (cdr error))
    (user-error "The terminal needs its native module: %s"
                (substitute-command-keys "\\[kittymacs-terminal-install-module]"))))

(defun kittymacs-terminal--ensure-module ()
  "Offer the module of the installed ghostel release when it is not there.
Signal `user-error' when the terminal cannot open yet."
  (when (and module-file-suffix
             (not (featurep 'ghostel-module))
             (not (kittymacs-terminal-module-current-p)))
    (unless (and (y-or-n-p
                  (format "The terminal needs ghostel %s's native module.  Install it? "
                          (or (kittymacs-terminal--package-version) "")))
                 (kittymacs-terminal-install-module))
      (user-error "Open the terminal once its module is installed: %s"
                  (substitute-command-keys "\\[kittymacs-terminal-install-module]")))))

(defun kittymacs-terminal--remote-name (program)
  "Return the name of PROGRAM's buffer on this buffer's machine, or nil if local.
This never connects."
  (when-let* ((remote (file-remote-p default-directory)))
    (format "*%s@%s*" program (substring remote 1 -1))))

(defun kittymacs-terminal-open (&optional arg)
  "Open a terminal on this buffer's machine.  With prefix ARG, open another one.
The first time, and after ghostel is upgraded, it offers the native module
of the installed release; declining leaves the terminal unavailable, so say
so in words.  Where ghostel
is not used at all, Eshell answers this key instead."
  (interactive "P")
  (if (not kittymacs-terminal-ghostel)
      (if-let* ((name (kittymacs-terminal--remote-name "eshell")))
          (let ((eshell-buffer-name name)) (eshell arg))
        (eshell arg))
    (kittymacs-terminal--ensure-module)
    (condition-case error
        (if-let* ((name (kittymacs-terminal--remote-name "ghostel")))
            (let ((ghostel-buffer-name name)) (ghostel arg))
          (ghostel arg))
      (void-function (kittymacs-terminal--without-module error)))))

(defun kittymacs-terminal-project (&optional arg)
  "Open a terminal at the current project's root.  ARG is passed through."
  (interactive "P")
  (if (not kittymacs-terminal-ghostel)
      (kittymacs-eshell-project)
    (kittymacs-terminal--ensure-module)
    (condition-case error (ghostel-project arg)
      (void-function (kittymacs-terminal--without-module error)))))

(keymap-set kittymacs-open-map "e" (cons "terminal" #'kittymacs-terminal-open))
(keymap-set kittymacs-open-map "p" (cons "project terminal" #'kittymacs-terminal-project))
(when kittymacs-terminal-ghostel
  (with-eval-after-load 'project
    (add-to-list 'project-switch-commands '(ghostel-project "Terminal" ?t) t))

  (use-package consult-ghostel
    :ensure t
    :after (ghostel consult)
    :demand t
    :bind (:map ghostel-semi-char-mode-map
           ("C-c h" . consult-ghostel-history))
    :config
    (consult-ghostel-mode 1))

  (keymap-set kittymacs-open-map "E" (cons "pick a terminal" #'consult-ghostel)))
(when kittymacs-terminal-ghostel
  (with-eval-after-load 'eshell
    (when (require 'ghostel-eshell nil t)
      (ghostel-eshell-visual-command-mode 1))))

(defun kittymacs-terminal--comint-colours ()
  "Render this comint buffer's output with ghostel's terminal parser."
  (when (and (kittymacs-terminal-module-installed-p)
             (require 'ghostel-comint nil t))
    (ghostel-comint-mode 1)))

(when kittymacs-terminal-ghostel
  (add-hook 'shell-mode-hook #'kittymacs-terminal--comint-colours))
(when kittymacs-terminal-ghostel
  ;; `ghostel-recompile' carries no autoload cookie, and `SPC m t' must work
  ;; before the terminal has ever been opened.
  (autoload 'ghostel-compile "ghostel-compile" "Run a command in a terminal." t)
  (autoload 'ghostel-recompile "ghostel-compile" "Re-run the last command." t)
  (with-eval-after-load 'ghostel
    (require 'ghostel-compile nil t))

  ;; `kittymacs-define-localleader' replaces a mode's whole map, and prog-mode's
  ;; belongs to the programming chapter, so add to the map it built.
  (with-eval-after-load 'kittymacs-programming
    (when-let* ((map (alist-get 'prog-mode kittymacs-localleader-alist)))
      (keymap-set map "t" (cons "compile in a terminal" #'ghostel-compile))
      (keymap-set map "T" (cons "recompile in a terminal" #'ghostel-recompile))
      (kittymacs-refresh-localleaders))))
(when kittymacs-terminal-ghostel
  (kittymacs-define-localleader 'ghostel-mode
    "i" (cons "type in the terminal" #'ghostel-semi-char-mode)
    "I" (cons "send every key (char mode)" #'ghostel-char-mode)
    "e" (cons "read live output" #'ghostel-emacs-mode)
    "C" (cons "freeze and copy" #'ghostel-copy-mode)
    "l" (cons "compose a line first" #'ghostel-line-mode)
    "y" (cons "copy everything" #'ghostel-copy-all)
    "P" (cons "paste" #'ghostel-paste)
    "c" (cons "clear" #'ghostel-clear)
    "K" (cons "clear scrollback" #'ghostel-clear-scrollback)
    "p" (cons "previous prompt" #'ghostel-previous-prompt)
    "n" (cons "next prompt" #'ghostel-next-prompt)
    "f" (cons "next link" #'ghostel-next-hyperlink)
    "F" (cons "previous link" #'ghostel-previous-hyperlink)
    "h" (cons "shell history" #'consult-ghostel-history)
    "b" (cons "another terminal" #'consult-ghostel)
    "q" (cons "send the next key literally" #'ghostel-send-next-key)
    "<escape>" (cons "where escape goes" #'kittymacs-terminal-toggle-escape)
    "M" (cons "install the native module" #'kittymacs-terminal-install-module)))

(provide 'kittymacs-terminal)
;;; kittymacs-terminal.el ends here
