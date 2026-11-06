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
Startup holds the garbage collector off, so a start that waits on Tramp allocates
about 200 MB a second until the machine runs out: this ends that start instead.")

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
