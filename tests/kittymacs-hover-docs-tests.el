;;; kittymacs-hover-docs-tests.el --- Hover documentation, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-hover-docs-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages, and no display: stubs stand for `eldoc-box-hover-mode',
;; Eglot and a graphical frame, and the tests read what each one was asked.
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-catalogue)
(defvar use-package-ensure-function)
(setq use-package-ensure-function #'ignore)

(defvar kittymacs-hover-docs-test-managed nil)
(defun eglot-managed-p () kittymacs-hover-docs-test-managed)
(defvar-local eldoc-box-hover-mode nil)
(defun eldoc-box-hover-mode (&optional arg)
  (setq eldoc-box-hover-mode (and arg (> arg 0))))
(defvar kittymacs-hover-docs-test-frame nil)
(defun eldoc-box--eldoc-display-function (docs interactive)
  (setq kittymacs-hover-docs-test-frame (list docs interactive)))

(require 'use-package)
(require 'kittymacs-features)
(require 'kittymacs-hover-docs)

(defmacro kittymacs-hover-docs-test-graphical (&rest body)
  "Run BODY as if on a graphical frame."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
     ,@body))

(ert-deftest kittymacs-hover-docs-full-has-it-and-minimal-does-not ()
  (let ((entry (alist-get 'hover-docs kittymacs-catalogue)))
    (should (eq (plist-get entry :profile) 'full))
    (should (eq (plist-get entry :group) 'look))
    (should (equal (plist-get entry :packages) '(eldoc-box)))
    (should-not (memq 'hover-docs (kittymacs-features--compute 'minimal nil nil)))
    (should (memq 'hover-docs (kittymacs-features--compute 'full nil nil)))
    (should-not (memq 'hover-docs (kittymacs-features--compute 'full nil '(hover-docs))))))

(ert-deftest kittymacs-hover-docs-loading-it-does-not-load-eglot-or-eldoc-box ()
  (should-not (featurep 'eglot))
  (should-not (featurep 'eldoc-box))
  (should (memq #'kittymacs-hover-docs--apply eglot-managed-mode-hook)))

(ert-deftest kittymacs-hover-docs-only-an-eglot-buffer-asks ()
  (kittymacs-hover-docs-test-graphical
    (with-temp-buffer
      (let ((kittymacs-hover-docs-test-managed nil))
        (kittymacs-hover-docs--apply)
        (should-not eldoc-box-hover-mode))
      (let ((kittymacs-hover-docs-test-managed t))
        (kittymacs-hover-docs--apply)
        (should eldoc-box-hover-mode))
      ;; Eglot runs the same hook when it lets a buffer go.
      (let ((kittymacs-hover-docs-test-managed nil))
        (kittymacs-hover-docs--apply)
        (should-not eldoc-box-hover-mode)))))

(ert-deftest kittymacs-hover-docs-a-terminal-keeps-the-echo-area ()
  ;; Batch has only a terminal frame.
  (with-temp-buffer
    (let ((kittymacs-hover-docs-test-managed t))
      (kittymacs-hover-docs--apply)
      (should-not eldoc-box-hover-mode))))

(ert-deftest kittymacs-hover-docs-a-buffer-seen-on-a-terminal-uses-the-echo-area ()
  (let ((kittymacs-hover-docs-test-frame nil)
        echoed)
    (cl-letf (((symbol-function 'eldoc-display-in-echo-area)
               (lambda (docs _interactive) (setq echoed docs))))
      (eldoc-box--eldoc-display-function '(("text")) nil)
      (should (equal echoed '(("text"))))
      (should-not kittymacs-hover-docs-test-frame)
      (setq echoed nil)
      (kittymacs-hover-docs-test-graphical
        (eldoc-box--eldoc-display-function '(("text")) nil))
      (should-not echoed)
      (should kittymacs-hover-docs-test-frame))))

(ert-deftest kittymacs-hover-docs-a-remote-buffer-gets-it-with-no-connection ()
  (kittymacs-hover-docs-test-graphical
    (with-temp-buffer
      (setq default-directory "/ssh:nobody@nowhere.invalid:/")
      (let ((kittymacs-hover-docs-test-managed t))
        (cl-letf (((symbol-function 'tramp-file-name-handler)
                   (lambda (&rest _) (error "Asked the connection"))))
          (kittymacs-hover-docs--apply))
        (should eldoc-box-hover-mode)))))

(ert-deftest kittymacs-hover-docs-turning-it-off-goes-through-the-buffers ()
  (kittymacs-hover-docs-test-graphical
    (with-temp-buffer
      (let ((kittymacs-hover-docs-test-managed t))
        (kittymacs-hover-docs--apply)
        (should eldoc-box-hover-mode)
        (kittymacs-hover-docs-mode -1)
        (unwind-protect
            (progn
              (should-not eldoc-box-hover-mode)
              (should-not (memq #'kittymacs-hover-docs--apply eglot-managed-mode-hook))
              (kittymacs-hover-docs--apply)
              (should-not eldoc-box-hover-mode))
          (kittymacs-hover-docs-mode 1))
        (should eldoc-box-hover-mode)))))

(ert-deftest kittymacs-hover-docs-has-its-toggle ()
  (should (eq (keymap-lookup kittymacs-toggle-map "e") 'kittymacs-hover-docs-mode)))

;;; kittymacs-hover-docs-tests.el ends here
