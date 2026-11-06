;;; connect.el --- Native Windows Emacs against a real WSL2 distribution -*- lexical-binding: t; -*-
;; Run by tests/wsl-backend/run.ps1, in a process it can kill.
;;
;; It starts the real configuration, so the remote module's guards and settings
;; are in play, then uses `:transport wsl' as a person would, and reports how long
;; a 1 MiB write takes through the pipe the start set up.  A table goes to
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
(defvar w32-pipe-buffer-size)
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

;; Random bytes, because Tramp compresses a large file on its way, and a repeated
;; byte would shrink until the pipe no longer mattered.
(defconst wsl-backend-megabyte
  (let ((bytes (make-string (* 1024 1024) 0)))
    (dotimes (index (length bytes) bytes)
      (aset bytes index (random 256)))))

;; It reports the time and does not judge it, because hosted runners vary.  The
;; limit only tells a stall from a slow write: this took 4.43 s with the small pipe.
(wsl-backend-check
 "write 1 MiB through the 1 MiB pipe" 120
 (lambda ()
   (unless (= w32-pipe-buffer-size (* 1024 1024))
     (error "The start left w32-pipe-buffer-size at %d" w32-pipe-buffer-size))
   (let ((file (wsl-backend-file "megabyte"))
         (coding-system-for-write 'binary))
     (write-region wsl-backend-megabyte nil file nil 'silent)
     (let ((size (file-attribute-size (file-attributes file))))
       (unless (eql size (length wsl-backend-megabyte))
         (error "%s bytes arrived" size))
       (format "%d bytes arrived" size)))))

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

;;; The terminal

(declare-function ghostel "ghostel" (&optional arg))
(declare-function ghostel--download-module "ghostel-module-install" (dir &optional version latest-release))
(declare-function ghostel--load-module "ghostel-module-install" (&optional prompt-user))
(declare-function ghostel--module-directory "ghostel-module-install" ())
(declare-function ghostel--resolve-shell-spec "ghostel-shell" ())
(declare-function ghostel-send-string "ghostel" (string))
(declare-function kittymacs-terminal-open "kittymacs-terminal" (&optional arg))
(defvar ghostel-buffer-name)
(defvar ghostel-use-native-pty)
(defvar ghostel-module-auto-install)

(defun wsl-backend-terminal-facts (file newline limit)
  "Have this buffer's terminal write what it is to FILE, and return that text.
FILE is under the backend's root, and NEWLINE ends the command, since a pty and a
pipe want different ones.  Signals after LIMIT seconds."
  (ghostel-send-string
   (format "{ tty; stty size; echo \"login=$0 pwd=$PWD distro=$WSL_DISTRO_NAME term=$TERM shell=$SHELL\"; } > %s 2>&1%s"
           file newline))
  (let ((remote (wsl-backend-file file))
        (end (+ (float-time) limit))
        (remote-file-name-inhibit-cache t))
    (while (and (< (float-time) end) (not (file-exists-p remote)))
      (accept-process-output nil 0.5))
    (accept-process-output nil 1)
    (unless (file-exists-p remote)
      (error "No %s after %d s; the terminal shows: %s" file limit
             (string-trim (buffer-substring-no-properties (point-min) (point-max)))))
    (with-temp-buffer
      (insert-file-contents remote)
      (buffer-string))))

(wsl-backend-check
 "the terminal's native module loads" 180
 (lambda ()
   (require 'ghostel)
   (let ((directory (ghostel--module-directory)))
     (unless (ghostel--download-module directory)
       (error "The download failed: see the log"))
     (ghostel--load-module)
     (unless (fboundp 'ghostel--new)
       (error "The module did not load"))
     (format "%s" (directory-files directory nil "\\`[^.]")))))

(wsl-backend-check
 "SPC o e: a login shell on a real pty, in the project" 100
 (lambda ()
   (let* ((default-directory (wsl-backend-root))
          (buffer (kittymacs-terminal-open)))
     (with-current-buffer buffer
       (unless (equal (file-remote-p default-directory) (file-remote-p (wsl-backend-root)))
         (error "The terminal's buffer left the backend: %s" default-directory))
       ;; A first start of a distribution eats what is typed before the prompt.
       (message "terminal: waiting for the prompt")
       (let ((end (+ (float-time) 60)))
         (while (and (< (float-time) end)
                     (not (string-match-p "project\\$ *$" (buffer-string))))
           (accept-process-output nil 0.5)))
       (message "terminal: sending the command")
       (let ((facts (wsl-backend-terminal-facts "terminal-facts" "\r" 20)))
         (message "terminal: facts %S" facts)
         (wsl-backend-expect "/dev/pts/" facts)
         (wsl-backend-expect "login=-bash" facts)
         (wsl-backend-expect "pwd=/home/backend/project" facts)
         (wsl-backend-expect (format "distro=%s" wsl-backend-distribution) facts)
         (string-replace "\n" " " facts))))))

(wsl-backend-check
 "Tramp finds the login shell" 60
 (lambda ()
   (let ((default-directory (wsl-backend-root)))
     (wsl-backend-expect "/bin/bash" (format "%S" (ghostel--resolve-shell-spec))))))

;; For the record, and it fails nothing: this is why `SPC o e' does not take this path.
(wsl-backend-check
 "a terminal through Tramp, for the record" 120
 (lambda ()
   (condition-case err
       (with-timeout (90 "no answer in 90 s")
         (let* ((default-directory (wsl-backend-root))
                (ghostel-use-native-pty nil)
                (ghostel-buffer-name "*through Tramp*"))
           (with-current-buffer (ghostel)
             (string-replace "\n" " " (wsl-backend-terminal-facts "tramp-facts" "\n" 45)))))
     (error (format "failed: %s" (error-message-string err))))))

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
