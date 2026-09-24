;;; kittymacs-platform-tests.el --- Platform policy per operating system -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-platform-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages: the platform module depends only on Emacs's own libraries.
;; `system-type' is a plain variable, so each test binds it to the platform it
;; exercises and the branches for every operating system run on any machine.
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "../lisp/" (file-name-directory load-file-name)))
(require 'kittymacs-platform)

;; Variables that only exist on macOS builds or once shell.el is loaded must
;; be declared special here, or `let' would bind them lexically and the
;; module's `setq' would miss them.
(defvar explicit-shell-file-name)
(defvar ns-command-modifier)
(defvar ns-option-modifier)
(defvar ns-right-option-modifier)
(defvar ns-use-native-fullscreen)
(defvar meow-insert-enter-hook)
(defvar meow-insert-exit-hook)
(defvar android-pass-multimedia-buttons-to-system)
(defvar auth-sources)

(defmacro kittymacs-platform-test-with (system executables &rest body)
  "Run BODY as SYSTEM with only EXECUTABLES findable and no global side effects."
  (declare (indent 2))
  `(let ((system-type ,system)
         (process-environment (copy-sequence process-environment))
         (default-frame-alist (copy-sequence default-frame-alist))
         (enable-theme-functions nil)
         (auth-sources (bound-and-true-p auth-sources))
         (saved-global-map (current-global-map))
         shell-file-name explicit-shell-file-name shell-command-switch
         delete-by-moving-to-trash trash-directory
         ns-command-modifier ns-option-modifier ns-right-option-modifier
         ns-use-native-fullscreen)
     (cl-letf (((symbol-function 'executable-find)
                (lambda (name &rest _)
                  (and (member name ,executables) (concat "/mock/bin/" name)))))
       (unwind-protect
           (progn (use-global-map (make-sparse-keymap))
                  ,@body)
         (use-global-map saved-global-map)))))

(ert-deftest kittymacs-platform-macos-sets-shell-and-modifiers ()
  (kittymacs-platform-test-with 'darwin '("zsh")
    (kittymacs-platform-apply)
    (should (equal shell-command-switch "-c"))
    (should (equal explicit-shell-file-name "/mock/bin/zsh"))
    (should (eq ns-command-modifier 'super))
    (should (eq ns-option-modifier 'meta))
    (should (eq ns-right-option-modifier 'none))
    (should-not ns-use-native-fullscreen)
    (should (eq (keymap-lookup (current-global-map) "s-Z") #'undo-redo))
    (should (eq (keymap-lookup (current-global-map) "s-q") #'kittymacs-delete-frame-or-quit))
    (should (eq (keymap-lookup (current-global-map) "C-s-f") #'toggle-frame-fullscreen))
    (should (memq #'kittymacs--macos-sync-titlebar enable-theme-functions))))

(ert-deftest kittymacs-platform-macos-reads-passwords-from-the-keychain ()
  (kittymacs-platform-test-with 'darwin '()
    (setq auth-sources '("~/.authinfo.gpg"))
    (kittymacs--macos-auth-sources)
    (kittymacs--macos-auth-sources)
    (should (equal auth-sources '("~/.authinfo.gpg"
                                  macos-keychain-internet
                                  macos-keychain-generic)))))

(defun kittymacs-platform-test-after-load-forms ()
  "Return how many forms are waiting in `after-load-alist'."
  (apply #'+ (mapcar (lambda (entry) (length (cdr entry))) after-load-alist)))

(ert-deftest kittymacs-platform-apply-registers-nothing-globally ()
  ;; `with-eval-after-load' registers its body for good, so a policy
  ;; function that used it would queue another copy on every call.
  (dolist (system '(darwin windows-nt gnu/linux android))
    (kittymacs-platform-test-with system '("zsh" "pwsh.exe")
      (let ((before (kittymacs-platform-test-after-load-forms)))
        (kittymacs-platform-apply)
        (kittymacs-platform-apply)
        (should (= (kittymacs-platform-test-after-load-forms) before))))))

(ert-deftest kittymacs-platform-macos-modifiers-are-customizable ()
  (kittymacs-platform-test-with 'darwin '("zsh")
    (let ((kittymacs-macos-modifiers '((ns-command-modifier . meta)
                                     (ns-option-modifier . super))))
      (kittymacs-platform-apply)
      (should (eq ns-command-modifier 'meta))
      (should (eq ns-option-modifier 'super))
      ;; Not listed, so untouched.
      (should-not ns-right-option-modifier))))

(ert-deftest kittymacs-platform-macos-sets-a-utf8-locale-only-when-missing ()
  (kittymacs-platform-test-with 'darwin '("zsh")
    (setenv "LANG" nil)
    (kittymacs-platform-apply)
    (should (equal (getenv "LANG") "en_US.UTF-8")))
  (kittymacs-platform-test-with 'darwin '("zsh")
    (setenv "LANG" "de_DE.UTF-8")
    (kittymacs-platform-apply)
    (should (equal (getenv "LANG") "de_DE.UTF-8"))))

(ert-deftest kittymacs-platform-macos-trash-prefers-native-then-tool-then-directory ()
  (kittymacs-platform-test-with 'darwin '("trash")
    (cl-letf (((symbol-function 'system-move-file-to-trash) #'ignore))
      (should (eq (kittymacs--macos-configure-trash) 'native))
      (should delete-by-moving-to-trash)))
  (kittymacs-platform-test-with 'darwin '("trash")
    (cl-letf (((symbol-function 'system-move-file-to-trash) nil))
      (should (eq (kittymacs--macos-configure-trash) 'trash-command))
      (should (eq (symbol-function 'system-move-file-to-trash) #'kittymacs--macos-trash))
      (should-not trash-directory)))
  (kittymacs-platform-test-with 'darwin '()
    (cl-letf (((symbol-function 'system-move-file-to-trash) nil))
      (should (eq (kittymacs--macos-configure-trash) 'directory))
      (should (equal trash-directory "~/.Trash"))
      (should delete-by-moving-to-trash))))

(ert-deftest kittymacs-platform-macos-titlebar-sync-is-quiet-without-a-display ()
  (kittymacs-platform-test-with 'darwin '()
    (cl-letf (((symbol-function 'display-graphic-p) #'ignore))
      (should-not (kittymacs--macos-sync-titlebar))
      (should-not (assq 'ns-appearance default-frame-alist)))))

(ert-deftest kittymacs-platform-windows-leaves-macos-settings-alone ()
  (kittymacs-platform-test-with 'windows-nt '("pwsh.exe")
    (kittymacs-platform-apply)
    (should (equal shell-command-switch "-Command"))
    (should-not ns-command-modifier)
    (should-not delete-by-moving-to-trash)
    (should-not (keymap-lookup (current-global-map) "s-q"))))

(ert-deftest kittymacs-platform-linux-leaves-macos-settings-alone ()
  (kittymacs-platform-test-with 'gnu/linux '("bash")
    (kittymacs-platform-apply)
    (should (equal shell-command-switch "-c"))
    (should (equal explicit-shell-file-name "/mock/bin/bash"))
    (should-not ns-command-modifier)
    (should-not (keymap-lookup (current-global-map) "s-q"))))

(defun kittymacs-platform-test-reveal (system file)
  "Return the command `kittymacs-reveal-in-file-manager' runs for FILE on SYSTEM."
  (let ((system-type system) (buffer-file-name file) command)
    (cl-letf (((symbol-function 'call-process)
               (lambda (program &rest args) (setq command (cons program (nthcdr 3 args))) 0))
              ((symbol-function 'file-directory-p) #'ignore))
      (kittymacs-reveal-in-file-manager)
      command)))

(ert-deftest kittymacs-platform-reveal-uses-each-desktops-file-manager ()
  (let ((file (expand-file-name "notes/todo.org" temporary-file-directory)))
    (should (equal (kittymacs-platform-test-reveal 'darwin file)
                   (list "open" "-R" file)))
    (should (equal (kittymacs-platform-test-reveal 'windows-nt file)
                   (list "explorer.exe" (concat "/select," (subst-char-in-string ?/ ?\\ file)))))
    (should (equal (kittymacs-platform-test-reveal 'gnu/linux file)
                   (list "xdg-open" (file-name-directory file))))))


;;; Android.  The port's `system-type' is `android', so every branch above
;;; falls through to its default unless it names the platform.  Termux lives
;;; in another application's data directory, readable only when the two share
;;; a user ID, so the tests cover both the paired and the unpaired device.

(defmacro kittymacs-platform-test-android (termux &rest body)
  "Run BODY as Android with TERMUX programs installed under Termux's root.
TERMUX is a list of program names; nil means Termux is not reachable,
which is what an unpaired installation looks like from Emacs."
  (declare (indent 1))
  `(kittymacs-platform-test-with 'android '()
     (let ((kittymacs-termux-root "/data/data/com.termux/files/usr/")
           (kittymacs-android-volume-keys nil)
           (kittymacs-android-modal-text-conversion t)
           (exec-path (copy-sequence exec-path))
           (programs ,termux)
           android-pass-multimedia-buttons-to-system
           meow-insert-enter-hook meow-insert-exit-hook)
       (cl-letf (((symbol-function 'file-executable-p)
                  (lambda (path)
                    (and (string-prefix-p kittymacs-termux-root path)
                         (member (file-name-nondirectory path) programs)
                         t)))
                 ((symbol-function 'file-accessible-directory-p)
                  (lambda (path)
                    (and (string-prefix-p kittymacs-termux-root path)
                         (consp programs)))))
         ,@body))))

(ert-deftest kittymacs-platform-android-prefers-termux-shell ()
  (kittymacs-platform-test-android '("bash" "sh")
    (kittymacs-platform-apply)
    (should (equal explicit-shell-file-name
                   "/data/data/com.termux/files/usr/bin/bash"))
    (should (equal shell-command-switch "-c")))
  ;; Only `sh': Termux is paired but minimal.
  (kittymacs-platform-test-android '("sh")
    (kittymacs-platform-apply)
    (should (equal explicit-shell-file-name
                   "/data/data/com.termux/files/usr/bin/sh"))))

(ert-deftest kittymacs-platform-android-falls-back-to-the-system-shell ()
  ;; No Termux at all.  Emacs's compiled-in /bin/sh does not exist on
  ;; Android, so a fallback that is always present is the point.
  (kittymacs-platform-test-android nil
    (kittymacs-platform-apply)
    (should (equal explicit-shell-file-name "/system/bin/sh"))
    (should (equal shell-file-name "/system/bin/sh"))
    (should (equal shell-command-switch "-c"))))

(ert-deftest kittymacs-platform-android-puts-termux-first-on-the-path ()
  (kittymacs-platform-test-android '("bash" "git" "rg")
    (setenv "PATH" "/system/bin")
    (setenv "LD_LIBRARY_PATH" "/vendor/lib64")
    (kittymacs-platform-apply)
    (let ((bin "/data/data/com.termux/files/usr/bin"))
      (should (equal (getenv "PATH") (concat bin path-separator "/system/bin")))
      (should (equal (car exec-path) bin))
      ;; Termux's programs find their own libraries; an inherited library
      ;; path interposes Android's system libraries of the same names.
      (should-not (getenv "LD_LIBRARY_PATH"))
      ;; Applying twice must not stack the entry up.
      (kittymacs-platform-apply)
      (should (equal (getenv "PATH") (concat bin path-separator "/system/bin"))))))

(ert-deftest kittymacs-platform-android-leaves-the-path-alone-without-termux ()
  (kittymacs-platform-test-android nil
    (setenv "PATH" "/system/bin")
    (setenv "LD_LIBRARY_PATH" "/vendor/lib64")
    (kittymacs-platform-apply)
    (should (equal (getenv "PATH") "/system/bin"))
    (should (equal (getenv "LD_LIBRARY_PATH") "/vendor/lib64"))))

(ert-deftest kittymacs-platform-android-keeps-its-inherited-environment ()
  ;; The POSIX importer would succeed here and report a `PATH' without
  ;; Termux, so it is overridden exactly as it is on Windows.
  (kittymacs-platform-test-android '("bash")
    (defalias 'exec-path-from-shell-initialize #'ignore)
    (unwind-protect
        (progn
          (kittymacs--configure-exec-path-from-shell)
          (should (advice-member-p #'kittymacs--skip-exec-path-from-shell
                                   #'exec-path-from-shell-initialize)))
      (fmakunbound 'exec-path-from-shell-initialize))))

(ert-deftest kittymacs-platform-android-sets-a-utf8-locale-only-when-missing ()
  (kittymacs-platform-test-android nil
    (setenv "LANG" nil)
    (kittymacs-platform-apply)
    (should (equal (getenv "LANG") "en_US.UTF-8")))
  (kittymacs-platform-test-android nil
    (setenv "LANG" "de_DE.UTF-8")
    (kittymacs-platform-apply)
    (should (equal (getenv "LANG") "de_DE.UTF-8"))))

(ert-deftest kittymacs-platform-android-volume-keys-are-customizable ()
  (kittymacs-platform-test-android nil
    (kittymacs-platform-apply)
    ;; Default: Emacs keeps them, so quitting without a keyboard still works.
    (should-not android-pass-multimedia-buttons-to-system))
  (kittymacs-platform-test-android nil
    (let ((kittymacs-android-volume-keys t))
      (kittymacs-platform-apply)
      (should android-pass-multimedia-buttons-to-system))))

(ert-deftest kittymacs-platform-android-leaves-macos-settings-alone ()
  (kittymacs-platform-test-android '("bash")
    (kittymacs-platform-apply)
    (should-not ns-command-modifier)
    (should-not delete-by-moving-to-trash)
    (should-not (keymap-lookup (current-global-map) "s-q"))))

(ert-deftest kittymacs-platform-android-follows-meow-with-text-conversion ()
  (kittymacs-platform-test-android nil
    (kittymacs-platform-apply)
    (should (memq #'kittymacs-android-suspend-text-conversion meow-insert-exit-hook))
    (should (memq #'kittymacs-android-resume-text-conversion meow-insert-enter-hook)))
  ;; Leaving Insert state takes the buffer away from the input method, and
  ;; entering it hands back the style that was in force.
  (let (style)
    (cl-letf (((symbol-function 'set-text-conversion-style)
               (lambda (value) (setq style value))))
      (with-temp-buffer
        (setq-local text-conversion-style 'action)
        (setq style 'action)
        (kittymacs-android-suspend-text-conversion)
        (should-not style)
        (should (eq kittymacs--android-text-conversion 'action))
        (kittymacs-android-resume-text-conversion)
        (should (eq style 'action))
        (should-not kittymacs--android-text-conversion)))))

(ert-deftest kittymacs-platform-android-text-conversion-can-be-turned-off ()
  (let ((kittymacs-android-modal-text-conversion nil)
        (style 'action))
    (cl-letf (((symbol-function 'set-text-conversion-style)
               (lambda (value) (setq style value))))
      (with-temp-buffer
        (setq-local text-conversion-style 'action)
        (kittymacs-android-suspend-text-conversion)
        (should (eq style 'action))
        (should-not kittymacs--android-text-conversion)))))

(ert-deftest kittymacs-platform-android-reveal-opens-dired ()
  ;; No `xdg-open', and the document picker addresses files by content URI
  ;; rather than by path, so Dired is the file manager that is here.
  ;; Only `dired' is mocked.  Redefining a primitive such as
  ;; `file-directory-p' makes native compilation build a subr trampoline,
  ;; which it does by starting Emacs in a subprocess -- so a test that
  ;; mocked one alongside `call-process' would catch the compiler instead
  ;; of the code under test.  The path below does not exist, so the real
  ;; `file-directory-p' already answers nil.
  (let ((system-type 'android)
        (buffer-file-name "/sdcard/Documents/todo.org")
        opened)
    (cl-letf (((symbol-function 'dired) (lambda (directory) (setq opened directory))))
      (kittymacs-reveal-in-file-manager)
      (should (equal opened "/sdcard/Documents/")))))

;;; Spell checking.  The option's setter is what talks to Hunspell, so the
;;; tests replace it and watch what it would have seen.

(require 'ispell)

(ert-deftest kittymacs-platform-ispell-is-told-its-dictionary-before-it-is-asked ()
  (kittymacs-platform-test-with 'windows-nt '("hunspell")
    (let ((ispell-program-name ispell-program-name)
          (ispell-dictionary ispell-dictionary)
          (kittymacs--spell-warned nil)
          seen)
      (setenv "DICTIONARY" nil)
      (cl-letf (((symbol-function 'ispell-set-spellchecker-params)
                 (lambda () (setq seen (getenv "DICTIONARY")))))
        (kittymacs--configure-ispell))
      (should (equal seen "en_US"))
      (should (equal ispell-program-name "/mock/bin/hunspell"))
      (should (equal ispell-dictionary "en_US"))
      (should-not kittymacs--spell-warned))))

(ert-deftest kittymacs-platform-ispell-keeps-an-inherited-dictionary ()
  (kittymacs-platform-test-with 'gnu/linux '("hunspell")
    (let ((ispell-program-name ispell-program-name)
          (ispell-dictionary ispell-dictionary)
          seen)
      (setenv "DICTIONARY" "de_DE")
      (cl-letf (((symbol-function 'ispell-set-spellchecker-params)
                 (lambda () (setq seen (getenv "DICTIONARY")))))
        (kittymacs--configure-ispell))
      (should (equal seen "de_DE")))))

(ert-deftest kittymacs-platform-a-broken-checker-does-not-abort-ispell ()
  ;; An error escaping here would abort the load of Ispell itself.
  (kittymacs-platform-test-with 'windows-nt '("hunspell")
    (let ((ispell-program-name ispell-program-name)
          (ispell-dictionary ispell-dictionary)
          (kittymacs--spell-warned nil))
      (cl-letf (((symbol-function 'ispell-set-spellchecker-params)
                 (lambda () (user-error "Hunspell error (is $LANG unset?)"))))
        (kittymacs--configure-ispell))
      (should kittymacs--spell-warned))))

(ert-deftest kittymacs-platform-no-checker-leaves-ispell-alone ()
  (kittymacs-platform-test-with 'gnu/linux '()
    (let ((ispell-program-name ispell-program-name) called)
      (cl-letf (((symbol-function 'ispell-set-spellchecker-params)
                 (lambda () (setq called t))))
        (kittymacs--configure-ispell))
      (should-not called))))

(ert-deftest kittymacs-platform-flyspell-asks-for-a-checker-when-a-buffer-opens ()
  ;; The hooks are always there, so a checker that appears after the module
  ;; loaded (MSYS2's, once private.el sets `kittymacs-msys2-root') still
  ;; turns spelling on.
  (should (memq #'kittymacs-flyspell-text text-mode-hook))
  (should (memq #'kittymacs-flyspell-prog prog-mode-hook))
  (kittymacs-platform-test-with 'windows-nt '()
    (let ((kittymacs-msys2-root "/msys64/") enabled)
      (cl-letf (((symbol-function 'flyspell-mode) (lambda () (setq enabled t))))
        (cl-letf (((symbol-function 'file-executable-p) #'ignore))
          (kittymacs-flyspell-text)
          (should-not enabled))
        (cl-letf (((symbol-function 'file-executable-p)
                   (lambda (file)
                     (equal file "/msys64/ucrt64/bin/hunspell.exe"))))
          (kittymacs-flyspell-text)
          (should enabled))))))

(ert-deftest kittymacs-platform-a-broken-flyspell-is-reported-once ()
  (kittymacs-platform-test-with 'gnu/linux '("hunspell")
    (let ((kittymacs--spell-warned nil) (reports 0))
      (cl-letf (((symbol-function 'flyspell-prog-mode)
                 (lambda () (error "No dictionary")))
                ((symbol-function 'message)
                 (lambda (&rest _) (setq reports (1+ reports)))))
        (kittymacs-flyspell-prog)
        (kittymacs-flyspell-prog))
      (should kittymacs--spell-warned)
      (should (= reports 1)))))

;;; Unix tools on Windows.

(ert-deftest kittymacs-platform-windows-puts-gits-unix-tools-last ()
  (kittymacs-platform-test-with 'windows-nt '("pwsh.exe" "git")
    (let ((exec-path (list "C:/Windows/system32")))
      (cl-letf (((symbol-function 'file-executable-p)
                 (lambda (path) (string-suffix-p "/mock/usr/bin/diff.exe" path))))
        (kittymacs-platform-apply)
        (should (equal (car exec-path) "C:/Windows/system32"))
        (should (= (length exec-path) 2))
        (should (string-suffix-p "/mock/usr/bin" (cadr exec-path)))
        ;; Applying twice must not stack the entry up.
        (kittymacs-platform-apply)
        (should (= (length exec-path) 2))))))

(ert-deftest kittymacs-platform-windows-leaves-exec-path-alone-without-tools ()
  (kittymacs-platform-test-with 'windows-nt '("pwsh.exe")
    (let ((exec-path (list "C:/Windows/system32")))
      (cl-letf (((symbol-function 'file-executable-p) #'ignore))
        (kittymacs-platform-apply)
        (should (equal exec-path '("C:/Windows/system32")))))))

(ert-deftest kittymacs-platform-linux-does-not-look-for-windows-tools ()
  (kittymacs-platform-test-with 'gnu/linux '("bash" "git")
    (let ((exec-path (list "/usr/bin")))
      (cl-letf (((symbol-function 'file-executable-p) (lambda (_) t)))
        (kittymacs-platform-apply)
        (should (equal exec-path '("/usr/bin")))))))

;;; kittymacs-platform-tests.el ends here
