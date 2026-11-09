;;; nixos.el --- Native Windows Emacs against a real NixOS-WSL distribution -*- lexical-binding: t; -*-
;; Run by tests/wsl-backend/nixos.ps1, in a process it can kill.
;;
;; It starts the real configuration, as connect.el does, and connects to NixOS-WSL
;; through `:transport wsl' with Tramp's traces at level 6.  Every few seconds it
;; writes Tramp's debug and connection buffers to the results directory, so a run
;; that stalls and gets killed still leaves them.  A table goes to standard output,
;; and a line after it says PASS or FAIL.
;;
;; The environment names the run:
;;   KITTYMACS_WSL_DISTRIBUTION  the distribution
;;   KITTYMACS_WSL_RESULTS       where the buffers go
;;   KITTYMACS_TEST_PACKAGES     the package directory

;;; Code:
(require 'cl-lib)
(require 'package)

(defvar tramp-connection-timeout)
(defvar tramp-dont-suspend-timers)
(defvar tramp-verbose)
(declare-function tramp-cleanup-connection "tramp-cmds" (vec &optional keep-debug keep-password keep-processes))
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function tramp-get-remote-path "tramp-sh" (vec))
(declare-function kittymacs-backend-root "kittymacs-remote" (name))
(declare-function kittymacs-backend-connect "kittymacs-remote" (name))
(declare-function kittymacs-backend-doctor "kittymacs-remote" (name))

(defconst nixos-source
  (file-name-directory (directory-file-name
                        (file-name-directory
                         (directory-file-name (file-name-directory load-file-name))))))
(defconst nixos-distribution (getenv "KITTYMACS_WSL_DISTRIBUTION"))
(defconst nixos-results (file-name-as-directory (getenv "KITTYMACS_WSL_RESULTS")))

(defvar nixos-rows nil "Each check so far: (NAME SECONDS OK DETAIL).")

;; Tramp's traces, before Tramp loads, and its timers kept running while it waits,
;; so the dump below and each check's limit still fire during a stall.
(setq tramp-verbose 6
      tramp-dont-suspend-timers t)

(defun nixos-dump ()
  "Write each Tramp buffer to the results directory."
  (dolist (buffer (buffer-list))
    (let ((name (buffer-name buffer)))
      (when (string-match-p "\\`\\*\\(debug \\)?tramp/" name)
        (with-current-buffer buffer
          (let ((coding-system-for-write 'utf-8-unix))
            (write-region nil nil
                          (expand-file-name
                           (concat (replace-regexp-in-string "[^[:alnum:].-]+" "-" (string-trim name "\\*" "\\*"))
                                   ".txt")
                           nixos-results)
                          nil 'silent)))))))

(run-at-time 5 5 #'nixos-dump)

(defun nixos-check (name limit function)
  "Call FUNCTION under LIMIT seconds, and record it as NAME.
FUNCTION returns a string saying what it saw, or signals.  A stall is a failure."
  (let ((began (float-time)) ok detail)
    (condition-case err
        (let ((value (with-timeout (limit 'stalled) (funcall function))))
          (if (eq value 'stalled)
              (setq detail (format "no answer in %d s" limit))
            (setq ok t detail value)))
      ((error quit) (setq detail (error-message-string err))))
    (push (list name (- (float-time) began) ok detail) nixos-rows)
    (message "%s: %.3f s %s %s" name (- (float-time) began) (if ok "ok" "FAILED") detail)
    (nixos-dump)
    ok))

(defun nixos-expect (expected actual)
  "Return ACTUAL if it contains EXPECTED, and signal if it does not."
  (unless (string-search expected actual)
    (error "Expected %S, and got %S" expected actual))
  (string-trim actual))

;;; The start, as connect.el makes it

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-nixos-" t))
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      native-comp-jit-compilation nil)
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file nixos-source)
             (expand-file-name file user-emacs-directory)))
(dolist (directory '("lisp" "literate" "tools"))
  (copy-directory (expand-file-name directory nixos-source)
                  (expand-file-name directory user-emacs-directory) nil t))
(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-profile 'full)\n"
          (format "(setopt kittymacs-backends '((\"nixos\" :transport wsl :host %S :root \"~/\")))\n"
                  nixos-distribution)))
(advice-add 'kittymacs-activate-packages :before
            (lambda (&rest _) (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES"))))
(advice-add 'y-or-n-p :override #'ignore)
(advice-add 'yes-or-no-p :override #'ignore)

(nixos-check
 "start, without loading Tramp" 600
 (lambda ()
   (setq after-init-time nil)
   (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
   (load user-init-file nil t)
   (setq after-init-time (current-time))
   (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
   (when (featurep 'tramp) (error "The start loaded Tramp"))
   (format "%s, %s" (emacs-version) system-type)))

;;; The connection

(defun nixos-vec ()
  "Return the backend's Tramp connection."
  (tramp-dissect-file-name (kittymacs-backend-root "nixos")))

(defun nixos-connect ()
  "Connect as `SPC o b' does, without the project prompt, and return the root."
  (let (opened)
    (cl-letf (((symbol-function 'project-switch-project)
               (lambda (directory) (setq opened directory))))
      (kittymacs-backend-connect "nixos"))
    (unless (equal opened (kittymacs-backend-root "nixos"))
      (error "Opened %S" opened))
    opened))

;; Past Tramp's own 60 s wait for a prompt, so its error shows instead of ours.
(setq tramp-connection-timeout 90)

(nixos-check
 "connect, the distribution stopped" 150
 (lambda ()
   (message "Tramp's method: %S" (assoc "wslm" (bound-and-true-p tramp-methods)))
   (nixos-connect)))

(nixos-check
 "the PATH Tramp set" 30
 (lambda ()
   (nixos-expect "/run/current-system/sw/bin"
                 (string-join (tramp-get-remote-path (nixos-vec)) ":"))))

(nixos-check
 "process-file: uname, and who and where" 60
 (lambda ()
   (let ((default-directory (kittymacs-backend-root "nixos")))
     (with-temp-buffer
       (unless (eql 0 (process-file "/bin/sh" nil t nil "-c" "uname -r; id -un; echo $HOME"))
         (error "It failed: %s" (buffer-string)))
       (nixos-expect "microsoft-standard-WSL2" (buffer-string))))))

(nixos-check
 "write a file, read it back" 60
 (lambda ()
   (let ((file (concat (kittymacs-backend-root "nixos") "kittymacs-nixos")))
     (write-region "hello\n" nil file nil 'silent)
     (with-temp-buffer
       (insert-file-contents file)
       (nixos-expect "hello" (buffer-string))))))

(defun nixos-wait-for (process text limit)
  "Wait up to LIMIT seconds for TEXT in PROCESS's buffer, and return its text."
  (let ((end (+ (float-time) limit)))
    (with-current-buffer (process-buffer process)
      (while (and (not (string-search text (buffer-string)))
                  (process-live-p process)
                  (< (float-time) end))
        (accept-process-output process 0.1))
      (buffer-string))))

(nixos-check
 "a direct process" 60
 (lambda ()
   (let* ((default-directory (kittymacs-backend-root "nixos"))
          (process (make-process :name "direct" :buffer (generate-new-buffer " *direct*")
                                 :noquery t :file-handler t :connection-type 'pipe
                                 :command '("/bin/sh" "-c" "echo direct-$((40+2))"))))
     (nixos-expect "direct-42" (nixos-wait-for process "direct-42" 30)))))

;; Through /bin/sh, as `M-x shell' runs it, whose prompt no one checks.
(nixos-check
 "M-x shell" 60
 (lambda ()
   (let* ((default-directory (kittymacs-backend-root "nixos"))
          (process (get-buffer-process (shell (generate-new-buffer-name "*nixos-shell*")))))
     (process-send-string process "echo shell-$((40+2)); exit\n")
     (nixos-expect "shell-42" (nixos-wait-for process "shell-42" 30)))))

(dolist (round '(2 3))
  (nixos-check
   (format "connect, the distribution running, round %d" round) 150
   (lambda ()
     (tramp-cleanup-connection (nixos-vec) t)
     (nixos-connect))))

(nixos-check
 "the doctor" 60
 (lambda ()
   (mapconcat (lambda (tool) (format "%s=%s" (car tool) (if (cdr tool) "yes" "no")))
              (kittymacs-backend-doctor "nixos") " ")))

;;; The report

(let ((rows (reverse nixos-rows)))
  (princ "\n| Check | Seconds | Result | Detail |\n|---|---:|---|---|\n")
  (pcase-dolist (`(,name ,seconds ,ok ,detail) rows)
    (princ (format "| %s | %.3f | %s | %s |\n" name seconds (if ok "pass" "FAIL")
                   (string-replace "|" "/" (string-replace "\n" " " (or detail ""))))))
  (let ((passed (cl-every #'caddr rows)))
    (princ (if passed "\nPASS\n" "\nFAIL\n"))
    (kill-emacs (if passed 0 1))))

;;; nixos.el ends here
