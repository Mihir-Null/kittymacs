;;; kittymacs-theme-tests.el --- The look works without doom -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-theme-tests.el -f ert-run-tests-batch-and-exit
;;
;; Activates every package but the `doom-look' feature's, chooses the minimal
;; profile, which leaves that feature off, and loads lisp/kittymacs-ui.el.  The
;; verifier covers the same module with the feature on.

;;; Code:
(require 'ert)
(require 'package)
(require 'seq)
(require 'cl-lib)

(defconst kittymacs-theme-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(load (expand-file-name "lisp/kittymacs-catalogue.el" kittymacs-theme-test-root) nil t)

(defconst kittymacs-theme-test-doom
  (plist-get (alist-get 'doom-look kittymacs-catalogue) :packages)
  "The packages the module has to work without.")

(setq user-emacs-directory (file-name-as-directory (make-temp-file "kittymacs-theme-" t))
      native-comp-jit-compilation nil)
(load (expand-file-name "early-init.el" kittymacs-theme-test-root) nil t)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(setq package-load-list
      (append (mapcar (lambda (name) (list name nil)) kittymacs-theme-test-doom) '(all)))
(package-initialize)
(dolist (fn '(package-install package-refresh-contents))
  (advice-add fn :override
              (lambda (&rest _) (error "Package installation forbidden in theme tests"))))
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-theme-test-root))
(require 'use-package)

(setq kittymacs-profile 'minimal)
(require 'kittymacs-ui)

(ert-deftest kittymacs-theme-pointer-word-is-only-the-pointer-in-scratch ()
  (with-current-buffer (get-buffer-create "*scratch*")
    (erase-buffer)
    (insert kittymacs--scratch-pointer "\n;; SPC\n")
    (should (kittymacs--scratch-pointer-word-p 4 7 nil))
    (should-not (kittymacs--scratch-pointer-word-p (- (point-max) 4) (- (point-max) 1) nil))
    (let ((text (buffer-string)))
      (with-temp-buffer
        (insert text)
        (should-not (kittymacs--scratch-pointer-word-p 4 7 nil))))
    (erase-buffer)))

(defun kittymacs-theme-test--hunspell-has-a-dictionary-p ()
  "Non-nil when Hunspell is here with the dictionary the configuration asks for."
  (and (executable-find "hunspell")
       (with-temp-buffer
         (call-process "hunspell" nil t nil "-D")
         (goto-char (point-min))
         (search-forward "en_US" nil t))))

(ert-deftest kittymacs-theme-flyspell-marks-spc-only-outside-the-pointer ()
  "Real Flyspell, because the hook's contract is what this relies on."
  (skip-unless (kittymacs-theme-test--hunspell-has-a-dictionary-p))
  (require 'flyspell)
  (let ((ispell-program-name "hunspell")
        (ispell-dictionary "en_US")
        (flyspell-issue-message-flag nil)
        (process-environment (cons "DICTIONARY=en_US" process-environment)))
    (with-current-buffer (get-buffer-create "*scratch*")
      (erase-buffer)
      (insert kittymacs--scratch-pointer "\n;; SPC\n")
      (flyspell-mode 1)
      (unwind-protect
          (let ((other-line (save-excursion
                              (goto-char (point-min))
                              (line-beginning-position 2))))
            (flyspell-region (point-min) (point-max))
            (let ((marks (seq-filter #'flyspell-overlay-p
                                     (overlays-in (point-min) (point-max)))))
              (should (= 1 (length marks)))
              (should (>= (overlay-start (car marks)) other-line))))
        (flyspell-mode -1)
        (erase-buffer)))))

(ert-deftest kittymacs-theme-module-loads-without-doom ()
  (should (= 2 (length kittymacs-theme-test-doom)))
  (should (featurep 'kittymacs-ui))
  (dolist (feature (append kittymacs-theme-test-doom '(doom-themes-ext-org)))
    (should-not (featurep feature)))
  (should-not (fboundp 'doom-modeline-mode)))

(ert-deftest kittymacs-theme-starts-on-the-built-in-theme ()
  (should (eq kittymacs-theme 'doom-sonokai))
  (should (equal custom-enabled-themes '(modus-vivendi))))

(ert-deftest kittymacs-theme-toggles-between-the-built-in-themes ()
  (kittymacs-load-theme (kittymacs--default-theme))
  (kittymacs-toggle-theme)
  (should (equal custom-enabled-themes '(modus-operandi)))
  (kittymacs-toggle-theme)
  (should (equal custom-enabled-themes '(modus-vivendi))))

(ert-deftest kittymacs-theme-keeps-a-choice-that-does-not-need-doom ()
  (let ((kittymacs-theme 'modus-vivendi-tinted)
        (kittymacs-light-theme 'modus-operandi-tinted))
    (should (eq (kittymacs--default-theme) 'modus-vivendi-tinted))
    (should (eq (kittymacs--other-theme) 'modus-operandi-tinted))))

(ert-deftest kittymacs-theme-module-leaves-org-unloaded ()
  (should-not (featurep 'org)))

;;; The pulse after a jump

(ert-deftest kittymacs-theme-the-jump-pulse-follows-ui-polish ()
  "The minimal profile keeps the pulse it had, on scrolling and window changes."
  (should-not (kittymacs-feature-p 'ui-polish))
  (should-not kittymacs-pulse-jumps-mode)
  (should-not (memq #'kittymacs--pulse-line next-error-hook))
  (should-not (advice-member-p #'kittymacs--pulse-line 'avy-goto-line))
  (should (advice-member-p #'kittymacs--pulse-line 'scroll-up-command)))

(ert-deftest kittymacs-theme-the-jump-pulse-goes-on-and-off-and-loads-nothing ()
  (unwind-protect
      (progn
        (kittymacs-pulse-jumps-mode 1)
        (should (memq #'kittymacs--pulse-line next-error-hook))
        (dolist (command kittymacs-pulse-jump-commands)
          (should (equal (list command t)
                         (list command (and (advice-member-p #'kittymacs--pulse-line command) t)))))
        (should-not (featurep 'avy))
        (should-not (featurep 'consult)))
    (kittymacs-pulse-jumps-mode -1))
  (should-not (memq #'kittymacs--pulse-line next-error-hook))
  (should-not (advice-member-p #'kittymacs--pulse-line 'consult-line)))

(ert-deftest kittymacs-theme-the-jump-pulse-leaves-a-missing-command-undefined ()
  (let ((command 'kittymacs-theme-test-no-such-jump)
        (kittymacs-pulse-jump-commands '(kittymacs-theme-test-no-such-jump)))
    (kittymacs-pulse-jumps-mode 1)
    (unwind-protect
        (should-not (fboundp command))
      (kittymacs-pulse-jumps-mode -1))))

(ert-deftest kittymacs-theme-the-jump-pulse-shows-after-a-mark-and-next-error ()
  (let (pulses)
    (cl-letf (((symbol-function 'pulse-momentary-highlight-one-line)
               (lambda (point &rest _) (push point pulses))))
      (kittymacs-pulse-jumps-mode 1)
      (unwind-protect
          (with-temp-buffer
            (insert "one\ntwo\nthree\n")
            (push-mark 5 t)
            (goto-char (point-max))
            (pop-to-mark-command)
            (should (equal pulses '(5)))
            (run-hooks 'next-error-hook)
            (should (equal pulses '(5 5))))
        (kittymacs-pulse-jumps-mode -1)))))

(ert-deftest kittymacs-theme-the-jump-list-holds-only-what-this-configuration-has ()
  "A command of a package is real if a module binds it; a built-in one, if Emacs has it."
  (let ((sources (with-temp-buffer
                   (dolist (file (directory-files
                                  (expand-file-name "lisp" kittymacs-theme-test-root) t
                                  "\\`kittymacs-.*\\.el\\'"))
                     (unless (string-suffix-p "kittymacs-ui.el" file)
                       (insert-file-contents file)))
                   (buffer-string))))
    (dolist (command kittymacs-pulse-jump-commands)
      (should (equal (list command t)
                     (list command
                           (and (or (string-search (format "#'%s" command) sources)
                                    (and (fboundp command)
                                         (not (autoloadp (symbol-function command)))))
                                t)))))))

;;; kittymacs-theme-tests.el ends here
