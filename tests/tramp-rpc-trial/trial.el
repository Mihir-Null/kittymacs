;;; trial.el --- Measure tramp-rpc and wslm from Windows to WSL2 -*- lexical-binding: t; -*-
;; A trial, not to merge.  Run by tests/tramp-rpc-trial/run.ps1, once per row, in a
;; process it can kill.  The phases, limits and fixtures follow step 15's harness, so
;; the two rows meet the same checks.  A failure is a result: every operation runs
;; under a limit, and its error text is recorded and not fixed.
;;
;; The environment names the run:
;;   TRIAL_TRANSPORT     rpc or wslm
;;   TRIAL_BOOT          plain, emacs -Q with Magit; or config, the real configuration
;;   TRIAL_PHASES        the phases to run, by name, after spaces
;;   TRIAL_ROUNDS        rounds for each timing
;;   TRIAL_ROW           the row's name in the results
;;   TRIAL_RESULT        the file that receives results
;;   TRIAL_DISTRIBUTION, TRIAL_SERVER, TRIAL_CAT, TRIAL_TRAMP_RPC, TRIAL_CLIENT_PACKAGES
;;   KITTYMACS_TEST_PACKAGES  the package directory
;;
;; With TRIAL_SUMMARISE naming a directory, it instead turns the result files there
;; into Markdown on standard output.

;;; Code:
(require 'cl-lib)
(require 'package)
(require 'seq)
(require 'subr-x)

(defvar w32-pipe-buffer-size)
(defvar tramp-methods)
(defvar tramp-dont-suspend-timers nil)
(defvar tramp-connection-timeout)
(defvar tramp-verbose)
(defvar tramp-copy-size-limit)
(defvar tramp-persistency-file-name)
(defvar tramp-use-ssh-controlmaster-options)
(defvar eglot-sync-connect)
(defvar eglot-connect-timeout)
(defvar kittymacs-backends)
(defvar kittymacs-host-directories nil)
(defvar tramp-rpc-deploy-remote-binary-path)
(defvar tramp-rpc-protocol-revision)
(defvar explicit-shell-file-name)
(declare-function tramp-cleanup-connection "tramp-cmds" (vec &optional keep-debug keep-password keep-processes))
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function tramp-send-command-and-read "tramp-sh" (vec command &optional noerror marker))
(declare-function tramp-direct-async-process-p "tramp" (&rest args))
(declare-function tramp-get-connection-process "tramp" (vec))
(declare-function connection-local-set-profile-variables "files-x" (profile variables))
(declare-function connection-local-set-profiles "files-x" (criteria &rest profiles))
(declare-function kittymacs-remote--apply-backend "kittymacs-remote" (name))
(declare-function kittymacs-backend-doctor "kittymacs-remote" (name))
(declare-function kittymacs-backend-connect "kittymacs-remote" (name))
(declare-function kittymacs-backend-root "kittymacs-remote" (name))
(declare-function kittymacs-remote-buffer-p "kittymacs-remote" (&rest _))
(declare-function kittymacs-remote-agent-path "kittymacs-remote" (path))
(declare-function magit-status-setup-buffer "magit-status" (&optional directory))
(declare-function eglot "eglot" (managed-major-modes project class contact language-id &optional interactive))
(declare-function eglot-current-server "eglot" ())
(declare-function eglot-shutdown "eglot" (server &optional timeout preserve-buffers))
(declare-function eglot--TextDocumentIdentifier "eglot" ())
(declare-function jsonrpc-request "jsonrpc" (connection method params &rest args))

;;; Summarising

(defun trial--read-results (directory)
  "Return every result in the .eld files of DIRECTORY."
  (let (results)
    (dolist (file (directory-files directory t "\\.eld\\'"))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8-unix)) (insert-file-contents file))
        (condition-case nil
            (while t (push (read (current-buffer)) results))
          (end-of-file nil))))
    (nreverse results)))

