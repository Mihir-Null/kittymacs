;;; kittymacs-hyperbole-tests.el --- Hyperbole fits Org, Meow and the leader -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-hyperbole-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages: what needs Hyperbole or Meow is skipped where they are
;; missing.  `just test' runs it so; `just test-packages' runs it again with
;; KITTYMACS_TEST_PACKAGES, where Hyperbole is installed, and so checks M-RET
;; in a real Org buffer.  HOME and the Org directory are temporary, so
;; Hyperbole's ~/.hyperb/ and the notes directories land nowhere real.

;;; Code:
(require 'ert)
(require 'package)
(require 'seq)
(require 'cl-lib)

(defconst kittymacs-hyperbole-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defconst kittymacs-hyperbole-test-home (make-temp-file "kittymacs-hyperbole-home-" t))
(setenv "HOME" kittymacs-hyperbole-test-home)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-hyperbole-test-root))
(require 'use-package)

(defvar kittymacs-profile)
(defvar kittymacs-org-directory)
(defvar hsys-org-enable-smart-keys)
(defvar hyperbole-mode)
(defvar hyperbole-mode-map)
(defvar hyrolo-file-list)
(defvar hywiki-directory)
(defvar hywiki-mode)
(defvar meow-mode-state-list)
(defvar org-link-frame-setup)
(setq kittymacs-profile 'full
      kittymacs-org-directory (expand-file-name "org/" kittymacs-hyperbole-test-home))
(require 'kittymacs-features)
(let ((use-package-ensure-function #'ignore))
  (require 'kittymacs-hyperbole))

(defconst kittymacs-hyperbole-test-loaded-at-start
  (list :hyperbole (featurep 'hyperbole) :org (featurep 'org)
        :m-ret (keymap-lookup global-map "M-RET")
        :c-h-h (keymap-lookup global-map "C-h h")
        :directories (seq-filter #'file-exists-p
                                 (list kittymacs-org-directory
                                       (file-name-directory (car hyrolo-file-list))
                                       hywiki-directory)))
  "What loading the module loaded or made, before any test could do more.")

(defun kittymacs-hyperbole-test--available-p ()
  "Return non-nil if Hyperbole can be loaded here."
  (locate-library "hyperbole"))

;;; Without Hyperbole

(ert-deftest kittymacs-hyperbole-module-loads-neither-hyperbole-nor-org ()
  "Hyperbole loads Org, and Org waits for its first use; no directory is made."
  (let ((start kittymacs-hyperbole-test-loaded-at-start))
    (should-not (plist-get start :hyperbole))
    (should-not (plist-get start :org))
    (should-not (plist-get start :directories))))

(defun kittymacs-hyperbole-test--leader (keys)
  "Return what KEYS under the leader run, without which-key's label."
  (let ((binding (keymap-lookup kittymacs-leader-map keys)))
    (if (and (consp binding) (stringp (car binding))) (cdr binding) binding)))

(ert-deftest kittymacs-hyperbole-leader-group-runs-commands ()
  (should (eq (kittymacs-hyperbole-test--leader "H") kittymacs-hyperbole-map))
  (dolist (key '("h" "a" "A" "?" "b" "l" "w" "i" "p" "r" "R" "k" "t"))
    (let ((command (kittymacs-hyperbole-test--leader (concat "H " key))))
      (should (equal (list key t) (list key (and (symbolp command) (commandp command))))))))

(ert-deftest kittymacs-hyperbole-global-keys-wait-for-hyperbole ()
  "Before Hyperbole loads, M-RET and C-h h load it first."
  (let ((start kittymacs-hyperbole-test-loaded-at-start))
    (should (eq (plist-get start :m-ret) #'kittymacs-hyperbole-action-key))
    (should (eq (plist-get start :c-h-h) #'kittymacs-hyperbole-menu))))

(ert-deftest kittymacs-hyperbole-org-keeps-m-ret-on-structure ()
  "Hyperbole's Org option is `buttons' unless something set it first."
  (should (eq hsys-org-enable-smart-keys 'buttons))
  (let ((hsys-org-enable-smart-keys nil))
    (kittymacs-hyperbole--hand-over)
    (should (eq hsys-org-enable-smart-keys nil)))
  (let ((hsys-org-enable-smart-keys 'unset))
    (kittymacs-hyperbole--hand-over)
    (should (eq hsys-org-enable-smart-keys 'buttons))))

(ert-deftest kittymacs-hyperbole-files-live-under-the-org-directory ()
  (should (equal kittymacs-hywiki-directory
                 (expand-file-name "hywiki/" kittymacs-org-directory)))
  (should (equal kittymacs-hyrolo-files
                 (list (expand-file-name "hyperbole/rolo.org" kittymacs-org-directory))))
  (should (equal hywiki-directory kittymacs-hywiki-directory))
  (should (equal hyrolo-file-list kittymacs-hyrolo-files)))

(ert-deftest kittymacs-hyperbole-init-loads-the-module-only-for-its-feature ()
  (let ((forms (with-temp-buffer
                 (insert-file-contents (expand-file-name "init.el" kittymacs-hyperbole-test-root))
                 (let (forms form)
                   (while (setq form (ignore-errors (read (current-buffer))))
                     (push form forms))
                   forms))))
    (should (member '(when (kittymacs-feature-p 'hyperbole)
                       (kittymacs-require-module 'kittymacs-hyperbole))
                    forms))
    (should (eq (plist-get (alist-get 'hyperbole kittymacs-catalogue) :profile) 'full))))

(ert-deftest kittymacs-hyperbole-off-leaves-no-trace ()
  "With the feature off, the leader has no SPC H and M-RET is Emacs's."
  (with-temp-buffer
    (let ((status (call-process
                   (expand-file-name invocation-name invocation-directory) nil t nil
                   "-Q" "--batch" "-L" (expand-file-name "lisp" kittymacs-hyperbole-test-root)
                   "--eval"
                   (prin1-to-string
                    '(progn
                       (setq kittymacs-profile 'full
                             kittymacs-features-excluded '(hyperbole))
                       (require 'kittymacs-features)
                       (require 'kittymacs-leader)
                       (when (kittymacs-feature-p 'hyperbole)
                         (require 'kittymacs-hyperbole))
                       (kittymacs-leader-drop-empty-groups)
                       (princ (format "%S" (list (kittymacs-feature-p 'hyperbole)
                                                 (featurep 'kittymacs-hyperbole)
                                                 (keymap-lookup kittymacs-leader-map "H")
                                                 (keymap-lookup global-map "M-RET")))))))))
      (should (equal status 0))
      (should (equal (car (last (split-string (buffer-string) "\n" t)))
                     "(nil nil nil nil)")))))

(ert-deftest kittymacs-hyperbole-meow-starts-koutlines-in-normal ()
  (skip-unless (locate-library "meow"))
  (require 'meow)
  (should (eq (alist-get 'kotl-mode meow-mode-state-list) 'normal))
  (should (eq (alist-get 'hyrolo-mode meow-mode-state-list) 'motion)))

(ert-deftest kittymacs-hyperbole-localleaders-exist ()
  (should (keymap-lookup (alist-get 'kotl-mode kittymacs-localleader-alist) "i"))
  (should (keymap-lookup (alist-get 'hyrolo-mode kittymacs-localleader-alist) "q")))

;;; With Hyperbole

(defmacro kittymacs-hyperbole-test-with-org (text &rest body)
  "Run BODY in an Org buffer holding TEXT, with Hyperbole on.
The buffer is in the selected window, as one you type in is: the Action
Key acts on the buffer of the window it was pressed in."
  (declare (indent 1))
  `(progn
     (skip-unless (kittymacs-hyperbole-test--available-p))
     (kittymacs-hyperbole-enable)
     (let ((buffer (generate-new-buffer "kittymacs-hyperbole-test.org")))
       (unwind-protect
           (progn
             (switch-to-buffer buffer)
             (org-mode)
             (insert ,text)
             (goto-char (point-min))
             ,@body)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(ert-deftest kittymacs-hyperbole-turns-on-and-fits-in ()
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (kittymacs-hyperbole-enable)
  (should hyperbole-mode)
  (should (eq hywiki-mode :pages))
  (should (eq hsys-org-enable-smart-keys 'buttons))
  ;; Hyperbole's map answers now, and the loaders are gone.
  (should (eq (keymap-lookup hyperbole-mode-map "M-RET") #'hkey-either))
  (should-not (keymap-lookup global-map "M-RET"))
  (should (eq (keymap-lookup global-map "C-h h") #'hyperbole))
  ;; Org's and Outline's C-c keys stay theirs, even after a second start.
  (should-not (keymap-lookup hyperbole-mode-map "C-c @"))
  (should-not (keymap-lookup hyperbole-mode-map "C-c \\"))
  (hyperbole-mode 0)
  (hyperbole-mode 1)
  (should-not (keymap-lookup hyperbole-mode-map "C-c @"))
  (should-not temp-buffer-show-function)
  (should-not (memq #'hkey-help-show temp-buffer-show-hook))
  (should (equal hywiki-directory kittymacs-hywiki-directory)))

(ert-deftest kittymacs-hyperbole-commands-under-spc-m-exist ()
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (kittymacs-hyperbole-enable)
  (require 'kotl-mode)
  (require 'hyrolo)
  (dolist (mode '(kotl-mode hyrolo-mode))
    (map-keymap (lambda (key binding)
                  (let ((command (if (consp binding) (cdr binding) binding)))
                    (should (equal (list mode key t) (list mode key (commandp command))))))
                (alist-get mode kittymacs-localleader-alist))))

(ert-deftest kittymacs-hyperbole-m-ret-on-a-heading-makes-a-heading ()
  (kittymacs-hyperbole-test-with-org "* First\n"
    (end-of-line)
    (should (eq (key-binding (kbd "M-RET")) #'hkey-either))
    (call-interactively #'hkey-either)
    (should (equal (count-matches "^\\* " (point-min) (point-max)) 2))))

(ert-deftest kittymacs-hyperbole-m-ret-in-a-list-makes-an-item ()
  (kittymacs-hyperbole-test-with-org "- one\n"
    (end-of-line)
    (call-interactively #'hkey-either)
    (should (equal (count-matches "^- " (point-min) (point-max)) 2))))

(ert-deftest kittymacs-hyperbole-m-ret-on-a-link-follows-it ()
  (let ((target (make-temp-file "kittymacs-hyperbole-target-" nil ".txt" "target\n"))
        (org-link-frame-setup '((file . find-file))))
    (unwind-protect
        (kittymacs-hyperbole-test-with-org (format "* Heading\nSee [[file:%s][the target]].\n" target)
          (search-forward "the target")
          (backward-char 3)
          (let ((origin (current-buffer)))
            (call-interactively #'hkey-either)
            (should (equal (buffer-file-name) target))
            (should (equal (count-matches "^\\* " (point-min) (point-max)) 0))
            (kill-buffer (current-buffer))
            (should (buffer-live-p origin))))
      (delete-file target))))

(ert-deftest kittymacs-hyperbole-spc-h-w-makes-a-new-page ()
  "Hyperbole's own `hywiki-find-page' opens only a page that exists."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "GardenPlans")))
    (call-interactively #'kittymacs-hywiki-find))
  (unwind-protect
      (progn
        (should (derived-mode-p 'org-mode))
        (should (equal buffer-file-name
                       (expand-file-name "GardenPlan.org" kittymacs-hywiki-directory))))
    (kill-buffer (current-buffer))))

(ert-deftest kittymacs-hyperbole-off-gives-m-ret-back-to-org ()
  (kittymacs-hyperbole-test-with-org "* First\n"
    (kittymacs-hyperbole-toggle)
    (unwind-protect
        (progn
          (should-not hyperbole-mode)
          (should (eq (key-binding (kbd "M-RET")) #'org-meta-return)))
      (kittymacs-hyperbole-toggle))
    (should hyperbole-mode)))

;;; kittymacs-hyperbole-tests.el ends here
