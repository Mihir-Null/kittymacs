;;; kittymacs-quickstart-tests.el --- Starting from the quickstart file -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-quickstart-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages: each test makes a package directory of small packages and an
;; archive in a temporary folder.  Each step of a test is a separate Emacs, because
;; what is under test is what one start leaves for the next.

;;; Code:
(require 'ert)
(require 'bytecomp)
(require 'cl-lib)
(require 'seq)

(defconst kittymacs-quickstart-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun kittymacs-quickstart-test--write (file &rest text)
  "Write the strings TEXT to FILE, making its directory."
  (make-directory (file-name-directory file) t)
  (with-temp-file file (apply #'insert text)))

(defun kittymacs-quickstart-test--package (directory name &optional requires)
  "Make the installed package NAME-1.0 in DIRECTORY, with the list REQUIRES."
  (let ((dir (expand-file-name (format "%s-1.0/" name) directory)))
    (kittymacs-quickstart-test--write
     (expand-file-name (format "%s-pkg.el" name) dir)
     (format ";; -*- no-byte-compile: t; lexical-binding: nil -*-\n(define-package %S \"1.0\" \"Test.\" '%S)\n"
             (symbol-name name)
             (mapcar (lambda (req) (list req "1.0")) requires)))
    (kittymacs-quickstart-test--write
     (expand-file-name (format "%s-autoloads.el" name) dir)
     ";;; -*- lexical-binding: t -*-\n"
     "(add-to-list 'load-path (directory-file-name (file-name-directory load-file-name)))\n"
     (format "(autoload '%s-hello %S)\n" name (symbol-name name))
     (format "(provide '%s-autoloads)\n" name))
    (kittymacs-quickstart-test--write
     (expand-file-name (format "%s.el" name) dir)
     ";;; -*- lexical-binding: t -*-\n"
     (format "(defun %s-hello () 'hello)\n(provide '%s)\n" name name))))

(defun kittymacs-quickstart-test--archive (directory)
  "Make an archive in DIRECTORY offering `new', which needs the installed `foo'."
  (kittymacs-quickstart-test--write
   (expand-file-name "archive-contents" directory)
   "(1 (new . [(1 0) ((foo (1 0))) \"Test.\" single nil]))\n")
  (kittymacs-quickstart-test--write
   (expand-file-name "new-1.0.el" directory)
   ";;; new.el --- Test -*- lexical-binding: t -*-\n"
   ";; Version: 1.0\n;; Package-Requires: ((foo \"1.0\"))\n"
   ";;; Code:\n;;;###autoload\n(defun new-hello () 'hello)\n(provide 'new)\n;;; new.el ends here\n"))

(defun kittymacs-quickstart-test--start (root &rest forms)
  "Run FORMS in a new Emacs that has read early-init.el with ROOT as its home.
Return the last form's value.  Fail if that Emacs did not exit cleanly."
  (let* ((elpa (expand-file-name "var/elpa/" root))
         (result (make-temp-file "kittymacs-quickstart-result-"))
         (script (make-temp-file "kittymacs-quickstart-script-" nil ".el"))
         (output (generate-new-buffer " *quickstart test*")))
    (with-temp-file script
      (insert ";;; -*- lexical-binding: t; -*-\n")
      (let ((print-length nil) (print-level nil))
        (prin1 `(with-temp-file ,result (prin1 (progn ,@forms) (current-buffer)))
               (current-buffer))))
    (unwind-protect
        (let ((status (call-process
                       (expand-file-name invocation-name invocation-directory)
                       nil output nil
                       "-Q" "--batch"
                       "--eval" (format "(setq user-emacs-directory %S)" (file-name-as-directory root))
                       "-l" (expand-file-name "early-init.el" kittymacs-quickstart-test-root)
                       "--eval" (format "(setq package-user-dir %S)" elpa)
                       "-l" script)))
          (unless (eql status 0)
            (ert-fail (list 'emacs-failed status
                            (with-current-buffer output (buffer-string)))))
          (with-temp-buffer
            (insert-file-contents result)
            (read (current-buffer))))
      (kill-buffer output)
      (delete-file result)
      (delete-file script))))

(defconst kittymacs-quickstart-test--report
  '(list :loaded kittymacs-quickstart-loaded
         :alist (sort (mapcar #'car package-alist) #'string<)
         :active (sort (copy-sequence package-activated-list) #'string<)
         :package.el (and (featurep 'package) t)
         :trap (boundp 'kittymacs-quickstart-test-trap))
  "What a test asks of a start once its packages have activated.")

(defun kittymacs-quickstart-test--activate (root &rest before)
  "Start in ROOT, run the forms BEFORE, activate, and return the report."
  (apply #'kittymacs-quickstart-test--start root
         (append before
                 (list '(kittymacs-activate-packages)
                       kittymacs-quickstart-test--report))))

(defun kittymacs-quickstart-test--write-file (root &rest before)
  "Write the quickstart file in ROOT, after the forms BEFORE, and return its name."
  (apply #'kittymacs-quickstart-test--start root
         (append before
                 (list '(kittymacs-quickstart-write)
                       '(kittymacs-quickstart-file)))))

(defun kittymacs-quickstart-test--age (file)
  "Set the time of FILE an hour back, so anything touched since is newer."
  (set-file-times file (time-subtract (current-time) 3600)))

(defun kittymacs-quickstart-test--plant-trap (file)
  "Replace the quickstart FILE, compiled, with one that says it was loaded."
  (kittymacs-quickstart-test--write
   file
   ";;; -*- lexical-binding: t -*-\n"
   "(defvar kittymacs-quickstart-test-trap t)\n"
   "(defvar package-activated-list)\n(setq package-activated-list '(trapped))\n")
  (let ((byte-compile-warnings nil)
        (inhibit-message t))
    (byte-compile-file file)))

(defmacro kittymacs-quickstart-test-with (root &rest body)
  "Run BODY with ROOT a checkout's home holding the installed packages foo and bar."
  (declare (indent 1))
  `(let ((,root (file-name-as-directory (make-temp-file "kittymacs-quickstart-" t))))
     (unwind-protect
         (progn
           (kittymacs-quickstart-test--package (expand-file-name "var/elpa/" ,root) 'foo)
           (kittymacs-quickstart-test--package (expand-file-name "var/elpa/" ,root) 'bar '(foo))
           ,@body)
       (delete-directory ,root t))))

;;; With no file, nothing changes

(ert-deftest kittymacs-quickstart-no-file-means-the-scan-it-always-was ()
  (kittymacs-quickstart-test-with root
    (let ((report (kittymacs-quickstart-test--activate root)))
      (should-not (plist-get report :loaded))
      (should (equal (plist-get report :alist) '(bar foo)))
      (should (equal (plist-get report :active) '(bar foo)))
      (should (plist-get report :package.el)))
    (should (kittymacs-quickstart-test--start
             root '(progn (kittymacs-activate-packages) package--initialized)))
    (should-not (file-directory-p (expand-file-name "var/cache/" root)))))

;;; With the file

(ert-deftest kittymacs-quickstart-a-start-uses-the-file ()
  "Only a start that read the file leaves `package-alist' empty and package.el unloaded."
  (kittymacs-quickstart-test-with root
    (should (file-exists-p (kittymacs-quickstart-test--write-file root)))
    (let ((report (kittymacs-quickstart-test--activate root)))
      (should (plist-get report :loaded))
      (should-not (plist-get report :alist))
      (should (equal (plist-get report :active) '(bar foo)))
      (should-not (plist-get report :package.el)))
    (should (kittymacs-quickstart-test--start
             root
             '(progn (kittymacs-activate-packages)
                     (and (fboundp 'foo-hello)
                          (eq (foo-hello) 'hello)
                          (require 'bar)))))))

(ert-deftest kittymacs-quickstart-remove-turns-it-off ()
  (kittymacs-quickstart-test-with root
    (kittymacs-quickstart-test--write-file root)
    (kittymacs-quickstart-test--start root '(kittymacs-quickstart-remove))
    (should-not (directory-files (expand-file-name "var/cache/" root) nil "quickstart"))
    (should-not (plist-get (kittymacs-quickstart-test--activate root) :loaded))))

;;; A new machine gets the file without asking

(defconst kittymacs-quickstart-test--settle
  `(progn
     (add-to-list 'load-path ,(expand-file-name "lisp" kittymacs-quickstart-test-root))
     (require 'kittymacs-features)
     (kittymacs-quickstart--settle)
     (and (kittymacs-quickstart--written) t))
  "What a start does once it has gone idle; says whether a file exists afterwards.")

(defun kittymacs-quickstart-test--stamp (root)
  "Mark the machine in ROOT as one that started on the default profile."
  (kittymacs-quickstart-test--write (expand-file-name "var/started-on-default" root) "Stamp.\n"))

(ert-deftest kittymacs-quickstart-a-new-machine-gets-the-file ()
  (kittymacs-quickstart-test-with root
    (kittymacs-quickstart-test--stamp root)
    (should (kittymacs-quickstart-test--start root kittymacs-quickstart-test--settle))
    (should (plist-get (kittymacs-quickstart-test--activate root) :loaded))))

(ert-deftest kittymacs-quickstart-a-machine-with-no-stamp-gets-no-file ()
  (kittymacs-quickstart-test-with root
    (dotimes (_ 2)
      (should-not (kittymacs-quickstart-test--start root kittymacs-quickstart-test--settle)))
    (should-not (plist-get (kittymacs-quickstart-test--activate root) :loaded))))

(ert-deftest kittymacs-quickstart-a-failed-install-leaves-no-file ()
  (kittymacs-quickstart-test-with root
    (kittymacs-quickstart-test--stamp root)
    (should-not (kittymacs-quickstart-test--start
                 root '(defvar kittymacs-features--failed '(foo))
                 kittymacs-quickstart-test--settle))))

(ert-deftest kittymacs-quickstart-removing-it-lasts-until-asked ()
  (kittymacs-quickstart-test-with root
    (kittymacs-quickstart-test--stamp root)
    (kittymacs-quickstart-test--start root kittymacs-quickstart-test--settle)
    (kittymacs-quickstart-test--start root '(kittymacs-quickstart-remove))
    (dotimes (_ 2)
      (should-not (kittymacs-quickstart-test--start root kittymacs-quickstart-test--settle)))
    (kittymacs-quickstart-test--write-file root)
    (should-not (file-exists-p (expand-file-name "var/quickstart-off" root)))
    (should (plist-get (kittymacs-quickstart-test--activate root) :loaded))))

(ert-deftest kittymacs-quickstart-writing-it-logs-no-compile-warning ()
  "From this code, and from the refresh Emacs runs after a later install."
  (kittymacs-quickstart-test-with root
    (kittymacs-quickstart-test--write
     (expand-file-name "var/elpa/foo-1.0/foo-autoloads.el" root)
     ";;; -*- lexical-binding: t -*-\n(defun foo-noisy () (foo-defined-nowhere))\n")
    (let ((log '(if (get-buffer byte-compile-log-buffer)
                    (with-current-buffer byte-compile-log-buffer (buffer-string))
                  "")))
      (should-not (string-search
                   "foo-defined-nowhere"
                   (kittymacs-quickstart-test--start
                    root '(kittymacs-quickstart-write) '(package--quickstart-maybe-refresh) log))))))

;;; A file for something else

(ert-deftest kittymacs-quickstart-a-file-for-other-directories-is-never-loaded ()
  "The trap in the file goes off under the directories it was written for, and only there."
  (kittymacs-quickstart-test-with root
    (let* ((other (expand-file-name "other/" root))
           (mine `(setq package-directory-list (list ,other)))
           (file (kittymacs-quickstart-test--write-file root mine)))
      (make-directory other t)
      (kittymacs-quickstart-test--age other)
      (kittymacs-quickstart-test--plant-trap file)
      (should (plist-get (kittymacs-quickstart-test--activate root mine) :trap))
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should-not (plist-get report :trap))
        (should-not (plist-get report :loaded))
        (should (equal (plist-get report :active) '(bar foo))))
      (let ((report (kittymacs-quickstart-test--activate
                     root `(setq package-directory-list (list ,other "/elsewhere/")))))
        (should-not (plist-get report :trap))))))

(ert-deftest kittymacs-quickstart-a-profile-that-moved-is-another-directory ()
  "A Nix profile keeps its path while its contents move to another store path."
  (kittymacs-quickstart-test-with root
    (let* ((first (expand-file-name "store/first" root))
           (second (expand-file-name "store/second" root))
           (profile (expand-file-name "profile" root))
           (mine `(setq package-directory-list (list ,profile))))
      (make-directory first t)
      (make-directory second t)
      (kittymacs-quickstart-test--age first)
      (kittymacs-quickstart-test--age second)
      (make-symbolic-link first profile)
      (kittymacs-quickstart-test--write-file root mine)
      (should (plist-get (kittymacs-quickstart-test--activate root mine) :loaded))
      (delete-file profile)
      (make-symbolic-link second profile)
      (should-not (plist-get (kittymacs-quickstart-test--activate root mine) :loaded)))))

(ert-deftest kittymacs-quickstart-the-name-depends-on-the-emacs-version ()
  (kittymacs-quickstart-test-with root
    (should-not
     (kittymacs-quickstart-test--start
      root '(equal (kittymacs-quickstart-file)
                   (let ((emacs-version "0.1")) (kittymacs-quickstart-file)))))))

;;; A stale file

(ert-deftest kittymacs-quickstart-a-package-added-behind-its-back-makes-it-stale ()
  "A package a shell or another Emacs added: scan now, and be right next time."
  (kittymacs-quickstart-test-with root
    (let ((elpa (expand-file-name "var/elpa/" root))
          (file (kittymacs-quickstart-test--write-file root)))
      (kittymacs-quickstart-test--age (concat file "c"))
      (kittymacs-quickstart-test--package elpa 'added)
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should-not (plist-get report :loaded))
        (should (memq 'added (plist-get report :active))))
      (kittymacs-quickstart-test--start
       root '(kittymacs-activate-packages) '(kittymacs-quickstart--keep-current))
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (plist-get report :loaded))
        (should (memq 'added (plist-get report :active)))))))

(ert-deftest kittymacs-quickstart-a-package-removed-behind-its-back-makes-it-stale ()
  (kittymacs-quickstart-test-with root
    (let ((elpa (expand-file-name "var/elpa/" root))
          (file (kittymacs-quickstart-test--write-file root)))
      (kittymacs-quickstart-test--age (concat file "c"))
      (delete-directory (expand-file-name "bar-1.0" elpa) t)
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should-not (plist-get report :loaded))
        (should (equal (plist-get report :active) '(foo)))))))

(ert-deftest kittymacs-quickstart-a-file-naming-a-deleted-package-does-not-end-startup ()
  "The directory's time is put back, so the file still looks current and loads."
  (kittymacs-quickstart-test-with root
    (let ((elpa (expand-file-name "var/elpa/" root)))
      (kittymacs-quickstart-test--age elpa)
      (kittymacs-quickstart-test--write-file root)
      (delete-directory (expand-file-name "bar-1.0" elpa) t)
      (kittymacs-quickstart-test--age elpa)
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (plist-get report :loaded))
        (should (memq 'bar (plist-get report :active))))
      (should-not (kittymacs-quickstart-test--start
                   root '(kittymacs-activate-packages) '(require 'bar nil t)))
      (should (kittymacs-quickstart-test--start
               root '(kittymacs-activate-packages) '(require 'foo nil t))))))

(ert-deftest kittymacs-quickstart-a-broken-file-scans-and-is-written-again ()
  (kittymacs-quickstart-test-with root
    (let ((file (kittymacs-quickstart-test--write-file root)))
      (kittymacs-quickstart-test--write (concat file "c") "(this does not close")
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (equal (plist-get report :active) '(bar foo))))
      (should-not (file-exists-p (concat file "c")))
      (kittymacs-quickstart-test--start
       root '(kittymacs-activate-packages) '(kittymacs-quickstart--keep-current))
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (plist-get report :loaded))
        (should-not (plist-get report :alist))))))

;;; Packages changing in a session that started from the file

(defconst kittymacs-quickstart-test--load-ensure
  `(progn
     (require 'use-package)
     (require 'seq)
     (defvar kittymacs--archives-refreshed nil)
     (with-temp-buffer
       (insert-file-contents ,(expand-file-name "init.el" kittymacs-quickstart-test-root))
       (condition-case nil
           (while t
             (let ((form (read (current-buffer))))
               (when (and (eq (car-safe form) 'defun)
                          (eq (cadr form) 'kittymacs-ensure-package))
                 (eval form t))))
         (end-of-file nil))))
  "Define `kittymacs-ensure-package' from init.el, and nothing else from that file.")

(defun kittymacs-quickstart-test--archive-settings (archive)
  "Return a form that makes the local ARCHIVE the only one."
  `(setq package-archives '(("local" . ,archive))
         package-check-signature nil
         package-selected-packages nil
         custom-file ,(make-temp-file "kittymacs-quickstart-custom-")))

(ert-deftest kittymacs-quickstart-a-missing-package-still-installs ()
  "A feature selected since the file was written: the start installs it, without
reinstalling what it needs, and the next start has it from the file."
  (kittymacs-quickstart-test-with root
    (let* ((archive (expand-file-name "archive/" root))
           (settings (kittymacs-quickstart-test--archive-settings archive)))
      (kittymacs-quickstart-test--archive archive)
      (kittymacs-quickstart-test--write-file root)
      (let ((after (kittymacs-quickstart-test--start
                    root settings
                    '(kittymacs-activate-packages)
                    kittymacs-quickstart-test--load-ensure
                    '(kittymacs-ensure-package 'new '(t) nil)
                    `(list :refreshed kittymacs--archives-refreshed
                           :loaded kittymacs-quickstart-loaded
                           :installed (package-installed-p 'new)
                           :active (and (memq 'new package-activated-list) t)
                           :hello (fboundp 'new-hello)
                           :current (kittymacs-quickstart--current-p (kittymacs-quickstart-file))))))
        (should (plist-get after :refreshed))
        (should (plist-get after :loaded))
        (should (plist-get after :installed))
        (should (plist-get after :active))
        (should (plist-get after :hello))
        ;; It is stale now, and the hook after init will rewrite it.
        (should-not (plist-get after :current)))
      (should (= 1 (length (directory-files (expand-file-name "var/elpa/" root) nil "\\`foo-"))))
      (kittymacs-quickstart-test--start
       root settings '(kittymacs-activate-packages) '(kittymacs-quickstart--keep-current))
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (plist-get report :loaded))
        (should (equal (plist-get report :active) '(bar foo new)))))))

(ert-deftest kittymacs-quickstart-a-package-on-disk-is-not-fetched-again ()
  "`foo' is active, and `broken' is on disk, though what it needs is not, so the file
did not activate it.  A scan would call both installed, so no refresh may follow."
  (kittymacs-quickstart-test-with root
    (kittymacs-quickstart-test--package (expand-file-name "var/elpa/" root) 'broken '(gone))
    (kittymacs-quickstart-test--write-file root)
    (let ((after (kittymacs-quickstart-test--start
                  root
                  '(setq package-archives nil)
                  '(kittymacs-activate-packages)
                  kittymacs-quickstart-test--load-ensure
                  '(kittymacs-ensure-package 'foo '(t) nil)
                  '(setq kittymacs-quickstart-test-before (bound-and-true-p package--initialized))
                  '(kittymacs-ensure-package 'broken '(t) nil)
                  `(list :before kittymacs-quickstart-test-before
                         :refreshed kittymacs--archives-refreshed
                         :initialized package--initialized
                         :active (and (memq 'broken package-activated-list) t)))))
      (should-not (plist-get after :before))
      (should-not (plist-get after :refreshed))
      (should (plist-get after :initialized))
      (should-not (plist-get after :active)))))

(ert-deftest kittymacs-quickstart-installing-and-deleting-in-a-session-refresh-the-file ()
  "After the hook, Emacs's own refresh keeps the file right, with no restart between."
  (kittymacs-quickstart-test-with root
    (let* ((archive (expand-file-name "archive/" root))
           (settings (kittymacs-quickstart-test--archive-settings archive)))
      (kittymacs-quickstart-test--archive archive)
      (kittymacs-quickstart-test--write-file root)
      (kittymacs-quickstart-test--start
       root settings
       '(kittymacs-activate-packages)
       '(kittymacs-quickstart--keep-current)
       '(package-install 'new))
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (plist-get report :loaded))
        (should (memq 'new (plist-get report :active))))
      (kittymacs-quickstart-test--start
       root settings
       '(kittymacs-activate-packages)
       '(kittymacs-quickstart--keep-current)
       '(package-initialize t)
       '(package-delete (cadr (assq 'new package-alist)) t))
      (let ((report (kittymacs-quickstart-test--activate root)))
        (should (plist-get report :loaded))
        (should (equal (plist-get report :active) '(bar foo))))
      ;; What a `:vc' package's install or upgrade calls when it has finished.
      (let ((file (kittymacs-quickstart-test--start root '(kittymacs-quickstart-file))))
        (kittymacs-quickstart-test--age (concat file "c"))
        (kittymacs-quickstart-test--start
         root settings
         '(kittymacs-activate-packages)
         '(kittymacs-quickstart--keep-current)
         '(package--quickstart-maybe-refresh))
        (should (time-less-p (time-subtract (current-time) 600)
                             (file-attribute-modification-time
                              (file-attributes (concat file "c")))))))))

;;; The rule that protects a machine when the default profile moves

(ert-deftest kittymacs-quickstart-a-machine-in-use-still-counts-as-one ()
  "The same answer from a scan and from the file, and a machine with nothing differs."
  (kittymacs-quickstart-test-with root
    (let ((choose `(progn
                     (add-to-list 'load-path ,(expand-file-name "lisp" kittymacs-quickstart-test-root))
                     (require 'kittymacs-features)
                     (setq kittymacs-default-profile 'minimal)
                     (let ((warning-minimum-level :emergency))
                       (kittymacs-features--choose-profile)))))
      (should (eq (kittymacs-quickstart-test--start root '(kittymacs-activate-packages) choose)
                  'full))
      (kittymacs-quickstart-test--write-file root)
      (should (eq (kittymacs-quickstart-test--start
                   root
                   '(kittymacs-activate-packages)
                   `(if package-alist (error "The start did not use the file") ,choose))
                  'full))))
  (let ((empty (file-name-as-directory (make-temp-file "kittymacs-quickstart-" t))))
    (unwind-protect
        (should (eq (kittymacs-quickstart-test--start
                     empty
                     '(kittymacs-activate-packages)
                     `(progn
                        (add-to-list 'load-path ,(expand-file-name "lisp" kittymacs-quickstart-test-root))
                        (require 'kittymacs-features)
                        (setq kittymacs-default-profile 'minimal)
                        (kittymacs-features--choose-profile)))
                    'minimal))
      (delete-directory empty t))))

;;; kittymacs-quickstart-tests.el ends here
