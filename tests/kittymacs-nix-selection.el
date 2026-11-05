;;; kittymacs-nix-selection.el --- What the Nix options say, a real start answers -*- lexical-binding: t; -*-
;; Run: `just nix-selection', which evaluates nix/selection-check and hands its
;; report to this file through KITTYMACS_NIX_REPORT.
;;
;; A real start for each host, in a process of its own, reading that host's
;; generated files from the host layer.  Nothing is installed.  The packages are
;; optional, because Elisp settles the selection before any of them loads: a
;; start without them warns about each one, and only warnings about the selection
;; or a host file count here.  KITTYMACS_TEST_PACKAGES names a directory to use.

;;; Code:
(require 'cl-lib)
(require 'json)
(require 'seq)

(defconst kittymacs-nix-source
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))

(defconst kittymacs-nix-this-file load-file-name)

(defconst kittymacs-nix-archive-only '(copilot consult-ghostel)
  "Packages that nix/packages.nix leaves out, though they are not Git packages.")

(defconst kittymacs-nix-full-settings
  '((kittymacs-nix-check-true . t)
    (kittymacs-nix-check-false . nil)
    (kittymacs-nix-check-null . nil)
    (kittymacs-nix-check-number . 3)
    (kittymacs-nix-check-string . "a \"quoted\" line\n")
    (kittymacs-nix-check-list . ("one" 2 three))
    (kittymacs-nix-check-symbol . chosen)
    (kittymacs-nix-check-host-file . t))
  "What the `full' host's `settings' and `hostFiles' must leave set.")

(defvar kittymacs-catalogue)
(defvar kittymacs-features)
(defvar kittymacs-features-excluded)
(defvar kittymacs-profile)
(declare-function kittymacs-feature-p "kittymacs-features" (feature))
(declare-function kittymacs-features-enabled "kittymacs-features" ())
(declare-function kittymacs-features-profile "kittymacs-features" ())

(defun kittymacs-nix--report ()
  "Return the report as an alist of hosts."
  (with-temp-buffer
    (insert-file-contents (getenv "KITTYMACS_NIX_REPORT"))
    (json-parse-buffer :object-type 'alist :array-type 'list
                       :null-object nil :false-object :false)))

;;; One start

(defvar kittymacs-nix-warnings nil
  "Warnings shown while this start ran.")

(defun kittymacs-nix--record-warning (_type message &rest _)
  "Remember a startup warning with MESSAGE."
  (push message kittymacs-nix-warnings))

(defun kittymacs-nix--selection-warnings ()
  "Return the warnings about the selection or a host file."
  (seq-filter (lambda (message)
                (string-match-p (rx (or "kittymacs-profile" "kittymacs-features" "stays off"
                                        "stays on"
                                        (seq "/host/" (* nonl) "did not finish loading")))
                                message))
              kittymacs-nix-warnings))

