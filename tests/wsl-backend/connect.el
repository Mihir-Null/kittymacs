;;; connect.el --- Native Windows Emacs against a real WSL2 distribution -*- lexical-binding: t; -*-
;; Run by tests/wsl-backend/run.ps1, in a process it can kill.
;;
;; It starts the real configuration, so the remote module's guards and settings
;; are in play, then uses `:transport wsl' as a person would.  A table goes to
;; standard output, a line after it says PASS or FAIL, and the exit status agrees.
;;
;; The environment names the run:
;;   KITTYMACS_WSL_DISTRIBUTION  the distribution, which holds ~/project/file
;;   KITTYMACS_WSL_KERNEL        what `uname -r' must contain there
;;   KITTYMACS_TEST_PACKAGES     the package directory

;;; Code:
(require 'cl-lib)
(require 'package)

(defvar tramp-connection-timeout)
(defvar tramp-dont-suspend-timers nil)
(defvar kittymacs-backends)
(defvar kittymacs-host-directories nil)
(declare-function tramp-cleanup-connection "tramp-cmds" (vec &optional keep-debug keep-password keep-processes))
(declare-function tramp-direct-async-process-p "tramp" (&rest args))
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function kittymacs-backend-root "kittymacs-remote" (name))
(declare-function kittymacs-backend-connect "kittymacs-remote" (name))
(declare-function kittymacs-backend-doctor "kittymacs-remote" (name))

(defconst wsl-backend-source
  (file-name-directory (directory-file-name
                        (file-name-directory
                         (directory-file-name (file-name-directory load-file-name))))))
(defconst wsl-backend-distribution (getenv "KITTYMACS_WSL_DISTRIBUTION"))

(defvar wsl-backend-rows nil "Each check so far: (NAME SECONDS OK DETAIL).")

(defun wsl-backend-check (name limit function)
  "Call FUNCTION under LIMIT seconds, and record it as NAME.
FUNCTION returns a string saying what it saw, or signals.  A stall is a failure.
Tramp suspends timers while it waits unless told not to, and the limit is a timer."
  (let ((began (float-time)) ok detail)
    (condition-case err
        (let* ((tramp-dont-suspend-timers t)
               (value (with-timeout (limit 'stalled) (funcall function))))
          (if (eq value 'stalled)
              (setq detail (format "no answer in %d s" limit))
            (setq ok t detail value)))
      ((error quit) (setq detail (error-message-string err))))
    (push (list name (- (float-time) began) ok detail) wsl-backend-rows)
    (message "%s: %.3f s %s %s" name (- (float-time) began) (if ok "ok" "FAILED") detail)
    ok))

(defun wsl-backend-expect (expected actual)
  "Return ACTUAL if it contains EXPECTED, and signal if it does not."
  (unless (string-search expected actual)
    (error "Expected %S, and got %S" expected actual))
  (string-trim actual))

;;; The start

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-wsl-" t))
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      native-comp-jit-compilation nil)
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file wsl-backend-source)
             (expand-file-name file user-emacs-directory)))
(dolist (directory '("lisp" "literate" "tools"))
  (copy-directory (expand-file-name directory wsl-backend-source)
                  (expand-file-name directory user-emacs-directory) nil t))
(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-profile 'full)\n"
          (format "(setopt kittymacs-backends '((\"wsl\" :transport wsl :host %S :root \"~/project/\")))\n"
                  wsl-backend-distribution)))
(advice-add 'kittymacs-activate-packages :before
            (lambda (&rest _) (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES"))))
;; Nothing here answers a prompt: the grammar offer, say.
(advice-add 'y-or-n-p :override #'ignore)
(advice-add 'yes-or-no-p :override #'ignore)

(wsl-backend-check
 "start, without loading Tramp" 600
 (lambda ()
   (setq after-init-time nil)
   (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
   (load user-init-file nil t)
   (setq after-init-time (current-time))
   (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
   (when (featurep 'tramp) (error "The start loaded Tramp"))
   (format "%s, %s" (emacs-version) system-type)))

;;; The transport

(defun wsl-backend-root ()
  "Return the backend's root, which loads Tramp."
  (kittymacs-backend-root "wsl"))

(defun wsl-backend-file (name)
  "Return the file NAME under the backend's root."
  (concat (wsl-backend-root) name))

(defun wsl-backend-disconnect ()
  "Drop the connection and what Tramp cached about it."
  (tramp-cleanup-connection (tramp-dissect-file-name (wsl-backend-root))))

(defun wsl-backend-wait-for (process text limit)
  "Wait up to LIMIT seconds for TEXT in PROCESS's buffer, and return the buffer's text."
  (let ((end (+ (float-time) limit)))
    (with-current-buffer (process-buffer process)
      (while (and (not (string-search text (buffer-string)))
                  (process-live-p process)
                  (< (float-time) end))
        (accept-process-output process 0.1))
      (buffer-string))))

(wsl-backend-check
 "the backend's name" 60
 (lambda () (wsl-backend-expect (format "/wslm:%s:" wsl-backend-distribution) (wsl-backend-root))))

(setq tramp-connection-timeout 45)

(dolist (round '(1 2 3))
  (wsl-backend-check
   (format "connect, round %d" round) 75
   (lambda ()
     (let (opened)
       (cl-letf (((symbol-function 'project-switch-project)
                  (lambda (directory) (setq opened directory))))
         (kittymacs-backend-connect "wsl"))
       (unless (equal opened (wsl-backend-root))
         (error "Opened %S" opened))
       (prog1 opened
         (when (< round 3) (wsl-backend-disconnect)))))))

(wsl-backend-check
 "process-file: a real WSL2 kernel" 60
 (lambda ()
   (let ((default-directory (wsl-backend-root)))
     (with-temp-buffer
       (unless (eql 0 (process-file "uname" nil t nil "-r"))
         (error "uname failed: %s" (buffer-string)))
       (wsl-backend-expect (getenv "KITTYMACS_WSL_KERNEL") (buffer-string))))))

(wsl-backend-check
 "open a file, save it, read it back" 60
 (lambda ()
   (let ((buffer (find-file-noselect (wsl-backend-file "file"))))
     (unwind-protect
         (with-current-buffer buffer
           (wsl-backend-expect "hello" (buffer-string))
           (goto-char (point-max))
           (insert "saved\n")
           (save-buffer)
           (with-temp-buffer
             (insert-file-contents (wsl-backend-file "file"))
             (wsl-backend-expect "saved" (buffer-string))))
       (with-current-buffer buffer (set-buffer-modified-p nil))
       (kill-buffer buffer)))))

(wsl-backend-check
 "a direct process" 60
 (lambda ()
   (let ((default-directory (wsl-backend-root)))
     (unless (tramp-direct-async-process-p)
       (error "Processes do not start directly"))
     (let* ((buffer (generate-new-buffer " *direct*"))
            (process (make-process :name "direct" :buffer buffer :noquery t
                                   :file-handler t :connection-type 'pipe
                                   :command '("/bin/sh" "-c" "echo direct-$((40+2))"))))
       (wsl-backend-expect "direct-42" (wsl-backend-wait-for process "direct-42" 30))))))

(wsl-backend-check
 "M-x shell" 60
 (lambda ()
   (let* ((default-directory (wsl-backend-root))
          (buffer (shell (generate-new-buffer-name "*wsl-shell*")))
          (process (get-buffer-process buffer)))
     (process-send-string process "echo shell-$((40+2)); exit\n")
     (wsl-backend-expect "shell-42" (wsl-backend-wait-for process "shell-42" 30)))))

(wsl-backend-check
 "the doctor" 60
 (lambda ()
   (let ((tools (kittymacs-backend-doctor "wsl")))
     (mapconcat (lambda (tool) (format "%s=%s" (car tool) (if (cdr tool) "yes" "no")))
                tools " "))))

;;; Where a program's variables come from: what \"A backend's environment\" says

(defvar tramp-remote-process-environment)

(defun wsl-backend-environment-report (text)
  "Return whether TEXT shows the variables, as a string for the report."
  (format "profile=%s list=%s"
          (if (string-search "profile-value" text) "yes" "no")
          (if (string-search "list-value" text) "yes" "no")))

(wsl-backend-check
 "the environment, for the record and the chapter's table" 120
 (lambda ()
   (let ((default-directory (wsl-backend-root))
         (command "echo \"$KITTYMACS_PROFILE_VAR $KITTYMACS_LIST_VAR\"; echo done")
         (tramp-remote-process-environment
          (cons "KITTYMACS_LIST_VAR=list-value" tramp-remote-process-environment)))
     (with-temp-file (concat (file-remote-p default-directory) "~/.profile")
       (insert "export KITTYMACS_PROFILE_VAR=profile-value\n"))
     (wsl-backend-disconnect)
     (let* ((through-shell
             (with-temp-buffer
               (process-file "/bin/sh" nil t nil "-c" command)
               (buffer-string)))
            (direct
             (let* ((buffer (generate-new-buffer " *environment*"))
                    (process (make-process :name "environment" :buffer buffer :noquery t
                                           :file-handler t :connection-type 'pipe
                                           :command (list "/bin/sh" "-c" command))))
               (wsl-backend-wait-for process "done" 30)))
            (slow
             (let* ((tramp-direct-async-process nil)
                    (buffer (generate-new-buffer " *environment slow*"))
                    (process (with-connection-local-variables
                              (make-process :name "environment-slow" :buffer buffer :noquery t
                                            :file-handler t :connection-type 'pipe
                                            :command (list "/bin/sh" "-c" command)))))
               (wsl-backend-wait-for process "done" 30)))
            (shell
             (let* ((buffer (shell (generate-new-buffer-name "*environment shell*")))
                    (process (get-buffer-process buffer)))
               (process-send-string process (concat command "; exit\n"))
               (wsl-backend-wait-for process "done" 30))))
       (format "process-file: %s; direct: %s; through Tramp's shell: %s; M-x shell: %s"
               (wsl-backend-environment-report through-shell)
               (wsl-backend-environment-report direct)
               (wsl-backend-environment-report slow)
               (wsl-backend-environment-report shell))))))

;; This check would pass if connecting could never fail.  So a distribution that
;; does not exist must not look like one that answers.
(wsl-backend-check
 "a distribution that does not exist is refused" 75
 (lambda ()
   (let ((name (concat "/wslm:no-such-distribution:/tmp")))
     (when (condition-case nil (file-exists-p name) (error nil))
       (error "%s answered" name))
     "refused")))

;;; The report

(let ((rows (reverse wsl-backend-rows)))
  ;; The blank line keeps the table apart from whatever the start wrote to the terminal.
  (princ "\n| Check | Seconds | Result | Detail |\n|---|---:|---|---|\n")
  (pcase-dolist (`(,name ,seconds ,ok ,detail) rows)
    (princ (format "| %s | %.3f | %s | %s |\n" name seconds (if ok "pass" "FAIL")
                   (string-replace "|" "/" (string-replace "\n" " " (or detail ""))))))
  (let ((passed (cl-every #'caddr rows)))
    (princ (if passed "\nPASS\n" "\nFAIL\n"))
    (kill-emacs (if passed 0 1))))

;;; connect.el ends here
