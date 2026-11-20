;;; kittymacs-typst-tests.el --- Typst math policy -*- lexical-binding: t; -*-
(require 'ert)
(require 'org)
(require 'cl-lib)
(let ((source (expand-file-name "../lisp/kittymacs-languages.el"
                                (file-name-directory (or load-file-name buffer-file-name)))))
  ;; Exercise the policy without installing editing packages or starting Emacs.
  (with-temp-buffer
    (insert-file-contents source)
    (goto-char (point-min))
    (search-forward "(defcustom kittymacs-typst-math-syntax")
    (goto-char (match-beginning 0))
    (while (not (looking-at "(when (kittymacs-feature-p"))
      (eval (read (current-buffer)) t)
      (skip-chars-forward "\n \t"))))
(ert-deftest kittymacs-typst-math-is-local-and-reversible ()
  (with-temp-buffer
    (org-mode)
    (kittymacs-typst-org-setup)
    (should (eq org-typst-from-latex-fragment 'org-typst-from-latex-with-naive))
    (kittymacs-typst-tex-compatibility)
    (should (eq org-typst-from-latex-environment 'kittymacs-typst-convert-tex-math))
    (kittymacs-typst-tex-compatibility)
    (should (eq kittymacs-typst-math-syntax 'typst)))
  (with-temp-buffer (should (eq kittymacs-typst-math-syntax 'typst))))
(ert-deftest kittymacs-typst-project-policy-and-suggestion ()
  (with-temp-buffer
    (org-mode)
    (insert "$\\frac{a}{b}$")
    (let (suggestion)
      (cl-letf (((symbol-function 'message) (lambda (format &rest args)
                                             (setq suggestion (apply #'format format args)))))
        (kittymacs-typst-org-setup))
      (should (string-match-p "compatibility" suggestion)))
    (setq-local kittymacs-typst-math-syntax 'latex)
    (kittymacs-typst-org-setup)
    (should (eq org-typst-from-latex-fragment 'kittymacs-typst-convert-tex-math))
    (should (equal (buffer-string) "$\\frac{a}{b}$"))))
(ert-deftest kittymacs-typst-no-parser-falls-back ()
  (with-temp-buffer
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'treesit-ensure-installed) #'ignore)
              ((symbol-function 'treesit-ready-p) (lambda (&rest _) nil)))
      (kittymacs-typst-mode)
      (should (eq major-mode 'text-mode)))))

(ert-deftest kittymacs-typst-missing-pandoc-is-actionable ()
  (cl-letf (((symbol-function 'executable-find) (lambda (_) nil)))
    (should-error (kittymacs-typst-convert-tex-math "$x$") :type 'user-error)))
(ert-deftest kittymacs-typst-failed-conversion-is-not-document-output ()
  (cl-letf (((symbol-function 'executable-find) (lambda (_) "/bin/pandoc"))
            ((symbol-function 'call-process-region) (lambda (&rest _) 1)))
    (should-error (kittymacs-typst-convert-tex-math "$x$") :type 'user-error)))

(defmacro kittymacs-test-with-typst-display (&rest body)
  "Exercise preview policy independently of this test runner's display."
  (declare (indent 0))
  `(let (calls (flymake-starts 0))
     (cl-letf (((symbol-function 'display-images-p) (lambda (&rest _) t))
               ((symbol-function 'image-type-available-p) (lambda (_) t))
               ((symbol-function 'executable-find) (lambda (_) "/bin/typst"))
               ((symbol-function 'treesit-ready-p) (lambda (&rest _) t))
               ((symbol-function 'require) (lambda (&rest _) t))
               ((symbol-function 'typst-overlay-mode)
                (lambda (arg)
                  (push arg calls)
                  (setq-local typst-overlay-mode (> arg 0))))
               ((symbol-function 'flymake-mode)
                (lambda (&rest _)
                  (cl-incf flymake-starts)
                  (setq-local flymake-mode t))))
       ,@body)))

(ert-deftest kittymacs-typst-overlays-follow-tex-compatibility ()
  (with-temp-buffer
    (org-mode)
    (kittymacs-test-with-typst-display
      (kittymacs-typst-overlay-setup)
      (should (equal calls '(1)))
      (kittymacs-typst-overlay-setup)
      (should (equal calls '(1)))
      (kittymacs-typst-tex-compatibility)
      (should-not typst-overlay-mode)
      (should (equal calls '(-1 1)))
      (kittymacs-typst-tex-compatibility)
      (should typst-overlay-mode)
      (should (equal calls '(1 -1 1)))
      ;; Re-enabling Flymake would discard the just-registered backend state.
      (should (= flymake-starts 1)))))

(ert-deftest kittymacs-typst-overlays-respect-file-locals-before-render ()
  (dolist (setting '((kittymacs-typst-math-syntax . latex)
                     (kittymacs-typst-inline-preview . nil)))
    (with-temp-buffer
      (org-mode)
      (setq buffer-file-name "/tmp/kittymacs-typst-test.org")
      (insert (format (concat "Equation $x$\n\n# Local " "Variables:\n# %s: %s\n# End:\n")
                      (car setting) (cdr setting)))
      (kittymacs-test-with-typst-display
        (kittymacs-typst-overlay-non-file-setup)
        (should-not calls)
        (let ((enable-local-variables :safe)
              (hack-local-variables-hook '(kittymacs-typst-overlay-setup)))
          (hack-local-variables))
        (should (local-variable-p (car setting)))
        (should-not calls)))))

(ert-deftest kittymacs-typst-overlays-non-file-and-typst-buffers ()
  (dolist (mode '(org-mode typst-ts-mode))
    (with-temp-buffer
      (setq major-mode mode)
      (kittymacs-test-with-typst-display
        (kittymacs-typst-overlay-non-file-setup)
        (should (equal calls '(1)))
        (setq-local kittymacs-typst-inline-preview nil)
        (kittymacs-typst-overlay-setup)
        (should (equal calls '(-1 1)))))))

(ert-deftest kittymacs-typst-overlays-missing-prerequisites-are-harmless ()
  (dolist (missing '(display-images-p image-type-available-p executable-find
                    treesit-ready-p require))
    (with-temp-buffer
      (org-mode)
      (kittymacs-test-with-typst-display
        (cl-letf (((symbol-function missing) (lambda (&rest _) nil)))
          (kittymacs-typst-overlay-setup)
          (should-not calls))))))

(ert-deftest kittymacs-typst-overlays-skip-remote-and-unrelated-buffers ()
  (with-temp-buffer
    (org-mode)
    (kittymacs-test-with-typst-display
      (cl-letf (((symbol-function 'file-remote-p) (lambda (&rest _) "remote")))
        (kittymacs-typst-overlay-setup)
        (should-not calls))
      (setq major-mode 'text-mode)
      (kittymacs-typst-overlay-setup)
      (should-not calls))))
