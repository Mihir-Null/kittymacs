;;; kittymacs-platform.el --- Portable platform defaults -*- lexical-binding: t; -*-
;; Generated from literate/30-platform.org; edit the Org source, then tangle.

;;; Commentary:
;; Safe defaults for Windows, GNU/Linux/Nix, macOS and Android.  Prefer
;; discovery with `executable-find' and platform-provided home locations over
;; machine-specific paths.  The macOS section is distilled from Lambda-Emacs by
;; Colin McLear (`lem-setup-macos', GPL-3.0-or-later).

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
(defun kittymacs-android-p ()
  "Return non-nil when this Emacs is the Android port.
A function rather than a constant so the tests can exercise the Android
branches by binding `system-type' on any machine."
  (eq system-type 'android))

(defcustom kittymacs-termux-root
  (file-name-as-directory
   (or (getenv "TERMUX_ROOT") "/data/data/com.termux/files/usr/"))
  "Root of the Termux installation whose programs Emacs may run on Android.
Reachable only when Emacs and Termux share a user ID; otherwise Android
denies access and every lookup below quietly returns nil."
  :type 'directory)

(defun kittymacs-termux-program (name)
  "Return Termux's NAME program when Emacs is allowed to run it, else nil."
  (let ((program (expand-file-name (concat "bin/" name) kittymacs-termux-root)))
    (and (file-executable-p program) program)))

(defun kittymacs-termux-bin-directory ()
  "Return Termux's program directory, without a trailing slash, or nil."
  (let ((bin (expand-file-name "bin" kittymacs-termux-root)))
    (and (file-accessible-directory-p bin) bin)))
(defun kittymacs--first-executable (&rest programs)
  "Return the first executable found in PROGRAMS."
  (seq-some #'executable-find programs))
(defun kittymacs--skip-exec-path-from-shell (&rest _)
  "Keep the inherited process environment unchanged.
Used on native Windows, whose shell cannot evaluate POSIX syntax, and on
Android, where the system shell would report a `PATH' without Termux."
  nil)

