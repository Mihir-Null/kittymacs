;;; kittymacs-shell-detach-tests.el --- A graphical program from M-! does not wait -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-shell-detach-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages.  Loads lisp/kittymacs-shell.el with installs turned off,
;; then stands in for the frame, the launcher and the synchronous command, so
;; nothing starts and nothing waits.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'use-package)
(require 'dired)
(require 'dired-aux)
(require 'dired-x)
(require 'project)

(defconst kittymacs-shell-detach-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-shell-detach-" t)))
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-shell-detach-test-root))
(require 'kittymacs-catalogue)
(require 'kittymacs-features)
(defvar kittymacs-features--enabled)
;; init.el's, which this test does not load.
(defun kittymacs-after-init (&rest _))
(let ((use-package-ensure-function #'ignore)
      (kittymacs-features--enabled nil))
  (require 'kittymacs-shell))

(require 'kittymacs-exwm)
(defvar exwm-wm-mode)
(defconst kittymacs-shell-detach-test--exwm-launch (symbol-function 'kittymacs-exwm-launch)
  "EXWM's launcher, which every start loads, as the module defines it.")

(defvar kittymacs-shell-detach-test--launched nil
  "The commands the stand-in launcher was given, latest first.")
(defvar kittymacs-shell-detach-test--waited nil
  "The commands the stand-in for the synchronous `shell-command' ran, latest first.")

(defun kittymacs-shell-detach-test--wait (command &rest _)
  "Stand in for `shell-command' itself: record COMMAND as run and waited for."
  (push command kittymacs-shell-detach-test--waited)
  0)

(defmacro kittymacs-shell-detach-test--with (graphic &rest body)
  "Run BODY in a GRAPHIC or terminal frame, with a programs directory and stand-ins.
A desktop entry starts `kittymacs-test-real', which `kittymacs-test-link'
links to; one that asks for a terminal starts `kittymacs-test-tui', and one
kept out of menus, a link handler, starts `kittymacs-test-cli'."
  (declare (indent 1))
  `(let* ((root (make-temp-file "kittymacs-shell-detach-" t))
          (bin (expand-file-name "bin" root))
          (applications (expand-file-name "share/applications" root))
          (exec-path (cons bin exec-path))
          (process-environment (cons (concat "XDG_DATA_DIRS=" (expand-file-name "share" root))
                                     (cons (concat "XDG_DATA_HOME=" (expand-file-name "home" root))
                                           process-environment)))
          (kittymacs-gui-programs '("kittymacs-test-listed"))
          (kittymacs-shell-detach-test--launched nil)
          (kittymacs-shell-detach-test--waited nil)
          (default-directory root))
     (make-directory bin t)
     (make-directory applications t)
     (dolist (program '("kittymacs-test-real" "kittymacs-test-tui" "kittymacs-test-cli"))
       (let ((file (expand-file-name program bin)))
         (write-region "#!/bin/sh\n" nil file nil 'silent)
         (set-file-modes file #o755)))
     (make-symbolic-link (expand-file-name "kittymacs-test-real" bin)
                         (expand-file-name "kittymacs-test-link" bin))
     (write-region (format "[Desktop Entry]\nType=Application\nName=Real\nExec=%s %%U\nTerminal=false\n"
                           (expand-file-name "kittymacs-test-real" bin))
                   nil (expand-file-name "real.desktop" applications) nil 'silent)
     (write-region "[Desktop Entry]\nType=Application\nName=TUI\nExec=kittymacs-test-tui\nTerminal=true\n"
                   nil (expand-file-name "tui.desktop" applications) nil 'silent)
     (write-region "[Desktop Entry]\nType=Application\nName=Links\nExec=kittymacs-test-cli %u\nNoDisplay=true\n"
                   nil (expand-file-name "links.desktop" applications) nil 'silent)
     (advice-add 'shell-command :override #'kittymacs-shell-detach-test--wait '((depth . 100)))
     (unwind-protect
         (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) ,graphic))
                   ((symbol-function 'kittymacs-exwm-launch)
                    (lambda (command) (push command kittymacs-shell-detach-test--launched) nil)))
           ,@body)
       (advice-remove 'shell-command #'kittymacs-shell-detach-test--wait)
       (delete-directory root t))))

(defun kittymacs-shell-detach-test--dired-on (file command function)
  "In Dired, on FILE, run FUNCTION as a key would, with COMMAND typed."
  (with-current-buffer (dired-noselect default-directory)
    (unwind-protect
        (progn
          (dired-goto-file (expand-file-name file))
          (if (eq function 'dired-do-shell-command)
              (funcall-interactively function command nil (list file))
            (funcall-interactively function command)))
      (kill-buffer))))

;;; What it decides

(ert-deftest kittymacs-shell-detach-desktop-entries-decide ()
  "An entry outside a terminal makes a program graphical, by name or by file."
  (kittymacs-shell-detach-test--with t
    (should (kittymacs-gui-program-p "kittymacs-test-real"))
    (should (kittymacs-gui-program-p "kittymacs-test-link"))
    (should (kittymacs-gui-program-p "kittymacs-test-listed"))
    (should-not (kittymacs-gui-program-p "kittymacs-test-tui"))
    (should-not (kittymacs-gui-program-p "kittymacs-test-cli"))))

(ert-deftest kittymacs-shell-detach-reads-the-program-from-a-command ()
  (should (equal (kittymacs--command-program "env A=1 B=2 prog --x") "prog"))
  (should (equal (kittymacs--command-program "\"/x y/prog\" %U") "/x y/prog"))
  (should-not (kittymacs--command-program "prog \"unbalanced")))

;;; In a graphical frame: the daemon's, EXWM's, WSLg's or a Mac's

(ert-deftest kittymacs-shell-detach-a-graphical-program-goes-to-the-launcher ()
  "A daemon's graphical frame, with EXWM not loaded, as with EXWM."
  (kittymacs-shell-detach-test--with t
    (funcall-interactively #'shell-command "kittymacs-test-link https://example.org")
    (should (equal kittymacs-shell-detach-test--launched '("kittymacs-test-link https://example.org")))
    (should-not kittymacs-shell-detach-test--waited)))

(ert-deftest kittymacs-shell-detach-under-exwm-through-its-launcher ()
  "EXWM's frame, through the real `kittymacs-exwm-launch': nothing waits."
  (kittymacs-shell-detach-test--with t
    (let (started process)
      (cl-letf (((symbol-function 'kittymacs-exwm-launch) kittymacs-shell-detach-test--exwm-launch)
                ((symbol-function 'start-process-shell-command)
                 (lambda (name buffer command)
                   (push (list name buffer command process-connection-type) started)
                   (setq process (start-process "kittymacs-test" nil "true")))))
        (let ((exwm-wm-mode t))
          (ignore exwm-wm-mode)
          (funcall-interactively #'shell-command "kittymacs-test-real")))
      (should (equal started '(("kittymacs-test-real" nil "kittymacs-test-real" nil))))
      (should-not (process-query-on-exit-flag process))
      (should-not kittymacs-shell-detach-test--waited))))

(ert-deftest kittymacs-shell-detach-without-the-exwm-launcher ()
  "Where the EXWM chapter has not loaded, a process starts with no buffer."
  (kittymacs-shell-detach-test--with t
    (let (started)
      (cl-letf (((symbol-function 'kittymacs-exwm-launch) nil)
                ((symbol-function 'start-process-shell-command)
                 (lambda (name buffer command)
                   (push (list name buffer command process-connection-type) started)
                   (start-process "kittymacs-test" nil "true"))))
        (funcall-interactively #'shell-command "kittymacs-test-real"))
      (should (equal started '(("kittymacs-test-real" nil "kittymacs-test-real" nil))))
      (should-not kittymacs-shell-detach-test--waited))))

(ert-deftest kittymacs-shell-detach-each-covered-command ()
  "M-!, project-shell-command, and Dired's !, X and M-!."
  (kittymacs-shell-detach-test--with t
    (write-region "" nil (expand-file-name "page.html" default-directory) nil 'silent)
    (cl-letf (((symbol-function 'read-shell-command) (lambda (&rest _) "kittymacs-test-real")))
      (call-interactively #'shell-command)
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) (cons 'transient default-directory))))
        (call-interactively #'project-shell-command)))
    (kittymacs-shell-detach-test--dired-on "page.html" "kittymacs-test-real" 'dired-do-shell-command)
    (kittymacs-shell-detach-test--dired-on "page.html" "kittymacs-test-real" 'dired-smart-shell-command)
    (should (= (length kittymacs-shell-detach-test--launched) 4))
    (should (string-prefix-p "kittymacs-test-real" (car kittymacs-shell-detach-test--launched)))
    (should-not kittymacs-shell-detach-test--waited)))

;;; Unchanged

(ert-deftest kittymacs-shell-detach-a-cli-command-waits ()
  (kittymacs-shell-detach-test--with t
    (funcall-interactively #'shell-command "kittymacs-test-cli")
    (funcall-interactively #'shell-command "kittymacs-test-tui")
    (should (equal kittymacs-shell-detach-test--waited '("kittymacs-test-tui" "kittymacs-test-cli")))
    (should-not kittymacs-shell-detach-test--launched)))

(ert-deftest kittymacs-shell-detach-an-asynchronous-command-is-untouched ()
  (kittymacs-shell-detach-test--with t
    (funcall-interactively #'shell-command "kittymacs-test-real &")
    (should (equal kittymacs-shell-detach-test--waited '("kittymacs-test-real &")))
    (should-not kittymacs-shell-detach-test--launched)))

(ert-deftest kittymacs-shell-detach-a-call-from-lisp-is-untouched ()
  (kittymacs-shell-detach-test--with t
    (shell-command "kittymacs-test-real")
    (dired-do-shell-command "kittymacs-test-real" nil (list "x"))
    (should (= (length kittymacs-shell-detach-test--waited) 2))
    (should-not kittymacs-shell-detach-test--launched)))

(ert-deftest kittymacs-shell-detach-output-here-is-untouched ()
  "A prefix argument asks for the output in this buffer."
  (kittymacs-shell-detach-test--with t
    (funcall-interactively #'shell-command "kittymacs-test-real" t)
    (should (equal kittymacs-shell-detach-test--waited '("kittymacs-test-real")))
    (should-not kittymacs-shell-detach-test--launched)))

(ert-deftest kittymacs-shell-detach-a-terminal-frame-is-untouched ()
  "An `emacsclient -t' frame, or batch."
  (kittymacs-shell-detach-test--with nil
    (funcall-interactively #'shell-command "kittymacs-test-real")
    (kittymacs-shell-detach-test--dired-on "." "kittymacs-test-real" 'dired-smart-shell-command)
    (should (= (length kittymacs-shell-detach-test--waited) 2))
    (should-not kittymacs-shell-detach-test--launched)))

;;; The tests above fail without the gate

(ert-deftest kittymacs-shell-detach-mutation-without-the-gate-fails ()
  "With the gate always open, every test of what stays unchanged must fail."
  (cl-letf (((symbol-function 'kittymacs--shell-command-detach-p) (lambda (&rest _) t)))
    (dolist (test '(kittymacs-shell-detach-a-cli-command-waits
                    kittymacs-shell-detach-an-asynchronous-command-is-untouched
                    kittymacs-shell-detach-a-call-from-lisp-is-untouched
                    kittymacs-shell-detach-output-here-is-untouched
                    kittymacs-shell-detach-a-terminal-frame-is-untouched))
      (should (equal (list test t)
                     (list test (ert-test-failed-p (ert-run-test (ert-get-test test)))))))))

;;; kittymacs-shell-detach-tests.el ends here
