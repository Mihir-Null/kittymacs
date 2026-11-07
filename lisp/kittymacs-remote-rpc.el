;;; kittymacs-remote-rpc.el --- tramp-rpc over wsl.exe, for a WSL backend -*- lexical-binding: t; -*-
;; Generated from literate/36-remote.org; edit the Org source, then tangle.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'kittymacs-remote)
(require 'kittymacs-wsl)

(defvar ghostel-tramp-shells)
(defvar tramp-rpc-use-controlmaster)
(defvar tramp-rpc-use-direct-ssh-pty)
(declare-function tramp-file-name-hop "tramp" (vec))
(declare-function tramp-file-name-host "tramp" (vec))
(declare-function tramp-file-name-method "tramp" (vec))

(defconst kittymacs-remote-rpc-repository "https://github.com/ArthurHeymans/emacs-tramp-rpc"
  "Where tramp-rpc comes from, its Lisp and its server alike.")

(defconst kittymacs-remote-rpc-revision "543b3bf30b8a80b8cd0200c98d00f22a4e0220ac"
  "The commit of tramp-rpc this Emacs uses: version 0.16.0.")

(defconst kittymacs-remote-rpc-msgpack-revision "5353a7b2da854c843cbec4536996242001f63471"
  "The commit of msgpack.el this Emacs uses: version 0.1.1, MELPA's 20260706.1555.")
(when (eq system-type 'windows-nt)
  (condition-case err
      (eval `(progn
               (use-package msgpack
                 :vc (:url "https://github.com/xuchunyang/msgpack.el"
                      :rev ,kittymacs-remote-rpc-msgpack-revision)
                 :defer t)
               (use-package tramp-rpc
                 :vc (:url ,kittymacs-remote-rpc-repository
                      :lisp-dir "lisp"
                      :rev ,kittymacs-remote-rpc-revision)
                 :defer t))
            t)
    (error
     (display-warning 'kittymacs
                      (format "tramp-rpc was not installed: %s
Check that `git clone %s' works from a terminal, and which git Emacs runs: %s"
                              (error-message-string err) kittymacs-remote-rpc-repository
                              (executable-find "git"))
                      :warning))))

;;; Where the server is looked for

(defconst kittymacs-remote-rpc-server-path
  '("$HOME/.local/bin"
    "$HOME/.local/state/nix/profiles/home-manager/home-path/bin"
    "$HOME/.local/state/nix/profile/bin"
    "/etc/profiles/per-user/$USER/bin")
  "Where a server may be installed, beyond `kittymacs-remote-nix-path'.
Each is for a shell to expand, so `$HOME' and not `~/'.")

(defun kittymacs-remote-rpc--path ()
  "Return the PATH that finds the server, and that the server inherits."
  (string-join
   (seq-uniq
    (append kittymacs-remote-rpc-server-path
            (mapcar (lambda (directory)
                      (if (string-prefix-p "~/" directory)
                          (concat "$HOME/" (substring directory 2))
                        directory))
                    kittymacs-remote-nix-path)
            (split-string kittymacs-remote-wsl-path ":")))
   ":"))

(defun kittymacs-remote-rpc--in-distribution (distribution script)
  "Return the arguments of `wsl.exe' that run SCRIPT in DISTRIBUTION."
  (list "-d" distribution "--exec" "/bin/sh" "-c"
        (format "PATH=%s %s" (kittymacs-remote-rpc--path) script)))

;;; The seam

(defun kittymacs-remote-rpc--vec-p (vec)
  "Return non-nil if VEC is a distribution that a `wsl-rpc' backend names."
  (and (equal (tramp-file-name-method vec) kittymacs-remote-wsl-rpc-method)
       (not (tramp-file-name-hop vec))
       (member (tramp-file-name-host vec) (kittymacs-remote--wsl-rpc-hosts))))

