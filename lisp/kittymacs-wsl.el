;;; kittymacs-wsl.el --- Which WSL distributions this machine has -*- lexical-binding: t; -*-
;; Generated from literate/36-remote.org; edit the Org source, then tangle.

;;; Code:

(defun kittymacs-wsl-distributions ()
  "Return the distributions that `wsl.exe --list' names, or nil.
Nil too where there is no `wsl.exe', and where it fails.  This starts no virtual
machine.  It writes UTF-16 unless told otherwise, and an older one ignores being
told, so this drops the NUL bytes either way."
  (let ((default-directory temporary-file-directory)
        (process-environment (cons "WSL_UTF8=1" process-environment))
        (coding-system-for-read 'no-conversion))
    (with-temp-buffer
      (when (eql 0 (ignore-error file-missing
                     (call-process "wsl.exe" nil '(t nil) nil "--list" "--quiet")))
        (split-string (string-replace "\0" "" (buffer-string)) "[\r\n]+" t "[ \t]+")))))

(provide 'kittymacs-wsl)
;;; kittymacs-wsl.el ends here
