;;; kittymacs-remote.el --- Tramp, named backends and guards for a dead connection -*- lexical-binding: t; -*-
;; Generated from literate/36-remote.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(defvar agent-shell-path-resolver-function)
(defvar tramp-methods)
(defvar tramp-remote-path)
(declare-function connection-local-set-profile-variables "files-x" (profile variables))
(declare-function connection-local-set-profiles "files-x" (criteria &rest profiles))
(declare-function tramp-direct-async-process-p "tramp" (&rest args))
(declare-function tramp-dissect-file-name "tramp" (name &optional nodefault))
(declare-function tramp-file-name-host "tramp" (vec))
(declare-function tramp-file-name-method "tramp" (vec))
(declare-function tramp-get-home-directory "tramp" (vec &optional user))
(declare-function tramp-get-method-parameter "tramp" (vec param &optional default))

(setopt tramp-persistency-file-name (expand-file-name "tramp" kittymacs-cache-dir)
        tramp-default-method "ssh"
        tramp-copy-size-limit nil
        tramp-use-ssh-controlmaster-options nil)
(defcustom kittymacs-remote-nix-path
  '("~/.nix-profile/bin" "/nix/var/nix/profiles/default/bin" "/run/current-system/sw/bin")
  "Directories Tramp searches on a remote machine, after its login shell's PATH.
Those that do not exist there are dropped when the connection opens."
  :type '(repeat string)
  :group 'kittymacs)

(defun kittymacs--remote-expand-home (original vec)
  "Call ORIGINAL, `tramp-get-remote-path', with `~/' expanded for VEC.
Tramp's existence check quotes the name, so it never sees a home directory."
  (let ((tramp-remote-path
         (mapcar (lambda (entry)
                   (if (and (stringp entry) (string-prefix-p "~/" entry))
                       (concat (tramp-get-home-directory vec) (substring entry 1))
                     entry))
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
`:transport', `:host', `:root', `:shell' and `:direct-async'; the remote chapter
says what each means.  For example:

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
  '((ssh . kittymacs-remote--tramp-root))
  "How each transport names a directory on its machine, by the `:transport' key.
A value is a function of the transport and the backend's plist.  A Tramp method
needs no row: its name is the transport, handled as `ssh' is.")

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
      (user-error "No transport called %s: not in `kittymacs-remote-transports', and Tramp has no such method"
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

(defun kittymacs-backend-connect (name)
  "Open the project on the backend called NAME."
  (interactive (list (kittymacs-remote--read-backend)))
  (let ((root (kittymacs-backend-root name)))
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

(defun kittymacs-backend-doctor (name)
  "Report which tools the backend called NAME has, and return them as an alist."
  (interactive (list (kittymacs-remote--read-backend)))
  (let* ((root (kittymacs-backend-root name))
         (backend (kittymacs-remote--backend name))
         (tools (progn (kittymacs-remote--apply-backend name)
                       (kittymacs-remote--tools root)))
         (exists (file-directory-p root))
         (direct (let ((default-directory (file-remote-p root)))
                   (tramp-direct-async-process-p))))
    (with-help-window "*kittymacs backend*"
      (princ (format "Backend %s, over %s\n\n" name (kittymacs-remote--transport backend)))
      (princ (format "Project  %s (%s)\n" root (if exists "exists" "MISSING")))
      (princ (format "Processes start %s\n\n" (if direct "directly" "through Tramp's shell")))
      (pcase-dolist (`(,tool . ,path) tools)
        (princ (format "%-20s %s\n" tool (or path "not found")))))
    tools))

(keymap-set kittymacs-open-map "b" (cons "backend: open its project" #'kittymacs-backend-connect))
(keymap-set kittymacs-open-map "B" (cons "backend: what it has" #'kittymacs-backend-doctor))
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
             (when direct '((tramp-direct-async-process . t)))))
    (connection-local-set-profiles
     `(:application tramp
       :protocol ,(tramp-file-name-method vec)
       :machine ,(tramp-file-name-host vec))
     profile)))

(defun kittymacs--remote-after-tramp ()
  "What waits for Tramp: the search path and the connection-local defaults."
  (kittymacs--remote-path-setup)
  (connection-local-set-profile-variables
   'kittymacs-remote-shell '((explicit-shell-file-name . "/bin/sh")))
  (connection-local-set-profiles '(:application tramp) 'kittymacs-remote-shell)
  ;; A typo must not stop Tramp loading; connecting to that backend reports it.
  (dolist (backend kittymacs-backends)
    (ignore-error user-error
      (kittymacs-remote--apply-backend (car backend)))))

(with-eval-after-load 'tramp
  (kittymacs--remote-after-tramp))
(setopt remote-file-name-inhibit-auto-save-visited t
        remote-file-name-inhibit-auto-save t)

(defun kittymacs-remote-buffer-p (&rest _)
  "Return non-nil if this buffer's directory is on another machine.
This never connects.  The arguments are ignored, so it can stand in front of any
function as advice."
  (file-remote-p default-directory))
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