(defun kittymacs-nix--check-said (said)
  "Return what is wrong with the start, against the options SAID."
  (let ((profile (alist-get 'profile said))
        failures)
    (if profile
        (unless (equal (symbol-name (kittymacs-features-profile)) profile)
          (push (format "the profile is %s, not %s" (kittymacs-features-profile) profile) failures))
      (when kittymacs-profile
        (push (format "kittymacs-profile is %s, and no option set it" kittymacs-profile) failures)))
    (when (and (null (alist-get 'features said))
               (or kittymacs-features kittymacs-features-excluded))
      (push "a feature list is set, and no option set it" failures))
    (pcase-dolist (`(,feature . ,enable) (alist-get 'features said))
      (unless (eq (kittymacs-feature-p feature) (eq enable t))
        (push (format "%s is %s, and the option said %s"
                      feature (if (kittymacs-feature-p feature) "on" "off") enable)
              failures)))
    failures))

(defun kittymacs-nix--check-enabled (said enabled)
  "Return what is wrong with Nix's answer ENABLED, for the options SAID.
With no profile, Nix answers from `full', so it need only cover what is on."
  (let* ((nix (mapcar #'intern enabled))
         (elisp (kittymacs-features-enabled))
         (too-few (seq-difference elisp nix))
         (too-many (seq-difference nix elisp)))
    (when enabled
      (append (and too-few (list (format "on here, and not in Nix's answer: %S" too-few)))
              (and too-many (alist-get 'profile said)
                   (list (format "in Nix's answer, and off here: %S" too-many)))))))

(defun kittymacs-nix--check-built (name built)
  "Return what is wrong with the packages Nix BUILT for the host NAME.
Only `minimal' builds the features that are on, and it adds Avy of its own."
  (when (eq name 'minimal)
    (let* ((names (mapcar #'intern built))
           (wanted (seq-mapcat
                    (lambda (feature)
                      (let ((entry (alist-get feature kittymacs-catalogue)))
                        (seq-difference (plist-get entry :packages) (plist-get entry :vc))))
                    (kittymacs-features-enabled)))
           (missing (seq-difference (seq-difference wanted names) kittymacs-nix-archive-only))
           (extra (seq-difference names wanted)))
      (append (and missing (list (format "not built: %S" missing)))
              (and (not (equal extra '(avy)))
                   (list (format "built beyond the features: %S, and extraPackages says (avy)"
                                 extra)))))))

(defun kittymacs-nix--check-settings (name)
  "Return what is wrong with the settings the host NAME asked for."
  (when (eq name 'full)
    (seq-keep (pcase-lambda (`(,variable . ,expected))
                (unless (equal (and (boundp variable) (symbol-value variable)) expected)
                  (format "%s is %S, not %S" variable
                          (and (boundp variable) (symbol-value variable)) expected)))
              kittymacs-nix-full-settings)))

(defun kittymacs-nix-start (name)
  "Start the configuration as the host NAME says; print the verdict and exit."
  (let* ((entry (alist-get name (kittymacs-nix--report)))
         (root (make-temp-file "kittymacs-nix-" t))
         (host-directory (expand-file-name "host/" root))
         (packages (getenv "KITTYMACS_TEST_PACKAGES"))
         failures)
    (dolist (fn '(package-install package-vc-install package-refresh-contents))
      (advice-add fn :override
                  (lambda (&rest _) (error "Package installation disabled in this check"))))
    (dolist (file '("early-init.el" "init.el"))
      (copy-file (expand-file-name file kittymacs-nix-source) (expand-file-name file root)))
    (copy-directory (expand-file-name "lisp" kittymacs-nix-source)
                    (expand-file-name "lisp" root) nil t)
    (make-directory host-directory)
    (make-directory (expand-file-name "var/etc" root) t)
    (pcase-dolist (`(,file . ,text) (alist-get 'files entry))
      (with-temp-file (expand-file-name (symbol-name file) host-directory)
        (insert text)))
    (defvar kittymacs-host-directories nil)
    (defvar kittymacs-org-directory)
    (setq kittymacs-host-directories (list host-directory)
          user-emacs-directory (file-name-as-directory root)
          default-directory user-emacs-directory
          user-init-file (expand-file-name "init.el" user-emacs-directory)
          kittymacs-org-directory (expand-file-name "org/" user-emacs-directory)
          native-comp-jit-compilation nil)
    (when packages
      (advice-add 'package-initialize :before
                  (lambda (&rest _) (setq package-user-dir packages))))
    (condition-case err
        (progn
          (setq after-init-time nil)
          (advice-add 'display-warning :before #'kittymacs-nix--record-warning)
          (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
          (load user-init-file nil t)
          (setq after-init-time (current-time))
          (run-hooks 'after-init-hook 'delayed-warnings-hook)
          (advice-remove 'display-warning #'kittymacs-nix--record-warning)
          (setq failures
                (append (kittymacs-nix--check-said (alist-get 'said entry))
                        (kittymacs-nix--check-enabled (alist-get 'said entry)
                                                      (alist-get 'enabled entry))
                        (kittymacs-nix--check-built name (alist-get 'built entry))
                        (kittymacs-nix--check-settings name)
                        (kittymacs-nix--selection-warnings))))
      (error (push (format "Startup error: %S" err) failures)))
    (setq kill-emacs-hook nil)
    (ignore-errors (delete-directory root t))
    (princ (format "\nKITTYMACS-NIX %S\n" failures))
    (kill-emacs (if failures 1 0))))

;;; Every start

(defun kittymacs-nix--run-host (name)
  "Start the host NAME in its own process; return nil if it passed, else why."
  (let ((process-environment (cons (format "KITTYMACS_NIX_HOST=%s" name) process-environment)))
    (with-temp-buffer
      (let ((status (call-process (expand-file-name invocation-name invocation-directory)
                                  nil t nil "-Q" "--batch" "-l" kittymacs-nix-this-file)))
        (goto-char (point-min))
        (cond ((and (eql status 0) (re-search-forward "^KITTYMACS-NIX nil$" nil t)) nil)
              ((re-search-forward "^KITTYMACS-NIX \\(.*\\)$" nil t) (match-string 1))
              (t (format "exit %s without a verdict: %s" status
                         (string-trim (buffer-substring
                                       (max (point-min) (- (point-max) 800)) (point-max))))))))))

(defun kittymacs-nix--check-report (report)
  "Return what is wrong with REPORT itself, before any start."
  (append
   (and (alist-get 'files (alist-get 'plain report))
        (list (format "plain writes files: %S" (alist-get 'files (alist-get 'plain report)))))
   (and (alist-get 'enabled (alist-get 'plain report))
        (list "plain chose features"))
   (and (null (alist-get 'plain report))
        (list "the report has no plain host"))
   (and (not (equal (alist-get 'built (alist-get 'extraOnly report)) '("vundo")))
        (list (format "extraOnly built %S" (alist-get 'built (alist-get 'extraOnly report)))))))

(defun kittymacs-nix-all ()
  "Check the report, start each host in it, print a table and exit."
  (let* ((report (kittymacs-nix--report))
         (failures (kittymacs-nix--check-report report)))
    (dolist (failure failures)
      (princ (format "FAIL report: %s\n" failure)))
    (pcase-dolist (`(,name . ,_) report)
      (if-let* ((verdict (kittymacs-nix--run-host name)))
          (progn (push name failures)
                 (princ (format "FAIL %s: %s\n" name verdict)))
        (princ (format "ok   %s\n" name))))
    (princ (format "\nKITTYMACS-NIX-SELECTION %s\n" (if failures "FAIL" "PASS")))
    (kill-emacs (if failures 1 0))))

(if-let* ((name (getenv "KITTYMACS_NIX_HOST")))
    (kittymacs-nix-start (intern name))
  (kittymacs-nix-all))

;;; kittymacs-nix-selection.el ends here
