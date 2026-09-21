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

(defmacro kittymacs-platform-test-with (system executables &rest body)
  "Run BODY as SYSTEM with only EXECUTABLES findable and no global side effects."
  (declare (indent 2))
  `(let ((system-type ,system)
         (process-environment (copy-sequence process-environment))
         (default-frame-alist (copy-sequence default-frame-alist))
         (enable-theme-functions nil)
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

;;; kittymacs-platform-tests.el ends here
