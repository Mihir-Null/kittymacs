;;; kittymacs-remote.el --- Tramp, named backends and guards for a dead connection -*- lexical-binding: t; -*-
;; Generated from literate/36-remote.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'kittymacs-catalogue)
(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(defvar agent-shell-path-resolver-function)
(defvar kittymacs-remote-wsl-method)
(defvar kittymacs-remote-wsl-rpc-method)
(defvar tramp-methods)
(defvar tramp-remote-path)
(declare-function connection-local-set-profile-variables "files-x" (profile variables))
(declare-function connection-local-set-profiles "files-x" (criteria &rest profiles))
(declare-function tramp-cleanup-connection "tramp-cmds" (vec &optional keep-debug keep-password keep-processes))
(declare-function tramp-direct-async-process-p "tramp" (&rest args))
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function tramp-file-name-host "tramp" (vec))
(declare-function tramp-file-name-method "tramp" (vec))
(declare-function tramp-file-name-user "tramp" (vec))
(declare-function tramp-get-connection-property "tramp-cache" (key property &optional default))
(declare-function tramp-get-home-directory "tramp" (vec &optional user))
(declare-function tramp-get-method-parameter "tramp" (vec param &optional default))
(declare-function tramp-send-command-and-read "tramp-sh" (vec command &optional noerror marker))
(declare-function tramp-set-connection-property "tramp-cache" (key property value))
(declare-function kittymacs-remote-rpc-preflight "kittymacs-remote-rpc" (name backend))
(declare-function kittymacs-remote-rpc-report "kittymacs-remote-rpc" (backend))

(setopt tramp-persistency-file-name (expand-file-name "tramp" kittymacs-cache-dir)
        tramp-default-method "ssh"
        tramp-copy-size-limit nil
        tramp-use-ssh-controlmaster-options nil)
(defcustom kittymacs-remote-nix-path
  '("/run/wrappers/bin" "~/.nix-profile/bin" "/etc/profiles/per-user/$USER/bin"
    "/nix/var/nix/profiles/default/bin" "/run/current-system/sw/bin")
  "Directories Tramp searches on a remote machine, after its login shell's PATH.
Those that do not exist there are dropped when the connection opens.  `~/' is
the machine's home directory, and `$USER' the user Tramp logs in as."
  :type '(repeat string)
  :group 'kittymacs)

