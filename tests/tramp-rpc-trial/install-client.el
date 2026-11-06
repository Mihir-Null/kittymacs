;;; install-client.el --- msgpack from MELPA, and tramp-rpc byte-compiled -*- lexical-binding: t; -*-
;; Run by tests/tramp-rpc-trial/run.ps1.  An installed package is byte-compiled, so
;; timing tramp-rpc's source would flatter wslm.
;;
;; Environment: TRIAL_CLIENT_PACKAGES, where msgpack goes.  TRIAL_TRAMP_RPC, the
;; pinned checkout's lisp directory.

;;; Code:
(require 'package)
(require 'bytecomp)

(setq package-user-dir (getenv "TRIAL_CLIENT_PACKAGES")
      package-archives '(("melpa" . "https://melpa.org/packages/")))
(package-refresh-contents)
(package-install 'msgpack)
(message "msgpack: %s"
         (package-version-join (package-desc-version (cadr (assq 'msgpack package-alist)))))

(let ((lisp (getenv "TRIAL_TRAMP_RPC")))
  (add-to-list 'load-path lisp)
  (setq byte-compile-warnings nil)
  (dolist (file (directory-files lisp t "\\.el\\'"))
    (unless (string-suffix-p "-autoloads.el" file)
      (let ((result (byte-compile-file file)))
        (message "%s: %s" (file-name-nondirectory file) (if result "compiled" "FAILED"))
        (unless result (kill-emacs 1))))))
(kill-emacs 0)

;;; install-client.el ends here
