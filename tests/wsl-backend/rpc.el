;;; rpc.el --- The wsl-rpc transport against wslm, on real WSL2 -*- lexical-binding: t; -*-
;; Run by tests/wsl-backend/run-rpc.ps1, one phase to one Emacs under a limit, so a
;; hang leaves the other phases.  It starts the real configuration with the feature
;; on and the package a user's start installed.  Nothing here runs anywhere but a
;; hosted runner, because this is where tramp-rpc's own code runs.
;;
;; The environment names the run:
;;   KITTYMACS_RPC_PHASE       killed-write, compare, ergonomics or dead
;;   KITTYMACS_RPC_ROUNDS      rounds of the timed rows in `compare'
;;   KITTYMACS_WSL_DISTRIBUTION  the distribution, with the fixtures rpc-fixtures.sh makes
;;   KITTYMACS_TEST_PACKAGES   the package directory
;;
;; A phase prints Markdown, then PASS or FAIL on a line of its own.

;;; Code:
(require 'cl-lib)
(require 'package)
(require 'seq)
(require 'subr-x)

(defvar kittymacs-backends)
(defvar kittymacs-host-directories nil)
(defvar tramp-connection-timeout)
(defvar tramp-dont-suspend-timers nil)
(defvar tramp-remote-process-environment)
(defvar eglot-sync-connect)
(defvar eglot-connect-timeout)
(defvar server-auth-dir)
(defvar ghostel-buffer-name)
(defvar auto-revert-remote-files)
(defvar auto-revert-use-notify)
(defvar tramp-rpc-use-controlmaster)
(defvar tramp-rpc-use-direct-ssh-pty)
(defvar tramp-rpc-deploy-never-deploy)

(defconst rpc-source
  (file-name-directory (directory-file-name
                        (file-name-directory
                         (directory-file-name (file-name-directory load-file-name))))))
(defconst rpc-distribution (getenv "KITTYMACS_WSL_DISTRIBUTION"))
(defconst rpc-home "/home/backend")
(defconst rpc-rounds (string-to-number (or (getenv "KITTYMACS_RPC_ROUNDS") "3")))
(defconst rpc-server-comm "tramp-rpc-serve" "The server's name in the kernel, cut to 15 bytes.")

(defvar rpc-rows nil "Each check so far: (NAME SECONDS OK DETAIL).")

(defun rpc-check (name limit function)
  "Call FUNCTION under LIMIT seconds, and record it as NAME.
FUNCTION returns a string saying what it saw, or signals.  A stall is a failure."
  (let ((began (float-time)) ok detail)
    (condition-case err
        (let* ((tramp-dont-suspend-timers t)
               (value (with-timeout (limit 'stalled) (funcall function))))
          (if (eq value 'stalled)
              (setq detail (format "no answer in %d s" limit))
            (setq ok t detail value)))
      ((error quit) (setq detail (error-message-string err))))
    (push (list name (- (float-time) began) ok detail) rpc-rows)
    (message "%s: %.3f s %s %s" name (- (float-time) began) (if ok "ok" "FAILED") detail)
    ok))

(defun rpc-record (name function)
  "As `rpc-check' for NAME under 120 s, for the record: failing fails nothing."
  (rpc-check name 150
             (lambda ()
               (condition-case err
                   (with-timeout (120 "no answer in 120 s") (funcall function))
                 ((error quit) (format "signalled: %s" (error-message-string err)))))))

(defun rpc-expect (expected actual)
  "Return ACTUAL if it contains EXPECTED, and signal if it does not."
  (unless (string-search expected actual)
    (error "Expected %S, and got %S" expected actual))
  (string-trim actual))

