;;; kittymacs-org-node-tests.el --- Linked notes across roots -*- lexical-binding: t; -*-

(require 'ert)
(require 'package)
(require 'use-package)

(setq native-comp-jit-compilation nil)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path (expand-file-name "../lisp" (file-name-directory load-file-name)))

(defvar kittymacs-org-directory temporary-file-directory)
(require 'kittymacs-org-node)
(defconst kittymacs-test-org-node-loaded-at-startup (featurep 'org-node))

(defun kittymacs-test-org-node-write (file contents)
  (make-directory (file-name-directory file) t)
  (with-temp-file file (insert contents)))

(ert-deftest kittymacs-org-node-startup-is-lazy ()
  (should-not kittymacs-test-org-node-loaded-at-startup)
  (should (eq (keymap-lookup kittymacs-notes-map "F") #'kittymacs-org-node-find-all)))

(ert-deftest kittymacs-org-node-keeps-capture-inside-project ()
  (let ((root (make-temp-file "kittymacs-org-node-" t))
        (outside (make-temp-file "kittymacs-org-node-outside-" t)))
    (unwind-protect
        (progn
          (should-error (kittymacs--org-node-root root :capture "../outside.org")
                        :type 'user-error)
          (should-error (kittymacs--org-node-root root :capture "not-org.md")
                        :type 'user-error)
          (condition-case nil
              (make-symbolic-link outside (expand-file-name "escape" root))
            (file-error (ert-skip "Cannot create symlinks")))
          (should-error (kittymacs--org-node-root root :capture "escape/outside.org")
                        :type 'user-error))
      (delete-directory root t)
      (delete-directory outside t))))

(ert-deftest kittymacs-org-node-index-scope-links-and-capture ()
  (require 'org-id)
  (let* ((base (make-temp-file "kittymacs-org-node-" t))
         (personal (expand-file-name "personal/" base))
         (project (expand-file-name "project/" base))
         (project2 (expand-file-name "project2/" base))
         (note (expand-file-name "docs/main.org" project))
         (other (expand-file-name "main.org" project2))
         (moved (expand-file-name "renamed.org" project2))
         (kittymacs-org-node-directory personal)
         (kittymacs-org-node-projects (list (list project2)))
         (kittymacs--org-node-discovered nil)
         (kittymacs--org-node-index-roots nil)
         (org-id-locations nil)
         (org-id-files nil)
         (org-id-locations-file (expand-file-name "org-id-locations" base))
         (org-id-track-globally t))
    (unwind-protect
        (progn
          (kittymacs-test-org-node-write
           (expand-file-name ".dir-locals.el" project)
           "((nil . ((kittymacs-org-node-project . t)
                     (kittymacs-org-node-project-directory . \"docs\")
                     (kittymacs-org-node-capture-file . \"notes/inbox.org\")
                     (kittymacs-org-node-excluded-directories . (\"secret\")))))")
          (kittymacs-test-org-node-write
           (expand-file-name "notes.org" personal)
           "* Same title :personal:\n:PROPERTIES:\n:ID: home\n:END:\n[[id:one]]\n")
          (kittymacs-test-org-node-write
           note
           "* Same title :project:\n:PROPERTIES:\n:ID: one\n:ROAM_ALIASES: \"Old name\"\n:BLOCKER: ids(\"id:missing-task\")\n:END:\n[[id:two]] [[id:missing-note]]\n* Backlink\n:PROPERTIES:\n:ID: back\n:END:\n[[id:one]]\n")
          (kittymacs-test-org-node-write
           (expand-file-name "docs/secret/hidden.org" project)
           "* Hidden\n:PROPERTIES:\n:ID: hidden\n:END:\n")
          (kittymacs-test-org-node-write
           other
           "* Same title :second:\n:PROPERTIES:\n:ID: two\n:END:\n[[id:one]]\n* Duplicate\n:PROPERTIES:\n:ID: back\n:END:\n")
          (with-current-buffer (find-file-noselect note)
            (let* ((roots (kittymacs--org-node-prepare))
                   (scope (kittymacs--org-node-scope roots)))
              (should (equal (car scope) project))
              (should (equal (kittymacs--org-node-tags scope) '("project")))
              (should (equal (kittymacs--org-node-tags nil) '("personal" "project" "second")))
              (should (equal (length (kittymacs--org-node-entries scope)) 2))
              (should-not (org-mem-entry-by-id "hidden"))
              (should (org-mem-entry-by-id "home"))
              (should (= (length (org-mem-id-links-to-id "one")) 3))
              (should (equal (org-id-find "two") (cons other 1)))
              (let ((findings (string-join (kittymacs--org-node-audit roots) "\n")))
                (dolist (prefix '("Duplicate ID back" "Unresolved ID missing-note"
                                  "Unresolved BLOCKER target missing-task" "Roam metadata"))
                  (should (string-match-p prefix findings))))))
          (switch-to-buffer (find-file-noselect note))
          (kittymacs-org-node-capture)
          (should (bound-and-true-p org-capture-mode))
          (insert "Captured")
          (org-capture-finalize)
          (with-temp-buffer
            (insert-file-contents (expand-file-name "docs/notes/inbox.org" project))
            (should (re-search-forward "^:ID:[ \t]+[^ \t\n]" nil t)))
          (rename-file other moved)
          (kittymacs--org-node-prepare t)
          (should (equal (org-mem-entry-file (org-mem-entry-by-id "two")) moved)))
      (when (bound-and-true-p org-mem-updater-mode) (org-mem-updater-mode -1))
      (dolist (buffer (buffer-list))
        (when-let* ((name (buffer-file-name buffer)))
          (when (file-in-directory-p name base)
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer))))
      (delete-directory base t))))