(defun kittymacs--configure-exec-path-from-shell ()
  "Keep the inherited environment on Windows and Android; import Nix's elsewhere."
  (if (memq system-type '(windows-nt android))
      (advice-add #'exec-path-from-shell-initialize :override
                  #'kittymacs--skip-exec-path-from-shell)
    (setopt exec-path-from-shell-variables
            '("PATH" "MANPATH" "LANG" "NIX_PATH" "NIX_PROFILES"))))

(with-eval-after-load 'exec-path-from-shell
  (kittymacs--configure-exec-path-from-shell))
(defun kittymacs--windows-unix-tools ()
  "Return the directory holding Git for Windows' or MSYS2's Unix tools, or nil.
Magit's hunk refinement, Ediff and diff-hl ask for `diff', `diff3' and
`patch' by name, and Windows has none.  Git for Windows ships them
beside its own `git'; MSYS2 keeps them under `usr/bin'."
  (let ((git (file-name-directory (or (executable-find "git") ""))))
    (seq-find (lambda (dir) (file-executable-p (expand-file-name "diff.exe" dir)))
              (delq nil
                    (list
                     ;; git in Git/cmd or Git/bin: the tools are in Git/usr/bin.
                     ;; git found in Git/usr/bin itself: they are beside it.
                     (and git (expand-file-name "../usr/bin" git))
                     git
                     (expand-file-name "usr/bin" kittymacs-msys2-root))))))

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
             shell-command-switch "-c")))
    ;; Android has no /bin, so Emacs's compiled-in /bin/sh does not exist.
    ;; Termux's shells are preferred because they can see Termux's programs;
    ;; /system/bin/sh is always present, which makes it a real fallback
    ;; rather than a hopeful one.
    ('android
     (let ((shell (or (kittymacs-termux-program "bash")
                      (kittymacs-termux-program "sh")
                      "/system/bin/sh")))
       (setq-default shell-file-name shell)
       (setq explicit-shell-file-name shell
             shell-command-switch "-c"))))

  ;; Windows borrows Git's Unix tools.  They go last on `exec-path' so every
  ;; native program still wins, and `PATH' itself is left alone, so
  ;; subprocesses see no change.
  (when (eq system-type 'windows-nt)
    (when-let* ((tools (kittymacs--windows-unix-tools)))
      (add-to-list 'exec-path tools t)))

  (when (eq system-type 'darwin)
    (kittymacs--platform-apply-macos))
  (when (kittymacs-android-p)
    (kittymacs--platform-apply-android)))
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
  (keymap-global-set "s-Z" #'undo-redo)
  (keymap-global-set "s-q" #'kittymacs-delete-frame-or-quit)
  (keymap-global-set "C-s-f" #'toggle-frame-fullscreen)
  (add-hook 'enable-theme-functions #'kittymacs--macos-sync-titlebar)
  (kittymacs--macos-sync-titlebar))

(defun kittymacs--macos-auth-sources ()
  "Let `auth-source' read passwords from the macOS Keychain."
  (dolist (source '(macos-keychain-internet macos-keychain-generic))
    (add-to-list 'auth-sources source t)))

(with-eval-after-load 'auth-source
  (when (eq system-type 'darwin)
    (kittymacs--macos-auth-sources)))
;; Defined by the Android build; declared so the module byte-compiles cleanly
;; on every platform, as the NS variables above are.
(defvar android-pass-multimedia-buttons-to-system)
(defvar text-conversion-style)

(defcustom kittymacs-android-volume-keys nil
  "Who receives the volume keys on Android.
Nil leaves them to Emacs, which quits on two rapid presses of volume
down and is the only way to interrupt Emacs without a physical keyboard.
Non-nil returns them to the system so they adjust the volume."
  :type 'boolean)

(defcustom kittymacs-android-modal-text-conversion t
  "Whether Android's on-screen keyboard follows Meow's Insert state.
Android input methods edit the buffer directly rather than sending keys.
That suits Insert state and corrupts every other one, so when this is
non-nil the conversion style is suspended outside Insert state.  Set it
to nil to leave the input method alone."
  :type 'boolean)
(defvar-local kittymacs--android-text-conversion nil
  "The `text-conversion-style' suspended when Meow left Insert state.")

(defun kittymacs-android-suspend-text-conversion ()
  "Stop the on-screen keyboard editing this buffer outside Insert state."
  (when (and kittymacs-android-modal-text-conversion
             (fboundp 'set-text-conversion-style)
             (bound-and-true-p text-conversion-style))
    (setq kittymacs--android-text-conversion text-conversion-style)
    (set-text-conversion-style nil)))

(defun kittymacs-android-resume-text-conversion ()
  "Give the on-screen keyboard this buffer back on entering Insert state."
  (when (and kittymacs-android-modal-text-conversion
             (fboundp 'set-text-conversion-style)
             kittymacs--android-text-conversion)
    (set-text-conversion-style kittymacs--android-text-conversion)
    (setq kittymacs--android-text-conversion nil)))
(defun kittymacs--platform-apply-android ()
  "Apply the Android policy: Termux tools, locale, volume keys, keyboard."
  (when-let* ((bin (kittymacs-termux-bin-directory)))
    (unless (member bin (split-string (or (getenv "PATH") "") path-separator t))
      (setenv "PATH" (concat bin path-separator (getenv "PATH"))))
    (add-to-list 'exec-path bin)
    ;; Termux's programs know where their own libraries are.  An inherited
    ;; library path puts Android's system libraries of the same names first
    ;; and breaks them in ways that are very hard to read.
    (setenv "LD_LIBRARY_PATH" nil))
  (unless (getenv "LANG")
    (setenv "LANG" "en_US.UTF-8"))
  (setq android-pass-multimedia-buttons-to-system kittymacs-android-volume-keys)
  (add-hook 'meow-insert-exit-hook #'kittymacs-android-suspend-text-conversion)
  (add-hook 'meow-insert-enter-hook #'kittymacs-android-resume-text-conversion))
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
      ;; Android has no `xdg-open', and its document picker addresses files
      ;; by content URI rather than by path, so there is nothing to hand a
      ;; file manager.  Dired is the file manager that is actually here.
      ('android (dired directory))
      (_ (call-process "xdg-open" nil 0 nil directory)))))
(defun kittymacs-spell-checker ()
  "Return the spell-checker program to use, or nil."
  (or (executable-find "hunspell")
      (executable-find "aspell")
      (let ((msys2 (expand-file-name "ucrt64/bin/hunspell.exe" kittymacs-msys2-root)))
        (and (eq system-type 'windows-nt) (file-executable-p msys2) msys2))))

;; A checker that exists but has no dictionary must never break anything:
;; say so once and carry on.
(defvar kittymacs--spell-warned nil)
(defun kittymacs--spell-off (err)
  "Report once that spell checking is off because of ERR."
  (unless kittymacs--spell-warned
    (setq kittymacs--spell-warned t)
    (message "Spell checking off: %s" (error-message-string err))))

(defun kittymacs--configure-ispell ()
  "Point Ispell at the machine's checker; runs once, when Ispell loads.
Setting `ispell-program-name' with `setopt' runs its setter, which asks
Hunspell to list its dictionaries, and Hunspell needs a default
dictionary name from the environment even for that; Windows sets no
LANG.  So the environment comes first.  The whole thing is guarded
because an error here aborts the load of Ispell itself: Emacs then
restores Ispell's autoload stubs, and every later call reloads the
library, runs the checker and fails again."
  (when-let* ((program (kittymacs-spell-checker)))
    (condition-case err
        (progn
          (when (string-match-p "hunspell" program)
            (unless (getenv "DICTIONARY") (setenv "DICTIONARY" "en_US"))
            (when (string-prefix-p (expand-file-name kittymacs-msys2-root) program)
              (setenv "DICPATH" (expand-file-name "ucrt64/share/hunspell" kittymacs-msys2-root)))
            (setopt ispell-dictionary "en_US"))
          (setopt ispell-program-name program))
      (error (kittymacs--spell-off err)))))

(with-eval-after-load 'ispell (kittymacs--configure-ispell))

;; Enable Flyspell the same way: on any error say so once and carry on.
(defun kittymacs--flyspell (mode-function)
  "Enable Flyspell with MODE-FUNCTION when this machine has a spell checker.
A checker that fails is reported once instead of breaking the buffer."
  (when (kittymacs-spell-checker)
    (condition-case err
        (funcall mode-function)
      (error (kittymacs--spell-off err)))))
(defun kittymacs-flyspell-text () (kittymacs--flyspell #'flyspell-mode))
(defun kittymacs-flyspell-prog () (kittymacs--flyspell #'flyspell-prog-mode))

(add-hook 'text-mode-hook #'kittymacs-flyspell-text)
(add-hook 'prog-mode-hook #'kittymacs-flyspell-prog)
;; Do not force a font here. Inheriting the platform default makes first boot robust.
;; Fonts are chosen in the appearance chapter.

(provide 'kittymacs-platform)
;;; kittymacs-platform.el ends here
