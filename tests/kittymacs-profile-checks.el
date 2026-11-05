;;; kittymacs-profile-checks.el --- What a start must satisfy under any selection -*- lexical-binding: t; -*-
;; Loaded by tests/verify-config.el and tests/kittymacs-feature-probes.el, after
;; the configuration has started.  Each function returns what is wrong, as a list.

;;; Code:
(require 'package)
(require 'seq)

(defvar kittymacs-catalogue)
(defvar kittymacs-leader-map)
(defvar kittymacs-localleader-alist)
(defvar kittymacs-user-map)
(declare-function kittymacs-feature-p "kittymacs-features" (feature))
(declare-function kittymacs-features-enabled "kittymacs-features" ())
(declare-function kittymacs-features-profile "kittymacs-features" ())

(defconst kittymacs-check-chapter-features
  '((file-tree . kittymacs-treemacs)
    (home-page . kittymacs-dashboard)
    (org-extras . kittymacs-org-extras)
    (linked-notes . kittymacs-org-roam)
    (pdf-reading . kittymacs-reading)
    (notebooks . kittymacs-notebooks)
    (agents . kittymacs-agents)
    (suggestions . kittymacs-suggestions))
  "The features `init.el' loads a whole chapter for, and that chapter's module.")

(defun kittymacs-check--binding (binding)
  "Return what the keymap entry BINDING runs, without its label."
  (pcase binding
    (`(menu-item ,_ ,definition . ,_) definition)
    (`(,(pred stringp) . ,definition) definition)
    (_ binding)))

(defun kittymacs-check-uncallable-bindings (map prefix)
  "Return the keys under PREFIX in MAP whose binding is not a command.
Group maps are walked too.  Autoloaded commands count as commands, so a package
directory with leftovers in it can hide a key that lost its package."
  (let (uncallable)
    (map-keymap
     (lambda (event binding)
       (let ((key (vconcat prefix (vector event)))
             (definition (kittymacs-check--binding binding)))
         (cond ((keymapp definition)
                (setq uncallable
                      (nconc uncallable
                             (kittymacs-check-uncallable-bindings definition key))))
               ((and definition (not (commandp definition)))
                (push (format "%s -> %S" (key-description key) definition)
                      uncallable)))))
     map)
    uncallable))

(defun kittymacs-check-empty-groups ()
  "Return the labels of the groups under the leader with no key in them.
`SPC u' is allowed under the full profile, which must not change."
  (let (empty)
    (map-keymap
     (lambda (event binding)
       (let ((definition (kittymacs-check--binding binding)))
         (when (and (keymapp definition)
                    (null (cdr definition))
                    (not (and (eq definition kittymacs-user-map)
                              (eq (kittymacs-features-profile) 'full))))
           (push (key-description (vector event)) empty))))
     kittymacs-leader-map)
    empty))

(defun kittymacs-check--closure (names)
  "Return NAMES and the installed packages they need, however indirectly.
A requirement that is not installed is Emacs's own."
  (let (closure)
    (while names
      (let ((name (pop names)))
        (unless (memq name closure)
          (push name closure)
          (when-let* ((desc (cadr (assq name package-alist))))
            (setq names (append (mapcar #'car (package-desc-reqs desc)) names))))))
    closure))

(defun kittymacs-check-packages-on ()
  "Return the catalogue's packages for the features that are on."
  (seq-mapcat (lambda (feature)
                (plist-get (alist-get feature kittymacs-catalogue) :packages))
              (kittymacs-features-enabled)))

(defun kittymacs-check-package-set ()
  "Compare what is installed with what the features that are on need.
Return a list of texts: the packages missing, then those nothing needs."
  (let* ((wanted (kittymacs-check-packages-on))
         (needed (kittymacs-check--closure wanted))
         (installed (mapcar #'car package-alist)))
    (append (mapcar (lambda (name) (format "%s is missing" name))
                    (seq-difference wanted installed))
            (mapcar (lambda (name) (format "%s is installed, and nothing here needs it" name))
                    (seq-difference installed needed)))))

(defun kittymacs-check--packages-off ()
  "Return the catalogue's packages that nothing on this machine needs."
  (seq-difference
   (seq-mapcat (lambda (entry)
                 (unless (kittymacs-feature-p (car entry))
                   (plist-get (cdr entry) :packages)))
               kittymacs-catalogue)
   (kittymacs-check--closure (kittymacs-check-packages-on))))

(defun kittymacs-check--commands (map)
  "Return every command symbol bound under MAP."
  (let (commands)
    (map-keymap
     (lambda (_event binding)
       (let ((definition (kittymacs-check--binding binding)))
         (cond ((keymapp definition)
                (setq commands (nconc (kittymacs-check--commands definition) commands)))
               ((and definition (symbolp definition))
                (push definition commands)))))
     map)
    commands))

(defun kittymacs-check-dead-commands ()
  "Return the keys' commands that belong to a package no feature needs.
A menu under `SPC m' may name a command of a library that is not loaded yet, so
`commandp' cannot judge it; a name that starts with a package's can."
  (let ((off (mapcar #'symbol-name (kittymacs-check--packages-off)))
        dead)
    (dolist (command (seq-mapcat
                      #'kittymacs-check--commands
                      (cons kittymacs-leader-map
                            (mapcar #'cdr kittymacs-localleader-alist))))
      (let ((name (symbol-name command)))
        (when (seq-some (lambda (package)
                          (or (equal name package)
                              (string-prefix-p (concat package "-") name)))
                        off)
          (push command dead))))
    (seq-uniq dead)))

(defun kittymacs-check-empty-localleaders ()
  "Return the modes whose menu under `SPC m' has no key in it."
  (mapcar #'car (seq-filter (lambda (entry) (null (cdr (cdr entry))))
                            (mapcar (lambda (entry) (cons (car entry) (cdr entry)))
                                    kittymacs-localleader-alist))))

(defun kittymacs-check-org-features ()
  "Return the loaded features that are Org or one of its add-ons."
  (seq-filter (lambda (feature)
                (let ((name (symbol-name feature)))
                  (and (string-match-p "\\`\\(?:org\\|ol\\|ox\\)\\(?:-\\|\\'\\)" name)
                       (not (string-suffix-p "-autoloads" name)))))
              features))

(defun kittymacs-check-start ()
  "Return what is wrong after any start: dead keys, empty groups and Org."
  (append
   (mapcar (lambda (binding) (format "SPC %s is not a command" binding))
           (kittymacs-check-uncallable-bindings kittymacs-leader-map []))
   (mapcar (lambda (group) (format "SPC %s is an empty group" group))
           (kittymacs-check-empty-groups))
   (mapcar (lambda (command) (format "A key runs %s, whose feature is off" command))
           (kittymacs-check-dead-commands))
   (mapcar (lambda (mode) (format "%s has an empty menu under SPC m" mode))
           (kittymacs-check-empty-localleaders))
   (when-let* ((org (kittymacs-check-org-features)))
     (list (format "Startup loaded Org: %S" org)))))

;;; kittymacs-profile-checks.el ends here
