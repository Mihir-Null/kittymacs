;;; kittymacs-remote-rpc-tests.el --- The wsl-rpc transport, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-remote-rpc-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages.  tests/fake-tramp-rpc stands for tramp-rpc, and a stand-in
;; for `make-process' and `call-process' for wsl.exe.  The real package runs only in
;; the hosted job: tests/wsl-backend/rpc.el.
;;
;; Nothing here may install it either, even with the code under test broken, which
;; once fetched and compiled the real package.  So every way to install records the
;; call and does nothing, here and in each process these tests start.  Recording
;; and not signalling, because `use-package' turns an error into a warning.
(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst kittymacs-rpc-test-no-installs
  '(progn
     (require 'package)
     (require 'use-package)
     (setq package-user-dir (make-temp-file "rpc-test-elpa-" t))
     (defvar kittymacs-rpc-test-installs nil "Each call that would have installed something.")
     (dolist (function '(use-package-vc-install package-vc-install package-install
                         package-vc--unpack package-refresh-contents))
       (advice-add function :override
                   (lambda (&rest arguments) (push arguments kittymacs-rpc-test-installs) nil))))
  "What stops any install, in this process and each one the tests start.")
(eval kittymacs-rpc-test-no-installs t)

(defconst kittymacs-rpc-test-root
  (expand-file-name ".." (file-name-directory (or load-file-name buffer-file-name))))
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-rpc-test-root))
(add-to-list 'load-path (expand-file-name "tests/fake-tramp-rpc" kittymacs-rpc-test-root))
(defconst kittymacs-rpc-test-home
  (file-name-as-directory (make-temp-file "kittymacs-rpc-" t))
  "This run's own `user-emacs-directory', which the Emacs it starts shares.
