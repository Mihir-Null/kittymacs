;;; kittymacs-remote-start.el --- One start, then what it does to a remote buffer -*- lexical-binding: t; -*-
;; Run by tests/kittymacs-remote-tests.el, once per scenario, in a process of its
;; own that it can kill.  KITTYMACS_REMOTE_SCENARIO names the scenario and
;; KITTYMACS_REMOTE_RESULT the file that receives its results as an alist.
;;
;;   clean        a start with no remote project in play
;;   unreachable  a start that knows a project, a recent file and a bookmark on a
;;                machine whose login never answers
;;   hung         a start, a remote file, then a connection that stops answering:
;;                every idle timer and guarded subsystem runs, each with a limit
;;   working      a start and a connection that answers: backends and the programs
;;                a person uses in a remote project
;;
;; It replays a start as tests/verify-config.el does, in a copy of the checkout.

;;; Code:
(require 'cl-lib)
(require 'package)
(require 'seq)

(defconst kittymacs-remote-start-source
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(load (expand-file-name "tests/kittymacs-remote-fixture.el" kittymacs-remote-start-source) nil t)

(defvar kittymacs-remote-start-results nil "The alist this scenario reports.")
(defvar kittymacs-remote-start-scenario (intern (getenv "KITTYMACS_REMOTE_SCENARIO")))
(defvar tramp-connection-timeout)
(defvar ghostel-buffer-name)
(defvar eshell-buffer-name)
(defvar ghostel-macos-login-shell)
(defconst kittymacs-remote-start-limit 3 "Seconds a probe may take before it counts as stalled.")

(defun kittymacs-remote-start-report (key value)
  "Record VALUE under KEY, and write the results so far, in case a later step hangs."
  (push (cons key value) kittymacs-remote-start-results)
  (let ((print-length nil) (print-level nil))
    (with-temp-file (getenv "KITTYMACS_REMOTE_RESULT")
      (prin1 kittymacs-remote-start-results (current-buffer)))))

(defmacro kittymacs-remote-start-probe (key &rest body)
  "Report under KEY whether BODY finishes: `done', `stalled' or an error."
  (declare (indent 1))
  `(kittymacs-remote-start-report
    ,key
    (condition-case err
        (kittymacs-remote-fixture-bounded kittymacs-remote-start-limit
          ,@body
          'done)
      (error (list 'error (format "%S" err))))))

(defmacro kittymacs-remote-start-value (key &rest body)
  "Report under KEY the value of BODY, or the error it signals, or `stalled'."
  (declare (indent 1))
  `(kittymacs-remote-start-report
    ,key
    (condition-case err
        (kittymacs-remote-fixture-bounded 30 ,@body)
      (error (list 'error (format "%S" err))))))

;;; The start

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-remote-start-" t))
      default-directory user-emacs-directory
      user-init-file (expand-file-name "init.el" user-emacs-directory)
      native-comp-jit-compilation nil)
(setenv "HOME" (directory-file-name kittymacs-remote-fixture-dir))
(dolist (file '("early-init.el" "init.el"))
  (copy-file (expand-file-name file kittymacs-remote-start-source)
             (expand-file-name file user-emacs-directory)))
(dolist (directory '("lisp" "literate" "tools"))
  (copy-directory (expand-file-name directory kittymacs-remote-start-source)
                  (expand-file-name directory user-emacs-directory) nil t))
(defvar kittymacs-host-directories nil)

(defvar kittymacs-remote-start-project
  (kittymacs-remote-fixture--path "project/"))

(defun kittymacs-remote-start--var (name contents)
  "Write CONTENTS to the file NAME under the start's cache directory."
  (let ((file (expand-file-name (concat "var/cache/" name) user-emacs-directory)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert contents))))

(make-directory (expand-file-name "var/etc" user-emacs-directory) t)
(with-temp-file (expand-file-name "lisp/private.el" user-emacs-directory)
  (insert ";;; -*- lexical-binding: t; -*-\n"
          (format "(setopt kittymacs-profile '%s)\n" (getenv "KITTYMACS_TEST_PROFILE"))
          (format "(setopt kittymacs-backends '((\"here\" :transport kmock :host %S :root %S)
                                                (\"slow\" :transport kmock :host \"elsewhere\" :root \"/\" :direct-async nil :shell \"/custom/shell\")
                                                (\"typo\" :transport no-such-transport :host \"x\" :root \"/\")
                                                (\"tramp\" :transport sshx :host \"build\" :root \"~/src/\")
                                                (\"wsl\" :transport wsl :host \"Fake-24.04\" :root \"/tmp/\")
                                                (\"wsl-nameless\" :transport wsl :root \"/tmp/\")
                                                (\"default\" :host \"build\" :root \"~/src/\")))\n"
                  (system-name) kittymacs-remote-start-project)))

(when (eq kittymacs-remote-start-scenario 'unreachable)
  (let ((project (kittymacs-remote-fixture-name "project/" "khang")))
    (kittymacs-remote-start--var
     "projects" (format ";;; -*- lisp-data -*-\n((%S) (%S))\n"
                        project (directory-file-name temporary-file-directory)))
    (kittymacs-remote-start--var
     "recentf" (format "(setq recentf-list '(%S))\n" (concat project "a.py")))))

(kittymacs-remote-fixture-define-methods)
(advice-add 'kittymacs-activate-packages :before
            (lambda (&rest _) (setq package-user-dir (getenv "KITTYMACS_TEST_PACKAGES"))))
;; Nothing here answers a prompt: the grammar offer, say.
(advice-add 'y-or-n-p :override #'ignore)
(advice-add 'yes-or-no-p :override #'ignore)

(defvar kittymacs-remote-start-began (float-time))
(setq after-init-time nil)
(load (expand-file-name "early-init.el" user-emacs-directory) nil t)
(load user-init-file nil t)
(setq after-init-time (current-time))
(run-hooks 'after-init-hook 'delayed-warnings-hook 'emacs-startup-hook)
(kittymacs-remote-start-report 'start-seconds (- (float-time) kittymacs-remote-start-began))
(kittymacs-remote-start-report 'tramp-loaded (featurep 'tramp))

;;; What each scenario does next

(defun kittymacs-remote-start--project ()
  "Make the project on the fixture's remote side: one edited file under Git."
  (let ((default-directory (file-name-as-directory kittymacs-remote-start-project)))
    (make-directory "sub" t)
    (with-temp-file "a.py" (insert "import os\n"))
    (dolist (arguments '(("init" "-q") ("add" ".")
                         ("-c" "user.name=test" "-c" "user.email=test@example.org"
                          "commit" "-qm" "start")))
      (apply #'call-process "git" nil nil nil arguments))
    (with-temp-file "a.py" (insert "import os\nimport sys\n"))))

(defun kittymacs-remote-start--fake-programs ()
  "Add local programs that make the unguarded paths reach the connection.
Without them a machine that lacks `direnv' or `pycodestyle' would pass by luck."
  (dolist (name '("direnv" "pycodestyle"))
    (kittymacs-remote-fixture--script (concat "local-bin/" name) "exit 0"))
  (add-to-list 'exec-path (kittymacs-remote-fixture--path "local-bin")))

(defun kittymacs-remote-start--settle ()
  "Run what was waiting for Emacs to go idle, with the connection still up.
That is how a real session gets past opening a file; a timer that repeats runs
again later, and one that does not is gone."
  (dolist (timer (copy-sequence timer-idle-list))
    (ignore-errors (timer-event-handler timer))))

(defun kittymacs-remote-start--open ()
  "Open the project's edited file through kmock, and make it the current buffer."
  (kittymacs-remote-start--project)
  (setq remote-file-name-inhibit-cache 10)
  (find-file (kittymacs-remote-fixture-name "project/a.py"))
  (kittymacs-remote-start--settle))

(defun kittymacs-remote-start--hung ()
  "A remote file with unsaved text, and a connection that then stops answering."
  (kittymacs-remote-start--fake-programs)
  (kittymacs-remote-start--open)
  (when (fboundp 'auto-save-mode) (auto-save-mode 1))
  (kittymacs-remote-start-report 'auto-save-file buffer-auto-save-file-name)
  (when (boundp 'flymake-diagnostic-functions)
    (kittymacs-remote-start-report
     'collection-checkers
     (seq-filter (lambda (f) (and (symbolp f) (string-prefix-p "flymake-collection" (symbol-name f))))
                 flymake-diagnostic-functions)))
  (goto-char (point-max))
  (insert "# unsaved\nsub/")
  (let ((remote (current-buffer))
        (timers (append timer-idle-list timer-list)))
    ;; Every cached answer about the file goes stale, as after ten quiet seconds.
    (kittymacs-remote-fixture-hang)
    (setq remote-file-name-inhibit-cache t)
    (kittymacs-remote-start-probe 'file-exists-p (file-exists-p buffer-file-name))
    (let (idle)
      (dolist (timer timers)
        (let ((function (timer--function timer)))
          (with-current-buffer remote
            (let ((result
                   (condition-case err
                       (kittymacs-remote-fixture-bounded kittymacs-remote-start-limit
                         (apply function (timer--args timer))
                         'done)
                     (error (list 'error (format "%S" err))))))
              (push (cons (if (symbolp function) function 'lambda) result) idle)))))
      (kittymacs-remote-start-report 'timers idle))
    (with-current-buffer remote
      (kittymacs-remote-start-probe 'do-auto-save (do-auto-save t t))
      (kittymacs-remote-start-probe 'auto-revert
        (auto-revert-handler)
        (auto-revert-buffers))
      (kittymacs-remote-start-probe 'mode-line
        (when (boundp 'doom-modeline--project-root)
          (setq-local doom-modeline--project-root nil))
        (format-mode-line (default-value 'mode-line-format)))
      ;; Emacs's own trust check in `flymake-start' reads the file, for any
      ;; checker, so that command can wait; what must hold is that no timer runs it.
      (when (boundp 'flymake-no-changes-timeout)
        (kittymacs-remote-start-report 'flymake-timeout flymake-no-changes-timeout)
        (kittymacs-remote-start-report 'flymake-timer (and (boundp 'flymake-timer) flymake-timer t)))
      (when (fboundp 'corfu-mode)
        (require 'corfu-auto)
        (setq-local completion-at-point-functions '(cape-file))
        (kittymacs-remote-start-probe 'corfu-auto (corfu-auto--complete-deferred)))
      (when (fboundp 'diff-hl-after-undo)
        (kittymacs-remote-start-probe 'diff-hl-undo
          (with-silent-modifications (set-buffer-modified-p nil))
          (diff-hl-after-undo remote)
          (with-silent-modifications (set-buffer-modified-p t))))
      (when (fboundp 'doom-modeline-env-update-python)
        (kittymacs-remote-start-probe 'doom-env (doom-modeline-env-update-python))
        (kittymacs-remote-start-probe 'doom-update-env
          (setq doom-modeline-env--command "direnv"
                doom-modeline-env--command-args '("--version")
                doom-modeline-env--parser #'identity
                doom-modeline--project-root nil)
          (doom-modeline-update-env)))
      ;; Directly: `format-mode-line' returns nothing in batch.
      (kittymacs-remote-start-report
       'status-installed (and (member '(:eval (kittymacs-remote-mode-line)) mode-line-misc-info) t))
      (kittymacs-remote-start-probe 'status (kittymacs-remote-mode-line))
      (let ((default-directory (concat (file-remote-p default-directory) "~/"))
            (kittymacs-backends
             `(("home" :transport kmock :host ,(file-remote-p default-directory 'host) :root "~/"))))
        (kittymacs-remote-start-probe 'status-home (kittymacs-remote-mode-line)))
      (kittymacs-remote-start-value 'reconnect-hung
        (kittymacs-backend-reconnect "here")
        (let ((default-directory (kittymacs-backend-root "here")))
          (kittymacs-remote-mode-line)))
      (kittymacs-remote-start-probe 'windows-file
        (kittymacs-remote-start--windows-file-notes "/wslm:Fake-24.04:/mnt/c/hung.txt")))
    (kittymacs-remote-fixture-resume)))

(defun kittymacs-remote-start--wait (predicate)
  "Keep Emacs reading processes until PREDICATE holds, for ten seconds at most."
  (let ((deadline (+ (float-time) 10)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (funcall predicate))

(defun kittymacs-remote-start--stub-server ()
  "Write a language server that knows `initialize' and `shutdown', and return it."
  (let ((file (kittymacs-remote-fixture--path "stub-server.py")))
    (with-temp-file file
      (insert "import json, sys
def reply(ident, result):
    body = json.dumps({'jsonrpc': '2.0', 'id': ident, 'result': result}).encode()
    sys.stdout.buffer.write(b'Content-Length: %d\\r\\n\\r\\n' % len(body) + body)
    sys.stdout.buffer.flush()
while True:
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            sys.exit(0)
        if line.lower().startswith(b'content-length:'):
            length = int(line.split(b':')[1])
        if line in (b'\\r\\n', b'\\n'):
            break
    message = json.loads(sys.stdin.buffer.read(length))
    if message.get('method') == 'initialize':
        reply(message['id'], {'capabilities': {'completionProvider': {}}})
    elif 'id' in message and 'method' in message:
        reply(message['id'], None)
"))
    file))

(defun kittymacs-remote-start--tool ()
  "Install a program in the Nix profile of the fixture's remote side."
  (kittymacs-remote-fixture--script ".nix-profile/bin/kfake" "echo fake-tool-ran"))

(defun kittymacs-remote-start--windows-file-notes (file)
  "Run the note for FILE twice, as opening it twice would, and return what it said.
Only the note: other functions on `find-file-hook' read the file, as they may."
  (let (said)
    (cl-letf (((symbol-function 'message)
               (lambda (format-string &rest args)
                 (push (apply #'format format-string args) said))))
      (with-temp-buffer
        (setq buffer-file-name file)
        (kittymacs--remote-note-windows-file)
        (kittymacs--remote-note-windows-file)
        (setq buffer-file-name nil)))
    said))

(defun kittymacs-remote-start--newlines-saved (file text)
  "Open FILE, add TEXT at its end, save it, and return its bytes."
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-max))
    (insert text)
    (save-buffer)
    (kill-buffer))
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defun kittymacs-remote-start--newlines ()
  "What each kind of file saves with, under Windows's default of `dos'."
  (let ((default (default-value 'buffer-file-coding-system)))
    (setq-default buffer-file-coding-system 'utf-8-dos)
    (unwind-protect
        (progn
          (kittymacs-remote-start-value 'newlines-new
            (kittymacs-remote-start--newlines-saved
             (kittymacs-remote-fixture-name "newlines-new") "one\ntwo\n"))
          (kittymacs-remote-start-value 'newlines-existing
            (let ((file (kittymacs-remote-fixture-name "newlines-existing")))
              (let ((coding-system-for-write 'no-conversion))
                (write-region "a\r\nb\r\n" nil file))
              (kittymacs-remote-start--newlines-saved file "c\n")))
          (kittymacs-remote-start-value 'newlines-local
            (let ((file (make-temp-file "kittymacs-newlines-")))
              (delete-file file)
              (prog1 (kittymacs-remote-start--newlines-saved file "one\n")
                (delete-file file))))
          (kittymacs-remote-start-value 'newlines-named
            (let ((file (kittymacs-remote-fixture-name "newlines-named")))
              (with-current-buffer (generate-new-buffer "no file yet")
                (insert "one\n")
                (write-file file)
                (kill-buffer))
              (with-temp-buffer
                (set-buffer-multibyte nil)
                (insert-file-contents-literally file)
                (buffer-string)))))
      (setq-default buffer-file-coding-system default))))

(defun kittymacs-remote-start--windows-file ()
  "A file under /mnt/ on a WSL backend: one message, and no connection."
  (kittymacs-remote-start-value 'windows-file-names
    (mapcar #'kittymacs-remote--windows-file
            '("/wslm:Fake-24.04:/mnt/c/Users/me/a.txt"
              "/wslm:Fake-24.04:/mnt/d"
              "/wslm:Fake-24.04:/mnt/wsl/a"
              "/wslm:Fake-24.04:/home/me/mnt/c/a"
              "/ssh:build:/mnt/c/a"
              "/mnt/c/a")))
  (kittymacs-remote-start-value 'windows-file-hook
    (and (memq #'kittymacs--remote-note-windows-file find-file-hook) t))
  (kittymacs-remote-start-value 'windows-file-said
    (kittymacs-remote-start--windows-file-notes "/wslm:Fake-24.04:/mnt/c/once.txt"))
  (kittymacs-remote-start-value 'windows-file-silent
    (kittymacs-remote-start--windows-file-notes "/wslm:Fake-24.04:/home/me/a.txt"))
  (kittymacs-remote-start-value 'windows-file-note
    (let ((kittymacs-remote-windows-file-note "An extra word."))
      (kittymacs-remote-start--windows-file-notes "/wslm:Fake-24.04:/mnt/c/noted.txt")))
  (kittymacs-remote-start-value 'windows-file-reopen
    (let ((file (make-temp-file "kittymacs-windows-")))
      (cl-letf (((symbol-function 'find-alternate-file)
                 (lambda (name) (setq file (list 'reopened name)))))
        (with-temp-buffer
          (setq buffer-file-name "/wslm:Fake-24.04:/mnt/c/a.txt")
          (kittymacs-remote-reopen-natively)
          (setq buffer-file-name nil)))
      file))
  (kittymacs-remote-start-value 'windows-file-reopen-elsewhere
    (with-temp-buffer
      (condition-case _ (kittymacs-remote-reopen-natively)
        (user-error 'refused)))))

(defun kittymacs-remote-start--local ()
  "Report what the guards do to a local buffer: nothing."
  (kittymacs-remote-start--fake-programs)
  (let ((file (kittymacs-remote-fixture--path "local/a.py")))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert "import os\n"))
    (with-current-buffer (find-file-noselect file)
      (kittymacs-remote-start-value 'local-remote-p (kittymacs-remote-buffer-p))
      (when (boundp 'flymake-diagnostic-functions)
        (kittymacs-remote-start-value 'local-collection-checkers
          (seq-filter (lambda (f) (and (symbolp f) (string-prefix-p "flymake-collection" (symbol-name f))))
                      flymake-diagnostic-functions)))
      (kittymacs-remote-start-value 'local-agent-path (kittymacs-remote-agent-path "/some/path/"))
      (kittymacs-remote-start-value 'local-shell
        (let ((explicit-shell-file-name "/local/shell"))
          (with-connection-local-variables explicit-shell-file-name)))
      (when (fboundp 'corfu-mode)
        (require 'corfu-auto)
        (kittymacs-remote-start-value 'local-auto-sources
          (let ((seen nil))
            (defalias 'kittymacs-remote-start--spy (lambda () (setq seen t) nil))
            (let ((completion-at-point-functions '(kittymacs-remote-start--spy)))
              (corfu-auto--complete-deferred))
            seen)))
      (kittymacs-remote-start-value 'local-file-remote-p-seconds
        (car (benchmark-run 100000 (kittymacs-remote-buffer-p))))
      (kittymacs-remote-start-value 'local-auto-save-file
        (progn (auto-save-mode 1) (and buffer-auto-save-file-name t))))))

(defun kittymacs-remote-start--wsl ()
  "The `wsl' transport: refused without `wsl.exe', and connecting through a stand-in."
  (kittymacs-remote-start-value 'wsl-refused
    (let ((exec-path nil))
      (condition-case err (kittymacs-backend-root "wsl")
        (user-error (cadr err)))))
  (let* ((bin (kittymacs-remote-fixture-wsl-exe))
         (exec-path (cons bin exec-path))
         (process-environment
          (cons (concat "PATH=" bin path-separator (getenv "PATH")) process-environment))
         (root (kittymacs-backend-root "wsl")))
    (kittymacs-remote-start-value 'wsl-root root)
    (kittymacs-remote-start-value 'wsl-nameless
      (condition-case err (kittymacs-backend-root "wsl-nameless")
        (user-error (cadr err))))
    (kittymacs-remote-start-value 'wsl-row-login
      (prin1-to-string (assq 'tramp-login-args
                             (assoc kittymacs-remote-wsl-method tramp-methods))))
    (kittymacs-remote--apply-backend "wsl")
    (let ((default-directory root))
      (kittymacs-remote-start-value 'wsl-connects (file-directory-p root))
      (kittymacs-remote-start-value 'wsl-direct (tramp-direct-async-process-p))
      (kittymacs-remote-start-value 'wsl-process-file
        (with-temp-buffer
          (list (process-file "/bin/sh" nil t nil "-c" "echo wsl-ran")
                (buffer-string))))
      (kittymacs-remote-start-value 'wsl-direct-process
        (let* ((buffer (generate-new-buffer " *wsl direct*"))
               (process (make-process :name "wsl-direct" :buffer buffer :noquery t
                                      :file-handler t :connection-type 'pipe
                                      :command '("/bin/sh" "-c" "echo wsl-direct-ran")))
               (end (+ (float-time) 20)))
          (while (and (process-live-p process) (< (float-time) end))
            (accept-process-output process 0.1))
          (list (process-exit-status process)
                (with-current-buffer buffer (buffer-string))))))
    (kittymacs-remote-start-value 'wsl-no-such-distribution
      (let ((tramp-connection-timeout 10)
            (name (concat "/" kittymacs-remote-wsl-method ":Nosuch-24.04:/tmp")))
        (condition-case _ (file-exists-p name)
          (error nil))))))

(defun kittymacs-remote-start--terminal ()
  "What `SPC o e' opens: on a remote machine, that machine's, in a buffer of its own."
  (kittymacs-remote-start-value 'terminal-eshell
    ;; The local one first, as it would be: Eshell then has a buffer it could reuse.
    (let* ((kittymacs-terminal-ghostel nil)
           (open (lambda (directory)
                   (with-temp-buffer
                     (setq default-directory directory)
                     (kittymacs-terminal-open))))
           (local (funcall open temporary-file-directory))
           (remote (funcall open (kittymacs-backend-root "here"))))
      (list (buffer-name local) (buffer-name remote)
            (buffer-local-value 'default-directory remote))))
  (when kittymacs-terminal-ghostel
    (kittymacs-remote-start-value 'terminal-slots
      (cl-letf (((symbol-function 'ghostel)
                 (lambda (&optional _) (bound-and-true-p ghostel-buffer-name))))
        (list (let ((default-directory temporary-file-directory)
                    (ghostel-buffer-name "the-local-name"))
                (kittymacs-terminal-open))
              (let ((default-directory (kittymacs-backend-root "here")))
                (kittymacs-terminal-open))))))
  (when (locate-library "ghostel")
    (require 'ghostel)
    (kittymacs-remote-start-value 'terminal-login-shell
      (assoc kittymacs-remote-wsl-method ghostel-tramp-shells))
    ;; The real start, up to the spawn, which needs the native module.
    (let* ((bin (kittymacs-remote-fixture-wsl-exe))
           (exec-path (cons bin exec-path))
           (root (kittymacs-backend-root "wsl"))
           ;; It wraps a local shell in login(1) on a Mac, and `wsl.exe' is never there.
           (ghostel-macos-login-shell nil)
           (spawn (lambda (program args _environment remote)
                    (list program args remote default-directory))))
      (cl-letf (((symbol-function 'ghostel--spawn-pty) spawn))
        (with-temp-buffer
          (setq default-directory root)
          (kittymacs-remote-start-value 'terminal-wsl-spawn (ghostel--start-process))
          (kittymacs-remote-start-value 'terminal-wsl-directory default-directory)
          (setq default-directory (kittymacs-backend-root "here"))
          (kittymacs-remote-start-value 'terminal-other-spawn (ghostel--start-process)))))))

(defun kittymacs-remote-start--working ()
  "A connection that answers: backends, and each program a person would run."
  (kittymacs-remote-start--local)
  (kittymacs-remote-start--windows-file)
  (kittymacs-remote-start--project)
  (kittymacs-remote-start--tool)
  (kittymacs-remote-start--terminal)
  (kittymacs-remote-fixture--script "project/sub/kfake-here" "echo here")
  (kittymacs-remote-start-value 'backend-root (kittymacs-backend-root "here"))
  (kittymacs-remote-start-value 'backend-tramp-method (kittymacs-backend-root "tramp"))
  (kittymacs-remote-start-value 'backend-default-transport (kittymacs-backend-root "default"))
  (kittymacs-remote-start--wsl)
  (kittymacs-remote-start-value 'backend-typo
    (condition-case err (kittymacs-backend-root "typo")
      (user-error (cadr err))))
  (kittymacs-remote-start-value 'backend-dispatch
    (let ((kittymacs-remote-transports
           (cons (cons 'tunnel (lambda (transport backend)
                                 (format "%s|%s" transport (plist-get backend :root))))
                 kittymacs-remote-transports))
          (kittymacs-backends '(("t" :transport tunnel :root "/r/"))))
      (kittymacs-backend-root "t")))
  (kittymacs-remote-start-value 'remote-path-head (car tramp-remote-path))
  (kittymacs-remote-start-value 'remote-path-nix
    (seq-filter (lambda (entry) (member entry tramp-remote-path)) kittymacs-remote-nix-path))
  ;; Before anything connects: a typo in another backend must not have stopped it.
  (kittymacs-remote-start-value 'direct-async-at-load
    (let ((default-directory (kittymacs-backend-root "here")))
      (with-connection-local-variables tramp-direct-async-process)))
  (kittymacs-remote-start-value 'direct-async-opted-out
    (let ((default-directory "/kmock:elsewhere:/"))
      (with-connection-local-variables tramp-direct-async-process)))
  (kittymacs-remote-start-value 'backend-shell
    (let ((default-directory "/kmock:elsewhere:/")
          (explicit-shell-file-name "/local/only/shell"))
      (with-connection-local-variables (list explicit-shell-file-name shell-file-name))))
  (kittymacs-remote-start-value 'no-backend-shell
    (let ((default-directory "/kmock:not-a-backend:/")
          (explicit-shell-file-name "/local/only/shell"))
      (with-connection-local-variables explicit-shell-file-name)))
  (kittymacs-remote-start-value 'doctor
    (let ((kittymacs-backend-tools '("git" "kfake" "no-such-tool-anywhere")))
      (kittymacs-backend-doctor "here")))
  (kittymacs-remote-start-value 'doctor-buffer
    (with-current-buffer "*kittymacs backend*" (buffer-string)))
  (kittymacs-remote-start-value 'setup-advice
    (mapcar
     #'kittymacs-remote--setup-advice
     '((("git" . "/g") ("nix" . "/n"))
       (("git" . "/g") ("rg") ("nix" . "/n") ("claude-agent-acp"))
       (("git" . "/g") ("rg") ("fd") ("nix") ("claude-agent-acp"))
       (("git" . "/g") ("nix") ("claude-agent-acp"))
       (("git" . "/g") ("nix")))))
  (kittymacs-remote-start-value 'own-profile
    (connection-local-set-profile-variables
     'kittymacs-test-settings '((shell-command-switch . "-lc")))
    (connection-local-set-profiles
     '(:application tramp :protocol "kmock" :machine "elsewhere") 'kittymacs-test-settings)
    (let ((default-directory "/kmock:elsewhere:/"))
      (with-connection-local-variables shell-command-switch)))
  (kittymacs-remote-start-value 'connect
    (let ((project-switch-commands 'kittymacs-remote-start--opened)
          opened)
      ;; A symbol, so `project-switch-project' runs it rather than asking for a key.
      (defalias 'kittymacs-remote-start--opened
        (lambda () (interactive) (setq opened project-current-directory-override)))
      (kittymacs-backend-connect "here")
      opened))
  (kittymacs-remote-start-value 'status-names
    (let ((here (kittymacs-backend-root "here"))
          (status (lambda (directory)
                    (let ((default-directory directory))
                      (substring-no-properties (or (kittymacs-remote-mode-line) "none"))))))
      (list (funcall status here)
            (funcall status "/kmock:not-a-backend:/")
            (funcall status "/ssh:nobody-connected-here:/")
            (funcall status temporary-file-directory)
            (let ((kittymacs-backends nil))
              (funcall status here))
            (let ((kittymacs-backends '(("never" :transport wsl :host "Never-24.04" :root "/"))))
              (funcall status "/wslm:Never-24.04:/")))))
  (kittymacs-remote-start-value 'reconnect
    (let* ((root (kittymacs-backend-root "here"))
           (vec (tramp-dissect-file-name root))
           (before (tramp-get-connection-process vec)))
      (kittymacs-backend-reconnect "here")
      (let ((after (tramp-get-connection-process vec)))
        (list (process-live-p before) (and (process-live-p after) t) (eq before after)))))
  (kittymacs-remote-start-value 'reconnect-typo
    (condition-case err (kittymacs-backend-reconnect "typo")
      (user-error 'refused)))
  (kittymacs-remote-start-value 'connect-typo
    (condition-case err (kittymacs-backend-connect "typo")
      (user-error 'refused)))
  (let ((default-directory (kittymacs-backend-root "here")))
    (kittymacs-remote-start-value 'tramp-loaded-on-demand (featurep 'tramp))
    (kittymacs-remote-start-value 'nix-tool (executable-find "kfake" t))
    (kittymacs-remote-start-value 'direct-async
      (with-connection-local-variables tramp-direct-async-process))
    (kittymacs-remote-start-value 'direct-process
      (with-temp-buffer
        (let* ((output (current-buffer))
               (process (make-process :name "direct" :buffer output :noquery t
                                      :command '("kfake") :file-handler t)))
          (kittymacs-remote-start--wait (lambda () (not (process-live-p process))))
          (list (process-exit-status process) (buffer-string)))))
    (kittymacs-remote-start-value 'shell-profile
      (let ((explicit-shell-file-name "/local/only/shell"))
        (with-connection-local-variables explicit-shell-file-name)))
    (kittymacs-remote-start-value 'shell-run
      (let* ((explicit-shell-file-name "/local/only/shell")
             (buffer (get-buffer-create "*remote shell*")))
        (shell buffer)
        (with-current-buffer buffer
          (let ((process (get-buffer-process buffer)))
            (comint-send-string process "echo marker-$((40+2))\n")
            (kittymacs-remote-start--wait
             (lambda () (save-excursion (goto-char (point-min))
                                        (search-forward "marker-42" nil t))))))))
    (kittymacs-remote-start-value 'compile
      (let* ((compilation-buffer (compile "echo compiled-there")))
        (with-current-buffer compilation-buffer
          (kittymacs-remote-start--wait
           (lambda () (not (get-buffer-process compilation-buffer))))
          (save-excursion (goto-char (point-min))
                          (and (search-forward "compiled-there" nil t) t)))))
    (when (fboundp 'magit-status-setup-buffer)
      (kittymacs-remote-start-value 'magit
        (with-current-buffer (magit-status-setup-buffer default-directory)
          (save-excursion (goto-char (point-min))
                          (and (search-forward "a.py" nil t) t)))))
    (when (executable-find "python3")
      (kittymacs-remote-start-value 'eglot
        (require 'eglot)
        (with-current-buffer (find-file-noselect "a.py")
          (let ((eglot-sync-connect 8))
            (eglot 'python-mode (project-current) 'eglot-lsp-server
                   (list "python3" (kittymacs-remote-start--stub-server)) '("python")))
          (kittymacs-remote-start--wait #'eglot-current-server)
          (let ((server (eglot-current-server)))
            (prog1 (list (and server (jsonrpc-running-p server) t)
                         (and (memq 'eglot-completion-at-point completion-at-point-functions) t)
                         (and (memq 'eglot-completion-at-point kittymacs-remote-auto-capfs) t))
              (when server (ignore-errors (eglot-shutdown server))))))))
    (when (fboundp 'cape-file)
      (kittymacs-remote-start-value 'cape-asked
        (with-temp-buffer
          (setq default-directory (kittymacs-backend-root "here"))
          (insert "sub/")
          (and (cape-file) t))))
    (when (fboundp 'corfu-mode)
      (require 'corfu-auto)
      (kittymacs-remote-start-value 'remote-auto-sources
        (with-temp-buffer
          (setq default-directory (kittymacs-backend-root "here"))
          (let* ((seen nil)
                 (safe nil))
            (defalias 'kittymacs-remote-start--unknown (lambda () (setq seen t) nil))
            (defalias 'kittymacs-remote-start--safe (lambda () (setq safe t) nil))
            (let ((completion-at-point-functions
                   '(kittymacs-remote-start--unknown kittymacs-remote-start--safe))
                  (kittymacs-remote-auto-capfs '(kittymacs-remote-start--safe)))
              (corfu-auto--complete-deferred))
            (list :unknown seen :safe safe)))))
    (with-current-buffer (find-file-noselect "a.py")
      (kittymacs-remote-start-value 'auto-save-file buffer-auto-save-file-name)
      (kittymacs-remote-start-value 'watch auto-revert-notify-watch-descriptor)
      (kittymacs-remote-start-value 'revert-remote auto-revert-remote-files)
      (kittymacs-remote-start-value 'envrc
        (list (bound-and-true-p envrc-global-mode) (bound-and-true-p envrc-mode)))))
  (when (locate-library "agent-shell")
    (kittymacs-remote-start-value 'agent
      (require 'agent-shell)
      (let ((default-directory (kittymacs-backend-root "here")))
        (require 'agent-shell-project)
        (let ((request (acp-make-session-new-request
                        :cwd (agent-shell--resolve-path (agent-shell-cwd)))))
          (list :resolver agent-shell-path-resolver-function
                :cwd (map-nested-elt request '(:params cwd))
                :inbound (agent-shell--resolve-path "/inbound/file")))))))

(setq tramp-verbose 0)
(pcase kittymacs-remote-start-scenario
  ('hung (kittymacs-remote-start--hung))
  ('working
   (kittymacs-remote-start--working)
   ;; Last: its connection would otherwise fix the PATH before the fake tools exist.
   (kittymacs-remote-start--newlines))
  ('unreachable
   (kittymacs-remote-start-value 'projects (project-known-project-roots))
   (kittymacs-remote-start-value 'recentf (bound-and-true-p recentf-list))
   ;; The machine that never answers: the status must say so without a login.
   (let ((default-directory "/khang:unreachable:/")
         (kittymacs-backends '(("gone" :transport khang :host "unreachable" :root "/"))))
     (kittymacs-remote-start-value 'status-unreachable
       (substring-no-properties (kittymacs-remote-mode-line))))
   ;; The method whose login never answers, as if it were the WSL one.
   (let ((kittymacs-remote-wsl-method "khang"))
     (kittymacs-remote-start-value 'windows-file-unreachable
       (kittymacs-remote-start--windows-file-notes "/khang:unreachable:/mnt/c/a.txt")))))

(kittymacs-remote-start-report 'login-ran (file-exists-p (kittymacs-remote-fixture-login-marker)))
;; Now ask on purpose, so the test knows this machine really would have stalled.
(when (eq kittymacs-remote-start-scenario 'unreachable)
  (kittymacs-remote-start-probe 'asked
    (file-exists-p (kittymacs-remote-fixture-name "project/" "khang")))
  (kittymacs-remote-start-report 'asked-login-ran
                                 (file-exists-p (kittymacs-remote-fixture-login-marker))))
(kittymacs-remote-start-report 'finished t)
(setq kill-emacs-hook nil)
(kill-emacs 0)

;;; kittymacs-remote-start.el ends here
