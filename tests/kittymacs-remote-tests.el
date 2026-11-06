;;; kittymacs-remote-tests.el --- A remote machine must not stall Emacs -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PROFILE=full KITTYMACS_TEST_PACKAGES=/path/to/var/elpa \
;;      emacs -Q --batch -l tests/kittymacs-remote-tests.el -f ert-run-tests-batch-and-exit
;;
;; Each scenario is a real start of the configuration in a process of its own, in
;; tests/kittymacs-remote-start.el, which this file can kill when it hangs.  The
;; Tramp methods are in tests/kittymacs-remote-fixture.el, and need no ssh.

;;; Code:
(require 'ert)
(require 'seq)

(defconst kittymacs-remote-test-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

(defconst kittymacs-remote-test-kill-after 150
  "Seconds after which a scenario counts as hung, and is killed.
The same limit for every scenario: a start under load in CI takes tens of seconds.")

(defconst kittymacs-remote-test-start-margin 10
  "Seconds a start with an unreachable project may take beyond one without.
Less than `kittymacs-remote-fixture-hang-timeout', so a start that tried to log in
cannot pass, however slow the machine.")

(defconst kittymacs-remote-test-memory-kb 3000000
  "The address space a scenario may use, in kilobytes.
A start that waits on Tramp allocates about 200 MB a second.  Startup's threshold
keeps that flat, and if a change ever undoes that, this ends the start instead.")

(defvar kittymacs-remote-test-scenarios nil "Results of the scenarios run so far.")

(defun kittymacs-remote-test--run (scenario)
  "Run SCENARIO, and return its alist of results, with `seconds' and `killed'."
  (let* ((result (make-temp-file "kittymacs-remote-result-"))
         (log (generate-new-buffer " *remote scenario*"))
         (process-environment
          (append (list (format "KITTYMACS_REMOTE_SCENARIO=%s" scenario)
                        (format "KITTYMACS_REMOTE_RESULT=%s" result))
                  process-environment))
         (began (float-time))
         ;; A pipe, so the child's stdin stays open and empty: `while-no-input'
         ;; sees no input there, as in a session where nobody is typing.
         (process (make-process
                   :name "remote-scenario" :buffer log :noquery t
                   :connection-type 'pipe
                   :command (list "/bin/sh" "-c"
                                  (format "ulimit -v %d 2>/dev/null; exec \"$0\" \"$@\""
                                          kittymacs-remote-test-memory-kb)
                                  (expand-file-name invocation-name invocation-directory)
                                  "-Q" "--batch" "-l"
                                  (expand-file-name "tests/kittymacs-remote-start.el"
                                                    kittymacs-remote-test-root))))
         killed)
    (while (process-live-p process)
      (accept-process-output process 0.2)
      (when (> (- (float-time) began) kittymacs-remote-test-kill-after)
        (setq killed t)
        (delete-process process)))
    (let ((results (with-temp-buffer
                     (insert-file-contents result)
                     (if (= (point-min) (point-max)) nil (read (current-buffer))))))
      (unless (alist-get 'finished results)
        (message "Scenario %s did not finish; its output:\n%s" scenario
                 (with-current-buffer log (buffer-string))))
      (append (list (cons 'seconds (- (float-time) began)) (cons 'killed killed)) results))))

(defun kittymacs-remote-test--skip-on-a-mac ()
  "Skip a test that needs Tramp to send a long command to this machine.
Here the machine is its own remote.  On macOS `PIPE_BUF' is 512 bytes, and with
the hosted runner's `PATH' a command came to about 700, so Tramp refuses it with
\"Command too long\".  That shows for compile and Eglot.  Direct processes fail
there too, and the log does not say why.  Linux runs all three."
  (when (eq system-type 'darwin)
    (ert-skip "macOS as the remote machine: PIPE_BUF is 512 bytes")))

(defun kittymacs-remote-test--scenario (scenario)
  "Return the results of SCENARIO, running it the first time it is asked for."
  ;; The methods log in with /bin/sh, and hang by a signal.
  (when (eq system-type 'windows-nt) (ert-skip "No /bin/sh"))
  (or (alist-get scenario kittymacs-remote-test-scenarios)
      (setf (alist-get scenario kittymacs-remote-test-scenarios)
            (kittymacs-remote-test--run scenario))))

(defun kittymacs-remote-test--value (scenario key)
  "Return what SCENARIO reported under KEY."
  (alist-get key (kittymacs-remote-test--scenario scenario)))

(defun kittymacs-remote-test--ran-p (scenario key)
  "Return non-nil if SCENARIO reported KEY; a feature that is off reports nothing."
  (assq key (kittymacs-remote-test--scenario scenario)))

;;; Starts

(ert-deftest kittymacs-remote-a-start-leaves-tramp-unloaded ()
  (should (alist-get 'finished (kittymacs-remote-test--scenario 'clean)))
  (should-not (kittymacs-remote-test--value 'clean 'tramp-loaded)))

(ert-deftest kittymacs-remote-an-unreachable-project-cannot-stall-a-start ()
  (let ((clean (kittymacs-remote-test--value 'clean 'start-seconds))
        (unreachable (kittymacs-remote-test--scenario 'unreachable)))
    (should (alist-get 'finished unreachable))
    (should-not (alist-get 'login-ran unreachable))
    (should (< (alist-get 'start-seconds unreachable)
               (+ clean kittymacs-remote-test-start-margin)))
    ;; Not by forgetting it: the project and the recent file are still known.
    (should (seq-some (lambda (root) (string-prefix-p "/khang:" root))
                      (alist-get 'projects unreachable)))
    (when (assq 'recentf unreachable)
      (should (seq-some (lambda (file) (string-prefix-p "/khang:" file))
                        (alist-get 'recentf unreachable))))))

(ert-deftest kittymacs-remote-the-unreachable-machine-really-hangs ()
  "Without this, the test above could pass against a login that fails at once."
  (should (eq (kittymacs-remote-test--value 'unreachable 'asked) 'stalled))
  (should (kittymacs-remote-test--value 'unreachable 'asked-login-ran)))

;;; A connection that has stopped answering

(ert-deftest kittymacs-remote-the-fixture-really-hangs ()
  "Without this, every check below could pass against a healthy connection."
  (should (eq (kittymacs-remote-test--value 'hung 'file-exists-p) 'stalled)))

(ert-deftest kittymacs-remote-no-idle-timer-blocks ()
  (let ((timers (kittymacs-remote-test--value 'hung 'timers)))
    (should timers)
    ;; `with-timeout' is the probe's own timer: its handler stops the probe.
    (should-not (seq-filter (lambda (entry)
                              (and (eq (cdr entry) 'stalled)
                                   (not (eq (car entry) 'lambda))))
                            timers))))

(ert-deftest kittymacs-remote-auto-save-visited-leaves-a-remote-file ()
  (let ((timers (kittymacs-remote-test--value 'hung 'timers)))
    (should (assq 'save-some-buffers timers))
    (should (eq (alist-get 'save-some-buffers timers) 'done))))

(ert-deftest kittymacs-remote-auto-save-does-not-ask-the-connection ()
  (should-not (kittymacs-remote-test--value 'hung 'auto-save-file))
  (should (eq (kittymacs-remote-test--value 'hung 'do-auto-save) 'done)))

(ert-deftest kittymacs-remote-auto-revert-is-already-safe ()
  (should (eq (kittymacs-remote-test--value 'hung 'auto-revert) 'done))
  (should-not (kittymacs-remote-test--value 'working 'watch))
  (should-not (kittymacs-remote-test--value 'working 'revert-remote)))

(ert-deftest kittymacs-remote-mode-line-does-not-ask-the-connection ()
  (should (eq (kittymacs-remote-test--value 'hung 'mode-line) 'done)))

(ert-deftest kittymacs-remote-flymake-collection-stays-local ()
  (skip-unless (kittymacs-remote-test--ran-p 'working 'local-collection-checkers))
  (when (kittymacs-remote-test--value 'working 'local-collection-checkers)
    (should-not (kittymacs-remote-test--value 'hung 'collection-checkers)))
  ;; Flymake runs on save and on request, never from a timer.
  (should-not (kittymacs-remote-test--value 'hung 'flymake-timeout))
  (should-not (kittymacs-remote-test--value 'hung 'flymake-timer)))

(ert-deftest kittymacs-remote-corfu-does-not-read-a-dead-directory ()
  (skip-unless (kittymacs-remote-test--ran-p 'hung 'corfu-auto))
  (should (eq (kittymacs-remote-test--value 'hung 'corfu-auto) 'done)))

(ert-deftest kittymacs-remote-diff-hl-undo-waits-for-a-save ()
  (skip-unless (kittymacs-remote-test--ran-p 'hung 'diff-hl-undo))
  (should (eq (kittymacs-remote-test--value 'hung 'diff-hl-undo) 'done)))

(ert-deftest kittymacs-remote-doom-env-leaves-a-remote-buffer ()
  (skip-unless (kittymacs-remote-test--ran-p 'hung 'doom-env))
  (should (eq (kittymacs-remote-test--value 'hung 'doom-env) 'done))
  (should (eq (kittymacs-remote-test--value 'hung 'doom-update-env) 'done)))

;;; A connection that answers

(ert-deftest kittymacs-remote-backend-names-its-root ()
  (should (string-prefix-p "/kmock:" (kittymacs-remote-test--value 'working 'backend-root)))
  (should (equal (kittymacs-remote-test--value 'working 'backend-tramp-method) "/sshx:build:~/src/"))
  (should (equal (kittymacs-remote-test--value 'working 'backend-default-transport) "/ssh:build:~/src/")))

(ert-deftest kittymacs-remote-transport-is-a-key-the-code-dispatches-on ()
  (should (equal (kittymacs-remote-test--value 'working 'backend-dispatch) "tunnel|/r/"))
  (should (string-match-p "no-such-transport" (kittymacs-remote-test--value 'working 'backend-typo)))
  (should (eq (kittymacs-remote-test--value 'working 'connect-typo) 'refused)))

(ert-deftest kittymacs-remote-wsl-names-what-is-missing ()
  (should (string-match-p "wsl\\.exe" (kittymacs-remote-test--value 'working 'wsl-refused)))
  (should (string-match-p ":host" (kittymacs-remote-test--value 'working 'wsl-nameless))))

(ert-deftest kittymacs-remote-wsl-connects-through-its-row ()
  "Through a stand-in for `wsl.exe' that passes on a Windows `PATH'.
The stand-in cannot relay the two streams separately, and a login shell that sets
its own `PATH' hides the Windows one.  So this reads the row for those two, and the
job in .github/workflows/wsl-backend.yml covers them on real WSL2."
  (kittymacs-remote-test--skip-on-a-mac)
  (should (equal (kittymacs-remote-test--value 'working 'wsl-root) "/wslm:Fake-24.04:/tmp/"))
  (let ((login (kittymacs-remote-test--value 'working 'wsl-row-login)))
    (should (string-match-p "PATH=/usr/local/sbin" login))
    (should (string-match-p "2>&1" login)))
  (should (eq (kittymacs-remote-test--value 'working 'wsl-connects) t))
  (should (equal (kittymacs-remote-test--value 'working 'wsl-process-file) '(0 "wsl-ran\n")))
  (should-not (kittymacs-remote-test--value 'working 'wsl-no-such-distribution)))

(ert-deftest kittymacs-remote-wsl-starts-processes-directly ()
  (kittymacs-remote-test--skip-on-a-mac)
  (should (eq (kittymacs-remote-test--value 'working 'wsl-direct) t))
  (should (equal (kittymacs-remote-test--value 'working 'wsl-direct-process)
                 '(0 "wsl-direct-ran\n"))))

(ert-deftest kittymacs-remote-terminal-opens-on-that-machine ()
  "A local terminal already open must not answer the key in a remote buffer."
  (pcase-let ((`(,local ,remote ,directory)
               (kittymacs-remote-test--value 'working 'terminal-eshell)))
    (should (equal local "*eshell*"))
    (should (string-prefix-p "*eshell@kmock:" remote))
    (should (string-prefix-p "/kmock:" directory)))
  (when (kittymacs-remote-test--ran-p 'working 'terminal-slots)
    (pcase-let ((`(,local ,remote) (kittymacs-remote-test--value 'working 'terminal-slots)))
      (should (equal local "the-local-name"))
      (should (string-prefix-p "*ghostel@kmock:" remote)))))

(ert-deftest kittymacs-remote-wsl-terminal-runs-wsl-exe ()
  "The real `ghostel--start-process', up to the spawn: wsl.exe, local, in the directory.
The job in .github/workflows/wsl-backend.yml runs it against real WSL2."
  (skip-unless (kittymacs-remote-test--ran-p 'working 'terminal-wsl-spawn))
  (pcase-let ((`(,program ,args ,remote ,directory)
               (kittymacs-remote-test--value 'working 'terminal-wsl-spawn)))
    (should (equal program "wsl.exe"))
    (should (equal args '("-d" "Fake-24.04" "--cd" "/tmp/")))
    (should-not remote)
    (should-not (file-remote-p directory)))
  ;; The buffer stays on the backend, so finding a file there looks in Linux.
  (should (equal (kittymacs-remote-test--value 'working 'terminal-wsl-directory)
                 "/wslm:Fake-24.04:/tmp/"))
  ;; No other machine runs it: a kmock terminal still spawns through Tramp.
  (should (nth 2 (kittymacs-remote-test--value 'working 'terminal-other-spawn)))
  ;; If Tramp ever starts it: the login shell, not `:shell' or /bin/sh.
  (should (equal (kittymacs-remote-test--value 'working 'terminal-login-shell)
                 '("wslm" login-shell))))
(ert-deftest kittymacs-remote-status-names-the-backend ()
  (should (equal (kittymacs-remote-test--value 'working 'status-names)
                 ;; Named and connected; no backend's; another; local; no backends set;
                 ;; a backend this Emacs has not connected to.
                 '(" [here]" "none" "none" "none" "none" " [never?]"))))

(ert-deftest kittymacs-remote-status-never-connects ()
  (should (equal (kittymacs-remote-test--value 'unreachable 'status-unreachable) " [gone?]"))
  (should-not (kittymacs-remote-test--value 'unreachable 'login-ran)))

(ert-deftest kittymacs-remote-status-does-not-wait-on-a-hung-connection ()
  (should (kittymacs-remote-test--value 'hung 'status-installed))
  (should (eq (kittymacs-remote-test--value 'hung 'status) 'done))
  (should (eq (kittymacs-remote-test--value 'hung 'status-home) 'done)))

(ert-deftest kittymacs-remote-reconnect-replaces-the-connection ()
  (should (equal (kittymacs-remote-test--value 'working 'reconnect) '(nil t nil)))
  (should (eq (kittymacs-remote-test--value 'working 'reconnect-typo) 'refused)))

(ert-deftest kittymacs-remote-reconnect-gets-out-of-a-hung-connection ()
  (should (equal (kittymacs-remote-test--value 'hung 'reconnect-hung) " [here]")))
(ert-deftest kittymacs-remote-a-new-file-gets-unix-newlines ()
  (should (equal (kittymacs-remote-test--value 'working 'newlines-new) "one\ntwo\n"))
  (should (equal (kittymacs-remote-test--value 'working 'newlines-named) "one\n")))

(ert-deftest kittymacs-remote-an-existing-file-keeps-its-newlines ()
  (should (equal (kittymacs-remote-test--value 'working 'newlines-existing) "a\r\nb\r\nc\r\n")))

(ert-deftest kittymacs-remote-a-local-file-keeps-the-default-newlines ()
  (should (equal (kittymacs-remote-test--value 'working 'newlines-local) "one\r\n")))

(ert-deftest kittymacs-remote-windows-file-reads-the-name ()
  (should (equal (kittymacs-remote-test--value 'working 'windows-file-names)
                 '("c:/Users/me/a.txt" "d:/" nil nil nil nil))))

(ert-deftest kittymacs-remote-windows-file-speaks-once ()
  (should (kittymacs-remote-test--value 'working 'windows-file-hook))
  (let ((said (kittymacs-remote-test--value 'working 'windows-file-said)))
    (should (= (length said) 1))
    (should (string-search "slow" (car said)))
    (should (string-search "c:/once.txt" (car said))))
  (should-not (kittymacs-remote-test--value 'working 'windows-file-silent))
  (should (string-search "An extra word."
                         (car (kittymacs-remote-test--value 'working 'windows-file-note)))))

(ert-deftest kittymacs-remote-windows-file-reopens-when-asked ()
  (should (equal (kittymacs-remote-test--value 'working 'windows-file-reopen)
                 '(reopened "c:/a.txt")))
  (should (eq (kittymacs-remote-test--value 'working 'windows-file-reopen-elsewhere) 'refused)))

(ert-deftest kittymacs-remote-windows-file-check-does-not-connect ()
  (should (= (length (kittymacs-remote-test--value 'unreachable 'windows-file-unreachable)) 1))
  (should-not (kittymacs-remote-test--value 'unreachable 'login-ran))
  (should (eq (kittymacs-remote-test--value 'hung 'windows-file) 'done)))
(ert-deftest kittymacs-remote-doctor-says-what-to-run ()
  "It reports the machine's tools and what to run, and it runs nothing."
  (let ((buffer (kittymacs-remote-test--value 'working 'doctor-buffer)))
    (should (string-search "no-such-tool-anywhere" buffer))
    (should (string-search "Those are separate: no-such-tool-anywhere" buffer)))
  (pcase-let ((`(,nothing ,with-nix ,without-nix ,separate-only ,only-nix)
               (kittymacs-remote-test--value 'working 'setup-advice)))
    (should-not nothing)
    (should (string-search "nix profile install github:Mihir-Null/kittymacs#backend" with-nix))
    (should (string-search "separate: claude-agent-acp" with-nix))
    ;; Without Nix, a plain list comes first, and Nix itself is not on it.
    (should (string-search "  rg fd\n" without-nix))
    (should-not (string-search "  rg fd nix" without-nix))
    (should (string-search "does not have yet" without-nix))
    (should-not (string-search "nix profile" separate-only))
    (should-not only-nix)))

(ert-deftest kittymacs-remote-own-profile-applies-as-documented ()
  (should (equal (kittymacs-remote-test--value 'working 'own-profile) "-lc")))

(ert-deftest kittymacs-remote-connect-opens-the-project ()
  (let ((opened (kittymacs-remote-test--value 'working 'connect)))
    (should (stringp opened))
    (should (string-prefix-p "/kmock:" opened))
    (should (string-suffix-p "project/" opened))))

(ert-deftest kittymacs-remote-doctor-reports-the-tools ()
  (let ((tools (kittymacs-remote-test--value 'working 'doctor))
        (report (kittymacs-remote-test--value 'working 'doctor-buffer)))
    (should (alist-get "git" tools nil nil #'equal))
    (should (string-suffix-p ".nix-profile/bin/kfake" (alist-get "kfake" tools nil nil #'equal)))
    (should (assoc "no-such-tool-anywhere" tools))
    (should-not (alist-get "no-such-tool-anywhere" tools nil nil #'equal))
    (should (string-match-p "no-such-tool-anywhere +not found" report))
    (should (string-match-p "exists" report))))

(ert-deftest kittymacs-remote-tramp-finds-the-nix-profile ()
  (should (eq (kittymacs-remote-test--value 'working 'remote-path-head) 'tramp-own-remote-path))
  (should (equal (kittymacs-remote-test--value 'working 'remote-path-nix)
                 '("~/.nix-profile/bin" "/nix/var/nix/profiles/default/bin" "/run/current-system/sw/bin")))
  (should (string-suffix-p ".nix-profile/bin/kfake" (kittymacs-remote-test--value 'working 'nix-tool))))

(ert-deftest kittymacs-remote-a-backend-starts-processes-directly ()
  (kittymacs-remote-test--skip-on-a-mac)
  (should (eq (kittymacs-remote-test--value 'working 'direct-async-at-load) t))
  (should-not (kittymacs-remote-test--value 'working 'direct-async-opted-out))
  (should (eq (kittymacs-remote-test--value 'working 'direct-async) t))
  (pcase-let ((`(,status ,output) (kittymacs-remote-test--value 'working 'direct-process)))
    (should (eql status 0))
    (should (string-match-p "fake-tool-ran" output))))

(ert-deftest kittymacs-remote-shell-runs-a-program-the-machine-has ()
  (should (equal (kittymacs-remote-test--value 'working 'shell-profile) "/bin/sh"))
  (should (equal (kittymacs-remote-test--value 'working 'no-backend-shell) "/bin/sh"))
  (should (equal (kittymacs-remote-test--value 'working 'backend-shell)
                 '("/custom/shell" "/custom/shell")))
  (should (kittymacs-remote-test--value 'working 'shell-run)))

(ert-deftest kittymacs-remote-compile-runs-there ()
  (kittymacs-remote-test--skip-on-a-mac)
  (should (eq (kittymacs-remote-test--value 'working 'compile) t)))

(ert-deftest kittymacs-remote-magit-runs-there ()
  (skip-unless (kittymacs-remote-test--ran-p 'working 'magit))
  (should (eq (kittymacs-remote-test--value 'working 'magit) t)))

(ert-deftest kittymacs-remote-eglot-runs-there ()
  (kittymacs-remote-test--skip-on-a-mac)
  (skip-unless (kittymacs-remote-test--ran-p 'working 'eglot))
  (should (equal (kittymacs-remote-test--value 'working 'eglot) '(t t t))))

(ert-deftest kittymacs-remote-asking-still-completes-a-file-name ()
  (skip-unless (kittymacs-remote-test--ran-p 'working 'cape-asked))
  (should (eq (kittymacs-remote-test--value 'working 'cape-asked) t)))

(ert-deftest kittymacs-remote-popup-keeps-to-the-safe-sources ()
  (skip-unless (kittymacs-remote-test--ran-p 'working 'remote-auto-sources))
  (should (equal (kittymacs-remote-test--value 'working 'remote-auto-sources)
                 '(:unknown nil :safe t))))

(ert-deftest kittymacs-remote-agent-gets-a-path-the-machine-knows ()
  (skip-unless (kittymacs-remote-test--ran-p 'working 'agent))
  (let ((agent (kittymacs-remote-test--value 'working 'agent)))
    (should (eq (plist-get agent :resolver) 'kittymacs-remote-agent-path))
    (should (string-suffix-p "project" (plist-get agent :cwd)))
    (should-not (file-remote-p (plist-get agent :cwd)))
    (should (string-prefix-p "/kmock:" (plist-get agent :inbound)))
    (should (string-suffix-p ":/inbound/file" (plist-get agent :inbound)))))

(ert-deftest kittymacs-remote-envrc-is-already-safe ()
  (pcase-let ((`(,global ,local) (kittymacs-remote-test--value 'working 'envrc)))
    (when global (should-not local))))

;;; A local buffer

(ert-deftest kittymacs-remote-a-local-buffer-keeps-everything ()
  (should-not (kittymacs-remote-test--value 'working 'local-remote-p))
  (should (equal (kittymacs-remote-test--value 'working 'local-agent-path) "/some/path/"))
  (should (equal (kittymacs-remote-test--value 'working 'local-shell) "/local/shell"))
  (should (eq (kittymacs-remote-test--value 'working 'local-auto-save-file) t))
  (when (kittymacs-remote-test--ran-p 'working 'local-auto-sources)
    (should (eq (kittymacs-remote-test--value 'working 'local-auto-sources) t))))

(ert-deftest kittymacs-remote-a-guard-costs-a-local-buffer-almost-nothing ()
  "One `file-remote-p' on a local directory must stay far below a millisecond."
  (let ((seconds (kittymacs-remote-test--value 'working 'local-file-remote-p-seconds)))
    (message "100000 local checks took %.3f s" seconds)
    (should (< (/ seconds 100000.0) 0.0002))))

;;; kittymacs-remote-tests.el ends here