The defaults write savehist and other state into its cache, so a shared
directory such as /tmp would meet another user's files.")
(setq user-emacs-directory kittymacs-rpc-test-home)
(defvar kittymacs-cache-dir (expand-file-name "cache/" kittymacs-rpc-test-home))
(require 'kittymacs-catalogue)
(require 'kittymacs-remote)

(defvar kittymacs-backends)
(defvar tramp-rpc-fake-seen)
(defvar tramp-rpc-use-controlmaster)
(defvar tramp-rpc-use-direct-ssh-pty)
(defvar ghostel-shell)
(defvar ghostel-use-native-pty)

(defconst kittymacs-rpc-test-backends
  '(("wsl" :transport wsl-rpc :host "Fake-24.04" :root "~/src/")
    ("old" :transport wsl :host "Old-22.04" :root "~/src/")
    ("far" :transport ssh :host "far" :root "/src/")))

(defun kittymacs-rpc-test--in-fresh-emacs (&rest forms)
  "Run FORMS in a new batch Emacs with the tests' `load-path', and return its last output."
  (with-temp-buffer
    (let ((status (apply #'call-process
                         (expand-file-name invocation-name invocation-directory)
                         nil t nil "-Q" "--batch"
                         "-L" (expand-file-name "lisp" kittymacs-rpc-test-root)
                         "-L" (expand-file-name "tests/fake-tramp-rpc" kittymacs-rpc-test-root)
                         "--eval" (format "(setq user-emacs-directory %S)" kittymacs-rpc-test-home)
                         "--eval" (format "(defvar kittymacs-cache-dir %S)" kittymacs-cache-dir)
                         "--eval" (format "%S" kittymacs-rpc-test-no-installs)
                         (seq-mapcat (lambda (form) (list "--eval" (format "%S" form))) forms))))
      (unless (eql status 0) (error "Exit %s: %s" status (buffer-string)))
      (let ((lines (split-string (buffer-string) "\n" t)))
        (car (last lines))))))

(defmacro kittymacs-rpc-test--with-fakes (&rest body)
  "Run BODY as on a machine with `wsl.exe', with nothing really started."
  (declare (indent 0))
  `(let ((kittymacs-backends kittymacs-rpc-test-backends)
         (exec-path (cons (make-temp-file "rpc-test-" t) exec-path)))
     (cl-letf* ((real-find (symbol-function 'executable-find))
                ((symbol-function 'executable-find)
                 (lambda (name &rest rest)
                   (if (equal name "wsl.exe") "C:/Windows/wsl.exe" (apply real-find name rest)))))
       ,@body)))

(defmacro kittymacs-rpc-test--with-module (&rest body)
  "Run BODY with the module and the stand-in for tramp-rpc loaded."
  (declare (indent 0))
  `(kittymacs-rpc-test--with-fakes
     (require 'kittymacs-remote-rpc)
     (require 'tramp-rpc)
     (setq tramp-rpc-fake-seen nil)
     ,@body))

;;; The row

(ert-deftest kittymacs-rpc-row-names-the-distribution-on-the-rpc-method ()
  (kittymacs-rpc-test--with-module
    (should (equal (kittymacs-backend-root "wsl") "/rpc:Fake-24.04:~/src/"))))

(ert-deftest kittymacs-rpc-row-without-the-feature-names-it ()
  (kittymacs-rpc-test--with-fakes
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature &rest _) (not (eq feature 'kittymacs-remote-rpc)))))
      (let ((failure (should-error (kittymacs-remote--wsl-rpc-root
                                    'wsl-rpc '(:host "Fake-24.04" :root "/"))
                                   :type 'user-error)))
        (should (string-match-p "wsl-rpc feature" (cadr failure)))
        (should (string-match-p ":transport wsl" (cadr failure)))))))

(ert-deftest kittymacs-rpc-row-without-a-host-says-so ()
  (kittymacs-rpc-test--with-fakes
    (should-error (kittymacs-remote--wsl-rpc-root 'wsl-rpc '(:root "/")) :type 'user-error)))

;;; Names, which never connect

(ert-deftest kittymacs-rpc-mode-line-prefix-has-the-method ()
  (should (equal (kittymacs-remote--prefix '(:transport wsl-rpc :host "D")) "/rpc:D:"))
  (should (equal (kittymacs-remote--prefix '(:transport wsl :host "D")) "/wslm:D:"))
  (should (equal (kittymacs-remote--prefix '(:transport sshx :host "D")) "/sshx:D:"))
  (should (equal (kittymacs-remote--prefix '(:host "D")) "/ssh:D:")))

(ert-deftest kittymacs-rpc-a-buffer-knows-its-backend ()
  (let ((kittymacs-backends kittymacs-rpc-test-backends)
        (default-directory "/"))
    (cl-letf (((symbol-function 'file-remote-p)
               (lambda (&rest _) "/rpc:Fake-24.04:")))
      (should (equal (kittymacs-remote--buffer-backend) "wsl")))))

(ert-deftest kittymacs-rpc-a-distribution-is-read-from-the-name ()
  (let ((kittymacs-backends kittymacs-rpc-test-backends))
    (should (equal (kittymacs-remote--wsl-distribution "/rpc:Fake-24.04:/home/me/a") "Fake-24.04"))
    (should (equal (kittymacs-remote--wsl-distribution "/wslm:Any:/home/me/a") "Any"))
    ;; Any other /rpc: host is on Linux over ssh.
    (should-not (kittymacs-remote--wsl-distribution "/rpc:far:/mnt/c/a"))
    (should-not (kittymacs-remote--wsl-distribution "/ssh:Fake-24.04:/mnt/c/a"))
    (should-not (kittymacs-remote--wsl-distribution "c:/Users/me/a"))
    (should-not (kittymacs-remote--wsl-distribution nil))))

;;; direnv

(ert-deftest kittymacs-rpc-direnv-variables-survive-inheritenv ()
  "What direnv set, and this scope has, reaches tramp-rpc, and nothing else does."
  (kittymacs-rpc-test--with-module
    (let ((kittymacs-remote--envrc-variables '("FROM_DIRENV=a=b" "NOT_HERE=x" "KEPT=direnv"))
          (process-environment '("FROM_DIRENV=a=b" "KEPT=direnv" "OTHER=y")))
      (let ((result (kittymacs--remote-rpc-direnv-variables '(("KEPT" . "caller")))))
        (should (equal (cdr (assoc "FROM_DIRENV" result)) "a=b"))
        (should (equal (cdr (assoc "KEPT" result)) "caller"))
        (should-not (assoc "NOT_HERE" result))
        (should-not (assoc "OTHER" result))))))

(ert-deftest kittymacs-rpc-direnv-starts-on-a-pipe ()
  "A pty merges direnv's stderr into the JSON that envrc reads."
  (kittymacs-rpc-test--with-module
    (let ((default-directory "/rpc:Fake-24.04:/home/me/")
          seen)
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest arguments) (setq seen arguments) nil)))
        (kittymacs--remote-envrc-export (lambda () (make-process :name "direnv"))))
      (should (eq (plist-get seen :connection-type) 'pipe))
      (should (eq (plist-get seen :file-handler) t))
      (should (equal (plist-get seen :name) "direnv")))))

;;; Saving

(defun kittymacs-rpc-test--precious-after (file attributes)
  "Return `file-precious-flag' after a save's hook, on FILE with ATTRIBUTES.
That is `unset' if the hook left it alone, and it records any connecting."
  (with-temp-buffer
    (let ((buffer-file-name file)
          (asked 0))
      (cl-letf (((symbol-function 'file-attributes)
                 (lambda (&rest _) (cl-incf asked) attributes)))
        (kittymacs--remote-rpc-precious))
      (if (local-variable-p 'file-precious-flag)
          file-precious-flag
        (should (zerop asked))
        'unset))))

(ert-deftest kittymacs-rpc-a-save-replaces-the-file ()
  (kittymacs-rpc-test--with-module
    (should (memq #'kittymacs--remote-rpc-precious (default-value 'before-save-hook)))
    (let ((file "/rpc:Fake-24.04:/home/me/a"))
      ;; A file with one name, and a new one, which has no attributes.
      (should (eq t (kittymacs-rpc-test--precious-after file '(nil 1))))
      (should (eq t (kittymacs-rpc-test--precious-after file nil))))))

(ert-deftest kittymacs-rpc-a-save-keeps-a-link-and-other-names ()
  (kittymacs-rpc-test--with-module
    (let ((file "/rpc:Fake-24.04:/home/me/a"))
      (should-not (kittymacs-rpc-test--precious-after file '("target" 1)))
      (should-not (kittymacs-rpc-test--precious-after file '(nil 2))))))

(ert-deftest kittymacs-rpc-a-save-elsewhere-is-left-alone ()
  (kittymacs-rpc-test--with-module
    (dolist (file '("/wslm:Fake-24.04:/home/me/a" "/rpc:far:/home/me/a"
                    "/ssh:Fake-24.04:/home/me/a" "c:/Users/me/a" nil))
      (should (eq 'unset (kittymacs-rpc-test--precious-after file '(nil 1)))))))

(ert-deftest kittymacs-rpc-the-windows-file-message-follows-the-backend ()
  (let ((kittymacs-backends kittymacs-rpc-test-backends))
    (should (equal (kittymacs-remote--windows-file "/rpc:Fake-24.04:/mnt/c/Users/a.txt") "c:/Users/a.txt"))
    (should (equal (kittymacs-remote--windows-file "/wslm:Any:/mnt/d") "d:/"))
    (should-not (kittymacs-remote--windows-file "/rpc:far:/mnt/c/Users/a.txt"))
    (should-not (kittymacs-remote--windows-file "/rpc:Fake-24.04:/home/mnt/c/a"))))

(ert-deftest kittymacs-rpc-the-terminal-opens-in-the-distribution ()
  (let ((kittymacs-backends kittymacs-rpc-test-backends)
        (ghostel-use-native-pty t)
        (ghostel-shell "local")
        (original (lambda () (list ghostel-shell default-directory))))
    (cl-letf (((symbol-function 'expand-file-name) (lambda (name &rest _) name))
              ((symbol-function 'file-local-name)
               (lambda (name) (replace-regexp-in-string "\\`/[^:]*:[^:]*:" "" name))))
      (let ((default-directory "/rpc:Fake-24.04:/home/me/"))
        (should (equal (car (kittymacs--remote-wsl-terminal original))
                       '("wsl.exe" "-d" "Fake-24.04" "--cd" "/home/me/"))))
      (let ((default-directory "/rpc:far:/home/me/"))
        (should (equal (car (kittymacs--remote-wsl-terminal original)) "local"))))))

;;; The seam

(defun kittymacs-rpc-test--started-by (name)
  "Return the command that starting a server on the host NAME runs."
  (let (command)
    (cl-letf (((symbol-function 'make-process)
               (lambda (&rest arguments) (setq command (plist-get arguments :command)))))
      (tramp-rpc--connect (tramp-dissect-file-name (format "/rpc:%s:/" name))))
    command))

(ert-deftest kittymacs-rpc-seam-rewrites-the-server-start-for-a-backend ()
  (kittymacs-rpc-test--with-module
    (let ((command (kittymacs-rpc-test--started-by "Fake-24.04")))
      (should (equal (seq-take command 6)
                     '("wsl.exe" "-d" "Fake-24.04" "--exec" "/bin/sh" "-c")))
      (should (string-match-p "\\`PATH=[^ ]+ exec tramp-rpc-server\\'" (nth 6 command))))))

(ert-deftest kittymacs-rpc-seam-leaves-any-other-host-on-ssh ()
  (kittymacs-rpc-test--with-module
    (should (equal (car (kittymacs-rpc-test--started-by "far")) "ssh"))
    (should (equal (car (kittymacs-rpc-test--started-by "Old-22.04")) "ssh"))
    (let ((kittymacs-backends nil))
      (should (equal (car (kittymacs-rpc-test--started-by "Fake-24.04")) "ssh")))))

(ert-deftest kittymacs-rpc-seam-leaves-a-hop-on-ssh ()
  "A hop is sudo or a container, which the rewritten command would drop silently."
  (kittymacs-rpc-test--with-module
    (let (command)
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest arguments) (setq command (plist-get arguments :command)))))
        (tramp-rpc--start-server-process
         (tramp-dissect-file-name "/rpc:Fake-24.04|rpc:Fake-24.04:/") "tramp-rpc-server"))
      (should (equal (car command) "ssh")))))

(ert-deftest kittymacs-rpc-seam-leaves-a-local-process-alone ()
  "A timer can start a process during the start, and the rewrite is for `ssh' alone."
  (kittymacs-rpc-test--with-module
    (let (seen)
      (cl-letf (((symbol-function 'make-process)
                 (lambda (&rest arguments) (push (plist-get arguments :command) seen))))
        (kittymacs--remote-rpc-start-server
         (lambda (&rest _) (make-process :name "local" :command '("git" "status")))
         (tramp-dissect-file-name "/rpc:Fake-24.04:/") "tramp-rpc-server"))
      (should (equal seen '(("git" "status")))))))

(ert-deftest kittymacs-rpc-seam-switches-change-only-for-a-backend ()
  (kittymacs-rpc-test--with-module
    (cl-letf (((symbol-function 'make-process) #'ignore))
      (tramp-rpc--connect (tramp-dissect-file-name "/rpc:far:/"))
      (should (equal (car tramp-rpc-fake-seen) '(connect t)))
      (tramp-rpc--connect (tramp-dissect-file-name "/rpc:Fake-24.04:/"))
      (should (equal (car tramp-rpc-fake-seen) '(connect nil))))
    (tramp-rpc--make-pty-process (tramp-dissect-file-name "/rpc:far:/"))
    (should (equal (car tramp-rpc-fake-seen) '(pty t)))
    (tramp-rpc--make-pty-process (tramp-dissect-file-name "/rpc:Fake-24.04:/"))
    (should (equal (car tramp-rpc-fake-seen) '(pty nil)))
    ;; The global values never moved.
    (should (eq tramp-rpc-use-controlmaster t))
    (should (eq tramp-rpc-use-direct-ssh-pty t))))

(ert-deftest kittymacs-rpc-seam-says-so-when-a-private-function-is-gone ()
  (kittymacs-rpc-test--with-module
    (let ((kept (symbol-function 'tramp-rpc--start-server-process))
          warnings)
      (fmakunbound 'tramp-rpc--start-server-process)
      (unwind-protect
          (cl-letf (((symbol-function 'display-warning)
                     (lambda (_type text &rest _) (push text warnings))))
            (kittymacs-remote-rpc--install)
            (should (string-match-p "tramp-rpc--start-server-process" (car warnings)))
            (should (string-match-p ":transport wsl" (car warnings)))
            ;; No fall through to ssh with the distribution as a host.
            (let ((failure (should-error
                            (tramp-rpc-file-name-handler 'file-exists-p "/rpc:Fake-24.04:/a")
                            :type 'user-error)))
              (should (string-match-p "tramp-rpc--start-server-process" (cadr failure))))
            ;; A name that never connects, and every other host, pass.
            (should (eq (tramp-rpc-file-name-handler 'file-remote-p "/rpc:Fake-24.04:/a")
                        'file-remote-p))
            (let ((default-directory "/"))
              (should (eq (tramp-rpc-file-name-handler 'file-exists-p "/rpc:far:/a")
                          'file-exists-p))))
        (advice-remove 'tramp-rpc-file-name-handler #'kittymacs--remote-rpc-refuse)
        (fset 'tramp-rpc--start-server-process kept)))))

;;; The PATH

(ert-deftest kittymacs-rpc-path-has-one-home-and-reaches-nix ()
  (kittymacs-rpc-test--with-module
    (let ((path (split-string (kittymacs-remote-rpc--path) ":")))
      (should (equal (length path) (length (seq-uniq path))))
      ;; The wslm row's, and through the same constant.
      (dolist (directory (split-string kittymacs-remote-wsl-path ":"))
        (should (member directory path)))
      (should (member "/run/current-system/sw/bin" path))
      (dolist (directory '("/run/wrappers/bin"
                           "$HOME/.nix-profile/bin"
                           "/nix/var/nix/profiles/default/bin"
                           "/etc/profiles/per-user/$USER/bin"
                           "$HOME/.local/state/nix/profiles/home-manager/home-path/bin"
                           "$HOME/.local/state/nix/profile/bin"
                           "$HOME/.local/bin"))
        (should (member directory path)))
      ;; No shell expands a tilde inside PATH, and no Windows directory comes in.
      (should-not (seq-some (lambda (directory) (string-search "~" directory)) path))
      (should-not (seq-some (lambda (directory) (string-prefix-p "/mnt/" directory)) path)))))

(ert-deftest kittymacs-rpc-path-the-wslm-row-reads-the-same-constant ()
  (kittymacs-rpc-test--with-fakes
    (require 'tramp)
    (kittymacs-remote--add-wsl-method)
    (should (member (concat "\"PATH=" kittymacs-remote-wsl-path)
                    (flatten-tree (assoc kittymacs-remote-wsl-method tramp-methods))))))

;;; The doctor and the checks before connecting

(defvar kittymacs-rpc-test--calls nil "What a stand-in for `call-process' was asked.")

(defun kittymacs-rpc-test--wsl (output status)
  "Return a stand-in for `call-process' that gives OUTPUT and STATUS, recording its arguments."
  (lambda (program _input destination _display &rest arguments)
    (push (cons program arguments) kittymacs-rpc-test--calls)
    (when destination (insert output))
    status))

(ert-deftest kittymacs-rpc-preflight-reads-utf-16-and-refuses-a-missing-distribution ()
  (kittymacs-rpc-test--with-module
    (cl-letf (((symbol-function 'call-process)
               (kittymacs-rpc-test--wsl "U\0b\0u\0n\0t\0u\0\r\0\n\0D\0e\0b\0i\0a\0n\0\r\0\n\0" 0)))
      (should (equal (kittymacs-wsl-distributions) '("Ubuntu" "Debian")))
      (should-not (kittymacs-remote-rpc-preflight "a" '(:host "Debian")))
      (let ((failure (should-error (kittymacs-remote-rpc-preflight "a" '(:host "Fake-24.04"))
                                   :type 'user-error)))
        (should (string-match-p "Fake-24.04" (cadr failure)))
        (should (string-match-p "Ubuntu, Debian" (cadr failure)))))))

(ert-deftest kittymacs-rpc-preflight-with-no-distribution-says-none ()
  (kittymacs-rpc-test--with-module
    (cl-letf (((symbol-function 'call-process) (kittymacs-rpc-test--wsl "" 1)))
      (should (string-match-p "has none"
                              (cadr (should-error (kittymacs-remote-rpc-preflight "a" '(:host "D"))
                                                  :type 'user-error)))))))

(ert-deftest kittymacs-rpc-the-report-says-what-to-install ()
  (kittymacs-rpc-test--with-module
    (cl-letf* ((real-find (symbol-function 'executable-find))
               ((symbol-function 'executable-find)
                (lambda (name &rest rest)
                  (if (equal name "cat") nil (apply real-find name rest))))
               ((symbol-function 'call-process) (kittymacs-rpc-test--wsl "" 127)))
      (let ((report (kittymacs-remote-rpc-report '(:host "D"))))
        (should-not (plist-get report :server))
        (should-not (plist-get report :cat))
        (should (string-search kittymacs-remote-rpc-revision (plist-get report :text)))
        (should (string-search "cargo install" (plist-get report :text)))
        (should (string-search "kittymacs#rpc-server" (plist-get report :text)))
        (should (string-search "Git for Windows" (plist-get report :text)))))
    (cl-letf (((symbol-function 'call-process) (kittymacs-rpc-test--wsl "/nix/bin/tramp-rpc-server\n" 0)))
      (let ((report (kittymacs-remote-rpc-report '(:host "D"))))
        (should (equal (plist-get report :server) "/nix/bin/tramp-rpc-server"))
        (should-not (string-search "cargo install" (plist-get report :text)))))))

(ert-deftest kittymacs-rpc-the-server-key-is-what-the-doctor-looks-for ()
  (kittymacs-rpc-test--with-module
    (setq kittymacs-rpc-test--calls nil)
    (cl-letf (((symbol-function 'call-process) (kittymacs-rpc-test--wsl "/opt/server\n" 0)))
      (kittymacs-remote-rpc--server '(:host "D" :server "/opt/server")))
    (should (string-match-p "command -v /opt/server\\'" (car (last (car kittymacs-rpc-test--calls)))))))

(defconst kittymacs-rpc-test--untested "A stand-in sentence, for this test."
  "What a test gives `wsl-rpc' as its `:experimental', since no feature has one now.")

(defun kittymacs-rpc-test--labelled ()
  "Return the catalogue with `wsl-rpc' labelled `kittymacs-rpc-test--untested'."
  (mapcar (lambda (entry)
            (if (eq (car entry) 'wsl-rpc)
                (cons 'wsl-rpc (append (list :experimental kittymacs-rpc-test--untested)
                                       (cdr entry)))
              entry))
          kittymacs-catalogue))

(ert-deftest kittymacs-rpc-the-doctor-stops-at-a-missing-server ()
  "It must not ask the machine anything through a transport that cannot start."
  (kittymacs-rpc-test--with-module
    (let ((kittymacs-catalogue (kittymacs-rpc-test--labelled))
          asked)
      (cl-letf (((symbol-function 'call-process)
                 (lambda (_program _input destination _display &rest arguments)
                   (when (and destination (member "--list" arguments))
                     (insert "Fake-24.04\n"))
                   (if (member "--list" arguments) 0 127)))
                ((symbol-function 'kittymacs-remote--tools)
                 (lambda (&rest _) (setq asked t) nil)))
        (should-not (kittymacs-backend-doctor "wsl"))
        (should-not asked)
        (with-current-buffer "*kittymacs backend*"
          (should (string-search "NOT FOUND" (buffer-string)))
          (should (string-search "cargo install" (buffer-string)))
        ;; A backend that cannot start yet still says it.
        (should (string-search (concat "Experimental: " kittymacs-rpc-test--untested)
                               (buffer-string))))))))

(ert-deftest kittymacs-rpc-only-an-experimental-transport-is-labelled ()
  (should-not (kittymacs-remote--experimental 'wsl-rpc))
  (should-not (kittymacs-remote--experimental 'wsl))
  (should-not (kittymacs-remote--experimental 'ssh))
  (let ((kittymacs-catalogue (kittymacs-rpc-test--labelled)))
    (should (equal (kittymacs-remote--experimental 'wsl-rpc) kittymacs-rpc-test--untested))
    (should-not (kittymacs-remote--experimental 'wsl))))

(ert-deftest kittymacs-rpc-the-doctor-reports-processes-through-the-server ()
  (kittymacs-rpc-test--with-module
    (cl-letf (((symbol-function 'call-process)
               (lambda (_program _input destination _display &rest arguments)
                 (when destination
                   (insert (if (member "--list" arguments) "Fake-24.04\n" "/nix/server\n")))
                 0))
              ((symbol-function 'kittymacs-remote--tools) (lambda (&rest _) '(("git" . "/bin/git"))))
              ((symbol-function 'kittymacs-remote--apply-backend) #'ignore)
              ((symbol-function 'file-directory-p) (lambda (&rest _) t)))
      (should (equal (kittymacs-backend-doctor "wsl") '(("git" . "/bin/git"))))
      (with-current-buffer "*kittymacs backend*"
        (should (string-search "Server   /nix/server" (buffer-string)))
        (should (string-search "Processes start through tramp-rpc-server" (buffer-string)))
        (should-not (string-search "Experimental:" (buffer-string)))
        (should-not (string-search "directly" (buffer-string)))))))

;;; kittymacs-open

(ert-deftest kittymacs-rpc-a-name-from-kittymacs-open-takes-the-backend-s-method ()
  (kittymacs-rpc-test--with-module
    (should (equal (kittymacs-remote-rpc--own-name "/wslm:Fake-24.04:/home/me/a b")
                   "/rpc:Fake-24.04:/home/me/a b"))
    ;; A distribution with no such backend stays on wslm, and a local name is left alone.
    (should (equal (kittymacs-remote-rpc--own-name "/wslm:Other:/home/me") "/wslm:Other:/home/me"))
    (should (equal (kittymacs-remote-rpc--own-name "c:/Users/me") "c:/Users/me"))
    (should (equal (kittymacs--remote-rpc-own-names
                    '((("/wslm:Fake-24.04:/a" . (1 . 2))) proc t))
                   '((("/rpc:Fake-24.04:/a" . (1 . 2))) proc t)))))

;;; The Nix package pairs with the Lisp, with no negotiation

(defun kittymacs-rpc-test--nix-field (field)
  "Return the value of the string FIELD in nix/tramp-rpc-server.nix."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "nix/tramp-rpc-server.nix" kittymacs-rpc-test-root))
    (unless (re-search-forward (format "^ *%s = \"\\([^\"]+\\)\";" field) nil t)
      (error "No %s in the Nix package" field))
    (match-string 1)))

(ert-deftest kittymacs-rpc-the-nix-pin-is-the-lisp-pin ()
  (kittymacs-rpc-test--with-module
    (should (equal (kittymacs-rpc-test--nix-field "rev") kittymacs-remote-rpc-revision))
    (should (equal (format "https://github.com/%s/%s" (kittymacs-rpc-test--nix-field "owner")
                           (kittymacs-rpc-test--nix-field "repo"))
                   kittymacs-remote-rpc-repository))
    ;; The template's one line for a distribution without Nix.
    (with-temp-buffer
      (insert-file-contents (expand-file-name "nix/template-wsl-backend/flake.nix"
                                              kittymacs-rpc-test-root))
      (should (search-forward (concat "--rev " kittymacs-remote-rpc-revision) nil t)))
    (should (string-search (format "version %s" (kittymacs-rpc-test--nix-field "version"))
                           (documentation-property 'kittymacs-remote-rpc-revision
                                                   'variable-documentation)))))

;;; The boundary: this package installs on Windows alone

(ert-deftest kittymacs-rpc-the-catalogue-keeps-it-off-everywhere-but-windows ()
  (let ((entry (alist-get 'wsl-rpc kittymacs-catalogue)))
    (should (eq (plist-get entry :profile) 'optional))
    (should (equal (plist-get entry :packages) '(msgpack tramp-rpc)))
    (should (equal (plist-get entry :vc) '(msgpack tramp-rpc)))
    (should-not (memq 'windows-nt (plist-get entry :not-on)))
    (dolist (system '(gnu/linux darwin android))
      (should (memq system (plist-get entry :not-on))))))

(ert-deftest kittymacs-rpc-every-profile-stays-without-it-off-windows ()
  "`KITTYMACS_TEST_PROFILE=every' selects it, and `just install' must still not fetch it."
  (require 'kittymacs-features)
  (let ((system-type 'gnu/linux)
        (every (mapcar #'car kittymacs-catalogue)))
    (should-not (memq 'wsl-rpc (kittymacs-features--compute 'full every nil)))
    (should-not (memq 'wsl-rpc (kittymacs-features--compute 'minimal '(wsl-rpc) nil))))
  (let ((system-type 'windows-nt))
    (should (memq 'wsl-rpc (kittymacs-features--compute 'minimal '(wsl-rpc) nil)))
    (should-not (memq 'wsl-rpc (kittymacs-features--compute 'full nil nil)))))

(ert-deftest kittymacs-rpc-loading-the-module-here-installs-nothing ()
  (should (equal
           (kittymacs-rpc-test--in-fresh-emacs
            '(progn
               (load "kittymacs-remote-rpc" nil t)
               (princ (format "\n%S\n" (list (featurep 'tramp) (featurep 'tramp-rpc)
                                              kittymacs-rpc-test-installs)))))
           "(nil nil nil)"))
  (kittymacs-rpc-test--with-module
    (should-not kittymacs-rpc-test-installs)))

(ert-deftest kittymacs-rpc-compiling-the-module-installs-nothing ()
  "`use-package' installs a `:vc' package while it compiles, so `just compile' would."
  (should (equal
           (kittymacs-rpc-test--in-fresh-emacs
            `(progn
               (setq byte-compile-dest-file-function
                     (lambda (file)
                       (expand-file-name (concat (file-name-nondirectory file) "c")
                                         ,kittymacs-rpc-test-home)))
               (let ((compiled (byte-compile-file
                                ,(expand-file-name "lisp/kittymacs-remote-rpc.el"
                                                   kittymacs-rpc-test-root))))
                 (princ (format "\n%S\n" (list (and compiled t) kittymacs-rpc-test-installs))))))
           "(t nil)")))

(ert-deftest kittymacs-rpc-on-windows-a-start-declares-the-pins-and-loads-neither ()
  "The one test that lifts `system-type', with every way to install replaced."
  (let ((outcome
         (kittymacs-rpc-test--in-fresh-emacs
          '(progn
             (let ((system-type 'windows-nt))
               (load "kittymacs-remote-rpc" nil t))
             (princ (format "\n%S\n"
                            (list (featurep 'tramp) (featurep 'tramp-rpc)
                                  (mapcar (lambda (asked)
                                            (let ((arg (car asked)))
                                              (list (car arg) (plist-get (cadr arg) :lisp-dir)
                                                    (caddr arg))))
                                          (reverse kittymacs-rpc-test-installs)))))))))
    (should (equal (car (read-from-string outcome))
                   '(nil nil
                         ((msgpack nil "5353a7b2da854c843cbec4536996242001f63471")
                          (tramp-rpc "lisp" "543b3bf30b8a80b8cd0200c98d00f22a4e0220ac")))))))

;;; kittymacs-remote-rpc-tests.el ends here