(defun trial--median (numbers)
  "Return the median of NUMBERS."
  (let* ((sorted (sort (copy-sequence numbers) #'<))
         (n (length sorted)))
    (if (cl-oddp n)
        (nth (/ n 2) sorted)
      (/ (+ (nth (1- (/ n 2)) sorted) (nth (/ n 2) sorted)) 2.0))))

(defun trial-summarise (directory)
  "Print the results in DIRECTORY as Markdown."
  (let* ((results (trial--read-results directory))
         (keys (seq-uniq (mapcar (lambda (r) (cons (plist-get r :row) (plist-get r :op)))
                                 results))))
    (princ "| Row | Operation | Rounds | Failed | Median s | Worst s |\n|---|---|---:|---:|---:|---:|\n")
    (pcase-dolist (`(,row . ,op) keys)
      (let* ((rows (seq-filter (lambda (r) (and (equal (plist-get r :row) row)
                                                (equal (plist-get r :op) op)))
                               results))
             (seconds (mapcar (lambda (r) (plist-get r :seconds)) rows))
             (failed (seq-remove (lambda (r) (plist-get r :ok)) rows)))
        (princ (format "| %s | %s | %d | %d | %.3f | %.3f |\n"
                       row op (length rows) (length failed)
                       (trial--median seconds) (apply #'max seconds)))))
    (princ "\n## What each failure and probe said\n\n")
    (dolist (r results)
      (when (plist-get r :detail)
        (princ (format "- %s %s [%s] %s\n"
                       (plist-get r :row) (plist-get r :op)
                       (if (plist-get r :ok) "ok" "FAILED")
                       (replace-regexp-in-string
                        "[\r\n]+" " / "
                        (let ((text (format "%s" (plist-get r :detail))))
                          (if (> (length text) 900) (substring text 0 900) text)))))))))

(when-let* ((directory (getenv "TRIAL_SUMMARISE")))
  (trial-summarise directory)
  (kill-emacs 0))

;;; The run

(defconst trial-here (file-name-directory load-file-name))
(defconst trial-source
  (file-name-directory (directory-file-name
                        (file-name-directory (directory-file-name trial-here)))))
(defconst trial-transport (getenv "TRIAL_TRANSPORT"))
(defconst trial-rpc-p (equal trial-transport "rpc"))
(defconst trial-config-p (equal (getenv "TRIAL_BOOT") "config"))
(defconst trial-distribution (getenv "TRIAL_DISTRIBUTION"))
(defconst trial-row (getenv "TRIAL_ROW"))
(defconst trial-home "/home/spike")
(defconst trial-rounds (string-to-number (getenv "TRIAL_ROUNDS")))
(defconst trial-prefix (format "/%s:%s:" trial-transport trial-distribution))

(defconst trial-pipes '(("default pipe" . 0) ("1 MiB pipe" . 1048576))
  "The two values of `w32-pipe-buffer-size', which tramp-rpc never sets.")

(defun trial-name (path)
  "Return PATH under the fixture's home directory, on the backend."
  (concat trial-prefix trial-home "/" path))

(defun trial-log (format-string &rest arguments)
  "Say what is happening.  A graphical Emacs has no standard error, so use a file."
  (let ((line (format "[%s %s] %s" (format-time-string "%H:%M:%S") trial-row
                      (apply #'format format-string arguments))))
    (if noninteractive
        (message "%s" line)
      (let ((coding-system-for-write 'utf-8-unix) (inhibit-message t))
        (write-region (concat line "\n") nil
                      (concat (string-remove-suffix ".eld" (getenv "TRIAL_RESULT")) ".log")
                      t 'silent)))))

(defun trial-record (op round seconds ok &optional detail)
  "Append one result, and return OK."
  (let ((coding-system-for-write 'utf-8-unix)
        (print-escape-nonascii nil)
        (print-escape-control-characters t)
        (print-length nil)
        (print-level nil))
    (write-region
     (concat (prin1-to-string
              (list :row trial-row :op op :round round
                    :seconds seconds :ok (and ok t)
                    :detail (and detail (format "%s" detail))))
             "\n")
     nil (getenv "TRIAL_RESULT") t 'silent))
  (trial-log "%s #%s %.3fs %s %s" op round seconds (if ok "ok" "FAILED") (or detail ""))
  ok)

(defun trial-connection-tail ()
  "Return the end of what the connection printed.
tramp-rpc's main buffer holds binary frames, so its stderr buffer says more."
  (if-let* ((name (format "*tramp/%s %s*%s" trial-transport trial-distribution
                          (if trial-rpc-p " stderr" "")))
            (buffer (get-buffer name)))
      (with-current-buffer buffer
        (buffer-substring-no-properties (max (point-min) (- (point-max) 400)) (point-max)))
    ""))

(defun trial-measure (op round limit function)
  "Call FUNCTION under LIMIT seconds, and record it as OP's ROUND.
FUNCTION returns nil or a string saying what went wrong, or `:detail' and a
string for what was seen, or anything else for success.  Tramp suspends timers
while it waits unless told not to, and the limit is a timer."
  (let ((began (float-time)) ok detail)
    (condition-case err
        (let* ((tramp-dont-suspend-timers t)
               (value (with-timeout (limit 'stalled) (funcall function))))
          (pcase value
            ('stalled (setq detail (format "no answer in %d s | connection said: %s"
                                           limit (trial-connection-tail))))
            ('nil (setq detail "wrong result"))
            ((pred stringp) (setq detail value))
            (`(:detail ,text) (setq ok t detail text))
            (_ (setq ok t))))
      ((error quit)
       (setq detail (format "%s | connection said: %s"
                            (error-message-string err) (trial-connection-tail)))))
    (trial-record op round (- (float-time) began) ok detail)))

(defun trial-local (limit program &rest arguments)
  "Run the local PROGRAM with ARGUMENTS, for at most LIMIT seconds.
Return (STATUS . OUTPUT), with STATUS `stalled' if it passed the limit."
  (let* ((default-directory temporary-file-directory)
         (process-environment (cons "WSL_UTF8=1" process-environment))
         (buffer (generate-new-buffer " *trial-local*"))
         (process (make-process :name "trial-local" :buffer buffer :noquery t
                                :command (cons program arguments)
                                :connection-type 'pipe))
         (end (+ (float-time) limit)))
    (while (and (process-live-p process) (< (float-time) end))
      (accept-process-output process 0.1))
    (let ((live (process-live-p process)))
      (when live (delete-process process))
      (prog1 (cons (if live 'stalled (process-exit-status process))
                   (with-current-buffer buffer (buffer-string)))
        (kill-buffer buffer)))))

(defun trial-as-root (limit &rest arguments)
  "Run ARGUMENTS as root in the distribution."
  (apply #'trial-local limit "wsl.exe" "-d" trial-distribution "-u" "root" "--exec" arguments))

(defvar trial-keepalive nil "The wsl.exe session that keeps the distribution running.")

(defun trial-ensure-backend ()
  "Keep the distribution running, so the numbers compare the rows and not a cold start."
  (unless (process-live-p trial-keepalive)
    (setq trial-keepalive
          (let ((default-directory temporary-file-directory))
            (make-process :name "trial-keepalive" :noquery t :connection-type 'pipe
                          :command (list "wsl.exe" "-d" trial-distribution
                                         "--exec" "sleep" "86400"))))))

(defun trial-vec ()
  "Return the Tramp vector of the backend."
  (tramp-dissect-file-name trial-prefix))

(defun trial-disconnect ()
  "Drop the connection and what Tramp cached about it."
  (let ((tramp-dont-suspend-timers t))
    (with-timeout (30 (trial-log "tramp-cleanup-connection passed 30 s"))
      (tramp-cleanup-connection (trial-vec)))))

(defun trial-set-pipe (size)
  "Use a pipe of SIZE from the next connection on."
  (setq w32-pipe-buffer-size size)
  (trial-disconnect))

;;; The start

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-trial-" t))
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      native-comp-jit-compilation nil)
;; Nothing here answers a prompt.
(advice-add 'y-or-n-p :override #'ignore)
(advice-add 'yes-or-no-p :override #'ignore)

(defun trial-start-plain ()
  "Emacs's own Tramp and Eglot, with Magit from the package directory."
  (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES")
        package-archives nil)
  (package-initialize t)
  (package-activate 'magit)
  (require 'tramp)
  (require 'tramp-sh)
  (setq tramp-verbose 1
        tramp-copy-size-limit nil
        tramp-persistency-file-name nil
        tramp-use-ssh-controlmaster-options nil))

(defun trial-start-config ()
  "The real configuration, as `tests/wsl-backend/connect.el' starts it."
  (dolist (file '("early-init.el" "init.el"))
    (copy-file (expand-file-name file trial-source)
               (expand-file-name file user-emacs-directory)))
  (dolist (directory '("lisp" "literate" "tools"))
    (copy-directory (expand-file-name directory trial-source)
                    (expand-file-name directory user-emacs-directory) nil t))
  (make-directory (expand-file-name "var/etc" user-emacs-directory) t)
  (with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
    (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-profile 'full)\n"
            (format "(setopt kittymacs-backends '((\"trial\" :transport %s :host %S :root %S)))\n"
                    (if trial-rpc-p "rpc" "wsl") trial-distribution
                    (concat trial-home "/repo/"))))
  (advice-add 'kittymacs-activate-packages :before
              (lambda (&rest _) (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES"))))
  (let ((began (float-time)))
    (condition-case err
        (progn
          (setq after-init-time nil)
          (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
          (load user-init-file nil t)
          (setq after-init-time (current-time))
          (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
          (trial-record "start: the real configuration" 1 (- (float-time) began) t
                        (format "remote module loaded: %s, Tramp loaded by the start: %s"
                                (featurep 'kittymacs-remote) (featurep 'tramp))))
      (error (trial-record "start: the real configuration" 1 (- (float-time) began) nil
                           (error-message-string err))))))

(defun trial-add-wslm ()
  "Add the row `kittymacs-remote' adds for the `wsl' transport, with direct processes on."
  (add-to-list 'tramp-methods
               '("wslm"
                 (tramp-login-program "wsl.exe")
                 (tramp-login-args (("-d" "%h") ("--exec")
                                    ("/bin/sh" "-c"
                                     "\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/run/current-system/sw/bin"
                                     "exec" "%l" "2>&1\"")))
                 (tramp-direct-async ("/bin/sh" "-c"))
                 (tramp-remote-shell "/bin/sh")
                 (tramp-remote-shell-login ("-l"))
                 (tramp-remote-shell-args ("-c"))
                 (tramp-completion-use-cache nil)))
  (connection-local-set-profile-variables
   'trial-direct '((tramp-direct-async-process . t)))
  (connection-local-set-profiles
   '(:application tramp :protocol "wslm") 'trial-direct))

(defun trial-load-rpc ()
  "Load tramp-rpc, the seam and msgpack, and find a Windows `cat'.
Git for Windows's `cat', since GNU's Emacs ships none."
  (add-to-list 'load-path (getenv "TRIAL_TRAMP_RPC"))
  (dolist (directory (directory-files (getenv "TRIAL_CLIENT_PACKAGES") t "\\`msgpack-"))
    (add-to-list 'load-path directory))
  (require 'tramp)
  (setq exec-path (append exec-path (list (getenv "TRIAL_CAT"))))
  (load (expand-file-name "seam" trial-here) nil t)
  (setq tramp-rpc-deploy-remote-binary-path (getenv "TRIAL_SERVER")))

(if trial-config-p (trial-start-config) (trial-start-plain))
(require 'tramp)
(require 'tramp-sh)
(setq tramp-connection-timeout 45)
(when trial-rpc-p (trial-load-rpc))
(unless (or trial-rpc-p trial-config-p) (trial-add-wslm))
(when trial-config-p
  ;; The wsl transport adds its own row when the root is asked for.
  (condition-case err
      (progn (kittymacs-backend-root "trial")
             (kittymacs-remote--apply-backend "trial"))
    (error (trial-log "applying the backend failed: %s" (error-message-string err)))))
(trial-record
 "environment" 1 0.0 t
 (format "emacs %s; tramp %s; window-system %S; batch %S; rpc protocol %S; msgpack %S; cat %S"
         emacs-version (bound-and-true-p tramp-version) (window-system) noninteractive
         (bound-and-true-p tramp-rpc-protocol-revision)
         (and trial-rpc-p (locate-library "msgpack"))
         (executable-find "cat")))

;;; Connecting

(defun trial-phase-connect ()
  "Repeated connects, on the default pipe.  Return non-nil if any connected.
Two failures in a row end it: failing is a result, and a third try adds nothing."
  (trial-set-pipe 0)
  (let ((row 0) (any nil))
    (cl-loop for round from 1 to trial-rounds
             while (< row 2)
             do (trial-disconnect)
             (if (trial-measure "connect" round 75
                                (lambda () (or (file-exists-p (concat trial-prefix "/tmp"))
                                               "the remote /tmp does not exist")))
                 (setq row 0 any t)
               (setq row (1+ row))))
    (trial-set-pipe 1048576)
    any))

(defun trial-phase-badhost ()
  "What a user sees when the distribution, or the server, does not exist."
  (let ((name (format "/%s:nosuchhost:/tmp" trial-transport)))
    (trial-measure "probe: no such distribution" 1 75
                   (lambda ()
                     (list :detail (format "file-exists-p said %S" (file-exists-p name)))))
    (ignore-errors (tramp-cleanup-connection (tramp-dissect-file-name name))))
  (when trial-rpc-p
    (trial-disconnect)
    (let ((tramp-rpc-deploy-remote-binary-path "/no/such/tramp-rpc-server"))
      (trial-measure "probe: no server at that path" 1 75
                     (lambda ()
                       (list :detail (format "file-exists-p said %S"
                                             (file-exists-p (concat trial-prefix "/tmp")))))))
    (trial-disconnect)))

;;; Files

(defun trial-blob (size)
  "Return SIZE repeatable bytes, every value among them, as a unibyte string."
  (let ((bytes (make-string size 0)))
    (random "kittymacs-wsl-spike")
    (dotimes (i size) (aset bytes i (random 256)))
    bytes))

(defun trial-write (name bytes)
  "Write the unibyte BYTES to NAME."
  (let ((coding-system-for-write 'no-conversion))
    (write-region bytes nil name nil 'silent)
    t))

(defun trial-read (name)
  "Return the bytes of NAME."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'no-conversion))
      (insert-file-contents-literally name))
    (buffer-string)))

(defun trial-phase-files ()
  "Read, write, list and stat, with each pipe, and with the caches out of the way."
  (let ((remote-file-name-inhibit-cache t)
        (small (trial-blob 4096))
        (large (trial-blob 1048576))
        (small-file (trial-name "spike/small.bin"))
        (large-file (trial-name "spike/large.bin")))
    (pcase-dolist (`(,label . ,size) trial-pipes)
      (trial-set-pipe size)
      (dotimes (i trial-rounds)
        (let ((round (1+ i)))
          (trial-measure (format "write 4 KiB, %s" label) round 60
                         (lambda () (trial-write small-file small)))
          (trial-measure (format "read 4 KiB, %s" label) round 60
                         (lambda () (or (equal (trial-read small-file) small) "bytes differ")))
          (trial-measure (format "write 1 MiB, %s" label) round 120
                         (lambda () (trial-write large-file large)))
          (trial-measure (format "read 1 MiB, %s" label) round 120
                         (lambda () (or (equal (trial-read large-file) large) "bytes differ")))
          (trial-measure (format "directory-files, 200 names, %s" label) round 60
                         (lambda ()
                           (let ((count (length (directory-files (trial-name "many") nil "\\`f"))))
                             (or (= count 200) (format "%d names" count)))))
          (trial-measure (format "file-attributes, %s" label) round 60
                         (lambda () (and (file-attributes small-file) t))))))
    ;; Does the lock file explain a small write?  The pipe is still 1 MiB here.
    (let ((create-lockfiles nil))
      (dotimes (i trial-rounds)
        (trial-measure "write 4 KiB, no lock file, 1 MiB pipe" (1+ i) 60
                       (lambda () (trial-write small-file small)))))))

;;; Processes

(defun trial-async (limit command &optional stdin)
  "Run COMMAND on the backend as an asynchronous process over a pipe.
Send it the bytes STDIN, then end of file.  Return (STATUS . BYTES)."
  (let* ((default-directory (concat trial-prefix "/tmp/"))
         (buffer (generate-new-buffer " *trial-async*"))
         (process (make-process :name "trial-async" :buffer buffer :noquery t
                                :command command :connection-type 'pipe
                                :coding 'no-conversion :file-handler t))
         (end (+ (float-time) limit)))
    (with-current-buffer buffer (set-buffer-multibyte nil))
    (when stdin
      (process-send-string process stdin)
      (process-send-eof process))
    (while (and (process-live-p process) (< (float-time) end))
      (accept-process-output process 0.1))
    ;; A relay's output may still be on its way after the process ends: wait until
    ;; 50 ms pass with none, which both rows pay.
    (while (accept-process-output nil 0.05))
    (let ((live (process-live-p process)))
      (when live (delete-process process))
      (prog1 (cons (if live 'stalled (process-exit-status process))
                   (with-current-buffer buffer (buffer-string)))
        (kill-buffer buffer)))))

(defun trial-sync (command)
  "Run COMMAND on the backend with `process-file'.  Return (STATUS . BYTES)."
  (let ((default-directory (concat trial-prefix "/tmp/"))
        (coding-system-for-read 'no-conversion))
    ;; A multibyte buffer, since a unibyte one would mangle a non-ASCII argument here.
    (with-temp-buffer
      (let ((status (apply #'process-file (car command) nil t nil (cdr command))))
        (cons status (encode-coding-string (buffer-string) 'utf-8-unix))))))

(defun trial-show (bytes)
  "Return BYTES in a form that survives a log, cut short."
  (let ((shown (format "%S" (if (> (length bytes) 120) (substring bytes 0 120) bytes))))
    (format "%s (%d bytes)" shown (length bytes))))

(defun trial-into-process (label round blob hash)
  "Send BLOB to a process that hashes it, and compare with HASH."
  (trial-measure (format "1 MiB into a process, %s" label) round 90
                 (lambda ()
                   (pcase-let ((`(,status . ,bytes) (trial-async 80 '("sha256sum") blob)))
                     (or (and (equal status 0) (string-prefix-p hash bytes))
                         (format "exit %S, said %s, wanted %s" status (trial-show bytes) hash))))))

(defun trial-phase-into ()
  "1 MiB into a process with each pipe.  Three rounds, since two of three failed before."
  (let* ((blob (trial-blob 1048576))
         (hash (secure-hash 'sha256 blob)))
    (pcase-dolist (`(,label . ,size) trial-pipes)
      (trial-set-pipe size)
      (dotimes (i (min 3 trial-rounds))
        (trial-into-process label (1+ i) blob hash)))))

(defun trial-phase-process ()
  "A long-lived process, with a line in and the same line out, as a language server's are."
  (let* ((default-directory (concat trial-prefix "/tmp/"))
         (buffer (generate-new-buffer " *trial-cat*"))
         (began (float-time))
         (process (make-process :name "trial-cat" :buffer buffer :noquery t
                                :command '("cat") :connection-type 'pipe
                                :coding 'no-conversion :file-handler t))
         (exchange
          (lambda (text)
            (process-send-string process text)
            (with-current-buffer buffer
              (while (and (not (string-search text (buffer-string))) (process-live-p process))
                (accept-process-output process 0.01))
              (or (string-search text (buffer-string)) "the process ended")))))
    (trial-record "process: started" 1 (- (float-time) began) (process-live-p process))
    (trial-measure "process: first line back" 1 30 (lambda () (funcall exchange "first\n")))
    (dotimes (i trial-rounds)
      (trial-measure "process: line in, line out" (1+ i) 30
                     (lambda () (funcall exchange (format "line %d\n" i)))))
    (let ((text (concat (make-string 60000 ?x) "\n")))
      (trial-measure "process: 60,000 bytes in and out" 1 60
                     (lambda () (funcall exchange text))))
    (process-send-eof process)
    (let ((end (+ (float-time) 10)))
      (while (and (process-live-p process) (< (float-time) end))
        (accept-process-output process 0.1)))
    (trial-record "process: ended on end of file" 1 0.0 (not (process-live-p process))
                  (format "%S" (process-status process)))
    (when (process-live-p process) (delete-process process))
    (kill-buffer buffer)))

(defun trial-phase-shell ()
  "A pty through `M-x shell'."
  (trial-measure
   "M-x shell" 1 60
   (lambda ()
     (let* ((default-directory (concat trial-prefix trial-home "/"))
            (explicit-shell-file-name "/bin/sh")
            (buffer (shell (generate-new-buffer-name "*trial-shell*")))
            (process (get-buffer-process buffer))
            (end (+ (float-time) 30)))
       (process-send-string process "echo shell-$((40+2)); exit\n")
       (with-current-buffer buffer
         (while (and (not (string-search "shell-42" (buffer-string)))
                     (process-live-p process) (< (float-time) end))
           (accept-process-output process 0.1))
         (or (string-search "shell-42" (buffer-string))
             (format "the buffer said: %s" (buffer-string))))))))

;;; Magit and Eglot

(defun trial-magit-status ()
  "Open Magit status on the fixture from a fresh buffer, and return its text."
  (let ((buffer (magit-status-setup-buffer (trial-name "repo/"))))
    (prog1 (with-current-buffer buffer
             (buffer-substring-no-properties (point-min) (point-max)))
      (kill-buffer buffer))))

(defun trial-phase-magit ()
  "Magit status on a real repository with one edited file.
Then an edit no Emacs saw, since tramp-rpc holds Magit's answers in a cache."
  (dotimes (i trial-rounds)
    (trial-measure
     "Magit status" (1+ i) 120
     (lambda ()
       (let ((text (trial-magit-status)))
         (or (string-search "Unstaged changes" text)
             (format "no unstaged changes shown; the buffer said: %s"
                     (substring text 0 (min 300 (length text)))))))))
  ;; Magit may leave a section's body out, so read its heading.
  (let ((expect
         (lambda (op wanted)
           (trial-measure
            op 1 120
            (lambda ()
              (let ((text (trial-magit-status)))
                (or (eq wanted (and (string-search "Untracked files" text) t))
                    (format "wanted untracked files %S; the buffer said: %s" wanted
                            (substring text 0 (min 300 (length text)))))))))))
    (funcall expect "Magit status, before an outside edit" nil)
    (trial-as-root 30 "touch" (concat trial-home "/repo/outside-edit"))
    (funcall expect "Magit status shows an outside new file" t)
    (trial-as-root 30 "rm" "-f" (concat trial-home "/repo/outside-edit"))
    (funcall expect "Magit status shows it gone" nil)))

(defvar trial-eglot-failures 0 "How many Eglot starts have failed in a row.")

(defun trial-eglot-why ()
  "Record what Eglot's own buffers say, once, after a start that failed."
  (dolist (buffer (buffer-list))
    (when (string-search "EGLOT" (buffer-name buffer))
      (with-current-buffer buffer
        (trial-record "probe: what Eglot's buffer said" 1 0.0 t
                      (format "%s: %s" (buffer-name)
                              (buffer-substring-no-properties
                               (max (point-min) (- (point-max) 500)) (point-max))))))))

(defun trial-eglot-round (round)
  "Start clangd on the fixture's C file, ask for a hover, and shut it down."
  (let ((buffer (find-file-noselect (trial-name "cproj/main.c"))))
    (with-current-buffer buffer
      (goto-char (point-min))
      (search-forward "add (40")
      (backward-char 5)
      (let ((eglot-sync-connect t) (eglot-connect-timeout 60))
        (if (not (trial-measure
                  "Eglot start" round 75
                  (lambda ()
                    (eglot (list major-mode) (project-current) 'eglot-lsp-server
                           '("clangd") "c")
                    (and (eglot-current-server) t))))
            (setq trial-eglot-failures (1+ trial-eglot-failures))
          (setq trial-eglot-failures 0)
          (trial-measure
           "Eglot first hover" round 60
           (lambda ()
             (let ((answer (jsonrpc-request
                            (eglot-current-server) :textDocument/hover
                            (list :textDocument (eglot--TextDocumentIdentifier)
                                  :position (list :line (1- (line-number-at-pos))
                                                  :character (current-column)))
                            :timeout 50)))
               (or (string-search "add" (format "%S" answer))
                   (format "hover said: %S" answer)))))))
      (let ((server (eglot-current-server)))
        (when server
          (trial-measure "Eglot shutdown" round 30
                         (lambda () (eglot-shutdown server) t)))))
    (kill-buffer buffer)))

(defun trial-phase-eglot ()
  "Eglot as a backend gets it, stopping at two failures in a row, since each costs a minute."
  (require 'eglot)
  (let ((default-directory trial-prefix))
    (trial-record "probe: direct async on" 1 0.0 t (format "%S" (tramp-direct-async-process-p))))
  (setq trial-eglot-failures 0)
  (cl-loop for round from 1 to trial-rounds
           while (< trial-eglot-failures 2)
           do (trial-eglot-round round))
  (when (> trial-eglot-failures 0) (trial-eglot-why)))

;;; Pipes, quoting and encoding

(defun trial-expect (run command expected)
  "Return a check that RUN on COMMAND prints exactly EXPECTED."
  (lambda ()
    (pcase-let ((`(,status . ,bytes) (funcall run command)))
      (or (and (equal status 0) (equal bytes expected))
          (format "exit %S, said %s, wanted %s" status (trial-show bytes) (trial-show expected))))))

(defun trial-both (label command expected)
  "Check COMMAND prints EXPECTED, through `process-file' and through a process."
  (unless (trial-measure (format "probe: %s, process-file" label) 1 30
                         (trial-expect #'trial-sync command expected))
    ;; A shell left stalled would fail every probe after this one.
    (trial-disconnect))
  (trial-measure (format "probe: %s, async process" label) 1 30
                 (trial-expect (lambda (c) (trial-async 25 c)) command expected)))

(defun trial-phase-risks ()
  "Step 15's risks, on the 1 MiB pipe: pipes, quoting and encoding."
  (trial-set-pipe 1048576)
  (let* ((remote-file-name-inhibit-cache t)
         (directory (trial-name "spike/"))
         (spaced (concat directory "a file.txt"))
         (accented (concat directory "été 日本語.txt"))
         (content (encode-coding-string "contents é\n" 'utf-8)))
    (pcase-dolist (`(,label . ,name) `(("space" . ,spaced) ("non-ASCII" . ,accented)))
      (trial-measure
       (format "probe: file name with a %s" label) 1 60
       (lambda ()
         (trial-write name content)
         (cond ((not (member (file-name-nondirectory name) (directory-files directory)))
                (format "the listing lacks it: %S" (directory-files directory nil "txt")))
               ((not (file-attributes name)) "no attributes")
               ((not (equal (trial-read name) content)) "bytes differ")
               (t (delete-file name) (or (not (file-exists-p name)) "delete left it")))))))
  (trial-both "CRLF output" '("printf" "a\\r\\nb\\r\\n") "a\r\nb\r\n")
  (trial-both "LF output" '("printf" "a\\nb\\n") "a\nb\n")
  (let ((hazard "a b\"c'd$HOME\\e%PATH%^&|<>!;*"))
    (trial-both "shell characters in an argument" (list "printf" "%s" hazard) hazard))
  (let ((accented "é日本語"))
    (trial-both "non-ASCII argument" (list "printf" "%s" accented)
                (encode-coding-string accented 'utf-8)))
  ;; A command longer than PIPE_BUF, which is 4096 on Linux.
  (dolist (size '(3000 5000 20000))
    (trial-both (format "command of %d bytes" size)
                (list "/bin/sh" "-c" (format "printf %%s %s | wc -c" (make-string size ?x)))
                (format "%d\n" size)))
  (let* ((blob (trial-blob 1048576))
         (hash (secure-hash 'sha256 blob)))
    (trial-write (trial-name "spike/blob.bin") blob)
    (trial-measure "probe: 1 MiB out of an async process" 1 90
                   (lambda ()
                     (pcase-let ((`(,status . ,bytes)
                                  (trial-async 80 (list "cat" (concat trial-home "/spike/blob.bin")))))
                       (or (and (equal status 0) (equal (secure-hash 'sha256 bytes) hash))
                           (format "exit %S, %d bytes back" status (length bytes))))))))

;;; A dead connection

(defun trial-idle-timers (label)
  "Run every idle and ordinary timer in the current buffer, each under a limit.
The real remote buffer is current, so this is what the guards exist for."
  (let ((buffer (current-buffer)) stalled failed)
    (dolist (timer (append timer-idle-list timer-list))
      (let ((function (timer--function timer)))
        ;; A `with-timeout' still pending belongs to whoever set it, not to a guard.
        (unless (string-search "throw 'timeout" (format "%S" function))
          (with-current-buffer buffer
            (let ((began (float-time)))
              (condition-case err
                  (when (eq 'stalled
                            (let ((tramp-dont-suspend-timers t))
                              (with-timeout (5 'stalled)
                                (apply function (timer--args timer))
                                nil)))
                    (push (format "%S" function) stalled))
                ((error quit)
                 (when (> (- (float-time) began) 1)
                   (push (format "%S: %s" function (error-message-string err)) failed)))))))))
    (trial-record (format "probe: timers, %s" label) 1 0.0 (not stalled)
                  (format "stalled: %S; slow errors: %S" stalled failed))))

(defun trial-idle-wait (label buffer)
  "Show BUFFER and wait 5 s for real: anything that blocks makes the wait longer."
  (switch-to-buffer buffer)
  (let ((began (float-time)))
    (with-timeout (40 (trial-log "the idle wait passed 40 s"))
      (let ((tramp-dont-suspend-timers t)) (sit-for 5)))
    (trial-record (format "probe: a 5 s idle wait, %s" label) 1 (- (float-time) began)
                  (< (- (float-time) began) 7)
                  (format "%S" (buffer-name)))))

(defun trial-open-unsaved ()
  "Visit a remote file with unsaved text, and return the buffer."
  (let ((buffer (find-file-noselect (trial-name "spike/open.txt"))))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert "unsaved\n"))
    buffer))

(defvar trial-shell-pid nil "The connection's remote shell, on the Tramp row.")

(defun trial-stop-helper (signal)
  "Send SIGNAL, STOP or CONT, to what answers file operations, and report it.
For tramp-rpc, every server, since one may already have replaced another.  For
Tramp, the connection's shell."
  (let ((result
         (if trial-rpc-p
             (apply #'trial-as-root 30 "pkill" (concat "-" signal) "-x"
                    '("tramp-rpc-serve"))
           (trial-as-root 30 "kill" (concat "-" signal) (number-to-string trial-shell-pid)))))
    (trial-log "%s -> %S; server states: %S" signal result
               (cdr (trial-as-root 30 "ps" "-eo" "stat,comm")))
    result))

(defun trial-phase-hang ()
  "Stop what answers file operations: it lives and never answers.
That is a backend that hangs, seen from the transport.  tramp-rpc says it gives up
after 30 s and a 10 s probe, so its limit here is longer than step 15's 25 s."
  (trial-set-pipe 1048576)
  (let* ((limit (if trial-rpc-p 60 25))
         (remote-file-name-inhibit-cache t)
         (file (trial-name "spike/open.txt"))
         (buffer (progn (trial-write file "text\n") (trial-open-unsaved))))
    (unless trial-rpc-p
      (setq trial-shell-pid (tramp-send-command-and-read (trial-vec) "echo $$")))
    (let ((check (lambda () (list :detail (format "%S" (and (file-attributes file) t))))))
      (trial-stop-helper "STOP")
      (trial-measure "hang: file-attributes" 1 limit check)
      ;; On tramp-rpc a new server may take over here, with no one's action.
      (trial-measure "hang: the next file-attributes" 1 limit check)
      (trial-stop-helper "STOP")
      (when trial-config-p
        (with-current-buffer buffer
          (trial-idle-timers "backend hung")
          (trial-idle-wait "backend hung" buffer)))
      (trial-measure "hang: save the buffer" 1 limit
                     (lambda () (with-current-buffer buffer (save-buffer)) t))
      (trial-stop-helper "CONT")
      (trial-measure "hang: first answer after it resumes" 1 60 check))
    (with-current-buffer buffer (set-buffer-modified-p nil))
    (kill-buffer buffer)
    ;; A write larger than the pipe blocks in Emacs's own write, so try both pipes.
    (let ((large (trial-blob 1048576))
          (small (trial-blob 4096))
          (name (trial-name "spike/hung-write.bin")))
      (pcase-dolist (`(,label . ,size) trial-pipes)
        (trial-set-pipe size)
        (file-exists-p (concat trial-prefix "/tmp"))
        (unless trial-rpc-p
          (setq trial-shell-pid (tramp-send-command-and-read (trial-vec) "echo $$")))
        (trial-write name small)
        (trial-stop-helper "STOP")
        (trial-measure (format "hang: write 1 MiB to a stopped helper, %s" label) 1 75
                       (lambda () (trial-write name large)))
        (trial-stop-helper "CONT")
        (trial-measure (format "hang: what that write left, %s" label) 1 60
                       (lambda ()
                         (let ((bytes (trial-read name)))
                           (list :detail
                                 (cond ((equal bytes large) "all of the new bytes")
                                       ((equal bytes small) "all of the old bytes")
                                       (t (format "neither: %d bytes" (length bytes))))))))
        (trial-measure (format "hang: 4 KiB round trip after that write, %s" label) 1 60
                       (lambda ()
                         (trial-write name small)
                         (or (equal (trial-read name) small) "bytes differ")))))
    (trial-disconnect)))

;;; Where the time goes, on tramp-rpc

(defun trial-trace (op function)
  "Call FUNCTION once as OP, and record each RPC it made and how long it took.
What the calls leave unexplained is spent in Emacs."
  (let* (calls
         (advice (lambda (original &rest arguments)
                   (let ((began (float-time)))
                     (prog1 (apply original arguments)
                       (push (format "%s %.3f"
                                     (if (stringp (cadr arguments))
                                         (cadr arguments)
                                       "batch")
                                     (- (float-time) began))
                             calls))))))
    (dolist (name '(tramp-rpc--call tramp-rpc--call-batch))
      (advice-add name :around advice '((name . trial-trace))))
    (let ((began (float-time)))
      (unwind-protect
          (trial-measure op 1 120
                         (lambda ()
                           (funcall function)
                           (list :detail (format "total %.3f: %s" (- (float-time) began)
                                                 (string-join (reverse calls) ", ")))))
        (dolist (name '(tramp-rpc--call tramp-rpc--call-batch))
          (advice-remove name 'trial-trace))))))

(defun trial-phase-trace ()
  "Why a small write costs what it does, and a Magit status."
  (when trial-rpc-p
    (trial-set-pipe 1048576)
    (let ((small (trial-blob 4096))
          (name (trial-name "spike/small.bin"))
          (remote-file-name-inhibit-cache t))
      (dotimes (_ 2)
        (trial-trace "trace: write 4 KiB" (lambda () (trial-write name small))))
      (trial-trace "trace: read 4 KiB" (lambda () (trial-read name))))
    (dotimes (_ 2)
      (trial-trace "trace: Magit status" #'trial-magit-status))))

(defun trial-phase-shutdown ()
  "`wsl --shutdown' in the middle of a session, with an open file and a process."
  (trial-set-pipe 1048576)
  (let* ((remote-file-name-inhibit-cache t)
         (file (trial-name "spike/open.txt"))
         (buffer (progn (trial-write file "text\n") (trial-open-unsaved)))
         (events nil)
         (began (float-time))
         (default-directory (concat trial-prefix "/tmp/"))
         (server (make-process
                  :name "trial-server" :noquery t :connection-type 'pipe
                  :command '("sleep" "600") :file-handler t
                  :sentinel (lambda (_ event)
                              (push (format "%.1fs %s" (- (float-time) began) (string-trim event))
                                    events)))))
    (let ((default-directory temporary-file-directory))
      (setq began (float-time))
      (let ((result (trial-local 60 "wsl.exe" "--shutdown")))
        (trial-record "shutdown: wsl --shutdown itself" 1 (- (float-time) began)
                      (equal (car result) 0) (cdr result)))
      ;; A long-running process's death is what tells Eglot.
      (let ((end (+ (float-time) 20)))
        (while (and (not events) (< (float-time) end))
          (accept-process-output nil 0.1)))
      (trial-record "shutdown: an async process's end reached Emacs" 1
                    (- (float-time) began) (and events t)
                    (format "events: %S; process now %S" events (process-status server))))
    (when trial-config-p
      (with-current-buffer buffer
        (trial-idle-timers "after shutdown")
        (trial-idle-wait "after shutdown" buffer)))
    (let ((check (lambda () (list :detail (format "%S" (and (file-attributes file) t))))))
      (trial-measure "shutdown: first file-attributes" 1 75 check)
      (trial-log "connection tail: %s" (trial-connection-tail))
      (trial-measure "shutdown: second file-attributes" 1 75 check))
    (when (process-live-p server) (delete-process server))
    (trial-ensure-backend)
    (with-current-buffer buffer (set-buffer-modified-p nil))
    (kill-buffer buffer)
    (trial-disconnect)))

;;; Kittymacs itself

(defun trial-phase-kittymacs ()
  "The real module's commands and predicates, on this row's backend."
  (trial-measure "kittymacs: connect, by the real command" 1 75
                 (lambda ()
                   (let (opened)
                     (cl-letf (((symbol-function 'project-switch-project)
                                (lambda (directory) (setq opened directory))))
                       (kittymacs-backend-connect "trial"))
                     (or (equal opened (kittymacs-backend-root "trial"))
                         (format "opened %S" opened)))))
  (trial-measure "kittymacs-backend-doctor" 1 120
                 (lambda ()
                   (list :detail
                         (format "%S | %s" (kittymacs-backend-doctor "trial")
                                 (with-current-buffer "*kittymacs backend*" (buffer-string))))))
  (let ((default-directory (kittymacs-backend-root "trial")))
    (trial-record "kittymacs: predicates" 1 0.0
                  (and (kittymacs-remote-buffer-p)
                       (equal (kittymacs-remote-agent-path (trial-name "repo/x"))
                              (concat trial-home "/repo/x"))
                       (equal (kittymacs-remote-agent-path "/tmp/y")
                              (concat trial-prefix "/tmp/y")))
                  (format "remote %S; to the agent %S; from it %S"
                          (kittymacs-remote-buffer-p)
                          (kittymacs-remote-agent-path (trial-name "repo/x"))
                          (kittymacs-remote-agent-path "/tmp/y"))))
  (let ((buffer (find-file-noselect (trial-name "repo/Makefile"))))
    (with-current-buffer buffer
      (trial-idle-wait "a visited file, backend healthy" buffer)
      (set-buffer-modified-p nil))
    (kill-buffer buffer)))

;;; Everything, in order

(defun trial-phase (function)
  "Call FUNCTION, and record an error it lets out, so later phases still run.
Return its value."
  (let ((began (float-time)))
    (trial-log "phase %s" function)
    (condition-case err
        (let ((tramp-dont-suspend-timers t))
          (prog1 (funcall function)
            (trial-log "phase %s took %.0f s" function (- (float-time) began))))
      ((error quit)
       (trial-record (format "phase %s stopped" function) 1 (- (float-time) began) nil
                     (format "%s | connection said: %s"
                             (error-message-string err) (trial-connection-tail)))
       (ignore-errors (trial-disconnect))
       nil))))

(trial-ensure-backend)
(let ((phases (split-string (getenv "TRIAL_PHASES"))))
  (if (not (trial-phase #'trial-phase-connect))
      (trial-record "stopped: it did not connect" 1 0.0 nil)
    (dolist (name (remove "connect" phases))
      (trial-phase (intern (concat "trial-phase-" name))))))
(trial-log "done")
(when (process-live-p trial-keepalive) (delete-process trial-keepalive))
(kill-emacs 0)

;;; trial.el ends here
