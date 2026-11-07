;;; look-measure.el --- Start cost of each look feature, on or off -*- lexical-binding: t; -*-
;; Run from a checkout whose var/elpa holds every package.  It starts a graphical
;; Emacs per selection, first a warm-up, then several timed starts, and prints a
;; table.  tools/bench.el needs a pty, so it cannot do this on native Windows.
(require 'seq)

(defconst look-runs 7)
(defconst look-selections
  '(("off" . nil)
    ("smooth-scroll" . (smooth-scroll))
    ("hover-docs" . (hover-docs))
    ("which-key-frame" . (which-key-frame))
    ("buffer-tabs" . (buffer-tabs))
    ("meow-state-cursor" . (meow-state-cursor))))

(defun look--private (features)
  (with-temp-file "lisp/private.el"
    (insert ";;; -*- lexical-binding: t; -*-\n(setopt kittymacs-profile 'minimal)\n"
            (format "(setopt kittymacs-features '%S)\n" features))))

(defun look--start (settle)
  "Start a graphical Emacs and return the plist tools/bench-probe.el wrote."
  (let* ((out (make-temp-file "look-"))
         (extra (make-temp-file "look-extra-"))
         (process-environment
          (append (list (format "KITTYMACS_BENCH_OUT=%s" out)
                        (format "KITTYMACS_BENCH_SETTLE=%s" settle)
                        (format "KITTYMACS_BENCH_T0=%.6f" (float-time))
                        (format "KITTYMACS_BENCH_EL=%s" (expand-file-name "tools/bench.el"))
                        (format "KITTYMACS_BENCH_ORG=%s" (expand-file-name "literate/index.org")))
                  process-environment))
         (emacs (expand-file-name invocation-name invocation-directory))
         (process (make-process :name "look" :noquery t :sentinel #'ignore
                                :command (list emacs (format "--init-directory=%s" default-directory)
                                               "-l" (expand-file-name "tools/bench-probe.el"))))
         (deadline (+ (float-time) 180)))
    (ignore extra)
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05))
    (when (process-live-p process) (delete-process process))
    (let ((report (with-temp-buffer
                    (insert-file-contents out)
                    (goto-char (point-min))
                    (condition-case nil (read (current-buffer)) (error nil)))))
      (delete-file out)
      report)))

(defun look--median (numbers)
  (let ((sorted (sort (copy-sequence numbers) #'<)))
    (nth (/ (length sorted) 2) sorted)))

(princ (format "system-type %s, Emacs %s, window-system at batch %S\n\n" system-type emacs-version window-system))
(princ "| selection | graphical? | first idle, median s | CPU settled, median s | runs |\n|---|---|---|---|---|\n")
(pcase-dolist (`(,name . ,features) look-selections)
  (look--private features)
  (look--start 20)                      ; warm-up: lets native compilation finish
  (let* ((reports (delq nil (mapcar (lambda (_) (look--start 2)) (number-sequence 1 look-runs))))
         (pick (lambda (key) (delq nil (mapcar (lambda (r) (plist-get r key)) reports)))))
    (princ (format "| %s | %S | %s | %s | %d |\n" name
                   (plist-get (car reports) :graphic)
                   (let ((v (funcall pick :first-idle))) (if v (format "%.3f" (look--median v)) "n/a"))
                   (let ((v (funcall pick :cpu-settled))) (if v (format "%.3f" (look--median v)) "n/a"))
                   (length reports)))))
(delete-file "lisp/private.el")
