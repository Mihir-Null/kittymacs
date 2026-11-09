;;; verify-config.el --- Isolated startup regression check -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/verify-config.el
;; Set KITTYMACS_TEST_PACKAGES to an existing var/elpa directory.
;; No packages are installed, refreshed or upgraded by this check.
;; Set KITTYMACS_TEST_QUICKSTART as well to start from a quickstart file.
(require 'cl-lib)
(require 'package)
(require 'warnings)
(require 'package-vc)
(defvar kittymacs-verify-source
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defvar kittymacs-verify-root (make-temp-file "kittymacs-verify-" t))
(load (expand-file-name "tests/kittymacs-profile-checks.el" kittymacs-verify-source) nil t)
(defvar kittymacs-verify-profile (getenv "KITTYMACS_TEST_PROFILE")
  "The profile to check, or nil where KITTYMACS_TEST_PRIVATE's file names one.
This check always writes a private.el, so with neither a machine has no choice
and a sign of use, and the warning for that fails it.")
(defvar kittymacs-verify-private (getenv "KITTYMACS_TEST_PRIVATE")
  "A file to start private.el with, as onboarding wrote it, or nil.")
(defvar kittymacs-verify-expected
  (car (read-from-string (or (getenv "KITTYMACS_TEST_EXPECT") "nil")))
  "An alist of features and whether `kittymacs-feature-p' must say they are on.")
(defvar kittymacs-verify-host-mcp (member kittymacs-verify-profile '("full" "every"))
  "Non-nil where the profile brings agent-shell, so a host file sets its MCP servers.
Elsewhere the setting would warn that it does nothing, as it should.")
(defvar kittymacs-verify-failures nil)
(defun kittymacs-verify-check (predicate description)
  (unless predicate (push description kittymacs-verify-failures)))
(defvar kittymacs-verify-warnings nil
  "Warnings displayed while the configuration starts.")
(defun kittymacs-verify-record-warning (type message &optional level &rest _)
  "Remember a startup warning of TYPE with MESSAGE at LEVEL.
Types the configuration deliberately silences are left out."
  (unless (or (eq level :debug)
              (warning-suppress-p type warning-suppress-types))
    (push (format "%S: %s" type message) kittymacs-verify-warnings)))
(defun kittymacs-verify-org-options ()
  "Return the options that lisp/kittymacs-org.el sets at its top level."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "lisp/kittymacs-org.el" kittymacs-verify-source))
    (let (options)
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (memq (car-safe form) '(setopt setq))
                (setq form (cdr form))
                (while form
                  (push (car form) options)
                  (setq form (cddr form))))))
        (end-of-file nil))
      options)))
(defun kittymacs-verify-block-install (&rest args)
  (push (format "Unexpected package installation: %S" args) kittymacs-verify-failures)
  (error "Package installation disabled during verification"))
(dolist (fn '(package-install package-vc-install package-refresh-contents))
  (advice-add fn :override #'kittymacs-verify-block-install))
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file kittymacs-verify-source)
             (expand-file-name file kittymacs-verify-root)))
(copy-directory (expand-file-name "lisp" kittymacs-verify-source)
                (expand-file-name "lisp" kittymacs-verify-root) nil t)
(dolist (directory '("literate" "tools"))
  (copy-directory (expand-file-name directory kittymacs-verify-source)
                  (expand-file-name directory kittymacs-verify-root) nil t))
(setq user-emacs-directory (file-name-as-directory kittymacs-verify-root)
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      kittymacs-org-directory (expand-file-name "org/" user-emacs-directory)
      native-comp-jit-compilation nil)
(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "var/etc/custom.el" user-emacs-directory)
  ;; Emacs 31 warns about a Lisp file without this cookie.
  (insert ";;; -*- lexical-binding: t; -*-\n"
          "(setq kittymacs-verify-custom-loaded t)\n"
          ;; The completion chapter sets this to 25 (Corfu's default is 15);
          ;; Customize must win, also over an Org option set before Org loads.
          "(custom-set-variables '(corfu-min-width 20) '(org-tags-column 7))\n"))
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert (if kittymacs-verify-private
              (with-temp-buffer
                (insert-file-contents kittymacs-verify-private)
                (buffer-string))
            ";;; -*- lexical-binding: t; -*-\n")
          (if kittymacs-verify-profile
              (format "(setopt kittymacs-profile '%s)\n" kittymacs-verify-profile)
            "")
          "(unless (boundp 'kittymacs-project-directory) (error \"Private loaded before platform\"))\n"
          "(setq kittymacs-verify-private-loads (1+ (if (boundp 'kittymacs-verify-private-loads) kittymacs-verify-private-loads 0)))\n"
          "(setopt kittymacs-project-directory (expand-file-name \"test-projects/\" user-emacs-directory))\n"
          ;; The completion chapter sets the scroll margin to 5 (Corfu's
          ;; default is 2) and the navigation chapter turns filtered buffers
          ;; on; the late override must win, including over an option that
          ;; tabspaces-mode reads only as it turns on.
          "(add-hook 'after-init-hook (lambda () (setopt corfu-scroll-margin 3 tabspaces-use-filtered-buffers-as-default nil org-ellipsis \"!\")) 90)\n"))
