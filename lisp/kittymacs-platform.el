;;; kittymacs-platform.el --- Portable platform defaults -*- lexical-binding: t; -*-
;; Generated from literate/30-platform.org; edit the Org source, then tangle.

;;; Commentary:
;; Safe defaults for Windows, GNU/Linux/Nix, and macOS.  Prefer discovery with
;; `executable-find' and platform-provided home locations over machine-specific
;; paths.  The macOS section is distilled from Lambda-Emacs by Colin McLear
;; (`lem-setup-macos', GPL-3.0-or-later).

;;; Code:

(require 'seq)
(require 'subr-x)
(defgroup kittymacs-platform nil
  "Portable defaults for the Lambda learning configuration."
  :group 'kittymacs)
(defun kittymacs--user-home-directory ()
  "Return the user's ordinary home directory for configuration defaults.
On native Windows, Emacs may define HOME as AppData/Roaming, so prefer
USERPROFILE for user-owned projects and documents."
  (file-name-as-directory
   (if (eq system-type 'windows-nt)
       (or (getenv "USERPROFILE") (expand-file-name "~"))
     (expand-file-name "~"))))
(defcustom kittymacs-project-directory
  (expand-file-name "Projects/" (kittymacs--user-home-directory))
  "Default place to look for projects."
  :type 'directory)
(defcustom kittymacs-org-directory
  (expand-file-name "Documents/org/" (kittymacs--user-home-directory))
  "Portable starter Org directory."
  :type 'directory)
(defcustom kittymacs-msys2-root
  (file-name-as-directory (or (getenv "MSYS2_ROOT") "C:/msys64/"))
  "Root directory of the MSYS2 installation on Windows."
  :type 'directory)
(defun kittymacs--first-executable (&rest programs)
  "Return the first executable found in PROGRAMS."
  (seq-some #'executable-find programs))
(defun kittymacs--skip-exec-path-from-shell-on-windows (&rest _)
  "Keep native Windows Emacs's inherited process environment unchanged."
  nil)
(defun kittymacs-platform-apply ()
  "Apply the currently configured portable platform defaults."
  ;; Choose a usable shell without assuming a username, Homebrew prefix, Nix profile,
  ;; or conventional Unix filesystem on Windows.
  (pcase system-type
    ('windows-nt
     (cond
      ((executable-find "pwsh.exe")
       (setq-default shell-file-name (executable-find "pwsh.exe"))
       (setq explicit-shell-file-name (executable-find "pwsh.exe")
             shell-command-switch "-Command"))
      ((executable-find "powershell.exe")
       (setq-default shell-file-name (executable-find "powershell.exe"))
       (setq explicit-shell-file-name (executable-find "powershell.exe")
             shell-command-switch "-Command"))
      ((executable-find "cmd.exe")
       (setq-default shell-file-name (executable-find "cmd.exe"))
       (setq explicit-shell-file-name (executable-find "cmd.exe")
             shell-command-switch "/c"))))
    ('darwin
     (when-let ((shell (kittymacs--first-executable "zsh" "bash" "sh")))
       (setq-default shell-file-name shell)
       (setq explicit-shell-file-name shell
             shell-command-switch "-c")))
    ('gnu/linux
     (when-let ((shell (kittymacs--first-executable "zsh" "bash" "sh")))
       (setq-default shell-file-name shell)
       (setq explicit-shell-file-name shell
             shell-command-switch "-c"))))

  ;; Lambda configures exec-path-from-shell.  It supports POSIX shells, so native
  ;; Windows keeps the environment inherited from Windows instead of asking
  ;; PowerShell to evaluate Unix `printf' syntax.  Linux/macOS retain Lambda's
  ;; intended login-shell import without assuming a particular Nix profile path.
  (if (eq system-type 'windows-nt)
      (with-eval-after-load 'exec-path-from-shell
        (unless (advice-member-p
                 #'kittymacs--skip-exec-path-from-shell-on-windows
                 #'exec-path-from-shell-initialize)
          (advice-add #'exec-path-from-shell-initialize :override
                      #'kittymacs--skip-exec-path-from-shell-on-windows)))
    (with-eval-after-load 'exec-path-from-shell
      (setopt exec-path-from-shell-variables
              '("PATH" "MANPATH" "LANG" "NIX_PATH" "NIX_PROFILES"))))

  (when (eq system-type 'darwin)
    (kittymacs--platform-apply-macos)))
;; Defined by the Cocoa build and by auth-source; declared so the module
;; byte-compiles cleanly on every platform.
(defvar ns-use-native-fullscreen)
(defvar auth-sources)

(defcustom kittymacs-macos-modifiers
  '((ns-command-modifier . super)
    (ns-option-modifier . meta)
    (ns-right-option-modifier . none))
  "How the macOS modifier keys map to Emacs modifiers.
Each entry pairs an NS modifier variable with the modifier it produces:
`meta', `super', `hyper', `control', `alt', or `none' to leave the key
to macOS.  Applied by `kittymacs-platform-apply' after `private.el'."
  :type '(alist :key-type symbol :value-type symbol))
(defun kittymacs--macos-trash (path)
  "Move PATH to the macOS Trash with the `trash' command-line tool."
  (let ((status (call-process "trash" nil nil nil (expand-file-name path))))
    (unless (eql status 0)
      (error "Failed to move %s to the Trash (exit code %s)" path status))))

(defun kittymacs--macos-configure-trash ()
  "Send deleted files to the Trash by the best available means.
Return the means chosen: `native' when this Emacs moves files to the Trash
itself, `trash-command' for the `trash' tool, or `directory' for ~/.Trash."
  (setq delete-by-moving-to-trash t)
  (cond ((fboundp 'system-move-file-to-trash) 'native)
        ((executable-find "trash")
         (setq trash-directory nil)
         (defalias 'system-move-file-to-trash #'kittymacs--macos-trash)
         'trash-command)
        (t (setq trash-directory "~/.Trash")
           'directory)))

(defun kittymacs-delete-frame-or-quit ()
  "Close this frame when other frames remain; from the last one, quit Emacs."
  (interactive)
  (if (cdr (frame-list))
      (delete-frame)
    (save-buffers-kill-emacs)))

(defun kittymacs--macos-sync-titlebar (&rest _)
  "Give every frame's title bar the theme's light or dark appearance."
  (when (display-graphic-p)
    (let* ((background (face-background 'default nil (selected-frame)))
           (rgb (and (stringp background) (color-name-to-rgb background)))
           (appearance (if (and rgb (color-dark-p rgb)) 'dark 'light)))
      (setf (alist-get 'ns-appearance default-frame-alist) appearance)
      (dolist (frame (frame-list))
        (when (display-graphic-p frame)
          (set-frame-parameter frame 'ns-appearance appearance))))))
(defun kittymacs--platform-apply-macos ()
  "Apply the macOS policy: modifiers, Trash, locale, Keychain, keys, title bar."
  (pcase-dolist (`(,variable . ,modifier) kittymacs-macos-modifiers)
    (set variable modifier))
  (setq ns-use-native-fullscreen nil)
  (unless (getenv "LANG")
    (setenv "LANG" "en_US.UTF-8"))
  (kittymacs--macos-configure-trash)
  (with-eval-after-load 'auth-source
    (dolist (source '(macos-keychain-internet macos-keychain-generic))
      (add-to-list 'auth-sources source t)))
  (keymap-global-set "s-Z" #'undo-redo)
  (keymap-global-set "s-q" #'kittymacs-delete-frame-or-quit)
  (keymap-global-set "C-s-f" #'toggle-frame-fullscreen)
  (add-hook 'enable-theme-functions #'kittymacs--macos-sync-titlebar)
  (kittymacs--macos-sync-titlebar))
(defun kittymacs-reveal-in-file-manager (&optional file)
  "Show FILE in the desktop file manager, selected where the manager allows.
FILE defaults to this buffer's file, the file at point in Dired, or the
current directory."
  (interactive)
  (let* ((file (expand-file-name
                (or file
                    buffer-file-name
                    (and (derived-mode-p 'dired-mode)
                         (fboundp 'dired-get-filename)
                         (dired-get-filename nil t))
                    default-directory)))
         (directory (if (file-directory-p file)
                        (file-name-as-directory file)
                      (file-name-directory file))))
    (pcase system-type
      ('darwin (call-process "open" nil 0 nil "-R" file))
      ;; Explorer wants backslashes; `convert-standard-filename' would do
      ;; it, but only on a Windows build, and the tests run this branch
      ;; anywhere by binding `system-type'.
      ('windows-nt (call-process "explorer.exe" nil 0 nil
                                 (concat "/select," (subst-char-in-string ?/ ?\\ file))))
      (_ (call-process "xdg-open" nil 0 nil directory)))))
(defun kittymacs-spell-checker ()
  "Return the spell-checker program to use, or nil."
  (or (executable-find "hunspell")
      (executable-find "aspell")
      (let ((msys2 (expand-file-name "ucrt64/bin/hunspell.exe" kittymacs-msys2-root)))
        (and (eq system-type 'windows-nt) (file-executable-p msys2) msys2))))

(with-eval-after-load 'ispell
  (when-let* ((program (kittymacs-spell-checker)))
    (setopt ispell-program-name program)
    (when (string-match-p "hunspell" program)
      ;; Hunspell needs a default dictionary name from the environment even
      ;; to list its dictionaries; Windows sets no LANG, so name it here.
      (unless (getenv "DICTIONARY") (setenv "DICTIONARY" "en_US"))
      (setopt ispell-dictionary "en_US")
      (when (string-prefix-p (expand-file-name kittymacs-msys2-root) program)
        (setenv "DICPATH" (expand-file-name "ucrt64/share/hunspell" kittymacs-msys2-root))))))

;; A checker that exists but has no dictionary must never break startup:
;; enable Flyspell, and on any error say so once and carry on.
(defvar kittymacs--spell-warned nil)
(defun kittymacs--flyspell (mode-function)
  "Enable Flyspell with MODE-FUNCTION, reporting a broken checker instead of failing."
  (condition-case err
      (funcall mode-function)
    (error (unless kittymacs--spell-warned
             (setq kittymacs--spell-warned t)
             (message "Spell checking off: %s" (error-message-string err))))))
(defun kittymacs-flyspell-text () (kittymacs--flyspell #'flyspell-mode))
(defun kittymacs-flyspell-prog () (kittymacs--flyspell #'flyspell-prog-mode))

(when (kittymacs-spell-checker)
  (add-hook 'text-mode-hook #'kittymacs-flyspell-text)
  (add-hook 'prog-mode-hook #'kittymacs-flyspell-prog))
;; Do not force a font here. Inheriting the platform default makes first boot robust.
;; Fonts are chosen in the appearance chapter.

(provide 'kittymacs-platform)
;;; kittymacs-platform.el ends here
