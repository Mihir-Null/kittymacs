;;; seam.el --- tramp-rpc over wsl.exe: all that changes -*- lexical-binding: t; -*-
;; A trial, not to merge.  tramp-rpc's files stay as released, so the size of the
;; change is this file.  The method's host is the distribution's name.
;;
;; /bin/sh -c, because a missing program under wsl.exe --exec exits 1, and
;; tramp-rpc reads only 126 and 127 as a missing server.
;;
;; `make-process' is replaced only around one function, and only for its ssh
;; command, so a timer that starts a local process meanwhile is left alone.
;;
;; PATH, because wsl.exe appends the Windows PATH, and the server searches it for
;; each program it starts.  The wslm row sets the same one, for its own reason.

;;; Code:
(require 'cl-lib)
(require 'tramp-rpc)

(setq tramp-rpc-use-controlmaster nil
      tramp-rpc-use-direct-ssh-pty nil
      tramp-rpc-deploy-never-deploy t)

(defvar trial-seam-path
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/run/current-system/sw/bin "
  "What goes before the server's command.  An empty string keeps wsl.exe's PATH.")

(defun trial-seam-start-server (original vec binary-path &optional sudo-password)
  "Call ORIGINAL on VEC, BINARY-PATH and SUDO-PASSWORD, through wsl.exe and not ssh."
  (let ((real (symbol-function 'make-process)))
    (cl-letf (((symbol-function 'make-process)
               (lambda (&rest arguments)
                 (when (equal (car (plist-get arguments :command)) "ssh")
                   (setq arguments
                         (plist-put arguments :command
                                    (list "wsl.exe" "-d" (tramp-file-name-host vec)
                                          "--exec" "/bin/sh" "-c"
                                          (concat trial-seam-path "exec " binary-path)))))
                 (apply real arguments))))
      (funcall original vec binary-path sudo-password))))

(advice-add 'tramp-rpc--start-server-process :around #'trial-seam-start-server)

(provide 'seam)
;;; seam.el ends here
