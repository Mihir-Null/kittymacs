;;; tramp-rpc.el --- A stand-in for tramp-rpc, for tests/kittymacs-remote-rpc-tests.el -*- lexical-binding: t; -*-
;; Only what the seam touches, with the same names and the same shape as version
;; 0.16.0.  The real package is never installed, loaded or run by a local test.

;;; Code:
(require 'tramp)

;; The real package's autoloads do this when Tramp loads.
(add-to-list 'tramp-methods '("rpc" (tramp-login-args (("%h")))))

(defvar tramp-rpc-use-controlmaster t)
(defvar tramp-rpc-use-direct-ssh-pty t)
(defvar tramp-rpc-fake-seen nil "What each function saw of the switches, newest first.")

(defun tramp-rpc--start-server-process (vec binary-path &optional _sudo-password)
  "Start the server on VEC at BINARY-PATH with `ssh', as the real one does."
  (make-process :name "tramp-rpc-fake"
                :command (list "ssh" "-o" "BatchMode=yes" (tramp-file-name-host vec) binary-path)))

(defun tramp-rpc--connect (vec)
  "Record the switch `tramp-rpc--connect' reads, for VEC, and start the server."
  (push (list 'connect tramp-rpc-use-controlmaster) tramp-rpc-fake-seen)
  (tramp-rpc--start-server-process vec "tramp-rpc-server"))

(defun tramp-rpc--make-pty-process (_vec &rest _arguments)
  "Record the switch `tramp-rpc--make-pty-process' reads."
  (push (list 'pty tramp-rpc-use-direct-ssh-pty) tramp-rpc-fake-seen))

(defun tramp-rpc-file-name-handler (operation &rest _arguments)
  "Answer OPERATION with its name, so a test can see it was not refused."
  operation)

(provide 'tramp-rpc)
;;; tramp-rpc.el ends here
