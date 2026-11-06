;;; pipe.el --- Is a pipe through wsl.exe fit for length-prefixed binary frames? -*- lexical-binding: t; -*-

;; A spike, not to merge.  It answers one question for one research note, with no
;; code from any RPC helper: native Windows Emacs sends frames through wsl.exe to
;; echo.py, set up as an RPC helper's connection would be: a pipe, the binary
;; coding system, stderr in a buffer of its own, and a unibyte buffer with a filter.
;;
;; Environment:
;;   SPIKE_OUT     the results file, appended to as each result arrives
;;   SPIKE_MODE    main, stuck, duplex or gui
;;   SPIKE_WSL     the distribution; unset, only the local program runs
;;   SPIKE_PYTHON  the local Python, for the baseline without wsl.exe
;;   SPIKE_ECHO    the local path of echo.py

;;; Code:

(require 'cl-lib)
(require 'seq)

(defvar pipe-out (getenv "SPIKE_OUT"))
(defvar pipe-mode (getenv "SPIKE_MODE"))
(defvar pipe-distro (getenv "SPIKE_WSL"))
(defvar pipe-sizes '(1 64 4096 4097 65536 65537 1048576))
(defconst pipe-megabyte 1048576)

(defun pipe-log (&rest fields)
  "Append FIELDS to the results file at once, so a hang keeps what came before."
  (let ((coding-system-for-write 'utf-8-unix)
        (inhibit-message t))
    (write-region (concat (mapconcat (lambda (f) (format "%s" f)) fields "\t") "\n")
                  nil pipe-out t 'quiet)))

(defun pipe-hex (string)
  "Return the first bytes of STRING in hexadecimal."
  (mapconcat (lambda (c) (format "%02x" c))
             (substring string 0 (min 60 (length string))) ""))

(defun pipe-commands ()
  "Return each transport to measure, as (NAME . COMMAND)."
  (append
   (list (cons "local" (list (or (getenv "SPIKE_PYTHON") "python") "-u" (getenv "SPIKE_ECHO"))))
   (when pipe-distro
     (list (cons "wsl" (list "wsl.exe" "-d" pipe-distro "--exec" "python3" "-u" "/tmp/echo.py"))))))

(defun pipe-start (command)
  "Start COMMAND as a helper's connection would be started."
  (let ((buffer (generate-new-buffer " *pipe*"))
        (stderr (generate-new-buffer " *pipe-stderr*")))
    (dolist (b (list buffer stderr))
      (with-current-buffer b
        (buffer-disable-undo)
        (set-buffer-multibyte nil)))
    (let ((process
           (make-process
            :name "pipe" :buffer buffer :command command
            :connection-type 'pipe :coding 'binary :noquery t :stderr stderr
            :filter (lambda (process output)
                      (with-current-buffer (process-buffer process)
                        (goto-char (point-max))
                        (insert output))))))
      (process-put process :stderr-buffer stderr)
      process)))

(defun pipe-stderr (process)
  "Return what PROCESS has written to stderr, in hexadecimal."
  (with-current-buffer (process-get process :stderr-buffer)
    (pipe-hex (buffer-string))))

(defun pipe-stop (process)
  "End PROCESS and return how long that took."
  (let ((start (float-time)))
    (delete-process process)
    (- (float-time) start)))

(defun pipe-u32 (n)
  (unibyte-string (logand (ash n -24) 255) (logand (ash n -16) 255)
                  (logand (ash n -8) 255) (logand n 255)))

(defun pipe-frame (op body)
  (concat (pipe-u32 (1+ (length body))) (unibyte-string op) body))

(defun pipe-read-frame (process limit)
  "Return the next frame from PROCESS, or nil after LIMIT seconds or at its end."
  (let ((deadline (+ (float-time) limit)))
    (with-current-buffer (process-buffer process)
      (catch 'frame
        (while t
          (when (>= (buffer-size) 4)
            (let ((length (+ (ash (char-after 1) 24) (ash (char-after 2) 16)
                             (ash (char-after 3) 8) (char-after 4))))
              (when (>= (buffer-size) (+ 4 length))
                (let ((frame (buffer-substring-no-properties 5 (+ 5 length))))
                  (delete-region 1 (+ 5 length))
                  (throw 'frame frame)))))
          (when (or (> (float-time) deadline) (not (process-live-p process)))
            (throw 'frame nil))
          (accept-process-output process 0.1 nil t))))))

(defun pipe-digest (string) (secure-hash 'sha256 string nil nil t))

(defun pipe-first-difference (a b)
  "Return where unibyte strings A and B first differ, with both lengths."
  (let ((i 0) (end (min (length a) (length b))))
    (while (and (< i end) (eq (aref a i) (aref b i))) (setq i (1+ i)))
    (format "offset %d, lengths %d and %d, got %02x" i (length a) (length b)
            (if (< i (length a)) (aref a i) 0))))

(defun pipe-judge (frame expected)
  "Return PASS, or what is wrong with echo FRAME of bytes EXPECTED."
  (cond ((null frame) "TIMEOUT")
        ((< (length frame) 32) (format "FAIL short frame %s" (pipe-hex frame)))
        (t (let ((in (string= (substring frame 0 32) (pipe-digest expected)))
                 (back (substring frame 32)))
             (cond ((and in (string= back expected)) "PASS")
                   (in (format "FAIL out only: %s" (pipe-first-difference back expected)))
                   ((string= back expected) "FAIL in only, digest differs")
                   (t (format "FAIL both ways: %s" (pipe-first-difference back expected))))))))

(defun pipe-pattern (bytes size)
  "Return SIZE bytes of BYTES repeated, as a unibyte string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (dotimes (_ (1+ (/ size (length bytes)))) (insert bytes))
    (buffer-substring-no-properties 1 (1+ size))))

(defconst pipe-all-bytes (apply #'unibyte-string (number-sequence 0 255)))
;; CR, LF and both orders, NUL, Ctrl-Z (end of file to a Windows text stream),
;; Ctrl-C, Ctrl-D, XON, XOFF, ESC, byte order marks, and an invalid UTF-8 pair.
(defconst pipe-traps (unibyte-string 13 10 10 13 0 0 26 3 4 17 19 27 255 254 239 187 191
                                     127 192 128 13 13 10 0 26))
(defvar pipe-random-megabyte
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (random "pipe spike")
    (dotimes (_ pipe-megabyte) (insert-byte (random 256) 1))
    (buffer-substring-no-properties 1 (1+ pipe-megabyte))))

(defun pipe-stats (label times)
  "Log the spread of TIMES under LABEL."
  (let* ((sorted (vconcat (sort (copy-sequence times) #'<)))
         (n (length sorted))
         (at (lambda (q) (aref sorted (min (1- n) (floor (* q n)))))))
    (if (zerop n)
        (pipe-log "time" label "no rounds")
      (pipe-log "time" label (format "n=%d" n)
                (format "median=%.6f" (funcall at 0.5))
                (format "p90=%.6f" (funcall at 0.9))
                (format "p99=%.6f" (funcall at 0.99))
                (format "max=%.6f" (aref sorted (1- n)))
                (format "mean=%.6f" (/ (apply #'+ times) n))))))

(defun pipe-integrity (name command rounds)
  "Echo each kind of bytes at each size through COMMAND, ROUNDS times, and check them."
  (let ((process (pipe-start command)) (pass 0) (fail 0))
    (dolist (kind `(("all-bytes" . ,pipe-all-bytes) ("traps" . ,pipe-traps) ("random" . nil)))
      (dolist (size pipe-sizes)
        (let ((payload (if (cdr kind)
                           (pipe-pattern (cdr kind) size)
                         (substring pipe-random-megabyte 0 size))))
          (dotimes (round rounds)
            (let ((start (float-time)))
              (process-send-string process (pipe-frame 0 payload))
              (let* ((frame (pipe-read-frame process 60))
                     (seconds (- (float-time) start))
                     (verdict (pipe-judge frame payload)))
                (if (equal verdict "PASS") (cl-incf pass) (cl-incf fail))
                (unless (and (equal verdict "PASS") (< size pipe-megabyte))
                  (pipe-log "integrity" name (car kind) size round verdict
                            (format "%.4f" seconds)))))))))
    ;; Every byte value alone in a frame, so none hides among its neighbours.
    (dotimes (byte 256)
      (let ((payload (unibyte-string byte)))
        (process-send-string process (pipe-frame 0 payload))
        (let ((verdict (pipe-judge (pipe-read-frame process 10) payload)))
          (if (equal verdict "PASS")
              (cl-incf pass)
            (cl-incf fail)
            (pipe-log "integrity" name "single-byte" byte verdict)))))
    ;; The source direction: bytes the far end made, checked against the known pattern.
    (dolist (size pipe-sizes)
      (let ((expected (pipe-pattern pipe-all-bytes size)))
        (process-send-string process (pipe-frame 2 (pipe-u32 size)))
        (let ((verdict (pipe-judge (pipe-read-frame process 60) expected)))
          (if (equal verdict "PASS")
              (cl-incf pass)
            (cl-incf fail)
            (pipe-log "integrity" name "source" size verdict)))))
    ;; Many frames in one write, as pipelined requests arrive.
    (let* ((payloads (mapcar (lambda (i) (substring pipe-random-megabyte i (+ i 1024)))
                             (number-sequence 0 199)))
           (bad 0))
      (process-send-string
       process (mapconcat (lambda (p) (pipe-frame 0 p)) payloads ""))
      (dolist (payload payloads)
        (unless (equal (pipe-judge (pipe-read-frame process 30) payload) "PASS")
          (cl-incf bad)))
      (if (zerop bad) (cl-incf pass) (cl-incf fail))
      (pipe-log "integrity" name "burst: 200 frames of 1 KiB, one write"
                (if (zerop bad) "PASS" (format "FAIL %d of 200" bad))))
    (pipe-log "integrity-total" name (format "pass=%d" pass) (format "fail=%d" fail)
              (format "stderr=%s" (pipe-stderr process)))
    (pipe-stop process)))

(defun pipe-round-trips (label command rounds limit)
  "Time small echoes through COMMAND, ROUNDS of them or LIMIT seconds' worth."
  (let* ((process (pipe-start command))
         (payload (substring pipe-random-megabyte 0 64))
         (request (pipe-frame 0 payload))
         (end (+ (float-time) limit))
         times bad)
    ;; The first answers include the program's start.
    (dotimes (_ 3)
      (process-send-string process request)
      (pipe-read-frame process 30))
    (let ((whole (float-time)) (done 0))
      (while (and (< done rounds) (< (float-time) end) (not bad))
        (let ((start (float-time)))
          (process-send-string process request)
          (if (equal (pipe-judge (pipe-read-frame process 10) payload) "PASS")
              (push (- (float-time) start) times)
            (setq bad t)))
        (cl-incf done))
      (pipe-stats (format "round trip, 64 bytes, %s" label) times)
      (pipe-log "time-whole" label (format "%d rounds in %.4f s" done (- (float-time) whole))
                (if bad "a round failed" "all passed")))
    (pipe-stop process)))

(defun pipe-sized (label command)
  "Time each direction at a few sizes through COMMAND."
  (let ((process (pipe-start command)))
    (dolist (spec '((4096 . 20) (65536 . 10) (1048576 . 5)))
      (let* ((size (car spec))
             (payload (substring pipe-random-megabyte 0 size))
             (source-expected (pipe-pattern pipe-all-bytes size))
             echo sink source (bad 0))
        (dotimes (_ (cdr spec))
          (let ((start (float-time)))
            (process-send-string process (pipe-frame 0 payload))
            (unless (equal (pipe-judge (pipe-read-frame process 60) payload) "PASS") (cl-incf bad))
            (push (- (float-time) start) echo))
          (let ((start (float-time)))
            (process-send-string process (pipe-frame 1 payload))
            (let ((frame (pipe-read-frame process 60)))
              (unless (and frame (string= (substring frame 0 32) (pipe-digest payload)))
                (cl-incf bad)))
            (push (- (float-time) start) sink))
          (let ((start (float-time)))
            (process-send-string process (pipe-frame 2 (pipe-u32 size)))
            (unless (equal (pipe-judge (pipe-read-frame process 60) source-expected) "PASS")
              (cl-incf bad))
            (push (- (float-time) start) source)))
        (pipe-stats (format "%s, echo %d" label size) echo)
        (pipe-stats (format "%s, write %d, digest back" label size) sink)
        (pipe-stats (format "%s, read %d" label size) source)
        (pipe-log "sized" label size (format "bad=%d" bad))))
    (pipe-stop process)))

(defun pipe-startup (label command rounds)
  "Time from starting COMMAND to the first answer, ROUNDS times."
  (let (times)
    (dotimes (_ rounds)
      (let* ((start (float-time))
             (process (pipe-start command))
             (payload (substring pipe-random-megabyte 0 64)))
        (process-send-string process (pipe-frame 0 payload))
        (when (equal (pipe-judge (pipe-read-frame process 60) payload) "PASS")
          (push (- (float-time) start) times))
        (pipe-stop process)))
    (pipe-stats (format "start to first answer, %s" label) times)))

(defun pipe-exit-codes ()
  "Report what a failed start through wsl.exe looks like to `make-process'.
A helper's client may read 126 and 127 as a missing binary, so these must survive,
and wsl.exe's own messages must not land on stdout, where frames go."
  (dolist (case '(("missing program" "--exec" "/no/such/program")
                  ("not executable" "--exec" "/etc/hostname")
                  ("sh exit 127" "--exec" "/bin/sh" "-c" "exit 127")
                  ("sh exit 3" "--exec" "/bin/sh" "-c" "exit 3")))
    (let* ((process (pipe-start (append (list "wsl.exe" "-d" pipe-distro) (cdr case))))
           (end (+ (float-time) 20)))
      (while (and (process-live-p process) (< (float-time) end))
        (accept-process-output process 0.1))
      (accept-process-output nil 0.2)
      (pipe-log "exit" (car case)
                (if (process-live-p process) "STILL RUNNING" (process-exit-status process))
                (format "stdout=%s" (with-current-buffer (process-buffer process)
                                      (pipe-hex (buffer-string))))
                (format "stderr=%s" (pipe-stderr process)))
      (pipe-stop process))))

(defun pipe-cat ()
  "Return a local cat, and log where it came from."
  (let ((found (executable-find "cat")))
    (pipe-log "cat" "on exec-path" (or found "no"))
    (or found
        (seq-find #'file-executable-p '("C:/Program Files/Git/usr/bin/cat.exe")))))

(defun pipe-relay (cat)
  "Time bytes through a local CAT: the relay such a helper's client keeps per process."
  (let* ((process (pipe-start (list cat)))
         (buffer (process-buffer process))
         (wait (lambda (size limit)
                 (let ((end (+ (float-time) limit)))
                   (while (and (< (buffer-size buffer) size) (< (float-time) end)
                               (process-live-p process))
                     (accept-process-output process 0.1 nil t))
                   (>= (buffer-size buffer) size))))
         (payload (substring pipe-random-megabyte 0 64))
         times)
    (dotimes (_ 500)
      (let ((start (float-time)))
        (process-send-string process payload)
        (when (funcall wait 64 5)
          (push (- (float-time) start) times))
        (with-current-buffer buffer (erase-buffer))))
    (pipe-stats "round trip, 64 bytes, local cat relay" times)
    (let ((bytes (pipe-pattern pipe-all-bytes 65536)))
      (process-send-string process bytes)
      (funcall wait 65536 15)
      (let ((back (with-current-buffer buffer (buffer-string))))
        (pipe-log "relay" "64 KiB of all byte values through cat"
                  (if (string= bytes back)
                      "PASS"
                    (format "FAIL %s" (pipe-first-difference back bytes))))))
    (pipe-stop process)))

(defun pipe-many-processes (cat count)
  "Start up to COUNT of CAT at once, past the old limit of about 32 on Windows."
  (let (processes failure)
    (condition-case err
        (dotimes (_ count) (push (pipe-start (list cat)) processes))
      (error (setq failure (error-message-string err))))
    (dolist (p processes) (process-send-string p "x"))
    (let ((end (+ (float-time) 20)))
      (while (and (< (float-time) end)
                  (seq-some (lambda (p) (zerop (buffer-size (process-buffer p)))) processes))
        (accept-process-output nil 0.1)))
    (pipe-log "processes"
              (format "started=%d" (length processes))
              (format "answered=%d" (seq-count (lambda (p) (> (buffer-size (process-buffer p)) 0))
                                               processes))
              (or failure "no error"))
    (mapc #'pipe-stop processes)))

(defun pipe-stuck-write (name command)
  "Stop the helper, then write more than the pipes hold.
Report whether Emacs stays responsive during the write: whether timers still run,
and whether `with-timeout' can end it."
  (let* ((process (pipe-start command))
         (payload (substring pipe-random-megabyte 0 64))
         (ticks 0)
         (ticker (run-at-time 0.5 0.5 (lambda () (cl-incf ticks))))
         (big (pipe-pattern pipe-random-megabyte (* 8 pipe-megabyte))))
    (process-send-string process (pipe-frame 0 payload))
    (pipe-read-frame process 60)
    (process-send-string process (pipe-frame 3 ""))
    (sleep-for 1)
    (let* ((before ticks)
           (start (float-time))
           (result (with-timeout (15 'timer-ended-the-write)
                     (process-send-string process (pipe-frame 0 big))
                     'write-returned)))
      (pipe-log "stuck-write" name result
                (format "seconds=%.2f" (- (float-time) start))
                (format "ticks-during=%d" (- ticks before))))
    ;; The read side of a dead helper, which any client's own timeout decides.
    (let* ((start (float-time))
           (frame (pipe-read-frame process 5)))
      (pipe-log "stuck-read" name (if frame "answered" "no answer")
                (format "seconds=%.2f" (- (float-time) start))))
    (pipe-log "stuck-delete" name (format "seconds=%.3f" (pipe-stop process)))
    (cancel-timer ticker)))

(defun pipe-duplex (name command)
  "Write 16 frames of 256 KiB in one call while the echoes come back.
Neither end can finish until the other reads, so a client that does not read
while it writes would hang here."
  (let* ((process (pipe-start command))
         (payloads (mapcar (lambda (i) (substring pipe-random-megabyte (* i 4096)
                                                  (+ (* i 4096) 262144)))
                           (number-sequence 0 15)))
         (start (float-time))
         (bad 0))
    (pipe-log "duplex" name "writing")
    (process-send-string process (mapconcat (lambda (p) (pipe-frame 0 p)) payloads ""))
    (pipe-log "duplex" name "write returned" (format "seconds=%.3f" (- (float-time) start)))
    (dolist (payload payloads)
      (unless (equal (pipe-judge (pipe-read-frame process 60) payload) "PASS")
        (cl-incf bad)))
    (pipe-log "duplex" name (if (zerop bad) "PASS" (format "FAIL %d of 16" bad))
              (format "seconds=%.3f" (- (float-time) start)))
    (pipe-stop process)))

(defmacro pipe-section (name &rest body)
  "Run BODY, and log an error under NAME rather than end the run."
  (declare (indent 1))
  `(condition-case err
       (progn ,@body)
     (error (pipe-log "ERROR" ,name (error-message-string err)))))

(defun pipe-environment ()
  (pipe-log "env" "emacs" emacs-version system-configuration)
  (pipe-log "env" "batch" noninteractive "window-system" (window-system))
  (dolist (name '(w32-pipe-read-delay w32-pipe-buffer-size read-process-output-max
                                      process-adaptive-read-buffering
                                      w32-start-process-share-console
                                      w32-start-process-show-window))
    (pipe-log "env" name (if (boundp name) (symbol-value name) "unbound"))))

(defun pipe-with-setting (variable value function)
  "Call FUNCTION with VARIABLE set to VALUE, when this Emacs has it."
  (if (not (boundp variable))
      (pipe-log "skip" variable "unbound")
    (let ((old (symbol-value variable)))
      (set variable value)
      (unwind-protect (funcall function)
        (set variable old)))))

(defun pipe-main ()
  (pipe-environment)
  (when pipe-distro
    (pipe-section "exit codes" (pipe-exit-codes)))
  (dolist (transport (pipe-commands))
    (let ((name (car transport)) (command (cdr transport)))
      (pipe-section "integrity" (pipe-integrity name command 2))
      (pipe-section "round trips" (pipe-round-trips (format "%s, defaults" name) command 2000 40))
      (pipe-section "pipe delay 0"
        (pipe-with-setting 'w32-pipe-read-delay 0
                           (lambda () (pipe-round-trips (format "%s, w32-pipe-read-delay 0" name)
                                                        command 2000 40))))
      (pipe-section "no adaptive"
        (pipe-with-setting 'process-adaptive-read-buffering nil
                           (lambda () (pipe-round-trips (format "%s, adaptive read off" name)
                                                        command 2000 40))))
      (pipe-section "sized" (pipe-sized (format "%s, defaults" name) command))
      (pipe-section "sized large reads"
        (pipe-with-setting 'read-process-output-max pipe-megabyte
                           (lambda () (pipe-sized (format "%s, read-process-output-max 1 MiB" name)
                                                  command))))
      ;; Emacs waits 20 ms each time a write finds the pipe full, so its size may
      ;; set how fast a large write can go.
      (pipe-section "sized large pipe"
        (pipe-with-setting 'w32-pipe-buffer-size pipe-megabyte
                           (lambda () (pipe-sized (format "%s, w32-pipe-buffer-size 1 MiB" name)
                                                  command))))
      (pipe-section "startup" (pipe-startup name command 5))))
  (let ((cat (pipe-cat)))
    (if (not cat)
        (pipe-log "cat" "none found")
      (pipe-section "relay" (pipe-relay cat))
      (pipe-section "many" (pipe-many-processes cat 70)))))

(defun pipe-gui ()
  "The questions a console might change, again in a graphical Emacs."
  (pipe-environment)
  (let ((transport (car (last (pipe-commands)))))
    (pipe-section "integrity" (pipe-integrity (car transport) (cdr transport) 1))
    (pipe-section "round trips" (pipe-round-trips "gui" (cdr transport) 1000 30))
    (pipe-section "sized" (pipe-sized "gui" (cdr transport)))
    (pipe-section "startup" (pipe-startup "gui" (cdr transport) 3))))

(defun pipe-run ()
  (setq gc-cons-threshold (* 256 1024 1024))
  (when pipe-distro
    ;; WSL stops a distribution once no wsl.exe session holds it.
    (make-process :name "keepalive" :noquery t :connection-type 'pipe
                  :command (list "wsl.exe" "-d" pipe-distro "--exec" "sleep" "100000")))
  (let ((transport (car (last (pipe-commands)))))
    (pcase pipe-mode
      ("main" (pipe-main))
      ("gui" (pipe-gui))
      ("stuck" (pipe-section "stuck" (pipe-stuck-write (car transport) (cdr transport))))
      ("duplex" (pipe-section "duplex" (pipe-duplex (car transport) (cdr transport))))))
  (pipe-log "end" pipe-mode))

(condition-case err
    (pipe-run)
  (error (pipe-log "FATAL" (error-message-string err))))
(kill-emacs 0)

;;; pipe.el ends here