(defun kittymacs--remote-rpc-start-server (original vec binary-path &optional sudo-password)
  "Call ORIGINAL on VEC, BINARY-PATH and SUDO-PASSWORD, through `wsl.exe'.
That is for a WSL backend.  For any other host it calls ORIGINAL unchanged,
which starts `ssh'."
  (if (not (kittymacs-remote-rpc--vec-p vec))
      (funcall original vec binary-path sudo-password)
    (let ((real (symbol-function 'make-process)))
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest arguments)
                   (when (equal (car (plist-get arguments :command)) "ssh")
                     (setq arguments
                           (plist-put arguments :command
                                      (cons "wsl.exe"
                                            (kittymacs-remote-rpc--in-distribution
                                             (tramp-file-name-host vec)
                                             (concat "exec " binary-path))))))
                   (apply real arguments))))
        (funcall original vec binary-path sudo-password)))))

(defun kittymacs--remote-rpc-scope (original vec &rest arguments)
  "Call ORIGINAL on VEC and ARGUMENTS, with `ssh''s switches off for a WSL backend."
  (if (kittymacs-remote-rpc--vec-p vec)
      (let ((tramp-rpc-use-controlmaster nil)
            (tramp-rpc-use-direct-ssh-pty nil))
        (apply original vec arguments))
    (apply original vec arguments)))

(defun kittymacs--remote-rpc-direnv-variables (environment)
  "Return ENVIRONMENT, an alist, with what direnv set that this scope still has.
`envrc' runs `shell-command' under `inheritenv', which copies the buffer's
environment over the default that tramp-rpc compares with, so it sees no change."
  (dolist (entry process-environment environment)
    (when (and (member entry kittymacs-remote--envrc-variables)
               (string-match "\\`\\([^=]+\\)=\\(.*\\)\\'" entry)
               (not (assoc (match-string 1 entry) environment)))
      (push (cons (match-string 1 entry) (match-string 2 entry)) environment))))

(defconst kittymacs-remote-rpc-private-functions
  '(tramp-rpc--start-server-process tramp-rpc--connect tramp-rpc--make-pty-process
    tramp-rpc--caller-environment)
  "What the seam relies on in tramp-rpc, none of which it promises to keep.")