(with-temp-buffer
  (insert "(setq kittymacs-org-roam-directory (expand-file-name \"test-roam/\" user-emacs-directory) kittymacs-org-roam-excluded-directories '(\"test-excluded\"))\n")
  (append-to-file (point-min) (point-max) (expand-file-name "lisp/private.el" user-emacs-directory)))
;; Host files read in name order, before private.el, which must win over them.
(defvar kittymacs-host-directories
  (list (expand-file-name "host/" kittymacs-verify-root)))
(make-directory (car kittymacs-host-directories) t)
(with-temp-file (expand-file-name "20-second.el" (car kittymacs-host-directories))
  (insert ";;; -*- lexical-binding: t; -*-\n"
          "(unless (boundp 'kittymacs-project-directory) (error \"Host file loaded before platform\"))\n"
          "(setq kittymacs-verify-host-order (cons 'second kittymacs-verify-host-order))\n"
          "(setopt kittymacs-project-directory \"/host-must-lose/\")\n"))
(with-temp-file (expand-file-name "10-first.el" (car kittymacs-host-directories))
  (insert ";;; -*- lexical-binding: t; -*-\n"
          "(setq kittymacs-verify-host-order (list 'first))\n"
          (if kittymacs-verify-host-mcp
              "(setopt kittymacs-agent-mcp-servers '(((name . \"host-server\"))))\n"
            "")
          "(when (boundp 'kittymacs-verify-private-loads) (error \"Host file loaded after private.el\"))\n"))