(defun rpc-print-rows ()
  "Print the rows as a table, then whether they all passed, and exit."
  (let ((rows (reverse rpc-rows)))
    (princ "\n| Check | Seconds | Result | Detail |\n|---|---:|---|---|\n")
    (pcase-dolist (`(,name ,seconds ,ok ,detail) rows)
      (princ (format "| %s | %.3f | %s | %s |\n" name seconds (if ok "pass" "FAIL")
                     (string-replace "|" "/" (string-replace "\n" " " (format "%s" (or detail "")))))))
    (let ((passed (cl-every #'caddr rows)))
      (princ (if passed "\nPASS\n" "\nFAIL\n"))
      (kill-emacs (if passed 0 1)))))

;;; Reaching the distribution without going through either transport

(defun rpc-wsl (limit as-root script)
  "Run the shell SCRIPT in the distribution under LIMIT seconds, as root if AS-ROOT.
Return (STATUS . OUTPUT)."
  (let ((default-directory temporary-file-directory)
        (arguments (append (list "-d" rpc-distribution)
                           (and as-root '("-u" "root"))
                           (list "--exec" "/bin/sh" "-c" script))))
    (with-temp-buffer
      (let* ((process (apply #'start-process "rpc-wsl" (current-buffer) "wsl.exe" arguments))
             (end (+ (float-time) limit)))
        (set-process-query-on-exit-flag process nil)
        ;; Or Emacs writes "Process rpc-wsl finished" into what this returns.
        (set-process-sentinel process #'ignore)
        (while (and (process-live-p process) (< (float-time) end))
          (accept-process-output process 0.05))
        (when (process-live-p process) (delete-process process))
        (cons (process-exit-status process) (string-trim (buffer-string)))))))

;;; The start

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-rpc-" t))
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      native-comp-jit-compilation nil)
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file rpc-source) (expand-file-name file user-emacs-directory)))
(dolist (directory '("lisp" "literate" "tools"))
  (copy-directory (expand-file-name directory rpc-source)
                  (expand-file-name directory user-emacs-directory) nil t))
(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert ";;; -*- lexical-binding: t; -*-\n"
          "(setopt kittymacs-profile 'full kittymacs-features '(wsl-rpc))\n"
          (format "(setopt kittymacs-backends '((\"rpc\" :transport wsl-rpc :host %S :root \"~/project/\")
                                               (\"wslm\" :transport wsl :host %S :root \"~/project/\")))\n"
                  rpc-distribution rpc-distribution)))
(advice-add 'kittymacs-activate-packages :before
            (lambda (&rest _) (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES"))))
(dolist (function '(package-install package-vc-install package-refresh-contents))
  (advice-add function :override
              (lambda (&rest arguments) (error "This start must install nothing: %S" arguments))))
(advice-add 'y-or-n-p :override #'ignore)
(advice-add 'yes-or-no-p :override #'ignore)

(rpc-check
 "start, feature on, without loading Tramp or tramp-rpc" 600
 (lambda ()
   (setq after-init-time nil)
   (load (expand-file-name "early-init.el" user-emacs-directory) nil t)
   (load user-init-file nil t)
   (setq after-init-time (current-time))
   (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
   (unless (kittymacs-feature-p 'wsl-rpc) (error "The feature is off"))
   (when (featurep 'tramp) (error "The start loaded Tramp"))
   (when (featurep 'tramp-rpc) (error "The start loaded tramp-rpc"))
   ;; The installed package's autoloads ran, as the trial's harness never did.
   (unless (fboundp 'tramp-rpc--autoload-register)
     (error "tramp-rpc's autoloads did not run"))
   (format "%s, %s" (emacs-version) system-type)))

(setq tramp-connection-timeout 45)

(defun rpc-root (backend) "Return the root of BACKEND." (kittymacs-backend-root backend))
(defun rpc-prefix (backend) "Return the start of a file name on BACKEND."
       (file-remote-p (rpc-root backend)))
(defun rpc-name (backend path) "Return the name of PATH, under the home, on BACKEND."
       (concat (rpc-prefix backend) rpc-home "/" path))
(defun rpc-disconnect (backend) "Drop BACKEND's connection and what Tramp cached."
       (tramp-cleanup-connection (tramp-dissect-file-name (rpc-root backend))))
(defun rpc-blob (size)
  "Return SIZE random bytes, which Tramp's compression cannot shrink."
  (let ((bytes (make-string size 0)))
    (dotimes (index size bytes) (aset bytes index (random 256)))))
(defun rpc-write (file bytes)
  "Write BYTES to FILE."
  (let ((coding-system-for-write 'binary)) (write-region bytes nil file nil 'silent)))
(defun rpc-read (file)
  "Return FILE's bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'binary)) (insert-file-contents-literally file))
    (buffer-string)))

;;; Against wslm: the same rows, one after the other, in one job

(defun rpc-median-worst (numbers)
  "Return the median and worst of NUMBERS as a string."
  (let ((sorted (sort (copy-sequence numbers) #'<)))
    (format "%.3f / %.3f" (nth (/ (length sorted) 2) sorted) (car (last sorted)))))

(defvar rpc-compared nil "Each row of the comparison: (BACKEND OP TIME FAILURE).")

(defun rpc-timed (backend op rounds limit function)
  "Time FUNCTION ROUNDS times, and record OP for BACKEND as (BACKEND OP TEXT)."
  (let (times failure)
    (dotimes (round rounds)
      (let ((began (float-time)))
        (condition-case err
            (let* ((tramp-dont-suspend-timers t)
                   (value (with-timeout (limit 'stalled) (funcall function round))))
              (when (eq value 'stalled) (error "No answer in %d s" limit))
              (push (- (float-time) began) times))
          ((error quit) (setq failure (error-message-string err))))))
    (push (list backend op (if times (rpc-median-worst times) "")
                (or failure "")) rpc-compared)
    (rpc-check (format "%s: %s" backend op) 1
               (lambda () (when failure (error "%s" failure)) (rpc-median-worst times)))))

(defun rpc-magit-status (backend)
  "Open Magit status on the fixture from a fresh buffer on BACKEND, and return its text."
  (let ((buffer (magit-status-setup-buffer (rpc-name backend "repo/"))))
    (prog1 (with-current-buffer buffer
             (buffer-substring-no-properties (point-min) (point-max)))
      (kill-buffer buffer))))

(defun rpc-eglot-start (backend)
  "Start clangd on the fixture on BACKEND, and shut it down."
  (let ((buffer (find-file-noselect (rpc-name backend "cproj/main.c"))))
    (with-current-buffer buffer
      (let ((eglot-sync-connect t) (eglot-connect-timeout 60))
        (eglot (list major-mode) (project-current) 'eglot-lsp-server '("clangd") "c")
        (unless (eglot-current-server) (error "No server"))
        (eglot-shutdown (eglot-current-server))))
    (kill-buffer buffer)
    t))

(defun rpc-phase-compare ()
  "The rows the owner compares, on each transport."
  (require 'magit)
  (require 'eglot)
  (let ((small (rpc-blob 4096))
        (large (rpc-blob (* 1024 1024))))
    (dolist (backend '("rpc" "wslm"))
      (let ((directory (rpc-name backend "project/")))
        (rpc-timed backend "Connect, warm" rpc-rounds 75
                   (lambda (round)
                     (rpc-disconnect backend)
                     (or (file-directory-p (rpc-root backend))
                         (error "No root on round %d" round))))
        (rpc-write (concat directory "small") small)
        (rpc-write (concat directory "large") large)
        (rpc-timed backend "Read 4 KiB" rpc-rounds 60
                   (lambda (_) (or (equal (rpc-read (concat directory "small")) small)
                                   (error "Wrong bytes"))))
        (rpc-timed backend "Write 4 KiB" rpc-rounds 60
                   (lambda (_) (rpc-write (concat directory "small") small) t))
        (rpc-timed backend "Read 1 MiB" rpc-rounds 60
                   (lambda (_) (or (equal (rpc-read (concat directory "large")) large)
                                   (error "Wrong bytes"))))
        (rpc-timed backend "Write 1 MiB" rpc-rounds 120
                   (lambda (_) (rpc-write (concat directory "large") large) t))
        (rpc-timed backend "directory-files, 200 names" rpc-rounds 60
                   (lambda (_)
                     (let ((remote-file-name-inhibit-cache t))
                       (or (>= (length (directory-files (rpc-name backend "many/"))) 200)
                           (error "Too few names")))))
        (rpc-timed backend "file-attributes" rpc-rounds 60
                   (lambda (_)
                     (let ((remote-file-name-inhibit-cache t))
                       (or (file-attributes (concat directory "file")) (error "No attributes")))))
        (rpc-timed backend "Magit status, one edited file" rpc-rounds 120
                   (lambda (_) (or (string-search "Unstaged changes" (rpc-magit-status backend))
                                   (error "No unstaged changes shown"))))
        (rpc-timed backend "Eglot start, clangd" rpc-rounds 90
                   (lambda (_) (rpc-eglot-start backend)))))
    (princ "\n## Against wslm: median / worst, seconds\n\n| Operation | wsl-rpc | wslm |\n|---|---:|---:|\n")
    (dolist (op (seq-uniq (mapcar #'cadr (reverse rpc-compared))))
      (let ((row (lambda (backend)
                   (let ((found (seq-find (lambda (r) (and (equal (car r) backend) (equal (cadr r) op)))
                                          rpc-compared)))
                     (if (string-empty-p (nth 3 found)) (nth 2 found)
                       (format "%s FAILED: %s" (nth 2 found) (nth 3 found)))))))
        (princ (format "| %s | %s | %s |\n" op (funcall row "rpc") (funcall row "wslm")))))))

;;; Each ergonomics check

(defun rpc-wait-for (process text limit)
  "Wait up to LIMIT seconds for TEXT in PROCESS's buffer, and return the buffer's text."
  (let ((end (+ (float-time) limit)))
    (with-current-buffer (process-buffer process)
      (while (and (not (string-search text (buffer-string)))
                  (process-live-p process)
                  (< (float-time) end))
        (accept-process-output process 0.1))
      (buffer-string))))

(defun rpc-linux-path (file)
  "Return what the distribution calls the Windows FILE."
  (with-temp-buffer
    (unless (eql 0 (call-process "wsl.exe" nil t nil "-d" rpc-distribution
                                 "--exec" "wslpath" "-a"
                                 (string-replace "\\" "/" (expand-file-name file))))
      (error "wslpath failed: %s" (buffer-string)))
    (string-trim (buffer-string))))

(defun rpc-open (name)
  "Run `kittymacs-open' on NAME in the distribution, and return its output and status.
It waits with `accept-process-output', since this Emacs must answer the client."
  (let* ((script (rpc-linux-path (expand-file-name "nix/kittymacs-open.sh" rpc-source)))
         (buffer (generate-new-buffer " *kittymacs-open*"))
         (process (make-process :name "kittymacs-open" :buffer buffer :noquery t
                                :connection-type 'pipe
                                :command (list "wsl.exe" "-d" rpc-distribution
                                               "--cd" "~" "--exec" "sh" script name)))
         (end (+ (float-time) 45)))
    (while (and (process-live-p process) (< (float-time) end))
      (accept-process-output nil 0.2))
    (list (process-status process) (process-exit-status process)
          (with-current-buffer buffer (buffer-string)))))

(defun rpc-buffer-visiting (suffix limit)
  "Wait up to LIMIT seconds for a buffer whose file name ends in SUFFIX, and return it."
  (let ((end (+ (float-time) limit)) buffer)
    (while (and (< (float-time) end)
                (not (setq buffer (seq-find (lambda (b)
                                              (string-suffix-p suffix (or (buffer-file-name b) "")))
                                            (buffer-list)))))
      (accept-process-output nil 0.2))
    buffer))

(defun rpc-terminal-facts (file limit)
  "Have this buffer's terminal write what it is to FILE, and return that text."
  (ghostel-send-string
   (format "{ tty; stty size; echo \"login=$0 pwd=$PWD distro=$WSL_DISTRO_NAME\"; } > %s 2>&1\r" file))
  (let ((remote (concat (rpc-root "rpc") file))
        (end (+ (float-time) limit))
        (remote-file-name-inhibit-cache t))
    (while (and (< (float-time) end) (not (file-exists-p remote)))
      (accept-process-output nil 0.5))
    (accept-process-output nil 1)
    (unless (file-exists-p remote)
      (error "No %s after %d s; the terminal shows: %s" file limit
             (string-trim (buffer-substring-no-properties (point-min) (point-max)))))
    (with-temp-buffer (insert-file-contents remote) (buffer-string))))

(defun rpc-doctor-text (name)
  "Run the doctor on the backend called NAME, and return what it said."
  (kittymacs-backend-doctor name)
  (with-current-buffer "*kittymacs backend*" (buffer-string)))

(defun rpc-server-pids ()
  "Return the server processes the distribution has now."
  (cdr (rpc-wsl 30 t (concat "pgrep -x " rpc-server-comm " | tr '\\n' ' '"))))

(defun rpc-phase-ergonomics ()
  "Each place the remote chapter once assumed `wslm'."
  (rpc-check
   "the packages are at their pinned commits, from Git"
   60
   (lambda ()
     (let ((check (lambda (package revision)
                    (let* ((desc (cadr (assq package package-alist)))
                           (directory (package-desc-dir desc)))
                      (unless (package-vc-p desc) (error "%s is not from Git" package))
                      (let ((head (string-trim
                                   (with-temp-buffer
                                     (let ((default-directory directory))
                                       (call-process "git" nil t nil "rev-parse" "HEAD"))
                                     (buffer-string)))))
                        (unless (equal head revision)
                          (error "%s is at %s, and the pin says %s" package head revision))
                        (format "%s %s" package head))))))
       (concat (funcall check 'tramp-rpc kittymacs-remote-rpc-revision) ", "
               (funcall check 'msgpack kittymacs-remote-rpc-msgpack-revision)))))
  (rpc-check "the backend's name" 60
             (lambda () (rpc-expect (format "/rpc:%s:" rpc-distribution) (rpc-root "rpc"))))
  (rpc-check
   "the first /rpc: name loads tramp-rpc, and the seam goes on" 120
   (lambda ()
     (unless (file-directory-p (rpc-root "rpc")) (error "No root"))
     (unless (featurep 'tramp-rpc) (error "tramp-rpc did not load"))
     (dolist (pair '((tramp-rpc--start-server-process . kittymacs--remote-rpc-start-server)
                     (tramp-rpc--connect . kittymacs--remote-rpc-scope)
                     (tramp-rpc--make-pty-process . kittymacs--remote-rpc-scope)))
       (unless (advice-member-p (cdr pair) (car pair)) (error "No seam on %s" (car pair))))
     (when (kittymacs-remote-rpc--missing) (error "Missing %S" (kittymacs-remote-rpc--missing)))
     (format "tramp-rpc %s, protocol %s, servers: %s" tramp-rpc-deploy-version
             tramp-rpc-protocol-revision (rpc-server-pids))))
  (rpc-check
   "the global switches stay as upstream ships them; the backend's are per connection" 60
   (lambda ()
     (unless (and (default-value 'tramp-rpc-use-controlmaster)
                  (default-value 'tramp-rpc-use-direct-ssh-pty)
                  (not (default-value 'tramp-rpc-deploy-never-deploy)))
       (error "A global moved: %S" (list tramp-rpc-use-controlmaster tramp-rpc-use-direct-ssh-pty
                                         tramp-rpc-deploy-never-deploy)))
     (let ((plan (lambda (name)
                   (tramp-rpc-deploy-plan-mode
                    (tramp-rpc-deploy-plan (tramp-dissect-file-name name))))))
       (unless (eq (funcall plan (rpc-root "rpc")) 'never)
         (error "The backend's deployment is %S" (funcall plan (rpc-root "rpc"))))
       (when (eq (funcall plan "/rpc:elsewhere.invalid:/") 'never)
         (error "Another host's deployment is off"))
       "backend: never; any other host: as upstream")))
  (rpc-check
   "any other /rpc: host keeps ssh, and the backend does not" 30
   (lambda ()
     (let* ((started
             (lambda (host)
               (let (command)
                 (cl-letf (((symbol-function 'make-process)
                            (lambda (&rest arguments)
                              (setq command (plist-get arguments :command))
                              (error "Stop here"))))
                   (ignore-errors
                     (tramp-rpc--start-server-process
                      (tramp-dissect-file-name (format "/rpc:%s:/" host)) "tramp-rpc-server")))
                 command)))
            (other (funcall started "elsewhere.invalid"))
            (own (funcall started rpc-distribution)))
       (unless (equal (car other) "ssh") (error "Another host ran %S" other))
       (unless (equal (car own) "wsl.exe") (error "The backend ran %S" own))
       (format "%s; %s" (car other) (string-join own " ")))))
  (rpc-check
   "kittymacs-backend-connect" 90
   (lambda ()
     (let (opened)
       (cl-letf (((symbol-function 'project-switch-project)
                  (lambda (directory) (setq opened directory))))
         (kittymacs-backend-connect "rpc"))
       (unless (equal opened (rpc-root "rpc")) (error "Opened %S" opened))
       opened)))
  (rpc-check
   "the doctor names the server, cat and how processes start" 90
   (lambda ()
     (let ((text (rpc-doctor-text "rpc")))
       (rpc-expect "/home/backend/.local/bin/tramp-rpc-server" text)
       (rpc-expect "cat.exe" (downcase text))
       (rpc-expect "Processes start through tramp-rpc-server" text)
       (rpc-expect "exists" text)
       (when (string-search "NOT FOUND" text) (error "%s" text))
       (string-replace "\n" " " text))))
  (rpc-check
   "the doctor says what to install for a missing server, and uses :server" 90
   (lambda ()
     (let* ((kittymacs-backends
             (cons `("no-server" :transport wsl-rpc :host ,rpc-distribution :root "~/project/"
                     :server "/no/such/server")
                   kittymacs-backends))
            (text (rpc-doctor-text "no-server")))
       (rpc-expect "NOT FOUND" text)
       (rpc-expect "cargo install" text)
       (rpc-expect kittymacs-remote-rpc-revision text)
       (when (string-search "Project" text) (error "It went on past the server: %s" text))
       "names the install line")))
  (rpc-check
   "a missing distribution is refused, naming those WSL has" 30
   (lambda ()
     (let* ((kittymacs-backends
             (cons '("gone" :transport wsl-rpc :host "no-such-distribution" :root "/")
                   kittymacs-backends))
            (failure (condition-case err
                         (progn (kittymacs-backend-connect "gone") "connected")
                       (user-error (error-message-string err)))))
       (rpc-expect rpc-distribution failure)
       (rpc-expect "no-such-distribution" failure))))
  (rpc-record
   "a /rpc: name on a missing distribution, past the check, for the record"
   (lambda ()
     (let* ((kittymacs-backends
             (cons '("gone" :transport wsl-rpc :host "no-such-distribution" :root "/")
                   kittymacs-backends)))
       (kittymacs-remote--apply-backend "gone")
       (format "%S" (file-exists-p "/rpc:no-such-distribution:/tmp")))))
  (rpc-check
   "the mode line names the backend, and sees it go" 120
   (lambda ()
     (let ((buffer (find-file-noselect (concat (rpc-root "rpc") "file"))))
       (with-current-buffer buffer
         (let ((on (kittymacs-remote-mode-line)))
           (unless (equal (substring-no-properties on) " [rpc]")
             (error "Connected, it said %S" on))
           (rpc-disconnect "rpc")
           (let ((off (kittymacs-remote-mode-line)))
             (unless (equal (substring-no-properties off) " [rpc?]")
               (error "Not connected, it said %S" off))
             (kill-buffer buffer)
             (format "%S, then %S" (substring-no-properties on) (substring-no-properties off))))))))
  (rpc-check
   "kittymacs-backend-reconnect gets a new server" 120
   (lambda ()
     (let ((before (progn (file-directory-p (rpc-root "rpc")) (rpc-server-pids))))
       (kittymacs-backend-reconnect "rpc")
       (let ((after (rpc-server-pids)))
         (when (equal before after) (error "The same servers: %s" before))
         (format "%s, then %s" before after)))))
  (rpc-check
   "M-x shell" 60
   (lambda ()
     (let* ((default-directory (rpc-root "rpc"))
            (buffer (shell (generate-new-buffer-name "*rpc-shell*")))
            (process (get-buffer-process buffer)))
       (process-send-string process "echo shell-$((40+2)); exit\n")
       (rpc-expect "shell-42" (rpc-wait-for process "shell-42" 30)))))
  (rpc-check
   "the terminal's native module loads" 180
   (lambda ()
     (require 'ghostel)
     (let ((directory (ghostel--module-directory)))
       (unless (ghostel--download-module directory) (error "The download failed"))
       (ghostel--load-module)
       (unless (fboundp 'ghostel--new) (error "The module did not load"))
       "loaded")))
  (rpc-check
   "SPC o e: a login shell on a real pty, in the project" 100
   (lambda ()
     (let* ((default-directory (rpc-root "rpc"))
            (buffer (kittymacs-terminal-open)))
       (with-current-buffer buffer
         (unless (equal (file-remote-p default-directory) (rpc-prefix "rpc"))
           (error "The terminal's buffer left the backend: %s" default-directory))
         (let ((end (+ (float-time) 60)))
           (while (and (< (float-time) end)
                       (not (string-match-p "project\\$ *$" (buffer-string))))
             (accept-process-output nil 0.5)))
         (let ((facts (rpc-terminal-facts "terminal-facts" 20)))
           (rpc-expect "/dev/pts/" facts)
           (rpc-expect "login=-bash" facts)
           (rpc-expect "pwd=/home/backend/project" facts)
           (rpc-expect (format "distro=%s" rpc-distribution) facts)
           (string-replace "\n" " " facts))))))
  (setq server-auth-dir (expand-file-name "~/.emacs.d/server/"))
  (require 'server)
  (server-start)
  (rpc-check
   "kittymacs-open: a Linux file opens on the backend's method" 75
   (lambda ()
     (let ((outcome (rpc-open "project/file")))
       (unless (eql 0 (nth 1 outcome)) (error "kittymacs-open: %S" outcome))
       (let ((buffer (rpc-buffer-visiting "project/file" 30)))
         (unless buffer (error "No buffer; it said %S" outcome))
         (prog1 (rpc-expect (format "/rpc:%s:/home/backend/project/file" rpc-distribution)
                            (buffer-file-name buffer))
           (kill-buffer buffer))))))
  (rpc-check
   "kittymacs-open: a Windows-side file opens natively" 75
   (lambda ()
     (let* ((file (make-temp-file "kittymacs-open-"))
            (outcome (rpc-open (rpc-linux-path file))))
       (unless (eql 0 (nth 1 outcome)) (error "kittymacs-open: %S" outcome))
       (let ((buffer (rpc-buffer-visiting (file-name-nondirectory file) 30)))
         (unless buffer (error "No buffer; it said %S" outcome))
         (when (file-remote-p (buffer-file-name buffer))
           (error "It went through Tramp: %s" (buffer-file-name buffer)))
         (prog1 (buffer-file-name buffer) (kill-buffer buffer))))))
  (rpc-check
   "a file under /mnt/ says so once, and reopens natively" 60
   (lambda ()
     (let* ((file (format "/rpc:%s:/mnt/c/Windows/win.ini" rpc-distribution))
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
       (with-current-buffer buffer (kittymacs-remote-reopen-natively))
       (let ((native (get-file-buffer "c:/Windows/win.ini")))
         (unless native (error "No buffer on the native file"))
         (when (buffer-live-p buffer) (error "The buffer through Tramp is still there"))
         (kill-buffer native)
         "once, then c:/Windows/win.ini"))))
  (rpc-check
   "a new file has Unix newlines, and an existing one keeps its own" 90
   (lambda ()
     (let ((new (concat (rpc-root "rpc") "new"))
           (windows (concat (rpc-root "rpc") "windows")))
       (with-current-buffer (find-file-noselect new)
         (insert "one\ntwo\n")
         (save-buffer)
         (kill-buffer))
       (unless (equal (rpc-read new) "one\ntwo\n")
         (error "A new file has %S" (rpc-read new)))
       (let ((coding-system-for-write 'no-conversion))
         (write-region "a\r\nb\r\n" nil windows))
       (with-current-buffer (find-file-noselect windows)
         (goto-char (point-max))
         (insert "c\n")
         (save-buffer)
         (kill-buffer))
       (unless (equal (rpc-read windows) "a\r\nb\r\nc\r\n")
         (error "An existing file has %S" (rpc-read windows)))
       (delete-file new)
       (delete-file windows)
       "both")))
  (rpc-check
   "kittymacs-remote-buffer-p and kittymacs-remote-agent-path, both ways" 30
   (lambda ()
     (let ((remote (rpc-prefix "rpc")))
       (with-temp-buffer
         (setq default-directory (concat remote "/tmp/"))
         (unless (kittymacs-remote-buffer-p) (error "Not remote"))
         (unless (equal (kittymacs-remote-agent-path (concat remote "/tmp/a")) "/tmp/a")
           (error "Going out: %S" (kittymacs-remote-agent-path (concat remote "/tmp/a"))))
         (unless (equal (kittymacs-remote-agent-path "/tmp/a") (concat remote "/tmp/a"))
           (error "Coming in: %S" (kittymacs-remote-agent-path "/tmp/a"))))
       (with-temp-buffer
         (setq default-directory temporary-file-directory)
         (when (kittymacs-remote-buffer-p) (error "A local buffer is remote"))
         (unless (equal (kittymacs-remote-agent-path "/tmp/a") "/tmp/a")
           (error "A local path changed")))
       "right both ways")))
  (rpc-check
   "the guards: auto-save and checkers stay off a backend's buffer" 60
   (lambda ()
     (let ((buffer (find-file-noselect (concat (rpc-root "rpc") "file"))))
       (with-current-buffer buffer
         (when (and buffer-auto-save-file-name auto-save-default
                    remote-file-name-inhibit-auto-save
                    (auto-save-file-name-p (file-name-nondirectory buffer-auto-save-file-name))
                    (file-remote-p buffer-auto-save-file-name))
           (error "Auto-save writes over the connection: %s" buffer-auto-save-file-name)))
       (kill-buffer buffer)
       (format "%S" remote-file-name-inhibit-auto-save))))
  (rpc-record
   "a backend's environment, for the chapter's table"
   (lambda ()
     (let* ((default-directory (rpc-root "rpc"))
            (remote (file-remote-p default-directory))
            (command (concat "echo \"$KITTYMACS_PROFILE_VAR $KITTYMACS_LIST_VAR $PATH\"; echo done"))
            (tramp-remote-process-environment
             (cons "KITTYMACS_LIST_VAR=list-value" tramp-remote-process-environment))
            (report (lambda (text)
                      (format "profile=%s list=%s from-profile=%s"
                              (if (string-search "profile-value" text) "yes" "no")
                              (if (string-search "list-value" text) "yes" "no")
                              (if (string-search "from-profile" text) "yes" "no")))))
       (make-directory (concat remote "~/from-profile") t)
       (let ((coding-system-for-write 'utf-8-unix))
         (with-temp-file (concat remote "~/.profile")
           (insert "export KITTYMACS_PROFILE_VAR=profile-value\n"
                   "PATH=\"$HOME/from-profile:$PATH\"\nexport PATH\n")))
       (rpc-disconnect "rpc")
       (prog1
           (format "process-file: %s; a process: %s; M-x shell: %s"
                   (funcall report (with-temp-buffer
                                     (process-file "/bin/sh" nil t nil "-c" command)
                                     (buffer-string)))
                   (funcall report (let* ((buffer (generate-new-buffer " *environment*"))
                                          (process (make-process :name "environment" :buffer buffer
                                                                 :noquery t :file-handler t
                                                                 :connection-type 'pipe
                                                                 :command (list "/bin/sh" "-c" command))))
                                     (rpc-wait-for process "done" 30)))
                   (funcall report (let* ((buffer (shell (generate-new-buffer-name "*env shell*")))
                                          (process (get-buffer-process buffer)))
                                     (process-send-string process (concat command "; exit\n"))
                                     (rpc-wait-for process "done" 30))))
         (delete-file (concat remote "~/.profile"))))))
  (rpc-check
   "compile runs there, and reports its end" 90
   (lambda ()
     (let* ((default-directory (rpc-root "rpc"))
            (buffer (compile "echo compiled-$((40+2))"))
            (end (+ (float-time) 60)))
       (while (and (< (float-time) end) (get-buffer-process buffer))
         (accept-process-output nil 0.2))
       (with-current-buffer buffer
         (rpc-expect "compiled-42" (buffer-string))
         (rpc-expect "finished" (buffer-string))
         "compiled-42, finished"))))
  (rpc-record
   "auto-revert: off on a backend by default, and what it does with it on, for the record"
   (lambda ()
     (require 'autorevert)
     (let* ((file (concat (rpc-root "rpc") "revert"))
            (linux (concat rpc-home "/project/revert"))
            (edit (lambda (text)
                    (rpc-wsl 30 nil (format "printf %s > %s" text linux))))
            (wait (lambda (seconds)
                    (let ((end (+ (float-time) seconds)))
                      (while (< (float-time) end) (auto-revert-buffers) (accept-process-output nil 0.5)))))
            result)
       (funcall edit "one")
       (with-current-buffer (find-file-noselect file)
         (auto-revert-mode 1)
         (funcall edit "two")
         (funcall wait 3)
         (push (format "default: %S, %S" (buffer-string) auto-revert-remote-files) result)
         (auto-revert-mode -1)
         (let ((auto-revert-remote-files t))
           (auto-revert-mode 1)
           (funcall edit "three")
           (funcall wait 8)
           (push (format "with auto-revert-remote-files: %S, notify %S"
                         (buffer-string) auto-revert-notify-watch-descriptor)
                 result)
           (auto-revert-mode -1))
         (kill-buffer))
       (string-join (reverse result) "; "))))
  (rpc-check
   "the server is found in each directory a Nix install uses" 120
   (lambda ()
     (let* ((server (concat rpc-home "/.local/bin/tramp-rpc-server"))
            (kept (concat server ".kept"))
            (found nil))
       ;; Each one alone, because ~/.local/bin comes first.
       (rpc-wsl 30 nil (format "mv %s %s" server kept))
       (unwind-protect
           (dolist (directory (seq-remove
                               (lambda (d) (member d '("$HOME/.local/bin" "/usr/local/sbin" "/usr/local/bin"
                                                       "/usr/sbin" "/usr/bin" "/sbin" "/bin")))
                               (split-string (kittymacs-remote-rpc--path) ":")))
             (let ((link (format "%s/tramp-rpc-server" directory)))
               (rpc-wsl 30 t (format "HOME=%s USER=backend; mkdir -p %s; ln -sf %s %s"
                                     rpc-home directory kept link))
               (let ((where (kittymacs-remote-rpc--server (list :host rpc-distribution))))
                 (unless (and where (string-suffix-p "/tramp-rpc-server" where))
                   (error "Not found in %s: %S" directory where))
                 (push (format "%s -> %s" directory where) found))
               (rpc-wsl 30 t (format "HOME=%s USER=backend; rm -f %s" rpc-home link))))
         (rpc-wsl 30 nil (format "mv %s %s" kept server)))
       (string-join (reverse found) "; ")))))

;;; A dead connection

(defun rpc-signal-servers (signal)
  "Send SIGNAL to every server there is."
  (rpc-wsl 30 t (format "pkill -%s -x %s" signal rpc-server-comm)))

(defun rpc-phase-dead ()
  "What Emacs sees when the server stops answering, and when the distribution goes."
  (let ((file (concat (rpc-root "rpc") "file"))
        (remote-file-name-inhibit-cache t))
    (rpc-check "connect" 75 (lambda () (or (file-directory-p (rpc-root "rpc")) (error "No root"))))
    (rpc-signal-servers "STOP")
    (rpc-record "file-attributes, server stopped"
                (lambda () (format "%S" (and (file-attributes file) t))))
    (rpc-record "the next call, old server still stopped"
                (lambda () (format "%S" (and (file-attributes file) t))))
    (rpc-signal-servers "CONT")
    (rpc-check "after resuming, it answers" 60
               (lambda () (or (and (file-attributes file) "answers") (error "No attributes"))))
    (rpc-signal-servers "STOP")
    (rpc-record "a save, every server stopped"
                (lambda ()
                  (with-current-buffer (find-file-noselect file)
                    (goto-char (point-max))
                    (insert "dead\n")
                    (save-buffer)
                    (prog1 (format "saved, modified %S" (buffer-modified-p))
                      (set-buffer-modified-p nil)
                      (kill-buffer)))))
    (rpc-signal-servers "CONT")
    (let* ((default-directory (rpc-root "rpc"))
           (buffer (generate-new-buffer " *dead*"))
           (process (make-process :name "dead" :buffer buffer :noquery t :file-handler t
                                  :connection-type 'pipe :command '("/bin/sleep" "600")))
           (began (float-time)))
      (rpc-wsl 60 nil "true")
      (setq began (float-time))
      (call-process "wsl.exe" nil nil nil "--shutdown")
      (rpc-check "wsl --shutdown: a process's end reaches Emacs" 30
                 (lambda ()
                   (while (process-live-p process) (accept-process-output nil 0.1))
                   (format "after %.1f s" (- (float-time) began)))))
    (rpc-check "after the shutdown, the next call works" 120
               (lambda () (or (and (file-attributes file) "works") (error "No attributes"))))))

;;; A write killed midway

(defconst rpc-killed-size (+ (* 1024 1024) 17)
  "The old file's size, unlike the new one's, so a watcher sees any change.")

(defun rpc-killed-prepare (target)
  "Give the file TARGET, a path in the distribution, known old contents.
Return their hash."
  (let ((made (rpc-wsl 60 nil (format "rm -f %s*; yes OLD-CONTENT | head -c %d > %s && sha256sum < %s"
                                      (file-name-directory target) rpc-killed-size target target))))
    (unless (eql 0 (car made)) (error "Could not make the old file: %s" (cdr made)))
    (car (split-string (cdr made)))))

(defun rpc-killer (kind target)
  "Start what kills the server for KIND on the file TARGET, and return its process."
  (let ((default-directory temporary-file-directory)
        (script (pcase kind
                  ;; As soon as the size moves, which truncating does first.
                  ('watch (format "bash %s/kill-at-change.sh %s %d %s"
                                  rpc-home target rpc-killed-size rpc-server-comm))
                  ;; Whenever it arrives, which can be before the frame does.
                  ('at-once (format "pkill -KILL -x %s" rpc-server-comm))
                  ;; A delay before each write, so the kill lands between truncate and write.
                  ('widened (format "bash %s/kill-in-window.sh %s %s" rpc-home target rpc-server-comm))
                  ;; The same, as soon as a second file appears: a temporary one, or a backup.
                  ('widened-temp (format "bash %s/kill-in-window.sh %s %s second-file"
                                         rpc-home target rpc-server-comm)))))
    (make-process :name "killer" :buffer (generate-new-buffer " *killer*") :noquery t
                  :connection-type 'pipe :sentinel #'ignore
                  :command (list "wsl.exe" "-d" rpc-distribution "-u" "root"
                                 "--exec" "/bin/sh" "-c" script))))

(defun rpc-killed-left (target old-hash new)
  "Say what the file TARGET holds, against OLD-HASH and the bytes NEW."
  (let* ((seen (rpc-wsl 60 nil (format "stat -c %%s %s && sha256sum < %s" target target)))
         (parts (split-string (cdr seen)))
         (length (and (car parts) (string-to-number (car parts))))
         (hash (cadr parts))
         (others (cdr (rpc-wsl 60 nil (format "cd %s && ls -A -s --block-size=1 | tail -n +2 | tr '\\n' ' '"
                                              (file-name-directory target))))))
    (concat
     (cond ((not (eql 0 (car seen))) (format "NO FILE: %s" (cdr seen)))
           ((equal hash old-hash) (format "%d bytes, ALL OLD" length))
           ((zerop length) "0 bytes, EMPTY")
           ((and (= length (length new)) (equal hash (secure-hash 'sha256 new)))
            (format "%d bytes, ALL NEW" length))
           ;; A save adds the final newline a buffer lacks.
           ((equal hash (secure-hash 'sha256 (concat new "\n")))
            (format "%d bytes, ALL NEW, and the final newline" length))
           ((and (< length (length new)) (equal hash (secure-hash 'sha256 (substring new 0 length))))
            (format "%d bytes, SHORT: the first of the new" length))
           (t (format "%d bytes, OTHER" length)))
     "; the directory: " others)))

(defvar rpc-killed-rows nil "Each round: (KIND HOW ROUND SECONDS OUTCOME LEFT).")

(defun rpc-killed-round (kind how round new)
  "Kill the server during one write of NEW, by KIND, through HOW, and record what is left.
HOW is `write-region', `save-buffer', or `save-precious'."
  (let* ((path (format "%s/kill/target" rpc-home))
         (file (concat (rpc-prefix "rpc") path))
         (remote-file-name-inhibit-cache t)
         (old-hash (rpc-killed-prepare path))
         ;; A live connection, so this measures the write and not the connecting.
         (_ (file-attributes file))
         (buffer (unless (eq how 'write-region)
                   (with-current-buffer (find-file-noselect file t)
                     (let ((inhibit-read-only t))
                       (erase-buffer)
                       (set-buffer-multibyte nil)
                       (insert new))
                     (setq buffer-file-coding-system 'binary)
                     (current-buffer))))
         (killer (rpc-killer kind path))
         ;; A watcher must be watching, or it is too late for a write this quick.
         (_ (when (memq kind '(watch widened widened-temp))
              (let ((end (+ (float-time) 20)))
                (while (and (< (float-time) end)
                            (not (string-search
                                  "ready" (with-current-buffer (process-buffer killer)
                                            (buffer-string)))))
                  (accept-process-output killer 0.02)))))
         (began (float-time))
         (outcome
          (condition-case err
              (let ((tramp-dont-suspend-timers t))
                (with-timeout (120 "no answer in 120 s")
                  (pcase how
                    ('write-region
                     (let ((coding-system-for-write 'binary))
                       (write-region new nil file nil 'silent))
                     "returned")
                    ('save-buffer
                     (with-current-buffer buffer (save-buffer))
                     "save-buffer returned")
                    ('save-precious
                     (with-current-buffer buffer
                       (let ((file-precious-flag t)) (save-buffer)))
                     "save-buffer returned, with file-precious-flag"))))
            ((error quit) (format "signalled: %s" (error-message-string err)))))
         (seconds (- (float-time) began)))
    (let ((end (+ (float-time) 30)))
      (while (and (process-live-p killer) (< (float-time) end))
        (accept-process-output killer 0.1)))
    (when (process-live-p killer) (delete-process killer))
    (let ((killer-said (string-trim (with-current-buffer (process-buffer killer) (buffer-string))))
          (modified (and buffer (buffer-live-p buffer) (buffer-modified-p buffer))))
      (push (list kind how round seconds
                  (format "%s%s; the killer: %s" outcome
                          (if buffer (format "; buffer modified: %S" modified) "")
                          (string-replace "\n" " " killer-said))
                  (rpc-killed-left path old-hash new))
            rpc-killed-rows)
      (message "killed write: %S" (car rpc-killed-rows)))
    (when buffer
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))
    (kill-buffer (process-buffer killer))
    ;; A kill that came late, or a reader of the next round, must not meet the old state.
    (ignore-errors (rpc-wsl 30 t (format "pkill -CONT -x %s" rpc-server-comm)))))

(defun rpc-phase-killed-write ()
  "What `kill -KILL' on the server leaves of a 1 MiB write, and how the write reports it."
  (rpc-check "connect" 75 (lambda () (or (file-directory-p (rpc-root "rpc")) (error "No root"))))
  (let ((new (rpc-blob (* 1024 1024))))
    (dolist (round '(1 2 3 4 5))
      (rpc-killed-round 'watch 'write-region round new))
    (dolist (round '(1 2 3))
      (rpc-killed-round 'at-once 'write-region round new))
    (dolist (round '(1 2 3))
      (rpc-killed-round 'widened 'write-region round new))
    (dolist (round '(1 2 3))
      (rpc-killed-round 'watch 'save-buffer round new))
    (dolist (round '(1 2))
      (rpc-killed-round 'widened 'save-buffer round new))
    (dolist (round '(1 2))
      (rpc-killed-round 'widened-temp 'save-precious round new)))
  (princ "\n## A write killed midway\n\nOld contents 1 MiB + 17 bytes, new contents 1 MiB.\n\n")
  (princ "- `watch`: killed as soon as the file's size moves.\n")
  (princ "- `at-once`: killed as the write starts, which the write can finish first.\n")
  (princ "- `widened`: `strace` delays each write 300 ms, so the kill lands after truncate and before the bytes.\n")
  (princ "- `widened-temp`: the same, as soon as a second file appears, which for `file-precious-flag` is its temporary file.\n\n")
  (princ "| Kill | Through | Round | Seconds | How it reports | What the file holds |\n|---|---|---:|---:|---|---|\n")
  (pcase-dolist (`(,kind ,how ,round ,seconds ,outcome ,left) (reverse rpc-killed-rows))
    (princ (format "| %s | %s | %d | %.3f | %s | %s |\n" kind how round seconds
                   (string-replace "|" "/" (string-replace "\n" " " outcome)) left)))
  (rpc-check "after the last kill, the next call works" 90
             (lambda ()
               (let ((remote-file-name-inhibit-cache t))
                 (or (and (file-attributes (concat (rpc-root "rpc") "file")) "works")
                     (error "No attributes"))))))

;;; One phase

(pcase (getenv "KITTYMACS_RPC_PHASE")
  ("killed-write" (rpc-phase-killed-write))
  ("compare" (rpc-phase-compare))
  ("ergonomics" (rpc-phase-ergonomics))
  ("dead" (rpc-phase-dead))
  (phase (error "No phase called %S" phase)))
(rpc-print-rows)

;;; rpc.el ends here
