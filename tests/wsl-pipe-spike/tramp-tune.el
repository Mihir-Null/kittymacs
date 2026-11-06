;;; tramp-tune.el --- Does a larger Windows pipe speed up Tramp itself? -*- lexical-binding: t; -*-

;; A spike, not to merge.  pipe.el found 1 MiB written to a process takes about 3 s
;; with Windows Emacs's default pipe, and about 0.01 s with a larger one.  This asks
;; whether Tramp over the wslm row gains too, with Emacs's own Tramp and nothing else.
;; The row, the file names and the timed calls follow tests/wsl-spike/spike.el.
;;
;; Environment: SPIKE_OUT the results file, SPIKE_WSL the distribution.

;;; Code:

(require 'cl-lib)
(require 'tramp)

(defvar tune-out (getenv "SPIKE_OUT"))
(defvar tune-distro (getenv "SPIKE_WSL"))
(defvar tune-prefix (format "/wslm:%s:" tune-distro))

(setq tramp-verbose 1
      tramp-copy-size-limit nil
      tramp-persistency-file-name nil
      remote-file-name-inhibit-cache t
      gc-cons-threshold (* 256 1024 1024))

(add-to-list 'tramp-methods
             '("wslm"
               (tramp-login-program "wsl.exe")
               (tramp-login-args (("-d" "%h") ("--exec")
                                  ("/bin/sh" "-c"
                                   "\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
                                   "exec" "%l" "2>&1\"")))
               (tramp-direct-async ("/bin/sh" "-c"))
               (tramp-remote-shell "/bin/sh")
               (tramp-remote-shell-login ("-l"))
               (tramp-remote-shell-args ("-c"))
               (tramp-completion-use-cache nil)))

(defun tune-log (&rest fields)
  (let ((coding-system-for-write 'utf-8-unix) (inhibit-message t))
    (write-region (concat (mapconcat (lambda (f) (format "%s" f)) fields "\t") "\n")
                  nil tune-out t 'quiet)))

(defun tune-blob (size)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (random "tramp tune")
    (dotimes (_ size) (insert-byte (random 256) 1))
    (buffer-string)))

(defun tune-write (name bytes)
  (let ((coding-system-for-write 'no-conversion))
    (write-region bytes nil name nil 'silent))
  t)

(defun tune-read (name)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((coding-system-for-read 'no-conversion))
      (insert-file-contents-literally name))
    (buffer-string)))

(defun tune-time (label variant rounds function)
  "Time FUNCTION ROUNDS times under a 60 s limit each, and log the spread."
  (let (times (bad 0))
    (dotimes (_ rounds)
      (let* ((tramp-dont-suspend-timers t)
             (start (float-time))
             (value (condition-case err
                        (with-timeout (60 'stalled) (funcall function))
                      (error (tune-log "error" variant label (error-message-string err)) nil))))
        (if (or (null value) (eq value 'stalled))
            (cl-incf bad)
          (push (- (float-time) start) times))))
    (let* ((sorted (vconcat (sort (copy-sequence times) #'<)))
           (n (length sorted)))
      (tune-log variant label (format "n=%d" n) (format "bad=%d" bad)
                (if (zerop n) "no rounds"
                  (format "median=%.4f worst=%.4f" (aref sorted (/ n 2)) (aref sorted (1- n))))))))

(defun tune-process-file (size)
  "Run a command printing SIZE bytes, with `process-file'."
  (with-temp-buffer
    (let ((default-directory (concat tune-prefix "/tmp/")))
      (and (zerop (process-file "head" nil t nil "-c" (number-to-string size) "/dev/zero"))
           (= (buffer-size) size)))))

(defun tune-process-input (bytes)
  "Send BYTES to a process that counts them, and wait for the count."
  (let* ((default-directory (concat tune-prefix "/tmp/"))
         (buffer (generate-new-buffer " *tune*"))
         (process (make-process :name "tune" :buffer buffer :command '("wc" "-c")
                                :connection-type 'pipe :file-handler t :noquery t
                                :coding 'binary)))
    (process-send-string process bytes)
    (process-send-eof process)
    (while (process-live-p process) (accept-process-output process 0.05))
    (prog1 (with-current-buffer buffer
             (string-match-p (format "^%d" (length bytes)) (buffer-string)))
      (kill-buffer buffer))))

(defun tune-variant (variant value)
  "Measure with `w32-pipe-buffer-size' at VALUE, on a new connection."
  (setq w32-pipe-buffer-size value)
  (tramp-cleanup-all-connections)
  (let* ((small (tune-blob 4096))
         (large (tune-blob 1048576))
         (directory (concat tune-prefix "/tmp/tune/"))
         (small-file (concat directory "small.bin"))
         (large-file (concat directory "large.bin")))
    (tune-time "connect" variant 1 (lambda () (file-exists-p (concat tune-prefix "/tmp"))))
    (let ((default-directory directory))
      (process-file-shell-command "mkdir -p many; for i in $(seq 200); do : > many/f$i; done"
                                  nil nil nil))
    (tune-log variant "fixture ready")
    (tune-time "write 4 KiB" variant 10 (lambda () (tune-write small-file small)))
    (tune-time "read 4 KiB" variant 10 (lambda () (equal (tune-read small-file) small)))
    (tune-time "write 1 MiB" variant 5 (lambda () (tune-write large-file large)))
    (tune-time "read 1 MiB" variant 5 (lambda () (equal (tune-read large-file) large)))
    (tune-time "directory-files, 200 names" variant 10
               (lambda () (= 200 (length (directory-files (concat directory "many") nil "\\`f")))))
    (tune-time "file-attributes" variant 10 (lambda () (and (file-attributes small-file) t)))
    (tune-time "process-file, 20,000 bytes" variant 3 (lambda () (tune-process-file 20000)))
    (let ((tramp-direct-async-process t))
      (tune-time "1 MiB into a direct process" variant 3 (lambda () (tune-process-input large))))))

(defun tune-run ()
  (make-process :name "keepalive" :noquery t :connection-type 'pipe
                :command (list "wsl.exe" "-d" tune-distro "--exec" "sleep" "100000"))
  (tune-log "env" "tramp" tramp-version "emacs" emacs-version)
  ;; The directory for the small files, made once, so the first variant pays nothing more.
  (make-directory (concat tune-prefix "/tmp/tune/many/") t)
  (tune-variant "default pipe" 0)
  (tune-variant "1 MiB pipe" 1048576)
  (tune-log "end"))

(condition-case err
    (tune-run)
  (error (tune-log "FATAL" (error-message-string err))))
(kill-emacs 0)

;;; tramp-tune.el ends here