(defun kittymacs--remote-user (vec)
  "Return the user VEC logs in as: the one in its name, or the machine's answer.
The answer is kept per connection.  Nil if the machine gives none."
  (or (tramp-file-name-user vec)
      (tramp-get-connection-property vec "kittymacs-user")
      (let ((user (tramp-send-command-and-read vec "echo \\\"`id -un`\\\"" 'noerror)))
        (and (stringp user)
             (not (string-empty-p user))
             (tramp-set-connection-property vec "kittymacs-user" user)))))

(defun kittymacs--remote-expand-home (original vec)
  "Call ORIGINAL, `tramp-get-remote-path', with `~/' and `$USER' expanded for VEC.
Tramp's existence check quotes the name, so it never sees either."
  (let ((tramp-remote-path
         (mapcar (lambda (entry)
                   (cond ((not (stringp entry)) entry)
                         ((string-prefix-p "~/" entry)
                          (concat (tramp-get-home-directory vec) (substring entry 1)))
                         ((string-search "$USER" entry)
                          (let ((user (kittymacs--remote-user vec)))
                            (if user (string-replace "$USER" user entry) entry)))
                         (t entry)))
                 tramp-remote-path)))
    (funcall original vec)))

(defun kittymacs--remote-path-setup ()
  "Put the login shell's PATH first in `tramp-remote-path', then Nix's directories."
  (setq tramp-remote-path
        (append '(tramp-own-remote-path)
                kittymacs-remote-nix-path
                (seq-remove (lambda (entry)
                              (or (eq entry 'tramp-own-remote-path)
                                  (member entry kittymacs-remote-nix-path)))
                            tramp-remote-path)))
  (advice-add 'tramp-get-remote-path :around #'kittymacs--remote-expand-home))
(defcustom kittymacs-backends nil
  "The machines this Emacs works on, by name.
Each element is (NAME . PLIST), with NAME a string.  The keys of PLIST are
`:transport', `:host', `:root', `:shell', `:direct-async' and `:server'; the
remote chapter says what each means.  For example:

  ((\"build\" :transport ssh :host \"build.example.org\" :root \"~/src/project/\"))"
  :type '(alist :key-type string :value-type (plist :value-type sexp))
  :group 'kittymacs)

(defcustom kittymacs-backend-tools
  '("git" "rg" "fd" "direnv" "inotifywait" "nix" "claude-agent-acp")
  "Programs `kittymacs-backend-doctor' looks for on a backend.
Add the language servers your projects there use."
  :type '(repeat string)
  :group 'kittymacs)

(defvar kittymacs-remote-transports
  '((ssh . kittymacs-remote--tramp-root)
    (wsl . kittymacs-remote--wsl-root)
    (wsl-rpc . kittymacs-remote--wsl-rpc-root))
  "How each transport names a directory on its machine, by the `:transport' key.
A value is a function of the transport and the backend's plist.  An enabled
Tramp method needs no row: its name is the transport, handled as `ssh' is.")

(defun kittymacs-remote--tramp-root (transport backend)
  "Return the root of BACKEND as a Tramp name, with TRANSPORT as the method."
  (format "/%s:%s:%s" transport (or (plist-get backend :host) "") (plist-get backend :root)))

(defun kittymacs-remote--backend (name)
  "Return the plist of the backend called NAME."
  (or (cdr (assoc name kittymacs-backends))
      (user-error "No backend called %s in `kittymacs-backends'" name)))

(defun kittymacs-remote--transport (backend)
  "Return the transport of BACKEND, after checking this Emacs can use it."
  (let ((transport (or (plist-get backend :transport) 'ssh)))
    (require 'tramp)
    (unless (or (assq transport kittymacs-remote-transports)
                (assoc (symbol-name transport) tramp-methods))
      (user-error "No transport called %s: not in `kittymacs-remote-transports', and not an enabled Tramp method; `tramp-enable-method' enables an optional one"
                  transport))
    transport))

(defun kittymacs-backend-root (name)
  "Return the file name of the project on the backend called NAME."
  (let* ((backend (kittymacs-remote--backend name))
         (transport (kittymacs-remote--transport backend)))
    (funcall (alist-get transport kittymacs-remote-transports #'kittymacs-remote--tramp-root)
             transport backend)))

(defun kittymacs-remote--read-backend ()
  "Ask for the name of a backend."
  (unless kittymacs-backends
    (user-error "No backends: set `kittymacs-backends' in private.el"))
  (completing-read "Backend: " kittymacs-backends nil t))

(defun kittymacs-remote--rpc-p (backend)
  "Return non-nil if BACKEND uses the `wsl-rpc' transport."
  (eq (plist-get backend :transport) 'wsl-rpc))

(defun kittymacs-remote--preflight (name)
  "Refuse the backend called NAME if its transport can tell what would fail."
  (let ((backend (kittymacs-remote--backend name)))
    (when (kittymacs-remote--rpc-p backend)
      (kittymacs-remote-rpc-preflight name backend))))

(defun kittymacs-backend-connect (name)
  "Open the project on the backend called NAME."
  (interactive (list (kittymacs-remote--read-backend)))
  (let ((root (kittymacs-backend-root name)))
    (kittymacs-remote--preflight name)
    (kittymacs-remote--apply-backend name)
    (unless (file-directory-p root)
      (user-error "Backend %s has no directory %s" name root))
    (project-switch-project root)))

(defun kittymacs-remote--tools (root)
  "Return (TOOL . PATH) for each of `kittymacs-backend-tools' on ROOT's machine.
PATH is nil where the machine does not have the tool."
  (let ((default-directory (file-remote-p root))
        (remote-file-name-inhibit-cache t))
    (mapcar (lambda (tool) (cons tool (executable-find tool t)))
            kittymacs-backend-tools)))

(defconst kittymacs-remote-backend-package-tools
  '("git" "rg" "fd" "direnv" "inotifywait")
  "Which of `kittymacs-backend-tools' the flake's `packages.backend' installs.")

(defun kittymacs-remote--setup-advice (tools)
  "Return what to run for what TOOLS, the doctor's alist, lacks, or nil.
This only says it: nothing here installs anything."
  (let* ((missing (mapcar #'car (seq-remove #'cdr tools)))
         (nix (cdr (assoc "nix" tools)))
         (packaged (seq-filter (lambda (tool) (member tool kittymacs-remote-backend-package-tools))
                               missing))
         (others (seq-difference missing (cons "nix" packaged)))
         (install "nix profile install github:Mihir-Null/kittymacs#backend"))
    (when (or packaged others)
      (concat
       "\nTo get what is missing, on that machine:\n\n"
       (cond ((not packaged) "")
             (nix (format "  %s\n\n" install))
             (t (format "  %s\n\nfrom its package manager, or, with Nix, which it does not have yet:\n\n  %s\n\n"
                        (string-join packaged " ") install)))
       (if others
           (format "Those are separate: %s\n\n" (string-join others " "))
         "")
       "Tramp reads the machine's PATH once per connection, so then reconnect with\n"
       "M-x tramp-cleanup-connection.\n"))))

(defun kittymacs-remote--experimental (transport)
  "Return what the catalogue says is untested about TRANSPORT, or nil."
  (plist-get (alist-get transport kittymacs-catalogue) :experimental))

(defun kittymacs-backend-doctor (name)
  "Report which tools the backend called NAME has, and return them as an alist."
  (interactive (list (kittymacs-remote--read-backend)))
  (let* ((root (kittymacs-backend-root name))
         (backend (kittymacs-remote--backend name))
         (rpc (kittymacs-remote--rpc-p backend))
         (report (when rpc
                   (kittymacs-remote--preflight name)
                   (kittymacs-remote-rpc-report backend)))
         ;; Without a server, asking the machine anything would only fail.
         (reachable (or (not rpc) (plist-get report :server)))
         (tools (when reachable
                  (kittymacs-remote--apply-backend name)
                  (kittymacs-remote--tools root)))
         (exists (and reachable (file-directory-p root)))
         (direct (and reachable (not rpc)
                      (let ((default-directory (file-remote-p root)))
                        (tramp-direct-async-process-p)))))
    (with-help-window "*kittymacs backend*"
      (princ (format "Backend %s, over %s\n\n" name (kittymacs-remote--transport backend)))
      (when-let* ((untested (kittymacs-remote--experimental
                             (kittymacs-remote--transport backend))))
        (princ (format "Experimental: %s\n\n" untested)))
      (when rpc (princ (plist-get report :text)))
      (when reachable
        (princ (format "Project  %s (%s)\n" root (if exists "exists" "MISSING")))
        (princ (format "Processes start %s\n"
                       (cond (rpc "through tramp-rpc-server")
                             (direct "directly")
                             (t "through Tramp's shell"))))
        (princ (format "A project's direnv is %s\n\n"
                       (if (kittymacs-remote--direnv-p root) "on" "off")))
        (pcase-dolist (`(,tool . ,path) tools)
          (princ (format "%-20s %s\n" tool (or path "not found"))))
        (when-let* ((advice (kittymacs-remote--setup-advice tools)))
          (princ advice))))
    tools))

(defun kittymacs-backend-reconnect (name)
  "Drop the connection to the backend called NAME, and open a new one.
Interactively, NAME is this buffer's backend, or else one you choose."
  (interactive (list (or (kittymacs-remote--buffer-backend)
                         (kittymacs-remote--read-backend))))
  (let ((root (kittymacs-backend-root name)))
    (kittymacs-remote--preflight name)
    (kittymacs-remote--apply-backend name)
    (tramp-cleanup-connection (tramp-dissect-file-name root))
    (unless (file-directory-p root)
      (user-error "Backend %s has no directory %s" name root))
    (message "Reconnected to %s" name)))

(keymap-set kittymacs-open-map "b" (cons "backend: open its project" #'kittymacs-backend-connect))
(keymap-set kittymacs-open-map "B" (cons "backend: what it has" #'kittymacs-backend-doctor))
(keymap-set kittymacs-open-map "R" (cons "backend: reconnect" #'kittymacs-backend-reconnect))
(defun kittymacs-remote--prefix (backend)
  "Return the start of a file name on BACKEND, without looking anything up."
  (let ((transport (or (plist-get backend :transport) 'ssh)))
    (format "/%s:%s:"
            (pcase transport
              ('wsl kittymacs-remote-wsl-method)
              ('wsl-rpc kittymacs-remote-wsl-rpc-method)
              (_ transport))
            (or (plist-get backend :host) ""))))

(defun kittymacs-remote--buffer-backend ()
  "Return the name of this buffer's backend, or nil.  It never connects."
  (when-let* ((kittymacs-backends)
              (remote (and default-directory (file-remote-p default-directory))))
    (car (seq-find (lambda (backend)
                     (equal remote (kittymacs-remote--prefix (cdr backend))))
                   kittymacs-backends))))

(defvar kittymacs-remote-mode-line-map
  (let ((map (make-sparse-keymap)))
    (keymap-set map "<mode-line> <mouse-1>" #'kittymacs-backend-reconnect)
    map)
  "The keys of the backend's name in the mode line.")

(defun kittymacs-remote-mode-line ()
  "Return the mode line's text for this buffer's backend, or nil.
It never connects."
  (when-let* ((name (kittymacs-remote--buffer-backend)))
    (let ((connected (file-remote-p default-directory nil t)))
      (propertize (format " [%s%s]" name (if connected "" "?"))
                  'face (unless connected 'warning)
                  'mouse-face 'mode-line-highlight
                  'local-map kittymacs-remote-mode-line-map
                  'help-echo (format "Backend %s, %s.  mouse-1: reconnect" name
                                     (if connected "connected" "not connected"))))))

(add-to-list 'mode-line-misc-info '(:eval (kittymacs-remote-mode-line)))
(defconst kittymacs-remote-wsl-method "wslm"
  "The Tramp method behind the `wsl' transport.")

(defconst kittymacs-remote-wsl-path
  "/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  "A Linux PATH, in place of the one `wsl.exe' gives, which ends in Windows's.")

(defun kittymacs-remote--add-wsl-method ()
  "Add the Tramp method behind the `wsl' transport, where `wsl.exe' exists."
  (when (executable-find "wsl.exe")
    (add-to-list 'tramp-methods
                 `(,kittymacs-remote-wsl-method
                   (tramp-login-program "wsl.exe")
                   (tramp-login-args (("-d" "%h") ("--exec")
                                      ("/bin/sh" "-c"
                                       ,(concat "\"PATH=" kittymacs-remote-wsl-path)
                                       "exec" "%l" "2>&1\"")))
                   (tramp-direct-async ("/bin/sh" "-c"))
                   (tramp-remote-shell "sh")
                   (tramp-remote-shell-login ("-l"))
                   (tramp-remote-shell-args ("-c"))
                   (tramp-completion-use-cache nil)))))

(defun kittymacs-remote--wsl-root (_transport backend)
  "Return the root of BACKEND, a distribution reached through `wsl.exe'."
  (unless (executable-find "wsl.exe")
    (user-error "The wsl transport needs wsl.exe, and this machine has none"))
  (unless (plist-get backend :host)
    (user-error "A wsl backend needs :host, the distribution's name in `wsl --list'"))
  (kittymacs-remote--add-wsl-method)
  (kittymacs-remote--tramp-root kittymacs-remote-wsl-method backend))
(defvar ghostel-shell)
(defvar ghostel-tramp-shells)
(defvar ghostel-use-native-pty)

(defun kittymacs--remote-wsl-terminal (original)
  "Call ORIGINAL, which starts a terminal, running `wsl.exe' for a WSL backend.
Anywhere else it calls ORIGINAL unchanged, after one test that never connects."
  (let ((distribution (and ghostel-use-native-pty
                           (kittymacs-remote--wsl-distribution default-directory))))
    (if (not distribution)
        (funcall original)
      (let ((ghostel-shell (list "wsl.exe"
                                 "-d" distribution
                                 "--cd" (file-local-name (expand-file-name default-directory))))
            (default-directory temporary-file-directory))
        (funcall original)))))

(with-eval-after-load 'ghostel
  (advice-add 'ghostel--start-process :around #'kittymacs--remote-wsl-terminal))
(with-eval-after-load 'ghostel-shell
  (add-to-list 'ghostel-tramp-shells (list kittymacs-remote-wsl-method 'login-shell)))
(defvar kittymacs-remote-windows-file-note nil
  "What the message about a Windows-side file adds, or nil.")

(defvar kittymacs-remote--windows-files-noted nil
  "The Windows-side files this session has already spoken about.")

(defun kittymacs-remote--wsl-rpc-hosts ()
  "Return the distributions that `wsl-rpc' backends name."
  (seq-keep (lambda (backend)
              (and (kittymacs-remote--rpc-p (cdr backend))
                   (plist-get (cdr backend) :host)))
            kittymacs-backends))

(defun kittymacs-remote--wsl-distribution (file)
  "Return the WSL distribution that the name FILE is on, or nil.
This reads the name, and never connects."
  (when (and (stringp file)
             (string-match "\\`/\\([^:/|]+\\):\\(?:[^:/|@]*@\\)?\\([^:/|]*\\):" file))
    (let ((method (match-string 1 file))
          (host (match-string 2 file)))
      (when (or (equal method kittymacs-remote-wsl-method)
                (and (equal method kittymacs-remote-wsl-rpc-method)
                     (member host (kittymacs-remote--wsl-rpc-hosts))))
        host))))

(defun kittymacs-remote--windows-file (file)
  "Return what Windows calls FILE, a name on a WSL backend under /mnt/, or nil.
This reads the name, and never connects."
  (when (and (kittymacs-remote--wsl-distribution file)
             (string-match "\\`/[^:]*:[^:]*:/mnt/\\([a-z]\\)\\(/.*\\)?\\'" file))
    (concat (match-string 1 file) ":" (or (match-string 2 file) "/"))))

(defun kittymacs--remote-note-windows-file ()
  "Say once that this buffer's file would be quicker opened on Windows."
  (when-let* ((buffer-file-name)
              (native (kittymacs-remote--windows-file buffer-file-name)))
    (unless (member buffer-file-name kittymacs-remote--windows-files-noted)
      (push buffer-file-name kittymacs-remote--windows-files-noted)
      (message "This file is on Windows, and reading it through WSL is slow.  %s reopens it as %s.%s"
               (substitute-command-keys "\\[kittymacs-remote-reopen-natively]")
               native
               (if kittymacs-remote-windows-file-note
                   (concat "  " kittymacs-remote-windows-file-note)
                 "")))))

(defun kittymacs-remote-reopen-natively ()
  "Replace this buffer's Windows-side file with the native file."
  (interactive)
  (let ((native (and buffer-file-name (kittymacs-remote--windows-file buffer-file-name))))
    (unless native
      (user-error "This buffer is not a Windows-side file on a WSL backend"))
    (find-alternate-file native)))

(add-hook 'find-file-hook #'kittymacs--remote-note-windows-file)
(keymap-set kittymacs-open-map "w" (cons "reopen a Windows file natively" #'kittymacs-remote-reopen-natively))
(defun kittymacs--remote-unix-newlines ()
  "Give a remote file that shows no line ending of its own Unix newlines.
A file with line endings keeps them.  This never connects."
  (when (and buffer-file-name
             (file-remote-p buffer-file-name)
             (or (not (local-variable-p 'buffer-file-coding-system))
                 (not (save-excursion
                        (save-restriction
                          (widen)
                          (goto-char (point-min))
                          (search-forward "\n" nil t))))))
    (set-buffer-file-coding-system 'undecided-unix nil t)))

(add-hook 'find-file-hook #'kittymacs--remote-unix-newlines)
(add-hook 'after-set-visited-file-name-hook #'kittymacs--remote-unix-newlines)
(defconst kittymacs-remote-wsl-rpc-method "rpc"
  "The Tramp method behind the `wsl-rpc' transport, which tramp-rpc registers.")

(defun kittymacs-remote--wsl-rpc-root (_transport backend)
  "Return the root of BACKEND, a distribution reached through tramp-rpc."
  (unless (executable-find "wsl.exe")
    (user-error "The wsl-rpc transport needs wsl.exe, and this machine has none"))
  (unless (plist-get backend :host)
    (user-error "A wsl-rpc backend needs :host, the distribution's name in `wsl --list'"))
  (unless (featurep 'kittymacs-remote-rpc)
    (user-error "The wsl-rpc transport needs the wsl-rpc feature: add it to `kittymacs-features' and restart, or use `:transport wsl'"))
  (unless (locate-library "tramp-rpc")
    (user-error "The wsl-rpc feature is on and tramp-rpc is not installed: see the warning from the start, or use `:transport wsl'"))
  (kittymacs-remote--tramp-root kittymacs-remote-wsl-rpc-method backend))
(defun kittymacs-remote--apply-backend (name)
  "Set the connection-local variables of the backend called NAME."
  (let* ((backend (kittymacs-remote--backend name))
         (vec (tramp-dissect-file-name (kittymacs-backend-root name)))
         (shell (plist-get backend :shell))
         (direct (and (tramp-get-method-parameter vec 'tramp-direct-async)
                      (or (not (plist-member backend :direct-async))
                          (plist-get backend :direct-async))))
         (profile (intern (format "kittymacs-backend-%s" name))))
    (connection-local-set-profile-variables
     profile
     (append (when shell
               `((shell-file-name . ,shell) (explicit-shell-file-name . ,shell)))
             (when direct '((tramp-direct-async-process . t)))
             ;; Upstream reads these two per connection, so no other /rpc: host sees them.
             (when (kittymacs-remote--rpc-p backend)
               `((tramp-rpc-deploy-never-deploy . t)
                 (tramp-rpc-deploy-remote-binary-path . ,(plist-get backend :server))))))
    (connection-local-set-profiles
     `(:application tramp
       :protocol ,(tramp-file-name-method vec)
       :machine ,(tramp-file-name-host vec))
     profile)))

(defun kittymacs--remote-after-tramp ()
  "What waits for Tramp: the search path and the connection-local defaults."
  (kittymacs--remote-path-setup)
  (kittymacs-remote--add-wsl-method)
  (connection-local-set-profile-variables
   'kittymacs-remote-shell '((explicit-shell-file-name . "/bin/sh")))
  (connection-local-set-profiles '(:application tramp) 'kittymacs-remote-shell)
  ;; A typo must not stop Tramp loading; connecting to that backend reports it.
  (dolist (backend kittymacs-backends)
    (ignore-error user-error
      (kittymacs-remote--apply-backend (car backend)))))

(with-eval-after-load 'tramp
  (kittymacs--remote-after-tramp))
(eval-when-compile (require 'cl-lib))
(defvar envrc-remote)
(defvar envrc-supported-tramp-methods)
(declare-function envrc--merged-environment "envrc" (process-env pairs))

(defun kittymacs-remote--direnv-p (directory)
  "Return non-nil if a buffer in DIRECTORY gets its project's direnv environment.
This reads the name, and never connects."
  (kittymacs-remote--wsl-distribution directory))

(defun kittymacs--remote-envrc-on-wsl ()
  "Let envrc's global mode turn on in this buffer, if it is on a WSL backend."
  (when (kittymacs-remote--direnv-p default-directory)
    (setq-local envrc-remote t
                envrc-supported-tramp-methods (list (file-remote-p default-directory 'method)))))
;; Before `envrc-global-mode-enable-in-buffer', which is at the default depth.
(add-hook 'after-change-major-mode-hook #'kittymacs--remote-envrc-on-wsl -50)

(defun kittymacs--remote-envrc-export (export)
  "Call EXPORT, which starts direnv, so that direnv runs on the WSL backend."
  (if (kittymacs-remote--direnv-p default-directory)
      (let ((make-process-original (symbol-function 'make-process)))
        (cl-letf (((symbol-function 'make-process)
                   (lambda (&rest args)
                     (apply make-process-original :file-handler t :connection-type 'pipe args))))
          (funcall export)))
    (funcall export)))

(defvar kittymacs-remote--envrc-variables nil
  "Each NAME=VALUE that direnv has set on a WSL backend in this session.")

(defun kittymacs--remote-envrc-apply (buffer result)
  "Give BUFFER's processes RESULT from direnv, if BUFFER is on a WSL backend."
  (with-current-buffer buffer
    (when (and result (listp result) (kittymacs-remote--direnv-p default-directory))
      (setq-local process-environment
                  (envrc--merged-environment (default-value 'process-environment) result))
      (pcase-dolist (`(,name . ,value) result)
        (when value
          (cl-pushnew (concat name "=" value) kittymacs-remote--envrc-variables
                      :test #'equal))))))

(defun kittymacs--remote-envrc-variable-local-p (original variable)
  "Call ORIGINAL on VARIABLE, unless it is one that direnv set on a WSL backend.
This asks about the variable, and not about the buffer or its directory,
because a direct process rebinds the directory, and `shell-command' runs
from a new buffer."
  (and (not (member variable kittymacs-remote--envrc-variables))
       (funcall original variable)))

(with-eval-after-load 'envrc
  (advice-add 'envrc--direnv-export :around #'kittymacs--remote-envrc-export)
  (advice-add 'envrc--apply :after #'kittymacs--remote-envrc-apply))
(with-eval-after-load 'tramp
  (advice-add 'tramp-local-environment-variable-p :around
              #'kittymacs--remote-envrc-variable-local-p))
(setopt remote-file-name-inhibit-auto-save-visited t
        remote-file-name-inhibit-auto-save t)
(defcustom kittymacs-remote-auto-capfs '(eglot-completion-at-point cape-keyword)
  "Completion sources Corfu's automatic popup may call in a remote buffer."
  :type '(repeat function)
  :group 'kittymacs)

(defun kittymacs--remote-corfu-auto (original &rest arguments)
  "Call ORIGINAL with ARGUMENTS, keeping a remote buffer to its safe sources.
ORIGINAL is the function behind Corfu's automatic popup."
  (if (not (kittymacs-remote-buffer-p))
      (apply original arguments)
    (let ((completion-at-point-functions
           (seq-filter (lambda (source) (memq source kittymacs-remote-auto-capfs))
                       (append completion-at-point-functions
                               (default-value 'completion-at-point-functions)))))
      (apply original arguments))))

(defun kittymacs--remote-undo-buffer-p (buffer)
  "Return non-nil if BUFFER, which `diff-hl' would update, is remote."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer (kittymacs-remote-buffer-p))))

(with-eval-after-load 'flymake-collection-hook
  (advice-add 'flymake-collection-hook-set-backends :before-until #'kittymacs-remote-buffer-p))
(with-eval-after-load 'corfu-auto
  (advice-add 'corfu-auto--complete-deferred :around #'kittymacs--remote-corfu-auto))
(with-eval-after-load 'diff-hl
  (advice-add 'diff-hl-after-undo :before-until #'kittymacs--remote-undo-buffer-p))
(defun kittymacs-remote-agent-path (path)
  "Return PATH as the other side of an agent's connection names it.
A remote file name becomes the path the agent knows; a path from an agent on the
machine of this buffer's directory becomes a remote file name."
  (cond ((file-remote-p path) (file-local-name path))
        ((kittymacs-remote-buffer-p) (concat (file-remote-p default-directory) path))
        (t path)))

(with-eval-after-load 'agent-shell
  (unless agent-shell-path-resolver-function
    (setopt agent-shell-path-resolver-function #'kittymacs-remote-agent-path)))
(provide 'kittymacs-remote)
;;; kittymacs-remote.el ends here
