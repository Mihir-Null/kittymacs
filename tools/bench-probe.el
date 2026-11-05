;;; bench-probe.el --- Report one startup to tools/bench.el -*- lexical-binding: t; -*-
;; tools/bench.el loads this with -l in every Emacs it starts; it is never run
;; by hand.  It waits for the first idle moment, lets deferred work settle,
;; times a few things a person does first, writes one plist and exits.

(defun kittymacs-bench-probe--env (name)
  "Return the number in environment variable NAME, or 0 when it is unset."
  (string-to-number (or (getenv name) "0")))

(defconst kittymacs-bench-probe-start (kittymacs-bench-probe--env "KITTYMACS_BENCH_T0")
  "Wall-clock time just before the driver started this process.
Unlike `before-init-time' it includes loading the dump.")

(defvar kittymacs-bench-probe-result nil
  "The plist this run reports.")

(defun kittymacs-bench-probe--note (key value)
  "Record VALUE under KEY in the report."
  (setq kittymacs-bench-probe-result
        (plist-put kittymacs-bench-probe-result key value)))

(defun kittymacs-bench-probe--cpu ()
  "Return the seconds of CPU this Emacs has used, or nil where unavailable."
  (let* ((attributes (process-attributes (emacs-pid)))
         (user (alist-get 'utime attributes))
         (system (alist-get 'stime attributes)))
    (when (and user system)
      (float-time (time-add user system)))))

(defun kittymacs-bench-probe--time (key function)
  "Record under KEY the seconds FUNCTION takes, redisplay included.
A failure records nil, so the report shows the step did not run."
  (let ((start (float-time)))
    (kittymacs-bench-probe--note
     key
     (condition-case nil
         (progn (funcall function)
                (redisplay t)
                (- (float-time) start))
       (error nil)))))

(defun kittymacs-bench-probe--press-leader ()
  "Run `SPC t m', a built-in command, through the leader in Normal state.
Signal an error unless the key reached the command."
  (let ((before (bound-and-true-p menu-bar-mode)))
    (execute-kbd-macro (kbd "SPC t m"))
    (when (eq before (bound-and-true-p menu-bar-mode))
      (error "SPC t m did not run"))))

(defun kittymacs-bench-probe--finish ()
  "Write the report for the driver, then exit."
  (with-temp-file (getenv "KITTYMACS_BENCH_OUT")
    (prin1 kittymacs-bench-probe-result (current-buffer)))
  (kill-emacs 0))

(defun kittymacs-bench-probe--drained-p ()
  "Return non-nil when no native compilation is queued or running."
  (or (not (featurep 'comp-run))
      (and (null (symbol-value 'comp-files-queue))
           (zerop (funcall 'comp--async-runnings)))))

(defun kittymacs-bench-probe--wait-for-queue (quiet)
  "Finish after QUIET checks in a row find the native-compile queue empty.
Several, because a file that has just loaded queues its compilation late."
  (cond ((not (kittymacs-bench-probe--drained-p))
         (run-with-timer 1 nil #'kittymacs-bench-probe--wait-for-queue 5))
        ((zerop quiet) (kittymacs-bench-probe--finish))
        (t (run-with-timer 1 nil #'kittymacs-bench-probe--wait-for-queue (1- quiet)))))

(defun kittymacs-bench-probe--settled ()
  "Record what the settled Emacs has cost, then time the first actions."
  (kittymacs-bench-probe--note :cpu-settled (kittymacs-bench-probe--cpu))
  (kittymacs-bench-probe--note :features (length features))
  (kittymacs-bench-probe--note :files-loaded (length load-history))
  (kittymacs-bench-probe--note :packages-activated
                               (length (bound-and-true-p package-activated-list)))
  (kittymacs-bench-probe--note :gcs gcs-done)
  (kittymacs-bench-probe--note :gc-elapsed gc-elapsed)
  (kittymacs-bench-probe--note :org-loaded (and (featurep 'org) t))
  (kittymacs-bench-probe--note :magit-loaded (and (featurep 'magit) t))
  (kittymacs-bench-probe--time
   :open-el (lambda () (find-file (getenv "KITTYMACS_BENCH_EL"))))
  (kittymacs-bench-probe--time
   :open-org (lambda () (find-file (getenv "KITTYMACS_BENCH_ORG"))))
  (when (boundp 'kittymacs-leader-map)
    (kittymacs-bench-probe--time :spc #'kittymacs-bench-probe--press-leader))
  (if (getenv "KITTYMACS_BENCH_DRAIN")
      (kittymacs-bench-probe--wait-for-queue 5)
    (kittymacs-bench-probe--finish)))

(run-with-idle-timer
 0 nil
 (lambda ()
   (kittymacs-bench-probe--note
    :first-idle (- (float-time) kittymacs-bench-probe-start))
   (kittymacs-bench-probe--note :graphic (and (display-graphic-p) t))
   ;; A plain timer, not an idle one: deferred timers run during the wait, and
   ;; the CPU they use is what `:cpu-settled' exists to catch.
   (run-with-timer (kittymacs-bench-probe--env "KITTYMACS_BENCH_SETTLE") nil
                   #'kittymacs-bench-probe--settled)))

;;; bench-probe.el ends here