(defun kittymacs--remote-rpc-refuse (operation &rest arguments)
  "Signal if OPERATION with ARGUMENTS would try `ssh' to a distribution.
Added only when the seam could not be, by `kittymacs-remote-rpc--install'."
  (unless (memq operation '(file-remote-p expand-file-name))
    (when (seq-some #'kittymacs-remote--wsl-distribution (cons default-directory arguments))
      (user-error "The wsl-rpc transport cannot start: tramp-rpc at this revision lacks %s"
                  (string-join (mapcar #'symbol-name (kittymacs-remote-rpc--missing)) ", ")))))

(defun kittymacs-remote-rpc--missing ()
  "Return which of `kittymacs-remote-rpc-private-functions' tramp-rpc lacks."
  (seq-remove #'fboundp kittymacs-remote-rpc-private-functions))

(defun kittymacs-remote-rpc--install ()
  "Put the seam on a loaded tramp-rpc, or say plainly that it does not fit."
  (if-let* ((missing (kittymacs-remote-rpc--missing)))
      (progn
        (display-warning
         'kittymacs
         (format "tramp-rpc no longer has %s, which the wsl-rpc transport relies on.  \
A distribution will refuse to connect rather than try ssh.  Set `:transport wsl' on the \
backend, or move the seam: see \"Moving the pin\" in the remote chapter."
                 (string-join (mapcar #'symbol-name missing) ", "))
         :error)
        (advice-add 'tramp-rpc-file-name-handler :before #'kittymacs--remote-rpc-refuse))
    (advice-add 'tramp-rpc--start-server-process :around #'kittymacs--remote-rpc-start-server)
    (advice-add 'tramp-rpc--connect :around #'kittymacs--remote-rpc-scope)
    (advice-add 'tramp-rpc--make-pty-process :around #'kittymacs--remote-rpc-scope)
    (advice-add 'tramp-rpc--caller-environment :filter-return
                #'kittymacs--remote-rpc-direnv-variables)))

(with-eval-after-load 'tramp-rpc
  (kittymacs-remote-rpc--install))

;;; What the rest of the remote chapter asks

(defun kittymacs-remote-rpc-preflight (name backend)
  "Refuse the backend NAME, with plist BACKEND, if WSL lacks its distribution."
  (let ((distribution (plist-get backend :host))
        (known (kittymacs-wsl-distributions)))
    (unless (member distribution known)
      (user-error "Backend %s names the distribution %s, and `wsl --list' has %s"
                  name distribution (if known (string-join known ", ") "none")))))

(defun kittymacs-remote-rpc--server (backend)
  "Return where BACKEND's distribution has its server, or nil."
  (let ((default-directory temporary-file-directory))
    (with-temp-buffer
      (when (eql 0 (apply #'call-process "wsl.exe" nil '(t nil) nil
                          (kittymacs-remote-rpc--in-distribution
                           (plist-get backend :host)
                           (format "command -v %s"
                                   (or (plist-get backend :server) "tramp-rpc-server")))))
        (string-trim (buffer-string))))))

(defun kittymacs-remote-rpc-report (backend)
  "Return what BACKEND needs of this transport, as a plist.
`:server' and `:cat' say where each is, or nil, and `:text' says that to a
person, with what to install for whichever is missing."
  (let ((server (kittymacs-remote-rpc--server backend))
        (cat (executable-find "cat")))
    (list :server server
          :cat cat
          :text
          (concat
           (format "Server   %s\n" (or server "NOT FOUND"))
           (format "cat      %s\n\n" (or cat "NOT FOUND"))
           (unless server
             (format "On that machine, with Rust 1.88 or later:\n\n  cargo install --locked --root ~/.local --git %s --rev %s tramp-rpc-server\n\nOr set `:server' on the backend, if it is installed where this PATH misses:\n\n  %s\n\n"
                     kittymacs-remote-rpc-repository kittymacs-remote-rpc-revision
                     (kittymacs-remote-rpc--path)))
           (unless cat
             "Every process there runs a local cat, and tramp-rpc has no fallback.\nInstall Git for Windows, whose usr/bin has one, and restart Emacs.\n\n")))))

(defun kittymacs-remote-rpc--own-name (file)
  "Return FILE, with a `wslm' name on a `wsl-rpc' backend's distribution as `rpc'."
  (if (and (string-match (format "\\`/%s:\\([^:/|]*\\):" (regexp-quote kittymacs-remote-wsl-method))
                         file)
           (member (match-string 1 file) (kittymacs-remote--wsl-rpc-hosts)))
      (format "/%s:%s:%s" kittymacs-remote-wsl-rpc-method (match-string 1 file)
              (substring file (match-end 0)))
    file))

(defun kittymacs--remote-rpc-own-names (arguments)
  "Return ARGUMENTS for `server-visit-files', each file on its backend's method."
  (cons (mapcar (lambda (file) (cons (kittymacs-remote-rpc--own-name (car file)) (cdr file)))
                (car arguments))
        (cdr arguments)))

(with-eval-after-load 'server
  (advice-add 'server-visit-files :filter-args #'kittymacs--remote-rpc-own-names))
(with-eval-after-load 'ghostel-shell
  (add-to-list 'ghostel-tramp-shells (list kittymacs-remote-wsl-rpc-method 'login-shell)))
(defun kittymacs-remote-rpc--file-p (file)
  "Return non-nil if the name FILE is on a `wsl-rpc' backend's distribution.
This reads the name, and never connects."
  (and (kittymacs-remote--wsl-distribution file)
       (string-prefix-p (format "/%s:" kittymacs-remote-wsl-rpc-method) file)))

(defun kittymacs--remote-rpc-precious ()
  "Have this save replace its file, if a `wsl-rpc' backend holds it.
Not a symbolic link or a file with other names, which replacing would cut off."
  (when (kittymacs-remote-rpc--file-p buffer-file-name)
    (let ((attributes (file-attributes buffer-file-name)))
      (setq-local file-precious-flag
                  (not (or (stringp (file-attribute-type attributes))
                           (> (or (file-attribute-link-number attributes) 1) 1)))))))

(add-hook 'before-save-hook #'kittymacs--remote-rpc-precious)

(provide 'kittymacs-remote-rpc)
;;; kittymacs-remote-rpc.el ends here
