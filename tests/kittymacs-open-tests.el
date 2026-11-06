;;; kittymacs-open-tests.el --- The command that opens Windows Emacs from WSL -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-open-tests.el -f ert-run-tests-batch-and-exit
;;
;; A real run of nix/kittymacs-open.sh, with a stand-in for emacsclient.exe that
;; records its arguments.  tests/wsl-backend/connect.el runs it on real WSL2.

;;; Code:
(require 'ert)

(defconst kittymacs-open-test-script
  (expand-file-name "../nix/kittymacs-open.sh"
                    (file-name-directory (or load-file-name buffer-file-name))))

(defun kittymacs-open-test--skip ()
  "Skip where the script's one dependency is not GNU's."
  (unless (and (executable-find "sh")
               (eql 0 (call-process "realpath" nil nil nil "-m" "--" "/no/such/file")))
    (ert-skip "It runs in a WSL distribution, and this has no GNU realpath")))

(defun kittymacs-open-test--run (arguments &rest options)
  "Run the script with ARGUMENTS, and return (STATUS OUTPUT CLIENT-ARGUMENTS).
OPTIONS is a plist: `:directory' to run in, `:distro' for $WSL_DISTRO_NAME, by
default Fake-24.04, `:client' for what the stand-in exits with, by default 0, or
`none' for no client at all."
  (let* ((bin (make-temp-file "kittymacs-open-" t))
         (log (expand-file-name "arguments" bin))
         (client (expand-file-name "emacsclient.exe" bin))
         (distro (if (plist-member options :distro) (plist-get options :distro) "Fake-24.04"))
         (exit (or (plist-get options :client) 0))
         (default-directory (or (plist-get options :directory) bin))
         (process-environment
          (append (list (concat "PATH=" bin path-separator (getenv "PATH"))
                        (if distro (concat "WSL_DISTRO_NAME=" distro) "WSL_DISTRO_NAME"))
                  process-environment)))
    (unwind-protect
        (progn
          (unless (eq exit 'none)
            (with-temp-file client
              (insert "#!/bin/sh\nfor a; do printf '%s\\n' \"$a\"; done > "
                      (shell-quote-argument log) "\nexit " (number-to-string exit) "\n"))
            (set-file-modes client #o755))
          (with-temp-buffer
            (let ((status (apply #'call-process "sh" nil t nil kittymacs-open-test-script arguments)))
              (list status (buffer-string)
                    (when (file-exists-p log)
                      (with-temp-buffer
                        (insert-file-contents log)
                        (split-string (buffer-string) "\n" t)))))))
      (delete-directory bin t))))

(defun kittymacs-open-test--names (&rest arguments)
  "Return the names the script gives the client for ARGUMENTS, without its options."
  (seq-remove (lambda (a) (string-prefix-p "--" a))
              (nth 2 (kittymacs-open-test--run arguments))))

(ert-deftest kittymacs-open-a-linux-path-goes-through-the-backend ()
  (kittymacs-open-test--skip)
  (should (equal (kittymacs-open-test--names "/home/me/src")
                 '("/wslm:Fake-24.04:/home/me/src")))
  (should (equal (kittymacs-open-test--names "/home/me/a/../b")
                 '("/wslm:Fake-24.04:/home/me/b")))
  (should (equal (kittymacs-open-test--names "/mnt/wsl/shared")
                 '("/wslm:Fake-24.04:/mnt/wsl/shared")))
  (should (equal (kittymacs-open-test--names "/mntc/x")
                 '("/wslm:Fake-24.04:/mntc/x"))))

(ert-deftest kittymacs-open-a-windows-path-opens-natively ()
  (kittymacs-open-test--skip)
  (should (equal (kittymacs-open-test--names "/mnt/c/Users/me") '("c:/Users/me")))
  (should (equal (kittymacs-open-test--names "/mnt/d") '("d:/")))
  (should (equal (kittymacs-open-test--names "/mnt/d/") '("d:/"))))

(ert-deftest kittymacs-open-with-no-name-opens-this-folder ()
  (kittymacs-open-test--skip)
  (let* ((here (make-temp-file "kittymacs-open-here-" t))
         (real (string-trim (shell-command-to-string
                             (concat "realpath " (shell-quote-argument here))))))
    (unwind-protect
        (should (member (concat "/wslm:Fake-24.04:" real)
                        (nth 2 (kittymacs-open-test--run nil :directory here))))
      (delete-directory here t))))

(ert-deftest kittymacs-open-keeps-each-name-whole ()
  (kittymacs-open-test--skip)
  (should (equal (kittymacs-open-test--names "/home/me/a b" "/mnt/c/Program Files" "/home/me/new file")
                 '("/wslm:Fake-24.04:/home/me/a b"
                   "c:/Program Files"
                   "/wslm:Fake-24.04:/home/me/new file"))))

(ert-deftest kittymacs-open-starts-emacs-when-none-answers ()
  (kittymacs-open-test--skip)
  (let ((options (nth 2 (kittymacs-open-test--run '("/tmp")))))
    (should (member "--no-wait" options))
    (should (member "--alternate-editor=runemacs.exe" options))))

(ert-deftest kittymacs-open-says-what-is-wrong ()
  (kittymacs-open-test--skip)
  (pcase-let ((`(,status ,output ,client) (kittymacs-open-test--run '("/tmp") :distro nil)))
    (should (eql status 1))
    (should (string-search "WSL_DISTRO_NAME" output))
    (should-not client))
  (pcase-let ((`(,status ,output) (kittymacs-open-test--run '("/tmp") :client 'none)))
    (should (eql status 1))
    (should (string-search "KITTYMACS_EMACSCLIENT" output)))
  (pcase-let ((`(,status ,output) (kittymacs-open-test--run '("/tmp") :client 3)))
    (should (eql status 1))
    (should (string-search "Start Windows Emacs" output))))

(ert-deftest kittymacs-open-passes-shellcheck ()
  (skip-unless (executable-find "shellcheck"))
  (with-temp-buffer
    (let ((status (call-process "shellcheck" nil t nil kittymacs-open-test-script)))
      (should (equal (list status (buffer-string)) '(0 ""))))))

;;; kittymacs-open-tests.el ends here
