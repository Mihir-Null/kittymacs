;;; kittymacs-leader-tests.el --- Leader and localleader behaviour -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
;; Loads only Meow and kittymacs-leader.el; the personal configuration is not loaded.

;;; Code:
(require 'ert)
(require 'package)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path
             (expand-file-name "../lisp"
                               (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-leader)

(keymap-set kittymacs-leader-map "f f" #'find-file)
(kittymacs-leader-enable)
(meow-global-mode 1)

(defmacro kittymacs-test-with-mode (mode state &rest body)
  "Run BODY in a fresh buffer in MODE after switching Meow to STATE."
  (declare (indent 2))
  `(with-temp-buffer
     (funcall ,mode)
     (meow--switch-state ,state)
     ,@body))

(ert-deftest kittymacs-leader-is-a-prefix-in-normal-and-motion ()
  (kittymacs-test-with-mode #'text-mode 'normal
    (should (meow-normal-mode-p))
    ;; `key-binding' merges every active map's prefix, so check identity on
    ;; Meow's own state map and effect on the merged result.
    (should (eq (keymap-lookup meow-normal-state-keymap "SPC") kittymacs-leader-map))
    (should (keymapp (key-binding (kbd "SPC"))))
    (should (eq (key-binding (kbd "SPC f f")) #'find-file)))
  (kittymacs-test-with-mode #'special-mode 'motion
    (should (meow-motion-mode-p))
    (should (eq (keymap-lookup meow-motion-state-keymap "SPC") kittymacs-leader-map))
    (should (eq (key-binding (kbd "SPC f f")) #'find-file))))

(ert-deftest kittymacs-leader-insert-state-still-inserts-spaces ()
  (kittymacs-test-with-mode #'text-mode 'insert
    (should (eq (key-binding (kbd "SPC")) #'self-insert-command))))

(ert-deftest kittymacs-localleader-composes-along-the-mode-lineage ()
  (let ((kittymacs-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile "r" #'recompile)
    (kittymacs-define-localleader 'emacs-lisp-mode "e" #'eval-buffer "c" #'byte-compile-file)
    (kittymacs-test-with-mode #'emacs-lisp-mode 'normal
      (should (eq (key-binding (kbd "SPC m e")) #'eval-buffer))
      (should (eq (key-binding (kbd "SPC m c")) #'byte-compile-file))
      (should (eq (key-binding (kbd "SPC m r")) #'recompile))
      (should (member "SPC m e" (mapcar #'key-description (where-is-internal #'eval-buffer)))))
    (kittymacs-test-with-mode #'text-mode 'normal
      (should-not (key-binding (kbd "SPC m")))
      (should-not kittymacs--localleader-alist))))

(ert-deftest kittymacs-localleader-is-gone-in-insert-state ()
  (let ((kittymacs-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile)
    (kittymacs-test-with-mode #'emacs-lisp-mode 'insert
      (should (eq (key-binding (kbd "SPC")) #'self-insert-command)))))

(ert-deftest kittymacs-keypad-is-unbound-unless-requested ()
  (should-not (where-is-internal #'meow-keypad kittymacs-leader-map))
  (let ((kittymacs-keypad-key "K"))
    (unwind-protect
        (progn
          (kittymacs-leader-enable)
          (should (eq (keymap-lookup kittymacs-leader-map "K") #'meow-keypad)))
      (keymap-unset kittymacs-leader-map "K" t)))
  (should-not (where-is-internal #'meow-keypad kittymacs-leader-map)))

(ert-deftest kittymacs-leader-enable-is-idempotent ()
  (let ((entries (seq-count (lambda (entry) (eq entry 'kittymacs--localleader-alist))
                            emulation-mode-map-alists)))
    (kittymacs-leader-enable)
    (should (= entries 1))
    (should (= 1 (seq-count (lambda (entry) (eq entry 'kittymacs--localleader-alist))
                            emulation-mode-map-alists)))))

(provide 'kittymacs-leader-tests)
;;; kittymacs-leader-tests.el ends here
