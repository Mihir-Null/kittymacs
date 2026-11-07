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
(require 'seq)

(defvar tramp-connection-timeout)
(defvar tramp-dont-suspend-timers nil)
(defvar kittymacs-backends)
(defvar kittymacs-host-directories nil)
(defvar envrc--status)
(declare-function envrc--get-current-env-or-run-direnv "envrc" (&optional force))
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

;;; Opening from the WSL side

;; First, while Tramp has not loaded, as for someone who has not connected yet.

(declare-function server-start "server" (&optional leave-dead inhibit-prompt))
(defvar server-auth-dir)

(defun wsl-backend-linux-path (file)
  "Return what the distribution calls the Windows FILE."
  (with-temp-buffer
    (unless (eql 0 (call-process "wsl.exe" nil t nil "-d" wsl-backend-distribution
                                 "--exec" "wslpath" "-a"
                                 (string-replace "\\" "/" (expand-file-name file))))
      (error "wslpath failed: %s" (buffer-string)))
    (string-trim (buffer-string))))

(defun wsl-backend-open (name)
  "Run `kittymacs-open' on NAME in the distribution, and return its output and status.
It waits with `accept-process-output', since this Emacs must answer the client."
  (let* ((script (wsl-backend-linux-path
                  (expand-file-name "nix/kittymacs-open.sh" wsl-backend-source)))
         (buffer (generate-new-buffer " *kittymacs-open*"))
         (process (make-process :name "kittymacs-open" :buffer buffer :noquery t
                                :connection-type 'pipe
                                :command (list "wsl.exe" "-d" wsl-backend-distribution
                                               "--cd" "~" "--exec" "sh" script name)))
         (end (+ (float-time) 45)))
    (while (and (process-live-p process) (< (float-time) end))
      (accept-process-output nil 0.2))
    (list (process-status process) (process-exit-status process)
          (with-current-buffer buffer (buffer-string)))))

(defun wsl-backend-wait-for-buffer (file limit)
  "Wait up to LIMIT seconds for a buffer visiting FILE, and return it."
  (let ((end (+ (float-time) limit)) buffer)
    (while (and (< (float-time) end)
                (not (setq buffer (seq-find (lambda (b)
                                              (string-suffix-p file (or (buffer-file-name b) "")))
                                            (buffer-list)))))
      (accept-process-output nil 0.2))
    buffer))

(wsl-backend-check
 "emacsclient.exe is what WSL finds" 60
 (lambda ()
   (with-temp-buffer
     (unless (eql 0 (call-process "wsl.exe" nil t nil "-d" wsl-backend-distribution
                                  "--exec" "sh" "-c" "command -v emacsclient.exe"))
       (error "It is not on the PATH: %s" (buffer-string)))
     (string-trim (buffer-string)))))

;; Where the client looks for the server, since this start's own directory is a
;; temporary one.
(setq server-auth-dir (expand-file-name "~/.emacs.d/server/"))
(require 'server)
(server-start)

(wsl-backend-check
 "kittymacs-open: a Linux file opens on the backend, Tramp loading for it" 75
 (lambda ()
   (when (featurep 'tramp) (error "Tramp has already loaded"))
   (let ((outcome (wsl-backend-open "project/file")))
     (unless (eql 0 (nth 1 outcome))
       (error "kittymacs-open: %S" outcome))
     (let ((buffer (wsl-backend-wait-for-buffer "project/file" 30)))
       (unless buffer (error "No buffer; kittymacs-open said %S" outcome))
       (prog1 (wsl-backend-expect (format "/wslm:%s:/home/backend/project/file"
                                          wsl-backend-distribution)
                                  (buffer-file-name buffer))
         (kill-buffer buffer))))))

(wsl-backend-check
 "kittymacs-open: a folder opens in Dired on the backend" 75
 (lambda ()
   (let* ((outcome (wsl-backend-open "project"))
          (end (+ (float-time) 30))
          (buffer nil))
     (while (and (< (float-time) end)
                 (not (setq buffer (seq-find (lambda (b)
                                               (with-current-buffer b
                                                 (and (derived-mode-p 'dired-mode)
                                                      (file-remote-p default-directory))))
                                             (buffer-list)))))
       (accept-process-output nil 0.2))
     (unless buffer (error "No Dired buffer; kittymacs-open said %S" outcome))
     (prog1 (buffer-local-value 'default-directory buffer)
       (with-current-buffer buffer
         (wsl-backend-expect "file" (buffer-string)))
       (kill-buffer buffer)))))

(wsl-backend-check
 "kittymacs-open: a Windows-side file opens natively" 75
 (lambda ()
   (let* ((file (make-temp-file "kittymacs-open-"))
          (outcome (wsl-backend-open (wsl-backend-linux-path file))))
     (unless (eql 0 (nth 1 outcome))
       (error "kittymacs-open: %S" outcome))
     (let ((buffer (wsl-backend-wait-for-buffer (file-name-nondirectory file) 30)))
       (unless buffer (error "No buffer; kittymacs-open said %S" outcome))
       (when (file-remote-p (buffer-file-name buffer))
         (error "It went through Tramp: %s" (buffer-file-name buffer)))
       (prog1 (buffer-file-name buffer)
         (kill-buffer buffer))))))

;; For the record: emacsclient.exe reads its arguments in the Windows code page.
(wsl-backend-check
 "kittymacs-open: a non-ASCII name, for the record" 75
 (lambda ()
   (let* ((name "caf\u00e9.txt")
          (outcome (wsl-backend-open name))
          (buffer (wsl-backend-wait-for-buffer name 15)))
     (format "%S, %s" outcome
             (if buffer (buffer-file-name buffer)
               (format "no buffer; these are open: %S"
                       (delq nil (mapcar #'buffer-file-name (buffer-list)))))))))

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
;;; A Windows-side file through the backend

(declare-function kittymacs-remote-reopen-natively "kittymacs-remote" ())

(wsl-backend-check
 "a file under /mnt/ says so once, and reopens natively" 60
 (lambda ()
   (let* ((file (format "/wslm:%s:/mnt/c/Windows/win.ini" wsl-backend-distribution))
          (messages (lambda ()
                      (with-current-buffer "*Messages*"
                        (how-many "through WSL is slow" (point-min) (point-max)))))
          (before (funcall messages))
          (buffer (find-file-noselect file))
          (said (- (funcall messages) before)))
     (unless (= said 1) (error "It spoke %d times" said))
     (kill-buffer buffer)
     (setq buffer (find-file-noselect file))
     (unless (= (- (funcall messages) before) 1) (error "It spoke again"))
     (let ((reading-seconds
            (car (benchmark-run 5
                   (let ((remote-file-name-inhibit-cache t))
                     (with-temp-buffer (insert-file-contents file)))))))
       (with-current-buffer buffer (kittymacs-remote-reopen-natively))
       (let ((native (get-file-buffer "c:/Windows/win.ini")))
         (unless native (error "No buffer on the native file"))
         (when (buffer-live-p buffer) (error "The buffer through Tramp is still there"))
         (prog1 (format "five reads through WSL %.3f s, natively %.3f s"
                        reading-seconds
                        (car (benchmark-run 5
                               (with-temp-buffer (insert-file-contents "c:/Windows/win.ini")))))
           (kill-buffer native)))))))
;;; Newlines in a file saved on a backend

(defun wsl-backend-bytes (file)
  "Return FILE's bytes, with nothing decoded."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defun wsl-backend-save-new (file)
  "Open FILE, which does not exist, save two lines in it, and return its bytes."
  (with-current-buffer (find-file-noselect file)
    (insert "one\ntwo\n")
    (save-buffer)
    (kill-buffer))
  (prog1 (wsl-backend-bytes file) (delete-file file)))

(wsl-backend-check
 "a new file has Unix newlines, and an existing one keeps its own" 90
 (lambda ()
   (let ((unix "one\ntwo\n")
         (without (let ((find-file-hook (remq 'kittymacs--remote-unix-newlines find-file-hook)))
                    (wsl-backend-save-new (wsl-backend-file "new-without"))))
         (windows (wsl-backend-file "windows"))
         (named (wsl-backend-file "named")))
     (unless (equal (wsl-backend-save-new (wsl-backend-file "new")) unix)
       (error "A new file has other newlines"))
     (with-current-buffer (generate-new-buffer "no file yet")
       (insert unix)
       (write-file named)
       (kill-buffer))
     (unless (equal (wsl-backend-bytes named) unix)
       (error "A buffer saved to a new name has %S" (wsl-backend-bytes named)))
     (delete-file named)
     (let ((coding-system-for-write 'no-conversion))
       (write-region "a\r\nb\r\n" nil windows))
     (with-current-buffer (find-file-noselect windows)
       (goto-char (point-max))
       (insert "c\n")
       (save-buffer)
       (kill-buffer))
     (unless (equal (wsl-backend-bytes windows) "a\r\nb\r\nc\r\n")
       (error "An existing file has %S" (wsl-backend-bytes windows)))
     (delete-file windows)
     (format "without this, a new file has %S" without))))

;;; Where a program's variables come from: what \"A backend's environment\" says

(defvar tramp-remote-process-environment)

(defun wsl-backend-environment-report (text)
  "Return which of the variables TEXT shows, as a string for the report."
  (format "profile=%s list=%s connection-local=%s path=%s"
          (if (string-search "profile-value" text) "yes" "no")
          (if (string-search "list-value" text) "yes" "no")
          (if (string-search "local-value" text) "yes" "no")
          (if (string-search "from-profile" text) "yes" "no")))

(wsl-backend-check
 "the environment, as the chapter's table says" 120
 (lambda ()
   (let* ((default-directory (wsl-backend-root))
          (remote (file-remote-p default-directory))
          (command (concat "echo \"$KITTYMACS_PROFILE_VAR $KITTYMACS_LIST_VAR "
                           "$KITTYMACS_LOCAL_VAR $PATH\"; echo done"))
          (tramp-remote-process-environment
           (cons "KITTYMACS_LIST_VAR=list-value" tramp-remote-process-environment)))
     (make-directory (concat remote "~/from-profile") t)
     ;; Unix line ends: a file this Emacs writes on Windows would get CRLF.
     (let ((coding-system-for-write 'utf-8-unix))
       (with-temp-file (concat remote "~/.profile")
         (insert "export KITTYMACS_PROFILE_VAR=profile-value\n"
                 "PATH=\"$HOME/from-profile:$PATH\"\nexport PATH\n")))
     (connection-local-set-profile-variables
      'wsl-backend-settings
      `((tramp-remote-process-environment
         . ("KITTYMACS_LOCAL_VAR=local-value" ,@tramp-remote-process-environment))))
     (connection-local-set-profiles
      `(:application tramp :protocol "wslm" :machine ,wsl-backend-distribution)
      'wsl-backend-settings)
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
            (shell
             (let* ((buffer (shell (generate-new-buffer-name "*environment shell*")))
                    (process (get-buffer-process buffer)))
               (process-send-string process (concat command "; exit\n"))
               (wsl-backend-wait-for process "done" 30)))
            (reports (mapcar #'wsl-backend-environment-report (list through-shell direct shell))))
       ;; The chapter's table: a change in Tramp must show here.
       (dolist (report reports)
         (wsl-backend-expect "profile=no list=yes connection-local=no path=yes" report))
       (format "process-file, a direct process and M-x shell: %s" (car reports))))))

(wsl-backend-check
 "the doctor says what to run" 60
 (lambda ()
   (kittymacs-backend-doctor "wsl")
   (let ((text (with-current-buffer "*kittymacs backend*" (buffer-string))))
     (wsl-backend-expect "does not have yet" text)
     (wsl-backend-expect "nix profile install" text)
     (wsl-backend-expect "rg fd direnv inotifywait" text))))

;;; direnv

;; After the doctor's check, which needs a machine with no direnv.

(defun wsl-backend-direnv-project (name)
  "Return the file NAME in a project with an allowed `.envrc', on the backend."
  (wsl-backend-file (concat "direnv/" name)))

(defun wsl-backend-as-root (command)
  "Run the shell COMMAND in the distribution as root, and signal if it fails."
  (with-temp-buffer
    (unless (zerop (call-process "wsl.exe" nil t nil "-d" wsl-backend-distribution
                                 "-u" "root" "--exec" "sh" "-c" command))
      (error "%s failed: %s" command (buffer-string)))))

(defun wsl-backend-stop ()
  "Stop the distribution, and drop what Emacs knows about its connection."
  (wsl-backend-disconnect)
  (call-process "wsl.exe" nil nil nil "--terminate" wsl-backend-distribution)
  (dolist (buffer (buffer-list))
    (when (string-prefix-p "*envrc" (buffer-name buffer))
      (kill-buffer buffer))))

(defun wsl-backend-open-and-close (direnv)
  "Open the project's file with the backend's DIRENV on or off, and close it."
  (if direnv
      (add-hook 'after-change-major-mode-hook #'kittymacs--remote-envrc-on-wsl -50)
    (remove-hook 'after-change-major-mode-hook #'kittymacs--remote-envrc-on-wsl))
  (let ((buffer (find-file-noselect (wsl-backend-direnv-project "file"))))
    (prog1 (format "envrc-mode %s" (buffer-local-value 'envrc-mode buffer))
      (kill-buffer buffer))))

(wsl-backend-check
 "direnv: install it, and allow a project's .envrc" 300
 (lambda ()
   (wsl-backend-as-root "apt-get update -qq && apt-get install -y -qq direnv")
   (make-directory (wsl-backend-direnv-project "") t)
   (let ((coding-system-for-write 'utf-8-unix))
     (with-temp-file (wsl-backend-direnv-project ".envrc")
       (insert "export KITTYMACS_ENVRC_PROBE=reached\n"))
     (with-temp-file (wsl-backend-direnv-project "file")
       (insert "hello\n")))
   (let ((default-directory (wsl-backend-direnv-project "")))
     (with-temp-buffer
       (unless (zerop (process-file "direnv" nil t t "allow"))
         (error "direnv allow: %s" (buffer-string)))
       "allowed"))))

(wsl-backend-check
 "direnv: a file opens with it off" 60
 (lambda () (wsl-backend-open-and-close nil)))

(wsl-backend-check
 "direnv: a file opens with it on, and direnv runs" 60
 (lambda () (wsl-backend-open-and-close t)))

(wsl-backend-check
 "direnv: a file opens with it on, and the result is known" 60
 (lambda () (wsl-backend-open-and-close t)))

(wsl-backend-check
 "direnv: its variable reaches each kind of process" 120
 (lambda ()
   (with-current-buffer (find-file-noselect (wsl-backend-direnv-project "file"))
     (let ((end (+ (float-time) 60))
           (report "echo [$KITTYMACS_ENVRC_PROBE]; echo done"))
       (while (and (memq envrc--status '(nil running none)) (< (float-time) end))
         (accept-process-output nil 0.2)
         (envrc--get-current-env-or-run-direnv))
       (unless (eq envrc--status 'on)
         (error "envrc says %s" envrc--status))
       (let* ((environment process-environment)
              (directory default-directory)
              (through-shell
               (with-temp-buffer
                 (setq process-environment environment
                       default-directory directory)
                 (process-file "/bin/sh" nil t nil "-c" report)
                 (buffer-string)))
              (direct
               (let* ((buffer (generate-new-buffer " *direnv direct*"))
                      (process (make-process :name "direnv-direct" :buffer buffer :noquery t
                                             :file-handler t :connection-type 'pipe
                                             :command (list "/bin/sh" "-c" report))))
                 (wsl-backend-wait-for process "done" 30)))
              (shell-command (shell-command-to-string report)))
         (dolist (seen (list through-shell direct shell-command))
           (wsl-backend-expect "[reached]" seen))
         "process-file, a direct process and shell-command")))))

(wsl-backend-check
 "direnv: a file opens with it off, in a stopped distribution" 120
 (lambda ()
   (wsl-backend-stop)
   (wsl-backend-open-and-close nil)))

(wsl-backend-check
 "direnv: a file opens with it on, in a stopped distribution" 120
 (lambda ()
   (wsl-backend-stop)
   (wsl-backend-open-and-close t)))

;; For the record: what a new file on the backend gets from Emacs on Windows.
(wsl-backend-check
 "line ends of a new file on the backend, for the record" 60
 (lambda ()
   (let* ((file (wsl-backend-file "line-ends"))
          (buffer (find-file-noselect file)))
     (with-current-buffer buffer
       (insert "one\ntwo\n")
       (save-buffer)
       (kill-buffer))
     (let ((default-directory (wsl-backend-root)))
       (with-temp-buffer
         (process-file "/usr/bin/od" nil t nil "-c" "line-ends")
         (string-trim (buffer-string)))))))

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
