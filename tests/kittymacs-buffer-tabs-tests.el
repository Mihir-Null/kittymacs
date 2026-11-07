;;; kittymacs-buffer-tabs-tests.el --- Grouped buffer tabs, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-buffer-tabs-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages: `tab-line' is built in, and draws in batch as well.
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-catalogue)
(require 'kittymacs-features)
(require 'conf-mode)
(require 'shell)
(require 'kittymacs-buffer-tabs)

(defvar tabspaces-mode)

(defmacro kittymacs-buffer-tabs-test-with-buffers (specs &rest body)
  "Make a buffer per (NAME MODE) in SPECS, and run BODY, then kill them."
  (declare (indent 1))
  `(let ((made (mapcar (lambda (spec)
                         (with-current-buffer (generate-new-buffer (car spec))
                           (funcall (cadr spec))
                           (current-buffer)))
                       ,specs)))
     (unwind-protect (progn ,@body)
       (mapc #'kill-buffer made))))

(ert-deftest kittymacs-buffer-tabs-the-catalogue-keeps-it-off-and-installs-nothing ()
  (let ((entry (alist-get 'buffer-tabs kittymacs-catalogue)))
    (should (eq (plist-get entry :profile) 'optional))
    (should (eq (plist-get entry :group) 'look))
    (should-not (plist-get entry :packages))
    (should-not (memq 'buffer-tabs (kittymacs-features--compute 'minimal nil nil)))
    (should-not (memq 'buffer-tabs (kittymacs-features--compute 'full nil nil)))))

(ert-deftest kittymacs-buffer-tabs-groups-by-mode-and-what-derives-from-it ()
  (kittymacs-buffer-tabs-test-with-buffers
      '(("a.el" emacs-lisp-mode) ("b.txt" text-mode) ("c.conf" conf-unix-mode)
        ("d" help-mode) ("e" shell-mode) ("f" fundamental-mode))
    (should (equal (mapcar #'kittymacs-buffer-tabs-group made)
                   '("Code" "Docs" "Config" "Tools" "Terminal" "Buffers")))))

(ert-deftest kittymacs-buffer-tabs-a-space-and-the-two-log-buffers-stay-out ()
  (kittymacs-buffer-tabs-test-with-buffers '((" hidden" fundamental-mode) ("seen" fundamental-mode))
    (get-buffer-create "*Messages*")
    (get-buffer-create "*Completions*")
    (let ((names (mapcar #'buffer-name (kittymacs-buffer-tabs-list))))
      (should (member "seen" names))
      (should-not (member " hidden" names))
      (should-not (member "*Messages*" names))
      (should-not (member "*Completions*" names)))))

(ert-deftest kittymacs-buffer-tabs-a-workspace-shows-only-its-own ()
  (kittymacs-buffer-tabs-test-with-buffers '(("mine" fundamental-mode) ("theirs" fundamental-mode))
    (let ((tabspaces-mode t))
      (cl-letf (((symbol-function 'tabspaces--local-buffer-p)
                 (lambda (buffer) (not (equal (buffer-name buffer) "theirs")))))
        (let ((names (mapcar #'buffer-name (kittymacs-buffer-tabs-list))))
          (should (member "mine" names))
          (should-not (member "theirs" names)))))))

(ert-deftest kittymacs-buffer-tabs-most-recent-first-within-a-group ()
  (kittymacs-buffer-tabs-test-with-buffers '(("one" prog-mode) ("two" prog-mode) ("three" prog-mode))
    (with-current-buffer "two"
      (dolist (buffer (reverse made)) (bury-buffer buffer))
      (switch-to-buffer "three")
      (switch-to-buffer "one")
      (switch-to-buffer "two")
      (let* ((tabs (tab-line-tabs-buffer-groups))
             (names (delq nil (mapcar (lambda (tab) (let ((buffer (alist-get 'buffer tab)))
                                                      (and buffer (buffer-name buffer))))
                                      tabs))))
        (should (equal (seq-take names 3) '("two" "one" "three")))))))

(ert-deftest kittymacs-buffer-tabs-a-tab-move-keeps-the-order ()
  (kittymacs-buffer-tabs-test-with-buffers '(("one" prog-mode) ("two" prog-mode) ("three" prog-mode))
    (let ((names (lambda ()
                   (seq-take (seq-filter (lambda (name) (member name '("one" "two" "three")))
                                         (mapcar #'buffer-name (kittymacs-buffer-tabs-list)))
                             3))))
      (switch-to-buffer "three")
      (switch-to-buffer "two")
      (switch-to-buffer "one")
      (let* ((this-command nil) (last-command 'ignore)
             (before (funcall names)))
        (should (equal before '("one" "two" "three")))
        ;; Press after press, the order holds, in the command and in the redisplay.
        (let ((this-command 'tab-line-switch-to-next-tab))
          (switch-to-buffer "two")
          (should (equal (funcall names) before)))
        (let ((this-command nil) (last-command 'tab-line-switch-to-next-tab))
          (should (equal (funcall names) before)))
        ;; Any other command puts the current buffer first.
        (let ((this-command 'ignore))
          (should (equal (funcall names) '("two" "one" "three"))))))))

(defvar kittymacs-buffer-tabs-test-handler-calls nil
  "What a buffer on the fake machine asked of its file handler.")

(defun kittymacs-buffer-tabs-test-handler (operation &rest _)
  "Record OPERATION, as a connection would see it, and fail."
  (push operation kittymacs-buffer-tabs-test-handler-calls)
  (error "A tab asked the connection: %s" operation))

(ert-deftest kittymacs-buffer-tabs-a-remote-buffer-asks-the-connection-nothing ()
  (kittymacs-buffer-tabs-test-with-buffers '(("remote.py" prog-mode) ("local.py" prog-mode))
    (with-current-buffer "remote.py"
      (setq default-directory "/kittymacs-fake:host:/"
            buffer-file-name "/kittymacs-fake:host:/remote.py"))
    (unwind-protect
        (let ((file-name-handler-alist
               (cons '("\\`/kittymacs-fake:" . kittymacs-buffer-tabs-test-handler)
                     file-name-handler-alist))
              (kittymacs-buffer-tabs-test-handler-calls nil))
          (with-current-buffer "remote.py"
            (switch-to-buffer (current-buffer))
            (dotimes (_ 3)
              (tab-line-format)
              (tab-line-tabs-buffer-groups)
              (kittymacs-buffer-tabs-group))
            (should-not kittymacs-buffer-tabs-test-handler-calls)))
      (with-current-buffer "remote.py"
        (setq buffer-file-name nil default-directory "/")))))

(ert-deftest kittymacs-buffer-tabs-the-handler-would-have-caught-it ()
  "So the test above has teeth: a call that does ask fails."
  (let ((file-name-handler-alist
         (cons '("\\`/kittymacs-fake:" . kittymacs-buffer-tabs-test-handler)
               file-name-handler-alist))
        (kittymacs-buffer-tabs-test-handler-calls nil))
    (should-error (file-exists-p "/kittymacs-fake:host:/remote.py"))
    (should kittymacs-buffer-tabs-test-handler-calls)))

(ert-deftest kittymacs-buffer-tabs-its-keys-go-with-the-tabs ()
  (should global-tab-line-mode)
  (with-temp-buffer
    (rename-buffer "kittymacs-tab-test" t)
    (tab-line-mode 1)
    (should (eq (key-binding (kbd "C-<tab>")) 'tab-line-switch-to-next-tab))
    (should (eq (key-binding (kbd "C-S-<tab>")) 'tab-line-switch-to-prev-tab))
    (should (eq (key-binding (kbd "C-<iso-lefttab>")) 'tab-line-switch-to-prev-tab))
    (tab-line-mode -1)
    (should-not (eq (key-binding (kbd "C-<tab>")) 'tab-line-switch-to-next-tab))))

(ert-deftest kittymacs-buffer-tabs-its-toggle-is-the-window-managers ()
  "`SPC t b' and `toggle-tabbed' must press one switch."
  (should (eq (keymap-lookup kittymacs-toggle-map "b") 'global-tab-line-mode))
  (with-temp-buffer
    (insert-file-contents (expand-file-name "../lisp/kittymacs-exwm.el"
                                            (file-name-directory
                                             (locate-library "kittymacs-buffer-tabs"))))
    (should (search-forward "(toggle-tabbed . global-tab-line-mode)" nil t))))

;;; kittymacs-buffer-tabs-tests.el ends here