(when (getenv "KITTYMACS_TEST_PACKAGES")
  (advice-add 'kittymacs-activate-packages :before
              (lambda (&rest _)
                (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES")))))
(defvar kittymacs-verify-quickstart (getenv "KITTYMACS_TEST_QUICKSTART")
  "Non-nil to write a quickstart file first, and to fail unless the start uses it.")
(defvar kittymacs-verify-alist-after-activation nil
  "What `package-alist' held once the packages had activated.")
(when kittymacs-verify-quickstart
  (unless (getenv "KITTYMACS_TEST_PACKAGES")
    (error "KITTYMACS_TEST_QUICKSTART needs KITTYMACS_TEST_PACKAGES"))
  ;; Another process, so this one's package.el stays as a real start finds it.
  (let ((status (call-process
                 (expand-file-name invocation-name invocation-directory) nil nil nil
                 "-Q" "--batch"
                 "--eval" (format "(setq user-emacs-directory %S)" user-emacs-directory)
                 "-l" (expand-file-name "early-init.el" user-emacs-directory)
                 "--eval" (format "(setq package-user-dir %S)" (getenv "KITTYMACS_TEST_PACKAGES"))
                 "-f" "kittymacs-quickstart-write")))
    (kittymacs-verify-check (eql status 0) (format "Writing the quickstart file exited %S" status)))
  (advice-add 'kittymacs-activate-packages :after
              (lambda (&rest _)
                (setq kittymacs-verify-alist-after-activation package-alist))))
(condition-case err
    (progn
      ;; Replay the order of a real startup (see `command-line' in
      ;; startup.el).  Batch Emacs has already finished its own startup by
      ;; the time this file runs, so `after-init-time' is set; clear it so
      ;; code that asks "has init finished?" gets the answer it would get.
      (setq after-init-time nil)
      (advice-add 'display-warning :before #'kittymacs-verify-record-warning)
      (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
      (load user-init-file nil t)
      (setq after-init-time (current-time))
      (run-hooks 'after-init-hook 'delayed-warnings-hook)
      (run-hooks 'emacs-startup-hook)
      (advice-remove 'display-warning #'kittymacs-verify-record-warning)
      (dolist (warning (reverse kittymacs-verify-warnings))
        (kittymacs-verify-check nil (format "Startup warning: %s" warning)))
      ;; What any start must satisfy: first of all, because Org must wait for
      ;; its first use, and the checks below load it themselves.
      (dolist (failure (kittymacs-check-start))
        (kittymacs-verify-check nil failure))
      ;; Only a start from the file leaves the list empty; every package a scan
      ;; would activate must be active all the same.
      (when kittymacs-verify-quickstart
        (kittymacs-verify-check (and kittymacs-quickstart-loaded
                                     (null kittymacs-verify-alist-after-activation))
                                "The quickstart file was ignored")
        (dolist (entry (package--alist))
          (kittymacs-verify-check
           (or (memq (car entry) package-activated-list)
               (package-built-in-p (car entry) (package-desc-version (cadr entry))))
           (format "%s is installed, and the quickstart file did not activate it" (car entry)))))
      ;; `just size' counts what the default profile loads by reading init.el;
      ;; a real start says whether it read correctly.
      (when (and (equal kittymacs-verify-profile "minimal") (not kittymacs-verify-private))
        (defvar kittymacs-bench-library-only t)
        (load (expand-file-name "tools/bench.el" kittymacs-verify-source) nil t)
        (let ((counted (kittymacs-bench-default-modules))
              (loaded (seq-filter (lambda (feature)
                                    (file-exists-p (expand-file-name
                                                    (format "lisp/%s.el" feature)
                                                    kittymacs-verify-source)))
                                  features)))
          (kittymacs-verify-check
           (and (null (seq-difference counted loaded)) (null (seq-difference loaded counted)))
           (format "just size counts other modules than a start loads: only counted %S, only loaded %S"
                   (seq-difference counted loaded) (seq-difference loaded counted)))))
      ;; A chapter's `require' must not search every package directory first.
      (let ((package-dir (file-name-as-directory (expand-file-name package-user-dir))))
        (kittymacs-verify-check
         (not (seq-some (lambda (directory)
                          (string-prefix-p package-dir (expand-file-name directory)))
                        (seq-take-while (lambda (directory)
                                          (not (file-equal-p directory kittymacs-lisp-dir)))
                                        load-path)))
         "A package directory comes before lisp/ on load-path"))
      (pcase-dolist (`(,feature . ,on) kittymacs-verify-expected)
        (kittymacs-verify-check (eq (kittymacs-feature-p feature) on)
                                (format "kittymacs-feature-p says %s is %s"
                                        feature (if on "off" "on"))))
      ;; The key loads onboarding when pressed, and the hint only speaks.
      (kittymacs-verify-check (eq (lookup-key kittymacs-leader-map (kbd "C o")) #'kittymacs-onboard)
                              "SPC C o is not onboarding")
      (kittymacs-verify-check (autoloadp (symbol-function 'kittymacs-onboard))
                              "Onboarding is loaded, not waiting for its key")
      (kittymacs-verify-check (memq 'kittymacs-onboard-hint emacs-startup-hook)
                              "The first-start hint is not on the startup hook")
      (let* ((noninteractive nil)
             (said nil)
             (hint (lambda ()
                     (setq said nil)
                     (cl-letf (((symbol-function 'message)
                                (lambda (format-string &rest args)
                                  (setq said (apply #'format format-string args)))))
                       (kittymacs-onboard-hint))
                     said)))
        (let ((kittymacs-profile nil) (kittymacs-features nil) (kittymacs-features-excluded nil))
          (kittymacs-verify-check (and (funcall hint) (string-search "SPC C o" said))
                                  "No selection, and the hint said nothing"))
        (dolist (chosen '(kittymacs-profile kittymacs-features kittymacs-features-excluded))
          (cl-progv '(kittymacs-profile kittymacs-features kittymacs-features-excluded)
              '(nil nil nil)
            (set chosen '(chosen))
            (kittymacs-verify-check (null (funcall hint))
                                    (format "%s is set, and the hint still spoke" chosen)))))
      (when (kittymacs-feature-p 'home-page)
        (save-window-excursion (dashboard-open))
        (kittymacs-verify-check (null (kittymacs-check-org-features))
                                (format "The home page loaded Org: %S" (kittymacs-check-org-features))))
      ;; Minimal's cache starts empty, so this directory holds what it installed.
      (when (equal kittymacs-verify-profile "minimal")
        (dolist (failure (kittymacs-check-package-set))
          (kittymacs-verify-check nil failure)))
      (require 'cus-edit)
      (kittymacs-verify-check (= kittymacs-verify-private-loads 1) "private.el must load once")
      (kittymacs-verify-check (equal (bound-and-true-p kittymacs-verify-host-order) '(second first))
                       "Host files did not load, or not in name order")
      (when (and kittymacs-verify-host-mcp (kittymacs-feature-p 'agents))
        (kittymacs-verify-check (equal (bound-and-true-p agent-shell-mcp-servers)
                                       '(((name . "host-server"))))
                                "A host file's MCP servers did not reach agent-shell"))
      (kittymacs-verify-check (equal kittymacs-project-directory
                              (expand-file-name "test-projects/" user-emacs-directory))
                       "Project override was overwritten")
      (kittymacs-verify-check (and (boundp 'kittymacs-verify-custom-loaded) kittymacs-verify-custom-loaded)
                       "Persistent Customize file was not loaded")
      (kittymacs-verify-check (string-suffix-p "var/etc/custom.el" custom-file)
                       "Customize file is not in persistent state")
      (kittymacs-verify-check (eql corfu-min-width 20)
                       "A chapter overwrote a value saved by Customize")
      (kittymacs-verify-check (eql corfu-scroll-margin 3)
                       "A chapter overwrote a private.el after-init-hook override")
      (when (kittymacs-feature-p 'workspaces)
        (kittymacs-verify-check (and tabspaces-mode
                                     (null (command-remapping 'switch-to-buffer)))
                                "tabspaces-mode turned on before the private.el override"))
      ;; Every generated module must have loaded, or be a chapter whose feature
      ;; is off: the list is the modules on disk.
      (dolist (file (directory-files (expand-file-name "lisp" kittymacs-verify-source)
                                     nil "\\`kittymacs-.*\\.el\\'"))
        (let* ((module (intern (file-name-sans-extension file)))
               (chapter-feature (car (rassq module kittymacs-check-chapter-features))))
          ;; A start never loads onboarding.  It loads the list of WSL distributions
          ;; only through the wsl-rpc chapter, which requires it.
          (when (and (not (memq module '(kittymacs-onboard kittymacs-wsl)))
                     (or (null chapter-feature) (kittymacs-feature-p chapter-feature)))
            (kittymacs-verify-check (featurep module) (format "Missing feature %s" module)))))
      ;; The terminal comes from MELPA.  package.el keeps a Git checkout left
      ;; by an older :vc install as installed, so name one if it is there.
      (when kittymacs-terminal-ghostel
        (dolist (name '(ghostel consult-ghostel))
          (let ((desc (cadr (assq name (package--alist)))))
            (kittymacs-verify-check
             (and desc (not (package-vc-p desc)))
             (if desc
                 (format "%s is a Git checkout, not MELPA's package; M-x package-delete it" name)
               (format "%s is not installed" name)))))
        ;; Loading the terminal and Consult turns on consult-ghostel-mode.
        (condition-case err
            (progn
              (require 'consult)
              (require 'ghostel)
              (kittymacs-verify-check (bound-and-true-p consult-ghostel-mode)
                               "Loading ghostel and Consult did not turn on consult-ghostel-mode"))
          (error (kittymacs-verify-check nil (format "Loading ghostel failed: %S" err)))))
      (when (kittymacs-feature-p 'linked-notes)
        (kittymacs-verify-check (equal kittymacs-org-roam-directory
                                       (expand-file-name "test-roam/" user-emacs-directory))
                                "Personal graph private override was overwritten")
        (kittymacs-verify-check (equal kittymacs-org-roam-excluded-directories '("test-excluded"))
                                "Graph exclusion private override was overwritten")
        (kittymacs-verify-check (equal org-roam-directory
                                       (file-name-as-directory (file-truename kittymacs-org-roam-directory)))
                                "Upstream root does not reflect personal graph override")
        (kittymacs-verify-check (not (file-exists-p kittymacs-org-roam-directory))
                                "Startup created the graph root")
        ;; A SPC n command loads Org-roam itself, and Org with it.  This one stops
        ;; at the root, which does not exist.
        (condition-case nil (kittymacs--org-roam-scope) (user-error nil))
        (kittymacs-verify-check (and (featurep 'org) (featurep 'org-roam)
                                     (memq 'kittymacs--org-roam-restore hack-local-variables-hook))
                                "A SPC n command did not load Org-roam")
        (kittymacs-verify-check (not org-roam-db-autosync-mode) "Org-roam must not rebuild at startup")
        (kittymacs-verify-check (= (hash-table-count org-roam-db--connection) 0) "Startup opened a graph database")
        (kittymacs-verify-check (string-match-p "\\${tags" org-roam-node-display-template)
                                "SPC n f does not show the notes' tags"))
      (require 'org)
      (kittymacs-verify-check (and (eql org-tags-column 7) (equal org-ellipsis "!"))
                              "Org's loading overwrote a value from Customize or private.el")
      ;; The Org chapter runs before these libraries load: `setopt' warns only
      ;; when one does, long after the warnings above, and `setq' never does.
      ;; ox-odt cannot load after a `setopt' on its output format: the check
      ;; calls a function defined later in that file.
      (dolist (library '(calendar org-agenda org-archive org-capture org-id org-refile
                                  org-table ox ox-html))
        (require library))
      (let ((options (remq 'org-odt-preferred-output-format (kittymacs-verify-org-options))))
        (kittymacs-verify-check (> (length options) 50) "The Org chapter's options were not found")
        (dolist (option options)
          (let ((type (get (indirect-variable option) 'custom-type)))
            (kittymacs-verify-check
             (and type (widget-apply (widget-convert type) :match (default-value option)))
             (format "The Org chapter sets %s to a value its type refuses, or it is no option"
                     option)))))
      ;; SPC s Q parses a plain query, lists its headings grouped by file,
      ;; refreshes through Org QL, and a group header keeps Meow's keys and
      ;; the leader.  An error here must not skip the checks after it.
      (when (kittymacs-feature-p 'org-extras)
        (with-temp-file (expand-file-name "tagged.org" org-directory)
          (insert "* TODO Choose the services :decision:\n* Unrelated heading\n"))
        (condition-case err
          (save-window-excursion
            (kittymacs-org-ql-search "tags:decision")
            (with-current-buffer "*Org QL View: tags:decision*"
              (kittymacs-verify-check (and org-super-agenda-mode (null org-super-agenda-header-map))
                               "Super-agenda is off, or its headers shadow Meow's keys")
              (kittymacs-verify-check (and (string-match-p "Choose the services" (buffer-string))
                                    (not (string-match-p "Unrelated" (buffer-string))))
                               "SPC s Q did not list exactly the tagged heading")
              (goto-char (point-min))
              (kittymacs-verify-check (and (search-forward "tagged" nil t)
                                    (get-text-property (pos-bol) 'org-super-agenda-header)
                                    (keymapp (key-binding (kbd "SPC"))))
                               "SPC on a group header is not the leader")
              ;; `org-agenda-redo' would leave an Org QL list as it was.
              (with-current-buffer (find-file-noselect (expand-file-name "tagged.org" org-directory))
                (goto-char (point-max))
                (insert "* Another decision :decision:\n")
                (save-buffer))
              (kittymacs-org-agenda-refresh)
              (kittymacs-verify-check (string-match-p "Another decision" (buffer-string))
                               "SPC m g did not run the Org QL query again")))
        (error (kittymacs-verify-check nil (format "SPC s Q failed: %S" err)))))
      (with-temp-buffer
        (org-mode)
        (kittymacs-verify-check (and kittymacs-org-prose-mode buffer-face-mode
                                     (assq 'org-block face-remapping-alist))
                                "Org buffers do not set prose in variable-pitch")
        (when (kittymacs-feature-p 'org-extras)
          (kittymacs-verify-check (bound-and-true-p org-modern-indent-mode)
                                  "org-modern-indent is not on in Org buffers")))
      ;; Sonokai needs doom-themes; without that feature the built-in pair stands in.
      (let ((dark (if (kittymacs-feature-p 'doom-look) 'doom-sonokai 'modus-vivendi))
            (light (if (kittymacs-feature-p 'doom-look) kittymacs-light-theme 'modus-operandi)))
        (kittymacs-verify-check (equal custom-enabled-themes (list dark)) "Theme changed")
        ;; Exercise the real loader in both directions: themes must not stack.
        (kittymacs-toggle-theme)
        (kittymacs-verify-check (equal custom-enabled-themes (list light))
                                "Light theme toggle failed")
        (kittymacs-toggle-theme)
        (kittymacs-verify-check (equal custom-enabled-themes (list dark))
                                "The dark theme was not restored by the theme toggle"))
      (kittymacs-verify-check meow-global-mode "Meow is off")
      (if (kittymacs-feature-p 'doom-look)
          (kittymacs-verify-check doom-modeline-mode "The mode line is missing")
        (kittymacs-verify-check (not (or (featurep 'doom-modeline) (featurep 'doom-themes)))
                                "A doom package loaded with doom-look off"))
      (kittymacs-verify-check (null kittymacs-eglot-auto-start-modes) "LSP auto-start changed")
      (kittymacs-verify-check (null kittymacs-language-packages) "Language package opt-ins changed")
      ;; Importing the login shell's PATH replaces `exec-path' whole; the
      ;; directories early-init.el found come back, once, on both lists.
      (let* ((dropped (make-temp-file "kittymacs-verify-bin-" t))
             (kept (car exec-path))
             (kittymacs-launcher-path (list dropped kept))
             (exec-path exec-path)
             (process-environment (copy-sequence process-environment)))
        (kittymacs--restore-launcher-path)
        (kittymacs-verify-check (and (member dropped exec-path)
                                     (member dropped (split-string (getenv "PATH") path-separator)))
                         "A directory early-init.el found was not restored after the PATH import")
        (kittymacs-verify-check (= 1 (seq-count (lambda (d) (equal d kept)) exec-path))
                         "Restoring early-init.el's directories duplicated one already on exec-path"))
      ;; Suggestions send buffers to GitHub: off by default, and copilot.el
      ;; loads only when a buffer turns them on.
      (when (kittymacs-feature-p 'suggestions)
        (kittymacs-verify-check (null kittymacs-suggestions) "Suggestions are on by default"))
      (kittymacs-verify-check (not (featurep 'copilot)) "copilot.el loaded at startup")
      ;; Next edits' TAB and C-g are a minor mode's; Meow's state maps must
      ;; not take them first.
      (dolist (key '("TAB" "<tab>" "C-g"))
        (dolist (map (list meow-normal-state-keymap meow-insert-state-keymap))
          (kittymacs-verify-check (not (commandp (keymap-lookup map key)))
                           (format "Meow binds %s, which next edits need" key))))
      (when (kittymacs-feature-p 'suggestions)
      (condition-case err
          (let ((kittymacs-verify-warnings nil))
            (advice-add 'display-warning :before #'kittymacs-verify-record-warning)
            (unwind-protect (require 'copilot)
              (advice-remove 'display-warning #'kittymacs-verify-record-warning))
            (kittymacs-verify-check (null kittymacs-verify-warnings)
                             (format "Loading copilot.el warned: %S" kittymacs-verify-warnings))
            (kittymacs-verify-check (and (memq 'kittymacs-suggestions-typing-p copilot-enable-predicates)
                                         (not (memq 'evil-insert-state-p copilot-enable-predicates))
                                         (memq 'kittymacs-suggestions-popup-p
                                               copilot-disable-display-predicates))
                             "copilot.el does not ask Meow and Corfu before suggesting")
            (kittymacs-verify-check (string-prefix-p (expand-file-name kittymacs-var-dir)
                                                     (expand-file-name copilot-install-dir))
                             "copilot.el would install its server outside var/")
            (with-temp-buffer
              (let ((meow-mode t) (meow-insert-mode nil))
                (kittymacs-verify-check (not (kittymacs-suggestions-typing-p))
                                 "Ghost text is asked for in Meow's Normal state"))
              (let ((meow-mode t) (meow-insert-mode t))
                (kittymacs-verify-check (kittymacs-suggestions-typing-p)
                                 "Ghost text is not asked for in Meow's Insert state"))
              (setq buffer-file-name (expand-file-name "lisp/private.el" user-emacs-directory))
              (kittymacs-verify-check (kittymacs--suggestions-excluded-p)
                               "private.el is not excluded from suggestions")
              (setq buffer-file-name (expand-file-name "main.py" user-emacs-directory))
              (kittymacs-verify-check (not (kittymacs--suggestions-excluded-p))
                               "An ordinary file is excluded from suggestions")
              ;; Without a server, turning suggestions on is a message and no mode.
              (let ((copilot-server-executable "kittymacs-no-such-server"))
                (kittymacs-verify-check (and (not (kittymacs--suggestions-start))
                                             (not copilot-mode))
                                 "Suggestions turned on without a server"))
              (setq buffer-file-name nil)))
        (error (kittymacs-verify-check nil (format "Suggestions failed: %S" err)))))
      ;; Jupyter kernels need emacs-zmq's native module: off by default, and
      ;; emacs-jupyter is not even loaded until a kernel is asked for.
      (when (kittymacs-feature-p 'notebooks)
        (kittymacs-verify-check (null kittymacs-notebooks-jupyter) "Jupyter kernels are on by default"))
      (kittymacs-verify-check (not (featurep 'jupyter)) "emacs-jupyter loaded at startup")
      ;; Remote programs are found on the remote login shell's PATH, so a
      ;; Nix profile on an SSH host (the Android VM backend) is searched.
      (require 'tramp)
      (kittymacs-verify-check (eq (car tramp-remote-path) 'tramp-own-remote-path)
                       "Tramp does not search the remote login shell's PATH first")
      (kittymacs-verify-check (member "~/.nix-profile/bin" tramp-remote-path)
                       "Tramp does not search the Nix profile")
      (kittymacs-verify-check (and (bound-and-true-p envrc-global-mode)
                                   (eq (lookup-key kittymacs-leader-map (kbd "p E a")) #'envrc-allow))
                       "envrc is not on, or SPC p E a is not envrc-allow")
      (kittymacs-verify-check (not (featurep 'kittymacs-key-hints)) "Hint adapter still loads")
      (kittymacs-verify-check (eq (lookup-key meow-normal-state-keymap (kbd "SPC")) kittymacs-leader-map)
                       "SPC is not the literal leader in Normal state")
      (kittymacs-verify-check (eq (lookup-key meow-motion-state-keymap (kbd "SPC")) kittymacs-leader-map)
                       "SPC is not the literal leader in Motion state")
      (kittymacs-verify-check (eq (lookup-key kittymacs-leader-map (kbd "l e")) #'eglot)
                       "SPC l is not the language-server menu")
      (kittymacs-verify-check (eq (lookup-key kittymacs-leader-map (kbd "s l")) #'vertico-repeat)
                       "SPC s l is not completion history")
      ;; The home page opens the cheat sheet, which describes the full profile.
      (when (eq (kittymacs-features-profile) 'full)
      (kittymacs-verify-check (eq (lookup-key kittymacs-leader-map (kbd "h ?"))
                           #'kittymacs-dashboard-open-cheatsheet)
                       "Cheat-sheet leader binding was overwritten")
      (kittymacs-verify-check (eq (lookup-key kittymacs-leader-map (kbd "h h")) #'dashboard-open)
                       "Home leader binding was overwritten")
      (require 'bookmark) (require 'recentf) (require 'project)
      (save-window-excursion
        (let ((recentf-list (list user-init-file))
              (project--list nil) (bookmark-alist nil))
          (dashboard-open) (set-buffer dashboard-buffer-name)
          (run-hooks 'post-command-hook)
          (kittymacs-verify-check (eq (key-binding (kbd "?")) #'kittymacs-dashboard-open-cheatsheet)
                           "Dashboard shortcut is hidden by modal editing")
          (goto-char (point-min))
          (search-forward "Config")
          (widget-button-press (1- (point)))
          (kittymacs-verify-check (and (derived-mode-p 'org-mode)
                                (file-equal-p buffer-file-name
                                              (expand-file-name "literate/index.org" user-emacs-directory)))
                           "Dashboard Config did not open the literate guide")
          (dashboard-open) (set-buffer dashboard-buffer-name)
          (run-hooks 'post-command-hook)
          (goto-char (point-min))
          (search-forward "Keys & commands")
          ;; Activate the actual widget, including its callback arguments.
          (widget-button-press (1- (point)))
          (kittymacs-verify-check (and (derived-mode-p 'org-mode)
                                (file-equal-p buffer-file-name
                                              (expand-file-name "keybindings.org" kittymacs-lisp-dir)))
                           "Dashboard button did not open the cheat sheet")
          (goto-char (point-min))
          (while (re-search-forward "^| \\(SPC [^|]+?\\) +|[^|]+| \\([a-z][a-z0-9-]+\\) +|" nil t)
            (let* ((key (string-trim (match-string 1)))
                   (command (intern (match-string 2))))
              (kittymacs-verify-check (eq (lookup-key kittymacs-leader-map (kbd (substring key 4))) command)
                               (format "Cheat sheet binding mismatch: %s -> %s" key command))))))))
  (error (push (format "Startup error: %S" err) kittymacs-verify-failures)))
;; Check syntax without running installed packages' programming-mode hooks.
(let ((emacs-lisp-mode-hook nil) (prog-mode-hook nil))
  (dolist (file (append (list (expand-file-name "early-init.el" kittymacs-verify-source)
                             (expand-file-name "init.el" kittymacs-verify-source))
                        (directory-files (expand-file-name "lisp" kittymacs-verify-source)
                                         t "\\.el$")))
    (condition-case err
        (with-temp-buffer (insert-file-contents file) (emacs-lisp-mode) (check-parens))
      (error (push (format "Syntax %s: %S" file err) kittymacs-verify-failures)))))
(princ (format "\nKITTYMACS-VERIFY %s\nTemporary state: %s\nFailures: %S\n"
               (if kittymacs-verify-failures "FAIL" "PASS") kittymacs-verify-root kittymacs-verify-failures))
;; Avoid save-session hooks retaining any references to installed state on exit.
(setq kill-emacs-hook nil)
(kill-emacs (if kittymacs-verify-failures 1 0))
