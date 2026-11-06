;;; kittymacs-feature-probes.el --- Each feature turns off and on, and Emacs still starts -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=<dir> emacs -Q --batch -l tests/kittymacs-feature-probes.el
;; or `just test-features'.  <dir> holds every feature's packages:
;; KITTYMACS_TEST_PROFILE=every just install makes one.
;;
;; A real start for each selection, in a process of its own: every feature
;; beyond the minimal profile off in turn from `full', and on in turn from
;; `minimal'.  Each start activates only the packages its selection needs, through
;; `package-load-list', so one directory stands in for a separate one per
;; selection: leftovers can't hide a missing dependency or a key that lost its
;; package.  Nothing is installed.
;;
;; KITTYMACS_PROBE_ONLY, a regexp, narrows the list to the names it matches.

;;; Code:
(require 'cl-lib)
(require 'package)
(require 'seq)

(defconst kittymacs-probe-source
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))

(defconst kittymacs-probe-this-file load-file-name)

(defvar kittymacs-catalogue)

;;; One start

(defvar kittymacs-probe-warnings nil
  "Warnings shown while this start ran.")

(defvar kittymacs-probe-failures nil
  "What is wrong with this start.")

(defun kittymacs-probe--record-warning (type message &optional level &rest _)
  "Remember a startup warning of TYPE with MESSAGE at LEVEL."
  (require 'warnings)
  (unless (or (eq level :debug) (warning-suppress-p type warning-suppress-types))
    (push (format "%S: %s" type message) kittymacs-probe-warnings)))

(defun kittymacs-probe--needed-packages (spec)
  "Return the packages that the selection SPEC needs, from what is installed."
  (let ((kittymacs-profile (plist-get spec :profile))
        (kittymacs-features (plist-get spec :features))
        (kittymacs-features-excluded (plist-get spec :excluded)))
    (cl-letf (((symbol-function 'display-warning) #'ignore))
      (kittymacs-features-resolve))
    (kittymacs-check--closure (kittymacs-check-packages-on))))

(defun kittymacs-probe--activate-only (needed)
  "Make `package-initialize' activate the packages in NEEDED and no others."
  (setq package-load-list
        (append (mapcar (lambda (entry) (list (car entry) nil))
                        (seq-remove (lambda (entry) (memq (car entry) needed))
                                    package-alist))
                '(all))))

(defun kittymacs-probe--write-private (spec)
  "Write a private.el with the selection SPEC, where the configuration looks."
  (with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
    (insert ";;; -*- lexical-binding: t; -*-\n"
            (format "(setopt kittymacs-profile '%s)\n" (plist-get spec :profile))
            (format "(setopt kittymacs-features '%S)\n" (plist-get spec :features))
            (format "(setopt kittymacs-features-excluded '%S)\n" (plist-get spec :excluded)))))

(defun kittymacs-probe--example-keys (feature)
  "Return the `SPC' keys that FEATURE's example in the catalogue quotes."
  (let ((text (plist-get (alist-get feature kittymacs-catalogue) :example))
        (start 0)
        keys)
    (while (string-match "=SPC \\([^=]+\\)=" text start)
      (push (match-string 1 text) keys)
      (setq start (match-end 0)))
    keys))

(defun kittymacs-probe--check-selection (spec)
  "Check the start against what the selection SPEC should have done."
  (dolist (feature (plist-get spec :off))
    (when (kittymacs-feature-p feature)
      (push (format "%s is on" feature) kittymacs-probe-failures))
    (when-let* ((module (alist-get feature kittymacs-check-chapter-features)))
      (when (featurep module)
        (push (format "%s loaded with %s off" module feature) kittymacs-probe-failures))))
  (dolist (package (kittymacs-check--packages-off))
    (when (featurep package)
      (push (format "%s loaded, and no feature that is on needs it" package)
            kittymacs-probe-failures)))
  (dolist (feature (plist-get spec :on))
    (unless (kittymacs-feature-p feature)
      (push (format "%s is off" feature) kittymacs-probe-failures))
    (when-let* ((module (alist-get feature kittymacs-check-chapter-features)))
      (unless (featurep module)
        (push (format "%s did not load with %s on" module feature) kittymacs-probe-failures)))
    (dolist (keys (kittymacs-probe--example-keys feature))
      (let ((binding (lookup-key kittymacs-leader-map (kbd keys))))
        (unless (or (commandp binding) (keymapp binding))
          (push (format "SPC %s, in %s's example, is not bound" keys feature)
                kittymacs-probe-failures))))))

(defun kittymacs-probe-one (spec)
  "Start the configuration with the selection SPEC, print the verdict and exit."
  (let ((root (make-temp-file "kittymacs-probe-" t))
        (packages (getenv "KITTYMACS_TEST_PACKAGES")))
    (dolist (fn '(package-install package-vc-install package-refresh-contents))
      (advice-add fn :override
                  (lambda (&rest args)
                    (push (format "Unexpected install: %S" args) kittymacs-probe-failures)
                    (error "Package installation disabled in a probe"))))
    (dolist (file '("early-init.el" "init.el"))
      (copy-file (expand-file-name file kittymacs-probe-source) (expand-file-name file root)))
    (copy-directory (expand-file-name "lisp" kittymacs-probe-source)
                    (expand-file-name "lisp" root) nil t)
    (defvar kittymacs-host-directories nil)
    (defvar kittymacs-org-directory)
    (setq user-emacs-directory (file-name-as-directory root)
          default-directory user-emacs-directory
          user-init-file (expand-file-name "init.el" user-emacs-directory)
          kittymacs-org-directory (expand-file-name "org/" user-emacs-directory)
          native-comp-jit-compilation nil
          package-user-dir packages)
    (make-directory (expand-file-name "var/etc" user-emacs-directory) t)
    (kittymacs-probe--write-private spec)
    (add-to-list 'load-path (expand-file-name "lisp" root))
    (load (expand-file-name "tests/kittymacs-profile-checks.el" kittymacs-probe-source) nil t)
    (require 'kittymacs-features)
    (when-let* ((feature (plist-get spec :lift-not-on)))
      (setf (alist-get feature kittymacs-catalogue)
            (plist-put (copy-sequence (alist-get feature kittymacs-catalogue)) :not-on nil)))
    (package-load-all-descriptors)
    (kittymacs-probe--activate-only (kittymacs-probe--needed-packages spec))
    (advice-add 'package-initialize :before
                (lambda (&rest _) (setq package-user-dir packages)))
    (condition-case err
        (progn
          (setq after-init-time nil)
          (advice-add 'display-warning :before #'kittymacs-probe--record-warning)
          (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
          (load user-init-file nil t)
          (setq after-init-time (current-time))
          (run-hooks 'after-init-hook 'delayed-warnings-hook)
          (run-hooks 'emacs-startup-hook)
          (advice-remove 'display-warning #'kittymacs-probe--record-warning)
          (setq kittymacs-probe-failures
                (append kittymacs-probe-failures (kittymacs-check-start)))
          (kittymacs-probe--check-selection spec)
          (unless (and (keymapp kittymacs-leader-map)
                       (keymapp kittymacs-project-map)
                       (boundp 'kittymacs-wm-keys))
            (push "The public names are gone" kittymacs-probe-failures)))
      (error (push (format "Startup error: %S" err) kittymacs-probe-failures)))
    (unless (= (length kittymacs-probe-warnings) (or (plist-get spec :warnings) 0))
      (push (format "Warnings: %S" (reverse kittymacs-probe-warnings)) kittymacs-probe-failures))
    (setq kill-emacs-hook nil)
    (ignore-errors (delete-directory root t))
    (princ (format "\nKITTYMACS-PROBE %S\n" (reverse kittymacs-probe-failures)))
    (kill-emacs (if kittymacs-probe-failures 1 0))))

;;; Every start

(defun kittymacs-probe--names (profile)
  "Return the catalogue's features whose `:profile' is PROFILE."
  (mapcar #'car (seq-filter (lambda (entry) (eq (plist-get (cdr entry) :profile) profile))
                            kittymacs-catalogue)))

(defun kittymacs-probe--applies-p (feature)
  "Return non-nil if FEATURE runs on this system."
  (not (memq system-type (plist-get (alist-get feature kittymacs-catalogue) :not-on))))

(defun kittymacs-probe--specs ()
  "Return every selection to try, each a property list with a `:name'."
  (append
   (list '(:name "minimal" :profile minimal)
         ;; No Windows here, so the probe lifts the rule that keeps it off this system.
         '(:name "msys2-fallback, as if on Windows" :profile minimal
                 :features (msys2-fallback) :lift-not-on msys2-fallback
                 :on (msys2-fallback) :warnings 1)
         '(:name "full" :profile full)
         '(:name "a name the catalogue lacks" :profile minimal
                 :features (no-such-feature) :warnings 1)
         '(:name "excluding what minimal needs" :profile minimal
                 :excluded (meow) :on (meow) :warnings 1))
   (mapcar (lambda (feature)
             (list :name (format "full without %s" feature) :profile 'full
                   :excluded (list feature) :off (list feature)))
           (kittymacs-probe--names 'full))
   (mapcar (lambda (feature)
             (list :name (format "minimal with %s" feature) :profile 'minimal
                   :features (list feature)
                   :on (and (kittymacs-probe--applies-p feature) (list feature))))
           (append (kittymacs-probe--names 'full) (kittymacs-probe--names 'optional)))))

(defun kittymacs-probe--start (spec)
  "Start a process that probes the selection SPEC; return it."
  (let* ((buffer (generate-new-buffer " *probe*"))
         (process-environment
          (cons (format "KITTYMACS_PROBE=%S" spec) process-environment))
         (process (make-process
                   :name "probe" :buffer buffer :stderr buffer :noquery t
                   :sentinel #'ignore
                   :command (list (expand-file-name invocation-name invocation-directory)
                                  "-Q" "--batch" "-l" kittymacs-probe-this-file))))
    (process-put process 'spec spec)
    (process-put process 'started (float-time))
    process))

(defun kittymacs-probe--verdict (process)
  "Return nil if PROCESS passed, or the text that says what went wrong."
  (let* ((output (with-current-buffer (process-buffer process) (buffer-string)))
         (line (and (string-match "^KITTYMACS-PROBE \\(.*\\)$" output)
                    (match-string 1 output))))
    (kill-buffer (process-buffer process))
    (cond ((and (zerop (process-exit-status process)) (equal line "nil")) nil)
          (line line)
          (t (format "exit %s without a verdict: %s" (process-exit-status process)
                     (string-trim (substring output (max 0 (- (length output) 800)))))))))

(defun kittymacs-probe-all ()
  "Probe every selection, a few at a time; print a table and exit."
  (load (expand-file-name "lisp/kittymacs-catalogue" kittymacs-probe-source) nil t)
  (let* ((only (getenv "KITTYMACS_PROBE_ONLY"))
         (specs (seq-filter (lambda (spec)
                              (or (not only) (string-match-p only (plist-get spec :name))))
                            (kittymacs-probe--specs)))
         (total (length specs))
         (workers (max 1 (min 8 (num-processors))))
         (timeout 300)
         (started (float-time))
         running failed)
    (while (or specs running)
      (while (and specs (< (length running) workers))
        (push (kittymacs-probe--start (pop specs)) running))
      (accept-process-output nil 0.2)
      (dolist (process running)
        (let ((name (plist-get (process-get process 'spec) :name)))
          (cond ((process-live-p process)
                 (when (> (- (float-time) (process-get process 'started)) timeout)
                   (delete-process process)
                   (setq running (delq process running))
                   (push name failed)
                   (princ (format "FAIL %s: over %d seconds\n" name timeout))))
                (t
                 (setq running (delq process running))
                 (if-let* ((verdict (kittymacs-probe--verdict process)))
                     (progn (push name failed)
                            (princ (format "FAIL %s: %s\n" name verdict)))
                   (princ (format "ok   %s\n" name))))))))
    (princ (format "\nKITTYMACS-PROBES %s: %d starts, %d failed, %d seconds\n"
                   (if failed "FAIL" "PASS") total (length failed)
                   (round (- (float-time) started))))
    (kill-emacs (if failed 1 0))))

(if-let* ((spec (getenv "KITTYMACS_PROBE")))
    (kittymacs-probe-one (car (read-from-string spec)))
  (kittymacs-probe-all))

;;; kittymacs-feature-probes.el ends here
