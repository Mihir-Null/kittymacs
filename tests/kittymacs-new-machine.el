;;; kittymacs-new-machine.el --- A new machine, start by start -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-new-machine.el
;;
;; `just test-new-machine'.  Needs the network, as a new machine does.  In a temporary
;; copy with an empty var/, no private.el and no host files, each start is a separate
;; Emacs replaying a real one, and the checks read what it leaves for the next.
;; The verifier cannot do this: it always writes a private.el, so it is never new.

;;; Code:
(defconst kittymacs-new-source
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defconst kittymacs-new-root
  (file-name-as-directory (make-temp-file "kittymacs-new-machine-" t)))
(defvar kittymacs-new-failures nil)

(defun kittymacs-new-check (ok description)
  "Record DESCRIPTION unless OK."
  (princ (format "  %s %s\n" (if ok "ok  " "FAIL") description))
  (unless ok (push description kittymacs-new-failures)))

(defun kittymacs-new-path (file)
  "Return FILE's name in the temporary machine."
  (expand-file-name file kittymacs-new-root))

(defun kittymacs-new-file-p ()
  "Return non-nil when a compiled quickstart file exists."
  (let ((cache (kittymacs-new-path "var/cache/")))
    (and (file-directory-p cache) (directory-files cache nil "\\`package-quickstart-.*\\.elc\\'"))))

(defun kittymacs-new-run (&rest arguments)
  "Run Emacs on the temporary machine with ARGUMENTS, and return (STATUS . OUTPUT)."
  (with-temp-buffer
    (let ((status (apply #'call-process (expand-file-name invocation-name invocation-directory)
                         nil t nil "-Q" "--batch"
                         "--eval" (format "(setq user-emacs-directory %S)" kittymacs-new-root)
                         arguments)))
      (cons status (buffer-string)))))

(defun kittymacs-new-start (title)
  "Replay one start, as the verifier does; print TITLE, and return what it reports."
  (princ (format "%s\n" title))
  (let* ((report (make-temp-file "kittymacs-new-report-"))
         (run (kittymacs-new-run
               "--eval" "(setq kittymacs-host-directories nil native-comp-jit-compilation nil package-native-compile nil after-init-time nil kittymacs-new-warnings nil)"
               "--eval" "(advice-add 'display-warning :before (lambda (type message &optional level &rest _) (unless (or (eq level :debug) (eq type 'bytecomp)) (push (format \"%S: %s\" type message) kittymacs-new-warnings))))"
               "-l" (kittymacs-new-path "early-init.el") "-l" (kittymacs-new-path "init.el")
               "--eval"
               (format "%S"
                       `(let ((armed nil))
                          (setq after-init-time (current-time))
                          (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
                          ;; Batch never goes idle, so run what was waiting for that.
                          (dolist (timer timer-idle-list)
                            (when (eq (timer--function timer) 'kittymacs-quickstart--settle)
                              (setq armed t)
                              (funcall (timer--function timer))))
                          (with-temp-file ,report
                            (prin1 (list :loaded kittymacs-quickstart-loaded
                                         :armed armed
                                         :profile (kittymacs-features-profile)
                                         :org (featurep 'org)
                                         :visual-regexp (and (memq 'visual-regexp package-activated-list) t)
                                         :warnings kittymacs-new-warnings)
                                   (current-buffer)))
                          (setq kill-emacs-hook nil))))))
    (kittymacs-new-check (eql (car run) 0) (format "the start exited %S" (car run)))
    (kittymacs-new-check (not (string-match-p "package-quickstart-[^\n]*Warning" (cdr run)))
                         "writing the file printed no compile warning")
    (let ((result (with-temp-buffer (insert-file-contents report) (read (current-buffer)))))
      (delete-file report)
      (kittymacs-new-check (null (plist-get result :warnings))
                           (format "no warning: %S" (plist-get result :warnings)))
      (kittymacs-new-check (eq (plist-get result :profile) 'minimal) "minimal resolves")
      result)))

(defun kittymacs-new-loaded (title expected)
  "Start under TITLE, and check whether it loaded from the file against EXPECTED."
  (let ((result (kittymacs-new-start title)))
    ;; Not on the first start, which compiles what it installs.
    (kittymacs-new-check (not (plist-get result :org)) "Org waits for its first use")
    (kittymacs-new-check (eq (and (plist-get result :loaded) t) expected)
                         (format "%s the file" (if expected "loaded from" "did not load")))
    (kittymacs-new-check (eq (and (kittymacs-new-file-p) t) expected)
                         (format "the file is %s" (if expected "there" "not there")))
    result))

(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file kittymacs-new-source) (kittymacs-new-path file)))
(dolist (directory '("lisp" "literate" "tools"))
  (copy-directory (expand-file-name directory kittymacs-new-source)
                  (kittymacs-new-path directory) nil t))
(let ((private (kittymacs-new-path "lisp/private.el")))
  (when (file-exists-p private) (delete-file private))
  (when (file-directory-p (kittymacs-new-path "var"))
    (delete-directory (kittymacs-new-path "var") t))
  (kittymacs-new-check (not (plist-get (kittymacs-new-start "First start: it installs") :loaded))
                       "the first start scanned")
  (kittymacs-new-check (file-exists-p (kittymacs-new-path "var/started-on-default")) "it has the stamp")
  (kittymacs-new-check (kittymacs-new-file-p) "the file is there once the start has gone idle")
  (kittymacs-new-loaded "Second start" t)
  (kittymacs-new-loaded "Third start" t)
  ;; A feature selected since: it must install, and the file must come to hold it.
  (with-temp-file private (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-features '(visual-replace))\n"))
  (kittymacs-new-check (plist-get (kittymacs-new-loaded "A selected feature installs" t) :visual-regexp)
                       "its package is active")
  (kittymacs-new-check (plist-get (kittymacs-new-loaded "Next start" t) :visual-regexp)
                       "the refreshed file activates it")
  ;; Off stays off, and asking turns it on again.
  (kittymacs-new-run "-l" (kittymacs-new-path "early-init.el") "-f" "kittymacs-quickstart-remove")
  (kittymacs-new-loaded "After removing it" nil)
  (kittymacs-new-loaded "The start after that" nil)
  (kittymacs-new-run "-l" (kittymacs-new-path "early-init.el") "-f" "kittymacs-quickstart-write")
  (kittymacs-new-check (not (file-exists-p (kittymacs-new-path "var/quickstart-off")))
                       "writing it deletes the opt-out")
  (kittymacs-new-loaded "After asking for it again" t)
  ;; A machine with packages and no stamp is not new: no file, nothing waiting.
  (kittymacs-new-run "-l" (kittymacs-new-path "early-init.el") "-f" "kittymacs-quickstart--delete")
  (delete-file (kittymacs-new-path "var/started-on-default"))
  (with-temp-file private (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-profile 'minimal)\n"))
  (dotimes (_ 2)
    (kittymacs-new-check (not (plist-get (kittymacs-new-loaded "No stamp, and a chosen profile" nil) :armed))
                         "nothing is waiting to write it")))

(delete-directory kittymacs-new-root t)
(princ (format "\nKITTYMACS-NEW-MACHINE %s\nFailures: %S\n"
               (if kittymacs-new-failures "FAIL" "PASS") (reverse kittymacs-new-failures)))
(kill-emacs (if kittymacs-new-failures 1 0))

;;; kittymacs-new-machine.el ends here
