;;; spike.el --- Measure one Tramp transport from Windows to WSL2 -*- lexical-binding: t; -*-
;; Run by tests/wsl-spike/run.ps1, once per transport, in a process it can kill.
;;
;; It starts the real configuration, so the remote module's guards and settings
;; are in play, then measures one transport and appends each result to a file.
;; A failure is a result: every operation runs under a limit, and its error text
;; is recorded rather than fixed.
;;
;; The environment names the run:
;;   KITTYMACS_SPIKE_TRANSPORT   wsl, wslm, ssh, sshx or sshtt
;;   KITTYMACS_SPIKE_DISTRIBUTION, KITTYMACS_SPIKE_USER_HOME
;;   KITTYMACS_SPIKE_SSH_CONFIG  an ssh configuration naming the host wslspike
;;   KITTYMACS_SPIKE_RESULT      the file that receives results
;;   KITTYMACS_SPIKE_QUICK       one round of everything, to test this file
;;   KITTYMACS_TEST_PACKAGES     the package directory
;;
;; With KITTYMACS_SPIKE_SUMMARISE naming a directory, it instead turns the result
;; files there into a Markdown table on standard output.

;;; Code:
(require 'cl-lib)
(require 'package)
(require 'seq)

(defvar tramp-methods)
(defvar tramp-dont-suspend-timers nil)
(defvar tramp-encoding-shell)
(defvar tramp-connection-timeout)
(defvar eglot-sync-connect)
(defvar eglot-connect-timeout)
(defvar magit-buffer-lock-functions)
(defvar kittymacs-backends)
(defvar kittymacs-host-directories nil)
(declare-function tramp-cleanup-connection "tramp-cmds" (vec &optional keep-debug keep-password keep-processes))
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function tramp-send-command-and-read "tramp-sh" (vec command &optional noerror marker))
(declare-function tramp-direct-async-process-p "tramp" (&rest args))
(declare-function kittymacs-remote--apply-backend "kittymacs-remote" (name))
(declare-function kittymacs-backend-doctor "kittymacs-remote" (name))
(declare-function magit-status-setup-buffer "magit-status" (&optional directory))
(declare-function eglot "eglot" (managed-major-modes project class contact language-id &optional interactive))
(declare-function eglot-current-server "eglot" ())
(declare-function eglot-shutdown "eglot" (server &optional timeout preserve-buffers))
(declare-function eglot--TextDocumentIdentifier "eglot" ())
(declare-function jsonrpc-request "jsonrpc" (connection method params &rest args))

;;; Summarising

(defun spike--read-results (directory)
  "Return every result in the .eld files of DIRECTORY."
  (let (results)
    (dolist (file (directory-files directory t "\\.eld\\'"))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8-unix)) (insert-file-contents file))
        (condition-case nil
            (while t (push (read (current-buffer)) results))
          (end-of-file nil))))
    (nreverse results)))

