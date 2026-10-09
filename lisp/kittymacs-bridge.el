;;; kittymacs-bridge.el --- A native front end on a Linux back end -*- lexical-binding: t; -*-
;; Generated from literate/36-bridge.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'subr-x)

(defvar tramp-methods)
(declare-function tramp-set-completion-function "tramp" (method function-list))

(defgroup kittymacs-bridge nil
  "A native Emacs front end working on a Linux back end."
  :group 'kittymacs)
(defcustom kittymacs-bridge-wsl-program "wsl.exe"
  "The program that runs commands in a WSL distribution."
  :type 'string
  :group 'kittymacs-bridge)

(defun kittymacs-bridge-wsl-available-p ()
  "Return the full name of `kittymacs-bridge-wsl-program', or nil."
  (executable-find kittymacs-bridge-wsl-program))

(defun kittymacs-bridge--decode-wsl-output (bytes)
  "Decode BYTES that wsl.exe printed itself: UTF-16LE, or UTF-8 with WSL_UTF8."
  (decode-coding-string bytes (if (string-search "\0" bytes) 'utf-16le 'utf-8)))

(defun kittymacs-bridge--parse-wsl-list (text)
  "Return the distribution names in TEXT, the output of wsl.exe --list --quiet."
  (seq-remove #'string-empty-p
              (mapcar #'string-trim
                      (split-string (string-replace "\ufeff" "" text) "[\r\n]+"))))

(defvar kittymacs-bridge--wsl-distros nil
  "The installed WSL distributions, the default first, once read.")

(defun kittymacs-bridge-wsl-distros (&optional refresh)
  "Return the installed WSL distributions, the default first.
The list is read once; REFRESH, or a prefix argument, reads it again."
  (interactive "P")
  (when (or refresh (null kittymacs-bridge--wsl-distros))
    (setq kittymacs-bridge--wsl-distros
          (when (kittymacs-bridge-wsl-available-p)
            (with-temp-buffer
              (set-buffer-multibyte nil)
              (let ((coding-system-for-read 'binary)
                    (default-directory temporary-file-directory))
                (when (eql 0 (call-process kittymacs-bridge-wsl-program nil t nil
                                           "--list" "--quiet"))
                  (kittymacs-bridge--parse-wsl-list
                   (kittymacs-bridge--decode-wsl-output (buffer-string)))))))))
  (when (called-interactively-p 'interactive)
    (message "WSL distributions: %s"
             (if kittymacs-bridge--wsl-distros
                 (string-join kittymacs-bridge--wsl-distros ", ")
               "none")))
  kittymacs-bridge--wsl-distros)
(defun kittymacs-bridge--wsl-completion (&rest _)
  "Offer the installed WSL distributions as host names after /wsl:."
  (mapcar (lambda (distro) (list nil distro)) (kittymacs-bridge-wsl-distros)))

(defun kittymacs-bridge-enable-wsl-method ()
  "Teach TRAMP the `wsl' method, so /wsl:USER@DISTRO:/path visits a file in WSL."
  (interactive)
  (require 'tramp)
  (setf (alist-get "wsl" tramp-methods nil nil #'equal)
        `((tramp-login-program ,kittymacs-bridge-wsl-program)
          (tramp-login-args (("-d" "%h") ("-u" "%u") ("--exec" "%l")))
          (tramp-direct-async ("--exec" "/bin/sh" "-c"))
          (tramp-remote-shell "/bin/sh")
          (tramp-remote-shell-login ("-l"))
          (tramp-remote-shell-args ("-i" "-c"))))
  (tramp-set-completion-function "wsl" '((kittymacs-bridge--wsl-completion "")))
  (kittymacs-bridge--apply-direct-async))
(defun kittymacs-bridge--apply-direct-async ()
  "Make `tramp-direct-async-process' follow the option on `wsl' connections."
  (connection-local-set-profile-variables
   'kittymacs-bridge-wsl
   `((tramp-direct-async-process . ,(bound-and-true-p kittymacs-bridge-wsl-direct-async))))
  (connection-local-set-profiles '(:application tramp :protocol "wsl")
                                 'kittymacs-bridge-wsl))

(defcustom kittymacs-bridge-wsl-direct-async t
  "Non-nil to start processes in WSL buffers directly, without TRAMP's shell."
  :type 'boolean
  :group 'kittymacs-bridge
  :initialize #'custom-initialize-default
  :set (lambda (symbol value)
         (set-default-toplevel-value symbol value)
         (when (featurep 'tramp) (kittymacs-bridge--apply-direct-async))))

(with-eval-after-load 'tramp
  (when (kittymacs-bridge-wsl-available-p)
    (kittymacs-bridge-enable-wsl-method)))
(defcustom kittymacs-bridge-backends nil
  "Linux back ends, best first; the first usable one is active.
Each entry is (NAME . PLIST) with the keys :when (a function of no
arguments; the entry is usable when it returns non-nil, or when :when
is absent), :transport ((wsl :distro DISTRO :user USER), (ssh :host
HOST :port PORT :user USER) or (local)) and :home (a directory, \"~/\"
when absent).  With no usable entry, WSL's default distribution is
active when wsl.exe is available."
  :type '(alist :key-type symbol :value-type plist)
  :group 'kittymacs-bridge)

(defun kittymacs-bridge--usable-p (plist)
  "Non-nil when the back end described by PLIST may be used here."
  (let ((test (plist-get plist :when)))
    (or (null test) (funcall test))))

(defun kittymacs-bridge-active ()
  "Return the active back end as (NAME . PLIST), or nil when there is none."
  (or (seq-find (lambda (entry) (kittymacs-bridge--usable-p (cdr entry)))
                kittymacs-bridge-backends)
      (when-let* (((kittymacs-bridge-wsl-available-p))
                  (distro (car (kittymacs-bridge-wsl-distros))))
        `(wsl :transport (wsl :distro ,distro)))))

(defun kittymacs-bridge-root (&optional backend)
  "Return the file name prefix that reaches BACKEND, the active one by default.
It is empty for a local back end, and nil when there is no back end."
  (when-let* ((backend (or backend (kittymacs-bridge-active))))
    (let* ((transport (plist-get (cdr backend) :transport))
           (args (cdr transport))
           (user (plist-get args :user))
           (at (if user (concat user "@") "")))
      (pcase (car transport)
        ('wsl (format "/wsl:%s%s:" at
                      (or (plist-get args :distro)
                          (car (kittymacs-bridge-wsl-distros))
                          (user-error "No WSL distribution is installed"))))
        ('ssh (format "/ssh:%s%s%s:" at (plist-get args :host)
                      (if-let* ((port (plist-get args :port))) (format "#%s" port) "")))
        ('local "")
        (_ (user-error "Unknown transport in back end %s: %S" (car backend) transport))))))

(defun kittymacs-bridge-home ()
  "Return the active back end's home directory as a file name."
  (if-let* ((backend (kittymacs-bridge-active)))
      (concat (kittymacs-bridge-root backend) (or (plist-get (cdr backend) :home) "~/"))
    (user-error "No Linux back end here; see `kittymacs-bridge-backends'")))

(defun kittymacs-bridge-find-file ()
  "Visit a file in the active back end, starting from its home directory."
  (interactive)
  (let ((default-directory (file-name-as-directory (kittymacs-bridge-home))))
    (call-interactively #'find-file)))

(defun kittymacs-bridge-dired ()
  "Open the active back end's home directory in Dired."
  (interactive)
  (dired (kittymacs-bridge-home)))
(defconst kittymacs-bridge--unc-prefix-regexp
  (rx bos (= 2 (any "/\\")) (any "Ww") (any "Ss") (any "Ll") (any ".$"))
  "Matches the start of every WSL share name; `file-name-handler-alist' uses it.")

(defconst kittymacs-bridge--unc-regexp
  (rx bos (= 2 (any "/\\")) (any "Ww") (any "Ss") (any "Ll")
      (or "$" (seq "." (any "Ll") (any "Oo") (any "Cc") (any "Aa") (any "Ll")
                   (any "Hh") (any "Oo") (any "Ss") (any "Tt")))
      (any "/\\") (group (+ (not (any "/\\")))) (group (* anychar)) eos)
  "Matches a WSL share name; the groups are the distribution and the path.")

(defun kittymacs-bridge-unc-to-tramp (name)
  "Return the /wsl: name for NAME, a \\\\wsl.localhost\\ or \\\\wsl$\\ name, else nil."
  (when (string-match kittymacs-bridge--unc-regexp name)
    (let ((distro (match-string 1 name))
          (path (string-replace "\\" "/" (match-string 2 name))))
      (concat "/wsl:" distro ":" (if (string-empty-p path) "/" path)))))

(defun kittymacs-bridge--unc-handler (operation &rest args)
  "Run file OPERATION with every WSL share name in ARGS as a /wsl: name."
  (let ((inhibit-file-name-handlers
         (cons #'kittymacs-bridge--unc-handler
               (and (eq inhibit-file-name-operation operation)
                    inhibit-file-name-handlers)))
        (inhibit-file-name-operation operation))
    (apply operation
           (mapcar (lambda (arg)
                     (or (and (stringp arg) (kittymacs-bridge-unc-to-tramp arg)) arg))
                   args))))

(define-minor-mode kittymacs-bridge-unc-mode
  "Visit \\\\wsl.localhost\\ and \\\\wsl$\\ names through the `wsl' method."
  :global t
  :group 'kittymacs-bridge
  (setq file-name-handler-alist
        (rassq-delete-all #'kittymacs-bridge--unc-handler file-name-handler-alist))
  (when kittymacs-bridge-unc-mode
    (push (cons kittymacs-bridge--unc-prefix-regexp #'kittymacs-bridge--unc-handler)
          file-name-handler-alist)))

(when (and (eq system-type 'windows-nt) (kittymacs-bridge-wsl-available-p))
  (kittymacs-bridge-unc-mode 1))
(provide 'kittymacs-bridge)
;;; kittymacs-bridge.el ends here
