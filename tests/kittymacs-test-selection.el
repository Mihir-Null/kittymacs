;;; kittymacs-test-selection.el --- What `just install' should install -*- lexical-binding: t; -*-
;; Loaded before init.el by `just install'.  KITTYMACS_TEST_PROFILE names a
;; selection, so CI and a contributor can make a package directory for each one:
;;   minimal, full   that profile
;;   every           `full' and every optional feature, for tests/kittymacs-feature-probes.el
;; Unset, the machine's own settings decide, as on any start.
;;
;; `every' also drops each `:one-of', so the members of a set, such as the coding
;; agents, are all on for this one run and all their packages install.  Their keys
;; then overwrite one another, which a run that only installs never sees.
;;
;; `setq' works before the options exist because `defcustom' keeps a value.

;;; Code:
(require 'map)

(defvar kittymacs-profile)
(defvar kittymacs-features)
(defvar kittymacs-catalogue)

(pcase (getenv "KITTYMACS_TEST_PROFILE")
  ((and (or "minimal" "full") profile)
   (setq kittymacs-profile (intern profile)))
  ("every"
   (load (expand-file-name "../lisp/kittymacs-catalogue" (file-name-directory load-file-name))
         nil t)
   (setq kittymacs-catalogue
         (mapcar (lambda (entry)
                   (cons (car entry) (map-delete (copy-sequence (cdr entry)) :one-of)))
                 kittymacs-catalogue)
         kittymacs-profile 'full
         kittymacs-features (mapcar #'car kittymacs-catalogue))))

;;; kittymacs-test-selection.el ends here