(defun spike--median (numbers)
  "Return the median of NUMBERS."
  (let* ((sorted (sort (copy-sequence numbers) #'<))
         (n (length sorted)))
    (if (cl-oddp n)
        (nth (/ n 2) sorted)
      (/ (+ (nth (1- (/ n 2)) sorted) (nth (/ n 2) sorted)) 2.0))))

(defun spike-summarise (directory)
  "Print the results in DIRECTORY as Markdown."
  (let* ((results (spike--read-results directory))
         (keys (seq-uniq (mapcar (lambda (r) (cons (plist-get r :transport) (plist-get r :op)))
                                 results))))
    (princ "| Transport | Operation | Rounds | Failed | Median s | Worst s |\n|---|---|---:|---:|---:|---:|\n")
    (pcase-dolist (`(,transport . ,op) keys)
      (let* ((rows (seq-filter (lambda (r) (and (equal (plist-get r :transport) transport)
                                                (equal (plist-get r :op) op)))
                               results))
             (seconds (mapcar (lambda (r) (plist-get r :seconds)) rows))
             (failed (seq-remove (lambda (r) (plist-get r :ok)) rows)))
        (princ (format "| %s | %s | %d | %d | %.3f | %.3f |\n"
                       transport op (length rows) (length failed)
                       (spike--median seconds) (apply #'max seconds)))))
    (princ "\n## What each failure and probe said\n\n")
    (dolist (r results)
      (when (plist-get r :detail)
        (princ (format "- %s %s [%s] %s\n"
                       (plist-get r :transport) (plist-get r :op)
                       (if (plist-get r :ok) "ok" "FAILED")
                       (replace-regexp-in-string
                        "[\r\n]+" " / "
                        (let ((text (format "%s" (plist-get r :detail))))
                          (if (> (length text) 600) (substring text 0 600) text)))))))))

(when-let* ((directory (getenv "KITTYMACS_SPIKE_SUMMARISE")))
  (spike-summarise directory)
  (kill-emacs 0))

;;; The run

(defconst spike-source
  (file-name-directory (directory-file-name
                        (file-name-directory
                         (directory-file-name (file-name-directory load-file-name))))))
(defconst spike-transport (getenv "KITTYMACS_SPIKE_TRANSPORT"))
(defconst spike-distribution (getenv "KITTYMACS_SPIKE_DISTRIBUTION"))
(defconst spike-home (or (getenv "KITTYMACS_SPIKE_USER_HOME") "/home/spike"))
(defconst spike-quick (getenv "KITTYMACS_SPIKE_QUICK"))
(defconst spike-ssh-p (string-prefix-p "ssh" spike-transport))
(defconst spike-host (if spike-ssh-p "wslspike" spike-distribution))
(defconst spike-prefix (format "/%s:%s:" spike-transport spike-host))

(defun spike-rounds (n)
  "Return N, or 1 in a quick run."
  (if spike-quick 1 n))

(defun spike-name (path)
  "Return PATH under the fixture's home directory, on the backend."
  (concat spike-prefix spike-home "/" path))

(defun spike-log (format-string &rest arguments)
  "Say what is happening on standard error, for the job's log."
  (message "[%s %s] %s" (format-time-string "%H:%M:%S") spike-transport
           (apply #'format format-string arguments)))

(defun spike-record (op round seconds ok &optional detail)
  "Append one result, and return OK."
  (let ((coding-system-for-write 'utf-8-unix)
        (print-escape-nonascii nil)
        (print-escape-control-characters t)
        (print-length nil)
        (print-level nil))
    (write-region
     (concat (prin1-to-string
              (list :transport spike-transport :op op :round round
                    :seconds seconds :ok (and ok t)
                    :detail (and detail (format "%s" detail))))
             "\n")
     nil (getenv "KITTYMACS_SPIKE_RESULT") t 'silent))
  (spike-log "%s #%s %.3fs %s %s" op round seconds (if ok "ok" "FAILED") (or detail ""))
  ok)

(defun spike-connection-tail ()
  "Return the end of the connection buffer, which holds what the login printed."
  (if-let* ((buffer (seq-find (lambda (b) (string-prefix-p
                                           (format "*tramp/%s " spike-transport)
                                           (buffer-name b)))
                              (buffer-list))))
      (with-current-buffer buffer
        (buffer-substring-no-properties (max (point-min) (- (point-max) 400)) (point-max)))
    ""))

(defun spike-measure (op round limit function)
  "Call FUNCTION under LIMIT seconds, and record it as OP's ROUND.
FUNCTION returns nil or a string saying what went wrong, or `:detail' and a
string for what was seen, or anything else for success.  Tramp suspends timers
while it waits unless told not to, and the limit is a timer."
  (let ((began (float-time)) ok detail)
    (condition-case err
        (let* ((tramp-dont-suspend-timers t)
               (value (with-timeout (limit 'stalled) (funcall function))))
          (pcase value
            ('stalled (setq detail (format "no answer in %d s | login printed: %s"
                                           limit (spike-connection-tail))))
            ('nil (setq detail "wrong result"))
            ((pred stringp) (setq detail value))
            (`(:detail ,text) (setq ok t detail text))
            (_ (setq ok t))))
      ((error quit)
       (setq detail (format "%s | login printed: %s"
                            (error-message-string err) (spike-connection-tail)))))
    (spike-record op round (- (float-time) began) ok detail)))

(defun spike-local (limit program &rest arguments)
  "Run the local PROGRAM with ARGUMENTS, for at most LIMIT seconds.
Return (STATUS . OUTPUT), with STATUS `stalled' if it passed the limit.  WSL_UTF8
is set here alone: the transports get the environment a user has, and wsl.exe's
own messages are then UTF-16."
  (let* ((default-directory temporary-file-directory)
         (process-environment (cons "WSL_UTF8=1" process-environment))
         (buffer (generate-new-buffer " *spike-local*"))
         (process (make-process :name "spike-local" :buffer buffer :noquery t
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

(defun spike-wsl (limit &rest arguments)
  "Run wsl.exe with ARGUMENTS against the distribution."
  (apply #'spike-local limit "wsl.exe" "-d" spike-distribution arguments))

(defun spike-as-root (limit &rest arguments)
  "Run ARGUMENTS as root in the distribution."
  (apply #'spike-wsl limit "-u" "root" "--exec" arguments))

(defvar spike-keepalive nil "The wsl.exe session that keeps the distribution running.")

(defun spike-ensure-backend ()
  "Keep the distribution running, and, for ssh, its sshd.
WSL stops a distribution once no wsl.exe session holds it, so ssh needs something
to hold it, and a wsl.exe method does not.  This holds it for both, so the numbers
compare the transports and not a cold start."
  (unless (process-live-p spike-keepalive)
    (setq spike-keepalive
          (let ((default-directory temporary-file-directory))
            (make-process :name "spike-keepalive" :noquery t :connection-type 'pipe
                          :command (list "wsl.exe" "-d" spike-distribution
                                         "--exec" "sleep" "86400")))))
  (when spike-ssh-p
    ;; Its own pid file, so a distribution's stock sshd on port 22 is not taken for it.
    (spike-as-root 60 "sh" "-c" "mkdir -p /run/sshd; kill -0 $(cat /run/sshd-spike.pid 2>/dev/null) 2>/dev/null || /usr/sbin/sshd -p 2222 -o PidFile=/run/sshd-spike.pid")
    (spike-ensure-route)))

(defun spike-ensure-route ()
  "Check Windows reaches sshd, and fall back to the distribution's own address.
WSL forwards localhost by default, and the address changes at each boot."
  (let ((config (getenv "KITTYMACS_SPIKE_SSH_CONFIG")))
    (unless (equal 0 (car (spike-local 30 "ssh" "-F" config "wslspike" "true")))
      (let ((address (car (split-string (cdr (spike-as-root 30 "hostname" "-I"))))))
        (with-temp-file config
          (insert-file-contents config)
          (when (re-search-forward "HostName .*" nil t)
            (replace-match (concat "HostName " address))))
        (spike-record "probe: ssh route" 1 0.0
                      (equal 0 (car (spike-local 30 "ssh" "-F" config "wslspike" "true")))
                      (format "the configured address did not answer; now %s" address))))))

(defun spike-vec ()
  "Return the Tramp vector of the backend."
  (tramp-dissect-file-name spike-prefix))

(defun spike-disconnect ()
  "Drop the connection and what Tramp cached about it."
  (let ((tramp-dont-suspend-timers t))
    (with-timeout (30 (spike-log "tramp-cleanup-connection passed 30 s"))
      (tramp-cleanup-connection (spike-vec)))))

;;; The start

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-spike-" t))
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      native-comp-jit-compilation nil)
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file spike-source)
             (expand-file-name file user-emacs-directory)))
(dolist (directory '("lisp" "literate" "tools"))
  (copy-directory (expand-file-name directory spike-source)
                  (expand-file-name directory user-emacs-directory) nil t))
(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-profile 'full)\n"
          (format "(setopt kittymacs-backends '((\"spike\" :transport %s :host %S :root %S)))\n"
                  spike-transport spike-host (concat spike-home "/repo/"))))
(advice-add 'kittymacs-activate-packages :before
            (lambda (&rest _) (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES"))))
;; Nothing here answers a prompt: the grammar offer, say.
(advice-add 'y-or-n-p :override #'ignore)
(advice-add 'yes-or-no-p :override #'ignore)

(let ((began (float-time)))
  (condition-case err
      (progn
        (setq after-init-time nil)
        (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
        (load user-init-file nil t)
        (setq after-init-time (current-time))
        (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
        (spike-record "start: the real configuration" 1 (- (float-time) began) t
                      (format "remote module loaded: %s, Tramp loaded by the start: %s"
                              (featurep 'kittymacs-remote) (featurep 'tramp))))
    (error (spike-record "start: the real configuration" 1 (- (float-time) began) nil
                         (error-message-string err)))))

;;; The method under test

(require 'tramp)
(require 'tramp-sh)
(setq tramp-connection-timeout 45)
(when spike-quick (setq tramp-verbose 6))

;; The wsl row, from the `distrobox' row in Emacs's net/tramp-container.el
;; (`tramp-enable-distrobox-method'): the same keys, with wsl.exe as the program.
;; --exec, so wsl.exe runs the program itself rather than through the default
;; shell, which would parse the arguments again.
(add-to-list 'tramp-methods
             '("wsl"
               (tramp-login-program "wsl.exe")
               (tramp-login-args (("-d" "%h") ("--exec") ("%l")))
               (tramp-direct-async ("/bin/sh" "-c"))
               (tramp-remote-shell "/bin/sh")
               (tramp-remote-shell-login ("-l"))
               (tramp-remote-shell-args ("-c"))
               (tramp-completion-use-cache nil)))

;; The wsl row changed in two ways, and so not a measure of the template.
;; - wsl.exe relays stdout and stderr separately, and an interactive sh prompts on
;;   stderr, so a prompt can overtake the output before it, and Tramp never sees a
;;   prompt at the end.  This row merges them on the Linux side.
;; - wsl.exe appends the Windows PATH, and Tramp writes PATH=... unquoted, so a
;;   directory such as "Program Files (x86)" is a syntax error once
;;   `tramp-own-remote-path' reads it.  This row starts from a Linux PATH.
;; A group with an empty element is dropped, so a direct process, which expands %l
;; to nothing, runs without either.
(add-to-list 'tramp-methods
             `("wslm"
               ,@(assq-delete-all 'tramp-login-args (copy-alist (cdr (assoc "wsl" tramp-methods))))
               (tramp-login-args (("-d" "%h") ("--exec")
                                  ("/bin/sh" "-c"
                                   "\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                                   "exec" "%l" "2>&1\"")))))

;; Tramp's ssh row changed in one way, and so not Tramp's own: -t -t.  Windows has
;; no terminal to give ssh.exe, and without one the remote shell never prompts.
;; sshx does this too, but through RemoteCommand, which rules out direct processes.
(add-to-list 'tramp-methods
             `("sshtt"
               ,@(assq-delete-all 'tramp-login-args (copy-alist (cdr (assoc "ssh" tramp-methods))))
               (tramp-login-args (("-l" "%u") ("-p" "%p") ("%c") ("-e" "none") ("-t" "-t") ("%h")))))

;; Every ssh row with one change: -F, so the run needs no line in the ~/.ssh/config
;; of whoever runs it.
(dolist (method '("ssh" "sshx" "sshtt"))
  (let ((login-args (assq 'tramp-login-args (assoc method tramp-methods))))
    (setcar (cdr login-args)
            (cons (list "-F" (getenv "KITTYMACS_SPIKE_SSH_CONFIG"))
                  (cadr login-args)))))

(condition-case err
    (kittymacs-remote--apply-backend "spike")
  (error (spike-log "applying the backend failed: %s" (error-message-string err))))
(spike-log "tramp-encoding-shell %s; Tramp %s" tramp-encoding-shell tramp-version)

;;; Connecting

(defun spike-phase-connect ()
  "Repeated connects, for the time and the failure rate.
Return non-nil if any connected.  Three failures in a row end it, since each can
take the whole login timeout."
  (let ((row 0) (any nil))
    (cl-loop for round from 1 to (spike-rounds 20)
             while (< row 3)
             do (spike-disconnect)
             (if (spike-measure "connect" round 75
                                (lambda () (or (file-exists-p (concat spike-prefix "/tmp"))
                                               "the remote /tmp does not exist")))
                 (setq row 0 any t)
               (setq row (1+ row))))
    any))

(defun spike-phase-leaks ()
  "Count what the repeated connects left behind, on both sides."
  (spike-disconnect)
  (spike-record "probe: leftovers after connects" 1 0.0 t
                (format "remote shells: %s; ssh.exe: %s; wsl.exe: %s"
                        (cdr (spike-wsl 30 "--exec" "sh" "-c" "ps -eo user,args | grep -c '[/]bin/sh -i'"))
                        (cdr (spike-local 30 "tasklist" "/fi" "imagename eq ssh.exe" "/nh"))
                        (cdr (spike-local 30 "tasklist" "/fi" "imagename eq wsl.exe" "/nh")))))

(defun spike-phase-bad-host ()
  "What a user sees for a backend that does not exist, and how soon."
  (let ((name (format "/%s:nosuchhost:/tmp" spike-transport)))
    (spike-measure "probe: no such host" 1 75
                   (lambda ()
                     (list :detail (format "file-exists-p said %S" (file-exists-p name)))))
    (ignore-errors (tramp-cleanup-connection (tramp-dissect-file-name name)))))

;;; Files

(defun spike-blob (size)
  "Return SIZE repeatable bytes, every value among them, as a unibyte string."
  (let ((bytes (make-string size 0)))
    (random "kittymacs-wsl-spike")
    (dotimes (i size) (aset bytes i (random 256)))
    bytes))

(defun spike-write (name bytes)
  "Write the unibyte BYTES to NAME."
  (let ((coding-system-for-write 'no-conversion))
    (write-region bytes nil name nil 'silent)
    t))

(defun spike-read (name)
  "Return the bytes of NAME."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'no-conversion))
      (insert-file-contents-literally name))
    (buffer-string)))

(defun spike-phase-files ()
  "Read, write, list and stat, with Tramp's cache out of the way."
  (let ((remote-file-name-inhibit-cache t)
        (small (spike-blob 4096))
        (large (spike-blob 1048576))
        (small-file (spike-name "spike/small.bin"))
        (large-file (spike-name "spike/large.bin")))
    (dotimes (i (spike-rounds 10))
      (let ((round (1+ i)))
        (spike-measure "write 4 KiB" round 60 (lambda () (spike-write small-file small)))
        (spike-measure "read 4 KiB" round 60
                       (lambda () (or (equal (spike-read small-file) small) "bytes differ")))
        (spike-measure "write 1 MiB" round 120 (lambda () (spike-write large-file large)))
        (spike-measure "read 1 MiB" round 120
                       (lambda () (or (equal (spike-read large-file) large) "bytes differ")))
        (spike-measure "directory-files, 200 names" round 60
                       (lambda ()
                         (let ((count (length (directory-files (spike-name "many") nil "\\`f"))))
                           (or (= count 200) (format "%d names" count)))))
        (spike-measure "file-attributes" round 60
                       (lambda () (and (file-attributes small-file) t)))))))

;;; Magit and Eglot

(defun spike-phase-magit ()
  "Magit status on a real repository with one edited file, from a fresh buffer."
  (dotimes (i (spike-rounds 5))
    (spike-measure
     "Magit status" (1+ i) 120
     (lambda ()
       (let ((buffer (magit-status-setup-buffer (spike-name "repo/"))))
         (prog1 (with-current-buffer buffer
                  (save-excursion
                    (goto-char (point-min))
                    (or (search-forward "Unstaged changes" nil t)
                        (format "no unstaged changes shown; the buffer said: %s"
                                (buffer-substring-no-properties
                                 (point-min) (min (point-max) (+ (point-min) 300)))))))
           (kill-buffer buffer)))))))

(defvar spike-eglot-failures 0 "How many Eglot starts have failed in a row.")

(defun spike-eglot-why ()
  "Record what Eglot's own buffers say, once, after a start that failed."
  (dolist (buffer (buffer-list))
    (when (string-search "EGLOT" (buffer-name buffer))
      (with-current-buffer buffer
        (spike-record "probe: what Eglot's buffer said" 1 0.0 t
                      (format "%s: %s" (buffer-name)
                              (buffer-substring-no-properties
                               (max (point-min) (- (point-max) 500)) (point-max))))))))

(defun spike-eglot-rounds (label rounds)
  "Run ROUNDS of Eglot as LABEL, stopping at two failures in a row, since each costs a minute."
  (setq spike-eglot-failures 0)
  (cl-loop for round from 1 to (spike-rounds rounds)
           while (< spike-eglot-failures 2)
           do (spike-eglot-round label round))
  (when (> spike-eglot-failures 0) (spike-eglot-why)))

(defun spike-eglot-round (label round)
  "Start clangd on the fixture's C file, ask for a hover, and shut it down."
  (let ((buffer (find-file-noselect (spike-name "cproj/main.c"))))
    (with-current-buffer buffer
      (goto-char (point-min))
      (search-forward "add (40")
      (backward-char 5)
      (let ((eglot-sync-connect t) (eglot-connect-timeout 60))
        (if (not (spike-measure
                  (format "Eglot start, %s" label) round 75
                  (lambda ()
                    (eglot (list major-mode) (project-current) 'eglot-lsp-server
                           '("clangd") "c")
                    (and (eglot-current-server) t))))
            (setq spike-eglot-failures (1+ spike-eglot-failures))
          (setq spike-eglot-failures 0)
          (spike-measure
           (format "Eglot first hover, %s" label) round 60
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
          (spike-measure (format "Eglot shutdown, %s" label) round 30
                         (lambda () (eglot-shutdown server) t)))))
    (kill-buffer buffer)))

(defun spike-set-direct (on)
  "Apply the backend with direct processes ON or off, through the real module."
  (setf (alist-get "spike" kittymacs-backends nil nil #'equal)
        (append (seq-take (cdr (assoc "spike" kittymacs-backends)) 6)
                (unless on '(:direct-async nil))))
  (kittymacs-remote--apply-backend "spike")
  (spike-disconnect))

(defun spike-phase-eglot ()
  "Eglot as a backend gets it, then with Tramp's slower process start."
  (let ((default-directory spike-prefix))
    (spike-record "probe: direct async on" 1 0.0 t
                  (format "%S" (tramp-direct-async-process-p))))
  (spike-eglot-rounds "backend default" 5)
  (spike-set-direct nil)
  (let ((default-directory spike-prefix))
    (spike-record "probe: direct async off" 1 0.0 t
                  (format "%S" (tramp-direct-async-process-p))))
  (spike-eglot-rounds "direct async off" 3)
  (spike-set-direct t))

(defun spike-phase-doctor ()
  "The real module's report on this backend."
  (spike-measure "kittymacs-backend-doctor" 1 120
                 (lambda ()
                   (list :detail (format "%S" (kittymacs-backend-doctor "spike"))))))

;;; Pipes, quoting and encoding

(defun spike-async (limit command &optional stdin)
  "Run COMMAND on the backend as an asynchronous process over a pipe.
Send it the bytes STDIN, then end of file.  Return (STATUS . BYTES)."
  (let* ((default-directory (concat spike-prefix "/tmp/"))
         (buffer (generate-new-buffer " *spike-async*"))
         (process (make-process :name "spike-async" :buffer buffer :noquery t
                                :command command :connection-type 'pipe
                                :coding 'no-conversion :file-handler t))
         (end (+ (float-time) limit)))
    (with-current-buffer buffer (set-buffer-multibyte nil))
    (when stdin
      (process-send-string process stdin)
      (process-send-eof process))
    (while (and (process-live-p process) (< (float-time) end))
      (accept-process-output process 0.1))
    (let ((live (process-live-p process)))
      (when live (delete-process process))
      (prog1 (cons (if live 'stalled (process-exit-status process))
                   (with-current-buffer buffer (buffer-string)))
        (kill-buffer buffer)))))

(defun spike-sync (command)
  "Run COMMAND on the backend with `process-file'.  Return (STATUS . BYTES)."
  (let ((default-directory (concat spike-prefix "/tmp/"))
        (coding-system-for-read 'no-conversion))
    ;; A multibyte buffer, since a unibyte one would mangle a non-ASCII argument here.
    (with-temp-buffer
      (let ((status (apply #'process-file (car command) nil t nil (cdr command))))
        (cons status (encode-coding-string (buffer-string) 'utf-8-unix))))))

(defun spike-show (bytes)
  "Return BYTES in a form that survives a log, cut short."
  (let ((shown (format "%S" (if (> (length bytes) 120) (substring bytes 0 120) bytes))))
    (format "%s (%d bytes)" shown (length bytes))))

(defun spike-expect (run command expected)
  "Return a check that RUN on COMMAND prints exactly EXPECTED."
  (lambda ()
    (pcase-let ((`(,status . ,bytes) (funcall run command)))
      (or (and (equal status 0) (equal bytes expected))
          (format "exit %S, said %s, wanted %s" status (spike-show bytes) (spike-show expected))))))

(defvar spike-async-label ""
  "Which way asynchronous processes start, for the names of the probes.")

(defun spike-both (label command expected)
  "Check COMMAND prints EXPECTED, through `process-file' and through a process."
  (unless (spike-measure (format "probe: %s, process-file" label) 1 30
                         (spike-expect #'spike-sync command expected))
    ;; A shell left stalled would fail every probe after this one.
    (spike-disconnect))
  (spike-measure (format "probe: %s, async process%s" label spike-async-label) 1 30
                 (spike-expect (lambda (c) (spike-async 25 c)) command expected)))

(defun spike-phase-risks ()
  "The risks the plan names: pipes, quoting and encoding."
  (file-exists-p (concat spike-prefix "/tmp"))
  (spike-record "probe: coding systems" 1 0.0 t
                (format "locale %S; file names %S; connection %S"
                        locale-coding-system file-name-coding-system
                        (process-coding-system (tramp-get-connection-process (spike-vec)))))
  ;; Encoding of file names.
  (let* ((remote-file-name-inhibit-cache t)
         (directory (spike-name "spike/"))
         (spaced (concat directory "a file.txt"))
         (accented (concat directory "été 日本語.txt"))
         (content (encode-coding-string "contents é\n" 'utf-8)))
    (pcase-dolist (`(,label . ,name) `(("space" . ,spaced) ("non-ASCII" . ,accented)))
      (spike-measure
       (format "probe: file name with a %s" label) 1 60
       (lambda ()
         (spike-write name content)
         (cond ((not (member (file-name-nondirectory name) (directory-files directory)))
                (format "the listing lacks it: %S" (directory-files directory nil "txt")))
               ((not (file-attributes name)) "no attributes")
               ((not (equal (spike-read name) content)) "bytes differ")
               (t (delete-file name) (or (not (file-exists-p name)) "delete left it"))))))
    ;; What the remote side made of the non-ASCII name.
    (spike-measure "probe: non-ASCII name as the backend sees it" 1 30
                   (lambda ()
                     (spike-write accented content)
                     (list :detail (spike-show (cdr (spike-sync
                                                     (list "sh" "-c" (format "ls %s/spike | grep txt | od -An -tx1 | head -3" spike-home)))))))))
  (spike-pipes)
  ;; A direct process is a different path from a shell's, so both get measured.
  (let ((default-directory spike-prefix))
    (when (tramp-direct-async-process-p)
      (let ((spike-async-label ", direct off"))
        (spike-set-direct nil)
        (spike-pipes)
        (spike-set-direct t)))))

(defun spike-pipes ()
  "Program output, arguments and bytes, through each way of running a program."
  ;; CRLF in program output, and that nothing adds a CR.
  (spike-both "CRLF output" '("printf" "a\\r\\nb\\r\\n") "a\r\nb\r\n")
  (spike-both "LF output" '("printf" "a\\nb\\n") "a\nb\n")
  ;; Quoting.
  (let ((hazard "a b\"c'd$HOME\\e%PATH%^&|<>!;*"))
    (spike-both "shell characters in an argument" (list "printf" "%s" hazard) hazard))
  (let ((accented "é日本語"))
    (spike-both "non-ASCII argument" (list "printf" "%s" accented)
                (encode-coding-string accented 'utf-8)))
  ;; A command longer than PIPE_BUF, which is 4096 on Linux.
  (dolist (size '(3000 5000 20000))
    (spike-both (format "command of %d bytes" size)
                (list "/bin/sh" "-c"
                      (format "printf %%s %s | wc -c" (make-string size ?x)))
                (format "%d\n" size)))
  ;; Bytes through the pipe in each direction, as a language server's are.
  (let* ((blob (spike-blob 1048576))
         (hash (secure-hash 'sha256 blob)))
    (spike-write (spike-name "spike/blob.bin") blob)
    (spike-measure (format "probe: 1 MiB out of an async process%s" spike-async-label) 1 90
                   (lambda ()
                     (pcase-let ((`(,status . ,bytes)
                                  (spike-async 80 (list "cat" (concat spike-home "/spike/blob.bin")))))
                       (or (and (equal status 0) (equal (secure-hash 'sha256 bytes) hash))
                           (format "exit %S, %d bytes back" status (length bytes))))))
    (spike-measure (format "probe: 1 MiB into an async process%s" spike-async-label) 1 90
                   (lambda ()
                     (pcase-let ((`(,status . ,bytes) (spike-async 80 '("sha256sum") blob)))
                       (or (and (equal status 0) (string-prefix-p hash bytes))
                           (format "exit %S, said %s, wanted %s" status (spike-show bytes) hash)))))))

;;; A dead connection

(defun spike-idle-timers (label)
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
    (spike-record (format "probe: timers, %s" label) 1 0.0 (not stalled)
                  (format "stalled: %S; slow errors: %S" stalled failed))))

(defun spike-open-unsaved ()
  "Visit a remote file with unsaved text, and return the buffer."
  (let ((buffer (find-file-noselect (spike-name "spike/open.txt"))))
    (with-current-buffer buffer
      (goto-char (point-max))
      (insert "unsaved\n"))
    buffer))

(defun spike-phase-hang ()
  "Stop the connection's remote shell: the process lives and never answers.
That is a backend that hangs, seen from the transport."
  (dotimes (i (spike-rounds 2))
    (let* ((round (1+ i))
           (remote-file-name-inhibit-cache t)
           (file (spike-name "spike/open.txt"))
           (buffer (progn (spike-write file "text\n") (spike-open-unsaved)))
           (pid (tramp-send-command-and-read (spike-vec) "echo $$")))
      (spike-record "probe: stopped the shell" round 0.0 t
                    (format "%S -> %S" pid (spike-as-root 30 "kill" "-STOP" (number-to-string pid))))
      (spike-measure "hang: file-attributes" round 25
                     (lambda () (list :detail (format "%S" (and (file-attributes file) t)))))
      (with-current-buffer buffer (spike-idle-timers "backend hung"))
      (spike-measure "hang: save the buffer" round 25
                     (lambda () (with-current-buffer buffer (save-buffer)) t))
      (spike-as-root 30 "kill" "-CONT" (number-to-string pid))
      (spike-measure "hang: first answer after it resumes" round 60
                     (lambda () (list :detail (format "%S" (and (file-attributes file) t)))))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer)
      (spike-disconnect))))

(defun spike-phase-shutdown ()
  "`wsl --shutdown' in the middle of a session, with an open file and a process."
  (dotimes (i (spike-rounds 2))
    (let* ((round (1+ i))
           (remote-file-name-inhibit-cache t)
           (file (spike-name "spike/open.txt"))
           (buffer (progn (spike-write file "text\n") (spike-open-unsaved)))
           (login (tramp-get-connection-process (spike-vec)))
           (events nil)
           (began (float-time))
           (default-directory (concat spike-prefix "/tmp/"))
           (server (make-process
                    :name "spike-server" :noquery t :connection-type 'pipe
                    :command '("sleep" "600") :file-handler t
                    :sentinel (lambda (_ event)
                                (push (format "%.1fs %s" (- (float-time) began) (string-trim event))
                                      events)))))
      (let ((default-directory temporary-file-directory))
        (setq began (float-time))
        (let ((result (spike-local 60 "wsl.exe" "--shutdown")))
          (spike-record "shutdown: wsl --shutdown itself" round (- (float-time) began)
                        (equal (car result) 0) (cdr result)))
        ;; A long-running process's death is what tells Eglot.
        (let ((end (+ (float-time) 20)))
          (while (and (not events) (< (float-time) end))
            (accept-process-output nil 0.1)))
        (spike-record "shutdown: an async process's end reached Emacs" round
                      (- (float-time) began) (and events t)
                      (format "events: %S; process now %S; login process now %S"
                              events (process-status server)
                              (and (processp login) (process-status login)))))
      (with-current-buffer buffer (spike-idle-timers "after shutdown"))
      (spike-measure "shutdown: first file-attributes" round 75
                     (lambda () (list :detail (format "%S" (and (file-attributes file) t)))))
      (spike-log "connection tail: %s" (spike-connection-tail))
      (spike-measure "shutdown: second file-attributes" round 75
                     (lambda () (list :detail (format "%S" (and (file-attributes file) t)))))
      (when (process-live-p server) (delete-process server))
      ;; What it takes to get working again: for ssh, someone has to start the
      ;; distribution and its sshd.
      (let ((restarted (float-time)))
        (spike-ensure-backend)
        (spike-record "shutdown: restart the distribution" round
                      (- (float-time) restarted) t))
      (spike-measure "shutdown: file-attributes after the restart" round 75
                     (lambda () (list :detail (format "%S" (and (file-attributes file) t)))))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer)
      (spike-disconnect))))

(defun spike-phase-idle-distribution ()
  "Whether sshd outlives the last wsl.exe session, which ssh depends on."
  (when spike-ssh-p
    (spike-disconnect)
    (spike-ensure-backend)
    (delete-process spike-keepalive)
    (let ((end (+ (float-time) 60)))
      (while (< (float-time) end) (accept-process-output nil 1)))
    (let* ((running (cdr (spike-local 30 "wsl.exe" "--list" "--running")))
           (answer (spike-local 30 "ssh" "-F" (getenv "KITTYMACS_SPIKE_SSH_CONFIG")
                                "wslspike" "true")))
      (spike-record "probe: sshd 60 s after the last wsl.exe session" 1 0.0
                    (equal (car answer) 0)
                    (format "running: %s; ssh: %S" running answer)))))

;;; Everything, in order

(defun spike-phase (function)
  "Call FUNCTION, and record an error it lets out, so later phases still run.
Return its value."
  (let ((began (float-time)))
    (spike-log "phase %s" function)
    (condition-case err
        (let ((tramp-dont-suspend-timers t))
          (prog1 (funcall function)
            (spike-log "phase %s took %.0f s" function (- (float-time) began))))
      ((error quit)
       (spike-record (format "phase %s stopped" function) 1 (- (float-time) began) nil
                     (format "%s | login printed: %s"
                             (error-message-string err) (spike-connection-tail)))
       (spike-disconnect)
       nil))))

(spike-ensure-backend)
(when (spike-phase #'spike-phase-connect)
  (mapc #'spike-phase '(spike-phase-leaks
                        spike-phase-files
                        spike-phase-doctor
                        spike-phase-magit
                        spike-phase-eglot
                        spike-phase-risks
                        spike-phase-hang
                        spike-phase-shutdown
                        spike-phase-idle-distribution)))
(spike-phase #'spike-phase-bad-host)
(when spike-quick
  (dolist (buffer (buffer-list))
    (when (string-prefix-p "*debug tramp/" (buffer-name buffer))
      (with-current-buffer buffer
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region (max (point-min) (- (point-max) 300000)) (point-max)
                        (concat (getenv "KITTYMACS_SPIKE_RESULT") ".debug") t 'silent))))))
(spike-log "done")
(when (process-live-p spike-keepalive) (delete-process spike-keepalive))
(kill-emacs 0)

;;; spike.el ends here
