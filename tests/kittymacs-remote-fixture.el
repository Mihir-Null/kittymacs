;;; kittymacs-remote-fixture.el --- Tramp methods that need no ssh -*- lexical-binding: t; -*-
;; Loaded by tests/kittymacs-remote-tests.el and the starts it runs.
;;
;; Two Tramp methods, based on the `mock' method in Emacs's own
;; test/lisp/net/tramp-tests.el, which logs in by running a local shell in a pty
;; (`tramp-login-program' is the shell, `tramp-login-args' is -i), so a real
;; Tramp connection opens with no ssh, no host and no network.
;;
;;   kmock  is that, with the shell a child of a small wrapper script, so the
;;          test can make a working connection hang: SIGSTOP the shell, and the
;;          process Emacs holds keeps running and never answers, as an ssh whose
;;          network went away does.
;;   khang  is a login that never answers: the program sleeps and prints no
;;          prompt, as an unreachable host behind a silent firewall does.
;;
;; `tramp-methods' is only touched once Tramp has loaded, so defining the methods
;; cannot be what loads it.

;;; Code:
(require 'cl-lib)

(defvar tramp-methods)
(defvar tramp-default-host-alist)
(defvar tramp-verbose)
;; With a value, so it is special in every file that binds it through the macro
;; below; Tramp's own `defvar' keeps this one.
(defvar tramp-dont-suspend-timers nil)
(declare-function tramp-cleanup-all-connections "tramp-cmds" ())

(defvar kittymacs-remote-fixture-dir
  (file-name-as-directory (make-temp-file "kittymacs-remote-fixture-" t))
  "Where the fixture keeps its scripts, its marker files and the remote side.")

(defconst kittymacs-remote-fixture-hang-timeout 20
  "Seconds Tramp waits for the khang login before it gives up.
Long enough that a start which tried to log in cannot pass the time limit.")

(defun kittymacs-remote-fixture--path (name)
  "Return the file called NAME in the fixture's directory."
  (expand-file-name name kittymacs-remote-fixture-dir))

(defun kittymacs-remote-fixture--script (name body)
  "Write the shell script NAME with BODY, and return its file name."
  (let ((file (kittymacs-remote-fixture--path name)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "#!/bin/sh\n" body "\n"))
    (set-file-modes file #o755)
    file))

(defun kittymacs-remote-fixture-login-marker ()
  "Return the file the khang login creates, if anything ever tries it."
  (kittymacs-remote-fixture--path "khang-login-ran"))

(defun kittymacs-remote-fixture-shell-pids ()
  "Return the process IDs of every kmock shell so far.
Each login adds one: Tramp opens another connection for an asynchronous process."
  (let ((file (kittymacs-remote-fixture--path "kmock-shell.pids")))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (mapcar #'string-to-number (split-string (buffer-string)))))))

(defun kittymacs-remote-fixture-define-methods ()
  "Add the kmock and khang methods, when Tramp loads."
  (let* ((kmock (kittymacs-remote-fixture--script
                 "kmock-login"
                 (concat
                  ;; A direct asynchronous process gives its command after -c.
                  "if [ \"$1\" = -c ]; then exec /bin/sh \"$@\"; fi\n"
                  ;; A child, so that stopping it leaves this script running and
                  ;; Emacs's process in the state `run'.
                  (format "/bin/sh -c 'echo $$ >> %s; exec /bin/sh -i'\n"
                          (shell-quote-argument
                           (kittymacs-remote-fixture--path "kmock-shell.pids"))))))
         (khang (kittymacs-remote-fixture--script
                 "khang-login"
                 (format "echo ran > %s\nexec sleep 3600"
                         (shell-quote-argument (kittymacs-remote-fixture-login-marker))))))
    (with-eval-after-load 'tramp
      (add-to-list 'tramp-methods
                   `("kmock"
                     (tramp-login-program "/bin/sh")
                     (tramp-login-args ((,kmock)))
                     (tramp-direct-async ("-c"))
                     (tramp-remote-shell "/bin/sh")
                     (tramp-remote-shell-args ("-c"))
                     (tramp-connection-timeout 10)))
      (add-to-list 'tramp-methods
                   `("khang"
                     (tramp-login-program "/bin/sh")
                     (tramp-login-args ((,khang "%h")))
                     (tramp-remote-shell "/bin/sh")
                     (tramp-remote-shell-args ("-c"))
                     (tramp-connection-timeout ,kittymacs-remote-fixture-hang-timeout)))
      (add-to-list 'tramp-default-host-alist `("\\`kmock\\'" nil ,(system-name)))
      (add-to-list 'tramp-default-host-alist `("\\`khang\\'" nil "unreachable")))))

(defun kittymacs-remote-fixture-name (path &optional method)
  "Return PATH on the fixture's remote side, through METHOD, kmock by default."
  (format "/%s::%s" (or method "kmock") (expand-file-name path kittymacs-remote-fixture-dir)))

(defun kittymacs-remote-fixture-hang ()
  "Make every open kmock connection hang: its process lives and never answers."
  (let ((pids (kittymacs-remote-fixture-shell-pids)))
    (unless pids (error "No kmock connection is open"))
    (dolist (pid pids) (signal-process pid 'SIGSTOP))))

(defun kittymacs-remote-fixture-resume ()
  "Undo `kittymacs-remote-fixture-hang'."
  (dolist (pid (kittymacs-remote-fixture-shell-pids))
    (signal-process pid 'SIGCONT)))

(defmacro kittymacs-remote-fixture-bounded (seconds &rest body)
  "Run BODY, and return `stalled' if it takes more than SECONDS.
Tramp suspends timers while it waits, unless told not to."
  (declare (indent 1))
  `(let ((tramp-dont-suspend-timers t))
     (with-timeout (,seconds 'stalled)
       ,@body)))

(provide 'kittymacs-remote-fixture)
;;; kittymacs-remote-fixture.el ends here
