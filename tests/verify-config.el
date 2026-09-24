;;; verify-config.el --- Isolated startup regression check -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/verify-config.el
;; Set EMACS_DOTS_TEST_PACKAGES to an existing Lambda var/elpa directory.
;; No packages are installed, refreshed or upgraded by this check.
(require 'cl-lib)
(require 'package)
(require 'warnings)
(require 'package-vc)
(defvar dots-test-source
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defvar dots-test-root (make-temp-file "emacs-dots-check-" t))
(defvar dots-test-failures nil)
(defun dots-test-check (predicate description)
  (unless predicate (push description dots-test-failures)))
(defvar dots-test-warnings nil
  "Warnings displayed while the configuration starts.")
(defun dots-test-record-warning (type message &optional level &rest _)
  "Remember a startup warning of TYPE with MESSAGE at LEVEL.
Types the configuration deliberately silences are left out."
  (unless (or (eq level :debug)
              (warning-suppress-p type warning-suppress-types))
    (push (format "%S: %s" type message) dots-test-warnings)))
(defun dots-test-uncallable-bindings (map prefix)
  "Return the keys under PREFIX in MAP whose binding is not a command.
Group maps are walked too.  Autoloaded commands count as commands."
  (let (uncallable)
    (map-keymap
     (lambda (event binding)
       (let ((key (vconcat prefix (vector event)))
             (definition (pcase binding
                           (`(menu-item ,_ ,definition . ,_) definition)
                           (`(,(pred stringp) . ,definition) definition)
                           (_ binding))))
         (cond ((keymapp definition)
                (setq uncallable
                      (nconc uncallable
                             (dots-test-uncallable-bindings definition key))))
               ((and definition (not (commandp definition)))
                (push (format "%s -> %S" (key-description key) definition)
                      uncallable)))))
     map)
    uncallable))
(defun dots-test-block-install (&rest args)
  (push (format "Unexpected package installation: %S" args) dots-test-failures)
  (error "Package installation disabled during verification"))
(dolist (fn '(package-install package-vc-install package-refresh-contents))
  (advice-add fn :override #'dots-test-block-install))
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file dots-test-source)
             (expand-file-name file dots-test-root)))
(copy-directory (expand-file-name "lisp" dots-test-source)
                (expand-file-name "lisp" dots-test-root) nil t)
(dolist (directory '("literate" "tools"))
  (copy-directory (expand-file-name directory dots-test-source)
                  (expand-file-name directory dots-test-root) nil t))
(setq user-emacs-directory (file-name-as-directory dots-test-root)
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      kittymacs-org-directory (expand-file-name "org/" user-emacs-directory)
      native-comp-jit-compilation nil)
(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "var/etc/custom.el" user-emacs-directory)
  (insert "(setq dots-test-custom-loaded t)\n"
          ;; The completion chapter sets this to 100; Customize must win.
          "(custom-set-variables '(corfu-max-width 80))\n"))
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert "(unless (boundp 'kittymacs-project-directory) (error \"Private loaded before platform\"))\n"
          "(setq dots-test-private-loads (1+ (if (boundp 'dots-test-private-loads) dots-test-private-loads 0)))\n"
          "(setopt kittymacs-project-directory (expand-file-name \"test-projects/\" user-emacs-directory))\n"
          ;; The completion chapter sets this to 10; the late override must win.
          "(add-hook 'after-init-hook (lambda () (setopt corfu-count 7)) 90)\n"))
(with-temp-buffer
  (insert "(setq kittymacs-org-roam-directory (expand-file-name \"test-roam/\" user-emacs-directory) kittymacs-org-roam-excluded-directories '(\"test-excluded\"))\n")
  (append-to-file (point-min) (point-max) (expand-file-name "lisp/private.el" user-emacs-directory)))
(when (getenv "EMACS_DOTS_TEST_PACKAGES")
  (advice-add 'package-initialize :before
              (lambda (&rest _)
                (setq package-user-dir (getenv "EMACS_DOTS_TEST_PACKAGES")))))
(condition-case err
    (progn
      ;; Replay the order of a real startup (see `command-line' in
      ;; startup.el).  Batch Emacs has already finished its own startup by
      ;; the time this file runs, so `after-init-time' is set; clear it so
      ;; code that asks "has init finished?" gets the answer it would get.
      (setq after-init-time nil)
      (advice-add 'display-warning :before #'dots-test-record-warning)
      (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
      (load user-init-file nil t)
      (setq after-init-time (current-time))
      (run-hooks 'after-init-hook 'delayed-warnings-hook)
      (run-hooks 'emacs-startup-hook)
      (advice-remove 'display-warning #'dots-test-record-warning)
      (dolist (warning (reverse dots-test-warnings))
        (dots-test-check nil (format "Startup warning: %s" warning)))
      (require 'cus-edit)
      (dots-test-check (= dots-test-private-loads 1) "private.el must load once")
      (dots-test-check (equal kittymacs-project-directory
                              (expand-file-name "test-projects/" user-emacs-directory))
                       "Project override was overwritten")
      (dots-test-check (and (boundp 'dots-test-custom-loaded) dots-test-custom-loaded)
                       "Persistent Customize file was not loaded")
      (dots-test-check (string-suffix-p "var/etc/custom.el" custom-file)
                       "Customize file is not in persistent state")
      (dots-test-check (eql corfu-max-width 80)
                       "A chapter overwrote a value saved by Customize")
      (dots-test-check (eql corfu-count 7)
                       "A chapter overwrote a private.el after-init-hook override")
      ;; Every generated module must have loaded: the list is the modules on disk.
      (dolist (file (directory-files (expand-file-name "lisp" dots-test-source)
                                     nil "\\`kittymacs-.*\\.el\\'"))
        (let ((feature (intern (file-name-sans-extension file))))
          (dots-test-check (featurep feature) (format "Missing feature %s" feature))))
      ;; Every key in the leader tree must run a command, not a void function.
      (dolist (binding (dots-test-uncallable-bindings kittymacs-leader-map []))
        (dots-test-check nil (format "SPC %s is not a command" binding)))
      (dots-test-check (equal kittymacs-org-roam-directory
                              (expand-file-name "test-roam/" user-emacs-directory))
                       "Personal graph private override was overwritten")
      (dots-test-check (equal kittymacs-org-roam-excluded-directories '("test-excluded"))
                       "Graph exclusion private override was overwritten")
      (dots-test-check (equal org-roam-directory kittymacs-org-roam-directory)
                       "Upstream root does not reflect personal graph override")
      (dots-test-check (not (file-exists-p kittymacs-org-roam-directory))
                       "Startup created the graph root")
      (dots-test-check (not org-roam-db-autosync-mode) "Org-roam must not rebuild at startup")
      (dots-test-check (= (hash-table-count org-roam-db--connection) 0) "Startup opened a graph database")
      (dots-test-check (equal custom-enabled-themes '(doom-sonokai)) "Theme changed")
      ;; Exercise the real loader in both directions: themes must not stack.
      (kittymacs-toggle-theme)
      (dots-test-check (equal custom-enabled-themes (list kittymacs-light-theme))
                       "Light theme toggle failed")
      (kittymacs-toggle-theme)
      (dots-test-check (equal custom-enabled-themes '(doom-sonokai))
                       "Sonokai was not restored by the theme toggle")
      (dots-test-check (and meow-global-mode doom-modeline-mode) "Editor modes missing")
      (dots-test-check (null kittymacs-eglot-auto-start-modes) "LSP auto-start changed")
      (dots-test-check (null kittymacs-language-packages) "Language package opt-ins changed")
      (dots-test-check (not (featurep 'kittymacs-key-hints)) "Hint adapter still loads")
      (dots-test-check (eq (lookup-key meow-normal-state-keymap (kbd "SPC")) kittymacs-leader-map)
                       "SPC is not the literal leader in Normal state")
      (dots-test-check (eq (lookup-key meow-motion-state-keymap (kbd "SPC")) kittymacs-leader-map)
                       "SPC is not the literal leader in Motion state")
      (dots-test-check (eq (lookup-key kittymacs-leader-map (kbd "l e")) #'kittymacs-eglot)
                       "SPC l is not the language-server menu")
      (dots-test-check (eq (lookup-key kittymacs-leader-map (kbd "s l")) #'vertico-repeat)
                       "SPC s l is not completion history")
      (dots-test-check (eq (lookup-key kittymacs-leader-map (kbd "h ?"))
                           #'kittymacs-dashboard-open-cheatsheet)
                       "Cheat-sheet leader binding was overwritten")
      (dots-test-check (eq (lookup-key kittymacs-leader-map (kbd "h h")) #'dashboard-open)
                       "Home leader binding was overwritten")
      (require 'bookmark) (require 'recentf) (require 'project)
      (save-window-excursion
        (let ((recentf-list (list user-init-file))
              (project--list nil) (bookmark-alist nil))
          (dashboard-open) (set-buffer dashboard-buffer-name)
          (run-hooks 'post-command-hook)
          (dots-test-check (eq (key-binding (kbd "?")) #'kittymacs-dashboard-open-cheatsheet)
                           "Dashboard shortcut is hidden by modal editing")
          (goto-char (point-min))
          (search-forward "Config")
          (widget-button-press (1- (point)))
          (dots-test-check (and (derived-mode-p 'org-mode)
                                (file-equal-p buffer-file-name
                                              (expand-file-name "literate/index.org" user-emacs-directory)))
                           "Dashboard Config did not open the literate guide")
          (dashboard-open) (set-buffer dashboard-buffer-name)
          (run-hooks 'post-command-hook)
          (goto-char (point-min))
          (search-forward "Keys & commands")
          ;; Activate the actual widget, including its callback arguments.
          (widget-button-press (1- (point)))
          (dots-test-check (and (derived-mode-p 'org-mode)
                                (file-equal-p buffer-file-name
                                              (expand-file-name "keybindings.org" kittymacs-lisp-dir)))
                           "Dashboard button did not open the cheat sheet")
          (goto-char (point-min))
          (while (re-search-forward "^| \\(SPC [^|]+?\\) +|[^|]+| \\([a-z][a-z0-9-]+\\) +|" nil t)
            (let* ((key (string-trim (match-string 1)))
                   (command (intern (match-string 2))))
              (dots-test-check (eq (lookup-key kittymacs-leader-map (kbd (substring key 4))) command)
                               (format "Cheat sheet binding mismatch: %s -> %s" key command)))))))
  (error (push (format "Startup error: %S" err) dots-test-failures)))
;; Check syntax without running installed packages' programming-mode hooks.
(let ((emacs-lisp-mode-hook nil) (prog-mode-hook nil))
  (dolist (file (append (list (expand-file-name "early-init.el" dots-test-source)
                             (expand-file-name "init.el" dots-test-source))
                        (directory-files (expand-file-name "lisp" dots-test-source)
                                         t "\\.el$")))
    (condition-case err
        (with-temp-buffer (insert-file-contents file) (emacs-lisp-mode) (check-parens))
      (error (push (format "Syntax %s: %S" file err) dots-test-failures)))))
(princ (format "\nEMACS-DOTS-VERIFY %s\nTemporary state: %s\nFailures: %S\n"
               (if dots-test-failures "FAIL" "PASS") dots-test-root dots-test-failures))
;; Avoid save-session hooks retaining any references to installed state on exit.
(setq kill-emacs-hook nil)
(kill-emacs (if dots-test-failures 1 0))
