;;; kittymacs-org-roam-windows-tests.el --- Real NTFS boundaries -*- lexical-binding: t; -*-
(setq native-comp-enable-subr-trampolines nil)
(load (expand-file-name "kittymacs-org-roam-tests.el"
                        (file-name-directory load-file-name)) nil t)
(defconst kittymacs-roam-windows-test-directory (file-name-directory load-file-name))
(defvar kittymacs-cache-dir)
(defvar kittymacs-roam-windows-fixture (getenv "KITTYMACS_JUNCTION_FIXTURE"))
(when (getenv "KITTYMACS_TEST_PYTHON")
  (setq kittymacs-org-roam-python-executable (getenv "KITTYMACS_TEST_PYTHON")))

(defmacro kittymacs-roam-windows-test (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (and (eq system-type 'windows-nt) kittymacs-roam-windows-fixture))
     (let* ((base (file-name-as-directory kittymacs-roam-windows-fixture))
            (project (expand-file-name "graph/" base))
            (alias (expand-file-name "alias ü space/" base))
            (kittymacs-cache-dir (expand-file-name "db-cache/" base))
            (kittymacs-org-roam-directory project)
            (org-roam-directory project)
            (org-roam-db-location nil)
            (org-id-locations-file (expand-file-name "ids" base))
            (org-id-locations (make-hash-table :test #'equal))
            (org-roam-db--connection (make-hash-table :test #'equal)))
       (unwind-protect (progn ,@body)
         (org-roam-db--close-all)
         (dolist (buffer (buffer-list))
           (when (and (buffer-file-name buffer)
                      (string-prefix-p (downcase base) (downcase (buffer-file-name buffer))))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer)))))))

(ert-deftest kittymacs-roam-windows-junction-identity ()
  (kittymacs-roam-windows-test
    (should (equal (kittymacs-org-roam-db-path project)
                   (kittymacs-org-roam-db-path alias)))
    (kittymacs-org-roam-sync)
    (let ((org-roam-directory alias))
      (kittymacs-org-roam-sync)
      (should (= 1 (hash-table-count org-roam-db--connection)))
      (should (equal '(("one")) (org-roam-db-query [:select id :from nodes])))
      (should (= 1 (length (org-roam-db-query [:select file :from files])))))
    (let ((marker (org-id-find "one" t)))
      (should (markerp marker))
      (set-marker marker nil))))

(ert-deftest kittymacs-roam-windows-junction-boundaries ()
  (kittymacs-roam-windows-test
    (dolist (path '("escape/out.org" "hidden/hidden.org" "secrets/hidden.org"))
      (should-not (kittymacs--org-roam-allowed-p (expand-file-name path project))))
    (let ((org-roam-db-location (expand-file-name "cache-alias/bad.sqlite" base)))
      (should-error (kittymacs--org-roam-scope) :type 'user-error))
    (let ((kittymacs--org-roam-capture-scope (cons project "unused")))
      (should-error (kittymacs--org-roam-capture-target
                     #'identity (expand-file-name "escape/new.org" project))
                    :type 'user-error)
      (should-not (file-exists-p (expand-file-name "outside/new.org" base))))))

(ert-deftest kittymacs-roam-windows-no-escape-reads-or-duplicate-records ()
  (kittymacs-roam-windows-test
    (let ((original (symbol-function 'insert-file-contents-literally)))
      (cl-letf (((symbol-function 'insert-file-contents-literally)
                 (lambda (file &rest args)
                   (should-not (string-match-p "out\\.org" file))
                   (apply original file args))))
        (kittymacs-org-roam-sync)
        (should-error (org-roam-db-update-file
                       (expand-file-name "escape/out.org" project))
                      :type 'user-error)))
    (with-current-buffer (find-file-noselect (expand-file-name "internal/one.org" project))
      (org-roam-db-update-file)
      (should (= 1 (length (org-roam-db-query [:select file :from files])))))))

(ert-deftest kittymacs-roam-windows-missing-and-cycle ()
  (kittymacs-roam-windows-test
    (should (equal (kittymacs--org-roam-path (expand-file-name "missing/a/b.org" alias))
                   (kittymacs--org-roam-path (expand-file-name "missing/a/b.org" project))))
    (should-error (kittymacs--org-roam-path (expand-file-name "notes/one.org/child" project))
                  :type 'user-error)
    (should-error (kittymacs--org-roam-path (expand-file-name "cycle/child" base))
                  :type 'user-error)
    ;; A dangling link resolving to an inside-graph missing target is allowed.
    (should (kittymacs--org-roam-allowed-p (expand-file-name "dangling/new.org" project)))
    (let ((org-roam-directory (expand-file-name "dangling" project)))
      (should-error (kittymacs--org-roam-scope) :type 'user-error))))

(ert-deftest kittymacs-roam-windows-owned-process ()
  (kittymacs-roam-windows-test
    (let (child stderr)
      (kittymacs--org-roam-operation
       (lambda ()
         (kittymacs--org-roam-path project)
         (setq child (aref kittymacs--org-roam-path-context 0))
         (setq stderr (get-buffer-process (aref kittymacs--org-roam-path-context 2)))
         (should (process-live-p child))
         (kittymacs--org-roam-path alias)
         (should (eq child (aref kittymacs--org-roam-path-context 0)))))
      (should-not (process-live-p child))
      (should-not (process-live-p stderr))
      (should-error
       (kittymacs--org-roam-operation
        (lambda ()
          (kittymacs--org-roam-path project)
          (setq child (aref kittymacs--org-roam-path-context 0))
          (error "fixture failure"))))
      (should-not (process-live-p child)))))

(ert-deftest kittymacs-roam-windows-unavailable-python ()
  (kittymacs-roam-windows-test
    (let ((kittymacs-org-roam-python-executable "C:/missing-python/python.exe"))
      (should-error (kittymacs--org-roam-scope) :type 'user-error)
      (should (= 0 (hash-table-count org-roam-db--connection)))
      (with-temp-buffer (org-mode)))))

(ert-deftest kittymacs-roam-windows-protocol-failures-close-child ()
  (kittymacs-roam-windows-test
    (dolist (code '("print('not-json', flush=True)"
                    "print('{\"paths\": []}', flush=True)"
                    "import sys; sys.stderr.write('fixture stderr'); sys.exit(3)"
                    "import time; time.sleep(30)"
                    "import sys; sys.stdin.readline(); print('{\"error\":\"Native Windows CPython with os.path.ALLOW_MISSING is required\"}',flush=True)"))
      (let ((kittymacs--org-roam-python-code code)
            (kittymacs-org-roam-path-timeout 0.5)
            child)
        (should-error
         (kittymacs--org-roam-operation
          (lambda ()
            (unwind-protect (kittymacs--org-roam-path project)
              (setq child (aref kittymacs--org-roam-path-context 0)))))
         :type 'user-error)
        (should (processp child))
        (should-not (process-live-p child))))))

(ert-deftest kittymacs-roam-windows-data-and-reentry ()
  (kittymacs-roam-windows-test
    (kittymacs--org-roam-operation
     (lambda ()
       (let ((paths (list project alias)))
         (should (equal (car (kittymacs--org-roam-native-paths paths))
                        (cadr (kittymacs--org-roam-native-paths paths)))))
       (aset kittymacs--org-roam-path-context 3 t)
       (unwind-protect
           (should-error (kittymacs--org-roam-path project) :type 'user-error)
         (aset kittymacs--org-roam-path-context 3 nil))
       (should (stringp (kittymacs--org-roam-path project)))))
    ;; These are invalid NTFS filename characters, but remain JSON data:
    ;; they cause an OS path error, not Python syntax/code execution.
    (dolist (suffix '("quote\".org" "line\nbreak.org"))
      (should-error (kittymacs--org-roam-path (expand-file-name suffix alias))
                    :type 'user-error))))

(ert-deftest kittymacs-roam-windows-quit-closes-child ()
  (kittymacs-roam-windows-test
    (let (child)
      (condition-case nil
          (kittymacs--org-roam-operation
           (lambda ()
             (kittymacs--org-roam-path project)
             (setq child (aref kittymacs--org-roam-path-context 0))
             (signal 'quit nil)))
        (quit nil))
      (should-not (process-live-p child)))))

(ert-deftest kittymacs-roam-windows-passive-visit-without-python ()
  (kittymacs-roam-windows-test
    (let ((kittymacs-org-roam-python-executable "C:/missing-python/python.exe")
          (file (expand-file-name "outside/out.org" base)))
      (with-current-buffer (find-file-noselect file)
        (should (derived-mode-p 'org-mode))
        (should-error (kittymacs-org-roam-sync) :type 'user-error)
        (kill-buffer)))))

(ert-deftest kittymacs-roam-windows-junction-retarget ()
  (kittymacs-roam-windows-test
    (let* ((link (expand-file-name "retarget" base))
           (first (kittymacs--org-roam-path link))
           (target (if (equal (directory-file-name first)
                              (directory-file-name (kittymacs--org-roam-path project)))
                       (expand-file-name "outside" base) project))
           (script (expand-file-name "org-roam-retarget.ps1"
                                     kittymacs-roam-windows-test-directory)))
      (should (= 0 (call-process "pwsh.exe" nil nil nil "-NoProfile" "-File"
                                 script "-Link" link "-Target" target "-Fixture" base)))
      (should-not (equal first (kittymacs--org-roam-path link)))
      (should (equal (directory-file-name (kittymacs--org-roam-path target))
                     (directory-file-name (kittymacs--org-roam-path link)))))))

(ert-deftest kittymacs-roam-windows-sync-one-process ()
  (kittymacs-roam-windows-test
    (let ((start (float-time)) (launches 0) (requests 0)
          (original-start (symbol-function 'kittymacs--org-roam-python-start))
          (original-request (symbol-function 'kittymacs--org-roam-native-paths)))
      (cl-letf (((symbol-function 'kittymacs--org-roam-python-start)
                 (lambda () (cl-incf launches) (funcall original-start)))
                ((symbol-function 'kittymacs--org-roam-native-paths)
                 (lambda (paths) (cl-incf requests) (funcall original-request paths))))
        (kittymacs-org-roam-sync))
      (message "Native junction sync: %d child, %d fresh requests, %.3fs"
               launches requests (- (float-time) start))
      (should (= launches 1))
      (should (> requests 1)))))
