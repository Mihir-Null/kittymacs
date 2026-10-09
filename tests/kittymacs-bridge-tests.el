;;; kittymacs-bridge-tests.el --- The Linux bridge: parsing, back ends, the wsl method -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-bridge-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages: the bridge depends only on Emacs's own libraries.
;; The TRAMP tests run on Linux against tests/bin/wsl.exe, a stand-in that
;; runs every command on this machine; elsewhere they are skipped.
(require 'ert)
(require 'cl-lib)
(require 'tramp)
(defconst kittymacs-bridge-test-dir (file-name-directory (or load-file-name buffer-file-name)))
(add-to-list 'load-path (expand-file-name "../lisp/" kittymacs-bridge-test-dir))
(require 'kittymacs-bridge)

(defconst kittymacs-bridge-test-bin (expand-file-name "bin/" kittymacs-bridge-test-dir)
  "Where the stand-in wsl.exe lives.")

;;;; Parsing what wsl.exe prints

(ert-deftest kittymacs-bridge-decodes-utf-16-lists ()
  (let ((bytes (encode-coding-string "\ufeffNixOS\r\nArch\r\n\r\n" 'utf-16le)))
    (should (equal (kittymacs-bridge--parse-wsl-list
                    (kittymacs-bridge--decode-wsl-output bytes))
                   '("NixOS" "Arch")))))

(ert-deftest kittymacs-bridge-decodes-utf-8-lists ()
  ;; WSL_UTF8=1 makes wsl.exe print UTF-8 instead.
  (should (equal (kittymacs-bridge--parse-wsl-list
                  (kittymacs-bridge--decode-wsl-output
                   (encode-coding-string "Ubuntu-24.04\nNixOS\n" 'utf-8)))
                 '("Ubuntu-24.04" "NixOS"))))

;;;; Windows share names

(ert-deftest kittymacs-bridge-translates-share-names ()
  (dolist (case '(("\\\\wsl.localhost\\NixOS\\home\\mihir\\a.org" . "/wsl:NixOS:/home/mihir/a.org")
                  ("//wsl.localhost/NixOS/home/mihir/" . "/wsl:NixOS:/home/mihir/")
                  ("\\\\wsl$\\Arch\\etc" . "/wsl:Arch:/etc")
                  ("\\\\WSL.LOCALHOST\\NixOS" . "/wsl:NixOS:/")
                  ("//Wsl$/Ubuntu-24.04/" . "/wsl:Ubuntu-24.04:/")))
    (should (equal (kittymacs-bridge-unc-to-tramp (car case)) (cdr case)))))

(ert-deftest kittymacs-bridge-leaves-other-names-alone ()
  (dolist (name '("C:/Users/mihir" "//server/share/x" "//wsl.localhost/" "//wsl.localhost"
                  "/wsl:NixOS:/home" "//wslx/NixOS/home" "/home/wsl.localhost/NixOS"))
    (should-not (kittymacs-bridge-unc-to-tramp name))))

;;;; Choosing a back end

(defmacro kittymacs-bridge-test-with-wsl (distros &rest body)
  "Run BODY as if wsl.exe were installed with DISTROS, or absent when nil."
  (declare (indent 1))
  `(let ((kittymacs-bridge--wsl-distros ,distros))
     (cl-letf (((symbol-function 'kittymacs-bridge-wsl-available-p)
                (lambda () (and ,distros "/mock/wsl.exe"))))
       ,@body)))

(ert-deftest kittymacs-bridge-defaults-to-the-default-distribution ()
  (kittymacs-bridge-test-with-wsl '("NixOS" "Arch")
    (let ((kittymacs-bridge-backends nil))
      (should (equal (kittymacs-bridge-root) "/wsl:NixOS:"))
      (should (equal (kittymacs-bridge-home) "/wsl:NixOS:~/")))))

(ert-deftest kittymacs-bridge-has-no-back-end-without-wsl ()
  (kittymacs-bridge-test-with-wsl nil
    (let ((kittymacs-bridge-backends nil))
      (should-not (kittymacs-bridge-active))
      (should-not (kittymacs-bridge-root))
      (should-error (kittymacs-bridge-home) :type 'user-error))))

(ert-deftest kittymacs-bridge-prefers-the-first-usable-configured-back-end ()
  (kittymacs-bridge-test-with-wsl '("NixOS")
    (let ((kittymacs-bridge-backends
           '((phone :when (lambda () nil) :transport (local))
             (box :transport (wsl :distro "Arch" :user "mihir") :home "/srv/")
             (later :transport (local)))))
      (should (eq (car (kittymacs-bridge-active)) 'box))
      (should (equal (kittymacs-bridge-home) "/wsl:mihir@Arch:/srv/")))))

(ert-deftest kittymacs-bridge-falls-back-when-nothing-configured-applies ()
  (kittymacs-bridge-test-with-wsl '("NixOS")
    (let ((kittymacs-bridge-backends '((phone :when (lambda () nil) :transport (local)))))
      (should (equal (kittymacs-bridge-root) "/wsl:NixOS:")))))

(ert-deftest kittymacs-bridge-builds-roots-for-every-transport ()
  (kittymacs-bridge-test-with-wsl '("NixOS")
    (should (equal (kittymacs-bridge-root '(x :transport (wsl))) "/wsl:NixOS:"))
    (should (equal (kittymacs-bridge-root '(x :transport (ssh :host "localhost" :port 8022
                                                              :user "nix-on-droid")))
                   "/ssh:nix-on-droid@localhost#8022:"))
    (should (equal (kittymacs-bridge-root '(x :transport (ssh :host "box"))) "/ssh:box:"))
    (should (equal (kittymacs-bridge-root '(x :transport (local))) ""))
    (should-error (kittymacs-bridge-root '(x :transport (carrier-pigeon))) :type 'user-error)))

;;;; The wsl method, end to end against the stand-in

(defun kittymacs-bridge-test-can-run-p ()
  "Non-nil where the stand-in wsl.exe can run: a POSIX shell and iconv."
  (and (memq system-type '(gnu/linux))
       (file-executable-p (expand-file-name "wsl.exe" kittymacs-bridge-test-bin))
       (executable-find "iconv")))

(defvar kittymacs-bridge-test-log nil
  "The stand-in's log of the current test.")

(defmacro kittymacs-bridge-test-with-fake-wsl (&rest body)
  "Run BODY with the stand-in wsl.exe first on the path and a fresh TRAMP."
  `(progn
     (skip-unless (kittymacs-bridge-test-can-run-p))
     (let* ((kittymacs-bridge-test-log (make-temp-file "fake-wsl-log"))
            (exec-path (cons kittymacs-bridge-test-bin exec-path))
            (process-environment
             (append (list (concat "PATH=" kittymacs-bridge-test-bin path-separator
                                   (getenv "PATH"))
                           (concat "KITTYMACS_FAKE_WSL_LOG=" kittymacs-bridge-test-log)
                           "KITTYMACS_FAKE_WSL_DISTROS=NixOS Arch")
                     process-environment))
            (kittymacs-bridge--wsl-distros nil)
            (tramp-verbose 0)
            (tramp-persistency-file-name nil)
            (temporary-file-directory (file-name-as-directory
                                       (make-temp-file "bridge-test" t))))
       (unwind-protect
           (progn
             (tramp-cleanup-all-connections)
             (kittymacs-bridge-enable-wsl-method)
             ,@body)
         (tramp-cleanup-all-connections)
         (delete-directory temporary-file-directory t)
         (delete-file kittymacs-bridge-test-log)))))

(defun kittymacs-bridge-test-log-lines ()
  "Return the stand-in's log, one string per call."
  (with-temp-buffer
    (insert-file-contents kittymacs-bridge-test-log)
    (split-string (buffer-string) "\n" t)))

(defmacro kittymacs-bridge-test-over-pty-and-pipes (&rest body)
  "Run BODY twice: over a pseudo-terminal, and over pipes as on Windows."
  `(dolist (pty '(t nil))
     (let ((tramp-process-connection-type pty))
       (tramp-cleanup-all-connections)
       (ert-info ((format "connection over %s" (if pty "a pty" "pipes")))
         ,@body))))

(ert-deftest kittymacs-bridge-lists-distributions-through-wsl ()
  (kittymacs-bridge-test-with-fake-wsl
   (should (equal (kittymacs-bridge-wsl-distros) '("NixOS" "Arch")))
   (should (equal (kittymacs-bridge--wsl-completion "") '((nil "NixOS") (nil "Arch"))))
   ;; Cached: a second call does not run wsl.exe again.
   (kittymacs-bridge-wsl-distros)
   (should (= (length (kittymacs-bridge-test-log-lines)) 1))))

(ert-deftest kittymacs-bridge-completes-distributions-after-the-method ()
  (kittymacs-bridge-test-with-fake-wsl
   ;; What C-x C-f /wsl: TAB asks: TRAMP answers only while the minibuffer
   ;; is completing a file name.
   (let ((minibuffer-completing-file-name t)
         (non-essential t))
     (should (equal (sort (file-name-all-completions "" "/wsl:") #'string<)
                    '("Arch:" "NixOS:")))
     (should (equal (file-name-all-completions "N" "/wsl:") '("NixOS:"))))))

(ert-deftest kittymacs-bridge-reads-and-writes-files ()
  (kittymacs-bridge-test-with-fake-wsl
   (kittymacs-bridge-test-over-pty-and-pipes
    (let* ((dir (concat "/wsl:Arch:" temporary-file-directory))
           (file (expand-file-name (format "note-%s.org" tramp-process-connection-type) dir))
           (text "* Höhere Mathematik\nλ-calculus, ∂ and ∫\n"))
      (with-temp-file file (insert text))
      (should (file-exists-p file))
      (should (equal (with-temp-buffer (insert-file-contents file) (buffer-string)) text))
      (should (member (file-name-nondirectory file) (directory-files dir)))
      (should (eq (file-attribute-type (file-attributes file)) nil))
      (rename-file file (concat file ".bak"))
      (should-not (file-exists-p file))
      (delete-file (concat file ".bak"))
      (should-not (file-exists-p (concat file ".bak")))))
   (should (seq-some (lambda (line) (string-match-p "\\`-d Arch .*--exec /bin/sh" line))
                     (kittymacs-bridge-test-log-lines)))))

(ert-deftest kittymacs-bridge-passes-the-user ()
  (kittymacs-bridge-test-with-fake-wsl
   (should (file-directory-p (concat "/wsl:" (user-login-name) "@NixOS:/")))
   (should (seq-some (lambda (line)
                       (string-prefix-p (format "-d NixOS -u %s " (user-login-name)) line))
                     (kittymacs-bridge-test-log-lines)))))

(ert-deftest kittymacs-bridge-runs-processes-in-the-distribution ()
  (kittymacs-bridge-test-with-fake-wsl
   (kittymacs-bridge-test-over-pty-and-pipes
    (let ((default-directory (concat "/wsl:Arch:" temporary-file-directory)))
      (should (equal (with-temp-buffer
                       (process-file "sh" nil t nil "-c" "printf %s \"$WSL_DISTRO_NAME\"")
                       (buffer-string))
                     "Arch"))
      (should (equal (string-trim (shell-command-to-string "pwd"))
                     (directory-file-name temporary-file-directory)))))))

(ert-deftest kittymacs-bridge-starts-asynchronous-processes-directly ()
  (kittymacs-bridge-test-with-fake-wsl
   (kittymacs-bridge-test-over-pty-and-pipes
    (let* ((default-directory (concat "/wsl:NixOS:" temporary-file-directory))
           (output "")
           (process (make-process :name "bridge-async" :file-handler t
                                  :command '("sh" "-c" "printf '%s in %s' \"$WSL_DISTRO_NAME\" \"$(pwd)\"")
                                  :filter (lambda (_ text) (setq output (concat output text))))))
      (should (tramp-direct-async-process-p))
      (while (process-live-p process) (accept-process-output process 0.1))
      (accept-process-output nil 0.1)
      ;; The directory matters: without --exec, wsl.exe would hand the
      ;; command line to a login shell and TRAMP's cd would be lost.
      (should (equal output (concat "NixOS in "
                                    (directory-file-name temporary-file-directory))))))
   ;; The direct process was its own wsl.exe call running /bin/sh -c.
   (should (seq-some (lambda (line) (string-match-p "\\`-d NixOS --exec /bin/sh -c " line))
                     (kittymacs-bridge-test-log-lines)))))

(ert-deftest kittymacs-bridge-direct-processes-follow-the-option ()
  (kittymacs-bridge-test-with-fake-wsl
   (let ((default-directory (concat "/wsl:NixOS:" temporary-file-directory)))
     (unwind-protect
         (progn
           (customize-set-variable 'kittymacs-bridge-wsl-direct-async nil)
           (should-not (tramp-direct-async-process-p))
           (customize-set-variable 'kittymacs-bridge-wsl-direct-async t)
           (should (tramp-direct-async-process-p)))
       (customize-set-variable 'kittymacs-bridge-wsl-direct-async t)))))

(ert-deftest kittymacs-bridge-refuses-an-unknown-distribution ()
  (kittymacs-bridge-test-with-fake-wsl
   (let ((tramp-connection-timeout 10))
     (should-error (file-exists-p "/wsl:Nope:/etc/hostname") :type 'file-error))))

(ert-deftest kittymacs-bridge-opens-share-names-through-the-method ()
  (kittymacs-bridge-test-with-fake-wsl
   (let ((file (expand-file-name "shared.txt" temporary-file-directory)))
     (with-temp-file file (insert "from the share\n"))
     (unwind-protect
         (progn
           (kittymacs-bridge-unc-mode 1)
           (let* ((share (concat "\\\\wsl.localhost\\Arch"
                                 (string-replace "/" "\\" file)))
                  (buffer (find-file-noselect share)))
             (unwind-protect
                 (with-current-buffer buffer
                   (should (equal buffer-file-name (concat "/wsl:Arch:" file)))
                   (should (equal (buffer-string) "from the share\n"))
                   (should (file-remote-p default-directory)))
               (kill-buffer buffer))))
       (kittymacs-bridge-unc-mode -1)))
   (should-not (rassq #'kittymacs-bridge--unc-handler file-name-handler-alist))))

;;; kittymacs-bridge-tests.el ends here
