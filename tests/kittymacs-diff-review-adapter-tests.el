;;; kittymacs-diff-review-adapter-tests.el --- The TRAMP adapter's six diff-review internals -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=/path/to/var/elpa \
;;      emacs -Q --batch -l tests/kittymacs-diff-review-adapter-tests.el -f ert-run-tests-batch-and-exit
;;
;; kittymacs-vc advises six of diff-review's internal functions so a review
;; works over TRAMP ("diff-review on another machine, over TRAMP" in
;; literate/66-vc.org).  A new pin can rename or change any of them without
;; an error until a remote review goes wrong.  This test reads the installed
;; diff-review.el as data, loads nothing, and fails when one of them is gone,
;; takes other arguments, or has another body.
;;
;; When it fails after a pin bump: read the changed functions, fix the adapter
;; if it needs it, then record the new values printed in the failure.

;;; Code:
(require 'ert)
(require 'package)
(require 'seq)

(defconst kittymacs-diff-review-adapter-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)

(defconst kittymacs-diff-review-adapter-pins
  '((diff-review--toplevel (directory)
     "82a89083c8a284bee36efe5b428e9c6124f122e24906d38c8d10dacbefad431c")
    (diff-review--common-dir (root)
     "8b1dbd8b55b7c1b0ae0cf0f52af75a796e4030319bbf38f1fe180d82b6880be9")
    (diff-review--worktrees (root)
     "f4393aba5e968809ab5436ba402a155b20dd4d3b3d8599e450970d597a61181f")
    (diff-review--git-at (directory &rest args)
     "e897f561b81bfb1000b108e0321565c4d89c2af2605920a6d609c7a3373677df")
    (diff-review--git-maybe (&rest args)
     "9e2193b03f0ad196fac56f2e26da42cb70e5daf93039766266f67a231b3ba8b0")
    (diff-review--buffer-blob ()
     "b4f794732eac61d913c30d2c36a9715b6c4437091d53b27539b3b3f8dc738da7"))
  "Each function the adapter advises: (NAME ARGLIST SHA256).
SHA256 is of the `defun' form as read and printed, so whitespace and
comments do not count.  Recorded at diff-review 49cba29.")

(defun kittymacs-diff-review-adapter--defuns ()
  "Every `defun' in the installed diff-review.el, as (NAME . FORM)."
  (let ((file (or (locate-library "diff-review.el" t)
                  (error "diff-review is not installed: run `just install' under the full profile")))
        forms)
    (with-temp-buffer
      (insert-file-contents file)
      (condition-case nil
          (while t
            (let ((form (read (current-buffer))))
              (when (eq (car-safe form) 'defun)
                (push (cons (cadr form) form) forms))))
        (end-of-file nil)))
    forms))

(defun kittymacs-diff-review-adapter--pin (form)
  "The ARGLIST and SHA256 of the `defun' FORM, as the pins record them."
  (let ((print-length nil) (print-level nil))
    (list (nth 2 form) (secure-hash 'sha256 (prin1-to-string form)))))

(ert-deftest kittymacs-diff-review-adapter-internals-are-as-pinned ()
  "Each advised internal exists, with the arguments and body the adapter was written for."
  (let ((defuns (kittymacs-diff-review-adapter--defuns)))
    (pcase-dolist (`(,name . ,pin) kittymacs-diff-review-adapter-pins)
      (let ((form (alist-get name defuns)))
        (should (equal (list name pin)
                       (list name (and form (kittymacs-diff-review-adapter--pin form)))))))))

(ert-deftest kittymacs-diff-review-adapter-pins-every-advised-function ()
  "The pins name exactly the functions literate/66-vc.org advises."
  (let ((module (expand-file-name "lisp/kittymacs-vc.el" kittymacs-diff-review-adapter-root))
        advised)
    (with-temp-buffer
      (insert-file-contents module)
      (while (re-search-forward "(advice-add '\\(diff-review--[^ ]+\\)" nil t)
        (push (intern (match-string 1)) advised)))
    (should (equal (sort advised #'string<)
                   (sort (mapcar #'car kittymacs-diff-review-adapter-pins) #'string<)))))

(provide 'kittymacs-diff-review-adapter-tests)
;;; kittymacs-diff-review-adapter-tests.el ends here
