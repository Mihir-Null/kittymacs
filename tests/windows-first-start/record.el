;;; record.el --- Record what a first start signals, with backtraces -*- lexical-binding: t; -*-
;; Loaded by tests/windows-first-start/run.ps1: with -l before early-init.el in
;; batch, and from site-start.el in a graphical start.
;;
;; Every error that reaches the debugger is appended to the report with its
;; backtrace, and the start carries on as if nothing were watching: the debugger
;; returns, so a `condition-case-unless-debug' still handles the error afterwards.
;; The report ends with the state a first start left: what failed to install,
;; the signature settings, and the *Warnings* and *Messages* buffers.
;;
;; KITTYMACS_FIRST_START_REPORT names the report file.

;;; Code:
(defvar first-start-report (or (getenv "KITTYMACS_FIRST_START_REPORT")
                               (expand-file-name "first-start-report.txt" temporary-file-directory))
  "The file this start's report is appended to.")

(defvar first-start-errors 0 "How many errors reached the debugger.")

(defun first-start-write (text)
  "Append TEXT to the report."
  (let ((coding-system-for-write 'utf-8-unix)
        (inhibit-message t))
    (write-region text nil first-start-report t 'silent)))

(defun first-start-short (object)
  "Return OBJECT printed briefly, on one line."
  (let* ((print-length 6)
         (print-level 3)
         (print-escape-newlines t)
         (text (format "%S" object)))
    (if (> (length text) 300) (concat (substring text 0 300) " ...") text)))

(defun first-start-debugger (&rest args)
  "Append ARGS and the backtrace to the report, then return so the error goes on."
  (let ((debug-on-error nil)
        (inhibit-quit t))
    (when (< first-start-errors 40)
      (setq first-start-errors (1+ first-start-errors))
      (condition-case err
          (first-start-write
           (format "\n=== error %d: %s\n%s\n" first-start-errors (first-start-short args)
                   (mapconcat (lambda (frame)
                                (concat "  " (first-start-short (cons (nth 1 frame) (nth 2 frame)))))
                              (backtrace-frames #'first-start-debugger)
                              "\n")))
        (error (first-start-write (format "\n=== the recorder failed: %S\n" err))))))
  nil)

(setq debug-on-error t
      debugger #'first-start-debugger)

(defvar package-check-signature)
(defvar package-archive-contents)
(defvar package-activated-list)
(defvar kittymacs-features--failed)
(declare-function epg-find-configuration "epg-config" (protocol &optional no-cache program-alist))

(defun first-start-finish (how)
  "Append the state this start left, for a start that ended HOW."
  (let ((debug-on-error nil))
    (first-start-write (format "\n=== state after the start (%s), %d errors recorded\n" how first-start-errors))
    (dolist (form '((list system-configuration emacs-version)
                    (and (fboundp 'native-comp-available-p) (native-comp-available-p))
                    (bound-and-true-p native-comp-jit-compilation)
                    package-check-signature
                    (executable-find "gpg")
                    (bound-and-true-p epg-gpg-program)
                    (progn (require 'epg-config) (epg-find-configuration 'OpenPGP))
                    (bound-and-true-p kittymacs-features--failed)
                    (and (fboundp 'kittymacs-features-profile) (kittymacs-features-profile))
                    (mapcar #'car package-archive-contents)
                    (length package-archive-contents)
                    (and (assq 'vundo package-archive-contents) t)
                    package-activated-list
                    exec-path))
      (first-start-write
       (format "%S\n  => %S\n" form (condition-case err (eval form t) (error (list 'signalled err))))))
    (dolist (name '("*Warnings*" "*Messages*" "*Error*" "*Async-native-compile-log*"))
      (when (get-buffer name)
        (first-start-write
         (format "\n=== %s\n%s\n" name
                 (with-current-buffer name
                   (buffer-substring-no-properties (point-min) (point-max)))))))))

(defun first-start-finish-batch ()
  "Run what a real start runs after init, record the state, and exit."
  (setq after-init-time (current-time))
  (run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
  (first-start-finish "batch")
  (setq kill-emacs-hook nil)
  (kill-emacs 0))

(defun first-start-finish-graphical (how)
  "Record the state for a graphical start that ended HOW, and exit."
  (first-start-finish how)
  (setq kill-emacs-hook nil
        kill-emacs-query-functions nil
        confirm-kill-emacs nil)
  (kill-emacs 0))

(unless noninteractive
  ;; Long enough for the quickstart file's idle write; the second is a backstop
  ;; for a start that waits for input.
  (add-hook 'emacs-startup-hook
            (lambda () (run-with-timer 30 nil #'first-start-finish-graphical "graphical")))
  (run-with-timer 1200 nil #'first-start-finish-graphical "graphical, stopped by the backstop"))

;;; record.el ends here
