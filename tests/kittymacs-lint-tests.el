;;; kittymacs-lint-tests.el --- Conventions a machine can check -*- lexical-binding: t; -*-
;; emacs -Q --batch -l tests/kittymacs-lint-tests.el -f ert-run-tests-batch-and-exit
;; (`just doc-test' runs this after tests/kittymacs-doc-tests.el.)
;;
;; Prose that has drifted from the code, and code that breaks a rule the
;; chapters state.  Everything is read, nothing is loaded, and no package is
;; needed.  See "What the doc tests check" in literate/conventions.org.
(require 'ert)
(require 'cl-lib)
(require 'project)
(require 'seq)

(defconst kittymacs-lint-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))

(defun kittymacs-lint--path (name)
  "Return NAME, relative to the root of this checkout, as an absolute file name."
  (expand-file-name name kittymacs-lint-root))

(defun kittymacs-lint--forms (file)
  "Every top-level form in FILE, read but not evaluated."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun kittymacs-lint--modules ()
  "Every generated module: lisp/kittymacs-*.el."
  (directory-files (kittymacs-lint--path "lisp") t "\\`kittymacs-.*\\.el\\'"))

(defun kittymacs-lint--pages ()
  "Every page of prose: chapters and other pages, the README, the architecture."
  (append (directory-files (kittymacs-lint--path "literate") t "\\.org\\'")
          (list (kittymacs-lint--path "README.md")
                (kittymacs-lint--path "ARCHITECTURE.md"))))

(defun kittymacs-lint--walk (form function)
  "Call FUNCTION on FORM and on every list nested inside it."
  (when (consp form)
    (funcall function form)
    (while (consp form)
      (kittymacs-lint--walk (car form) function)
      (setq form (cdr form)))))

(defun kittymacs-lint--walk-modules (function)
  "Call FUNCTION with each list in the modules, and the file it came from."
  (dolist (file (kittymacs-lint--modules))
    (dolist (form (kittymacs-lint--forms file))
      (kittymacs-lint--walk form (lambda (list) (funcall function list file))))))

(defun kittymacs-lint--lines-matching (regexp file)
  "Return (LINE-NUMBER . TEXT) for each line of FILE that matches REGEXP."
  (with-temp-buffer
    (insert-file-contents file)
    (let (lines (case-fold-search nil))
      (while (re-search-forward regexp nil t)
        (push (cons (line-number-at-pos)
                    (buffer-substring-no-properties (line-beginning-position)
                                                    (line-end-position)))
              lines)
        (forward-line 1))
      (nreverse lines))))

;;; The key tree

(defun kittymacs-lint--body-entries (body)
  "Return ((KEY . TARGET) ...) for the BODY of a `defvar-keymap' or `define-keymap'.
A `:parent' becomes the entry (:parent . MAP); other keywords are skipped."
  (let (entries)
    (while body
      (let ((key (pop body)) (value (pop body)))
        (cond ((stringp key)
               (push (cons key (kittymacs-lint--binding-target value)) entries))
              ((eq key :parent)
               (push (cons :parent value) entries)))))
    entries))

(defun kittymacs-lint--binding-target (value)
  "Return what the keymap VALUE form binds.
A map's symbol, a list of entries for an inline keymap, or t for a command."
  (pcase value
    (`(cons ,_ ,inner) (kittymacs-lint--binding-target inner))
    (`(define-keymap . ,body) (kittymacs-lint--body-entries body))
    ((pred symbolp) value)
    (_ t)))

(defun kittymacs-lint--collect-bindings (forms)
  "Return an alist (MAP . ((KEY . TARGET) ...)) of the bindings in FORMS.
Reads `defvar-keymap' and `keymap-set' with a literal key, however deeply a
form is nested, so a binding behind a gate counts."
  (let (maps)
    (dolist (form forms)
      (kittymacs-lint--walk
       form
       (lambda (list)
         (pcase list
           (`(defvar-keymap ,map . ,body)
            (setf (alist-get map maps)
                  (append (kittymacs-lint--body-entries body) (alist-get map maps))))
           (`(keymap-set ,(and map (pred symbolp)) ,(and key (pred stringp)) ,value)
            (push (cons key (kittymacs-lint--binding-target value))
                  (alist-get map maps)))))))
    maps))

(defun kittymacs-lint--built-in-key-p (keys map)
  "Return non-nil if KEYS is bound in MAP, a keymap Emacs itself defines.
Unknown names are not vouched for: a typo in `:parent' must not pass."
  (and (boundp map)
       (keymapp (symbol-value map))
       ;; `lookup-key' returns a number when the sequence is too long.
       (let ((binding (lookup-key (symbol-value map) (key-parse (string-join keys " ")))))
         (and binding (not (numberp binding))))))

(defun kittymacs-lint--entries-bind-p (keys entries maps)
  "Return non-nil if the list of KEYS leads somewhere through ENTRIES."
  (or (seq-some
       (pcase-lambda (`(,key . ,target))
         (when (stringp key)
           (let ((steps (split-string key " " t)))
             (when (equal steps (seq-take keys (length steps)))
               (let ((rest (seq-drop keys (length steps))))
                 (or (null rest)
                     (and (consp target)
                          (kittymacs-lint--entries-bind-p rest target maps))
                     (and target (symbolp target) (not (eq target t))
                          (kittymacs-lint--key-bound-p rest target maps))))))))
       entries)
      ;; A key bound here shadows the parent's, whatever follows it.
      (when-let* ((parent (alist-get :parent entries))
                  ((not (seq-some (lambda (entry)
                                    (and (stringp (car entry))
                                         (equal (car (split-string (car entry) " " t))
                                                (car keys))))
                                  entries))))
        (kittymacs-lint--key-bound-p keys parent maps))))

(defun kittymacs-lint--key-bound-p (keys map maps)
  "Return non-nil if the list of KEYS leads somewhere from MAP in MAPS.
A MAP that no module defines is looked up in Emacs itself."
  (if (assq map maps)
      (kittymacs-lint--entries-bind-p keys (alist-get map maps) maps)
    (kittymacs-lint--built-in-key-p keys map)))

(defun kittymacs-lint--real-maps ()
  "Return the bindings of every module."
  (kittymacs-lint--collect-bindings
   (seq-mapcat #'kittymacs-lint--forms (kittymacs-lint--modules))))

(defun kittymacs-lint--leader-references (file)
  "Return (LINE . KEYS) for each `SPC ...' that FILE quotes as code.
KEYS is a list without the leading SPC.  Org quotes with = or ~, Markdown
with a backtick.  `SPC m' is left out: a major mode's map decides what follows."
  (with-temp-buffer
    (insert-file-contents file)
    (let (references (case-fold-search nil))
      (while (re-search-forward "[=~`]SPC \\([^=~`\n]+\\)[=~`]" nil t)
        (let ((keys (split-string (match-string 1) " " t)))
          (unless (equal (car keys) "m")
            (push (cons (line-number-at-pos) keys) references))))
      (nreverse references))))

(ert-deftest kittymacs-lint-key-tree-resolves-direct-nested-and-group-keys ()
  (let ((maps (kittymacs-lint--collect-bindings
               '((defvar-keymap my-inner "x" (cons "x" #'x))
                 (defvar-keymap my-outer :doc "Outer." "i" (cons "inner" my-inner) "c p" #'y)
                 (when gate (keymap-set my-outer "g" #'z))))))
    (should (kittymacs-lint--key-bound-p '("i") 'my-outer maps))
    (should (kittymacs-lint--key-bound-p '("i" "x") 'my-outer maps))
    (should (kittymacs-lint--key-bound-p '("c" "p") 'my-outer maps))
    (should (kittymacs-lint--key-bound-p '("g") 'my-outer maps))
    (should-not (kittymacs-lint--key-bound-p '("i" "y") 'my-outer maps))
    (should-not (kittymacs-lint--key-bound-p '("g" "g") 'my-outer maps))
    (should-not (kittymacs-lint--key-bound-p '("q") 'my-outer maps))))

(ert-deftest kittymacs-lint-key-tree-reads-inline-maps-and-parents ()
  (let ((maps (kittymacs-lint--collect-bindings
               '((defvar-keymap my-map
                   :parent project-prefix-map
                   "E" (cons "env" (define-keymap "r" (cons "reload" #'r))))
                 (defvar-keymap my-typo :parent no-such-map-exists "a" #'a)))))
    (should (kittymacs-lint--key-bound-p '("E" "r") 'my-map maps))
    (should-not (kittymacs-lint--key-bound-p '("E" "z") 'my-map maps))
    ;; `f' is `project-find-file', inherited from Emacs's own map.
    (should (kittymacs-lint--key-bound-p '("f") 'my-map maps))
    (should-not (kittymacs-lint--key-bound-p '("F" "F") 'my-map maps))
    (should-not (kittymacs-lint--key-bound-p '("z") 'my-typo maps))))

(ert-deftest kittymacs-lint-key-tree-knows-a-kept-key-from-a-removed-one ()
  "`SPC s D' went with deadgrep, and prose kept naming keys like it."
  (let ((maps (kittymacs-lint--real-maps)))
    (should (kittymacs-lint--key-bound-p '("s" "d") 'kittymacs-leader-map maps))
    (should-not (kittymacs-lint--key-bound-p '("s" "D") 'kittymacs-leader-map maps))))

(ert-deftest kittymacs-lint-prose-names-only-keys-that-exist ()
  (let ((maps (kittymacs-lint--real-maps))
        (checked 0)
        missing)
    (dolist (file (kittymacs-lint--pages))
      (pcase-dolist (`(,line . ,keys) (kittymacs-lint--leader-references file))
        (setq checked (1+ checked))
        (unless (kittymacs-lint--key-bound-p keys 'kittymacs-leader-map maps)
          (push (format "%s:%d: SPC %s" (file-name-nondirectory file) line
                        (string-join keys " "))
                missing))))
    ;; A pattern that stopped matching would otherwise pass by checking nothing.
    (should (> checked 200))
    (should-not (reverse missing))))

;;; Removed packages

(defun kittymacs-lint--removed-packages ()
  "Return the names in tests/removed-packages.eld."
  (mapcar #'car (car (kittymacs-lint--forms (kittymacs-lint--path "tests/removed-packages.eld")))))

(defun kittymacs-lint--name-regexp (name)
  "Return a regexp for the package NAME as a whole word."
  (format "\\(?:^\\|[^[:alnum:]-]\\)%s\\(?:$\\|[^[:alnum:]-]\\)"
          (regexp-quote (symbol-name name))))

(defun kittymacs-lint--history-line-p (line)
  "Return non-nil if LINE is the record of what was dropped and why."
  (string-prefix-p "- **Dropped for good reasons:**" line))

(ert-deftest kittymacs-lint-name-regexp-matches-whole-names-only ()
  (let ((regexp (kittymacs-lint--name-regexp 'iedit))
        (case-fold-search nil))
    (should (string-match-p regexp "=iedit= edits"))
    (should (string-match-p regexp "(use-package iedit"))
    (should-not (string-match-p regexp "iedit-mode-extra"))
    (should-not (string-match-p regexp "my-iedit"))))

(ert-deftest kittymacs-lint-removed-packages-are-not-mentioned ()
  (let ((names (kittymacs-lint--removed-packages))
        (files (append (kittymacs-lint--pages)
                       (kittymacs-lint--modules)
                       (directory-files (kittymacs-lint--path "nix") t "\\.nix\\'")
                       (list (kittymacs-lint--path "init.el")
                             (kittymacs-lint--path "early-init.el")
                             (kittymacs-lint--path "lisp/keybindings.org")
                             (kittymacs-lint--path "lisp/private.example.el"))))
        found)
    (should (> (length names) 10))
    (dolist (name names)
      (dolist (file files)
        (pcase-dolist (`(,line . ,text)
                       (kittymacs-lint--lines-matching (kittymacs-lint--name-regexp name) file))
          (unless (kittymacs-lint--history-line-p text)
            (push (format "%s:%d: %s" (file-name-nondirectory file) line name) found)))))
    (should-not (reverse found))))

;;; Prose that goes stale by itself

(defconst kittymacs-lint-package-count-regexp
  (concat "\\b\\(?:[0-9][0-9]+\\|"
          "\\(?:twenty\\|thirty\\|forty\\|fifty\\|sixty\\|seventy\\|eighty\\|ninety\\|hundred\\)\\)"
          "\\(?:[ -][[:alpha:]]+\\)? packages\\b")
  "A package count written out in prose, which the next change makes false.")

(ert-deftest kittymacs-lint-package-count-regexp-tells-counts-from-words ()
  (let ((case-fold-search nil))
    (should (string-match-p kittymacs-lint-package-count-regexp "installing ninety packages"))
    (should (string-match-p kittymacs-lint-package-count-regexp "87 Emacs packages"))
    (should-not (string-match-p kittymacs-lint-package-count-regexp "the two packages"))
    (should-not (string-match-p kittymacs-lint-package-count-regexp "installed packages"))))

(ert-deftest kittymacs-lint-prose-does-not-count-packages ()
  (let (found)
    (dolist (file (kittymacs-lint--pages))
      (pcase-dolist (`(,line . ,text)
                     (kittymacs-lint--lines-matching kittymacs-lint-package-count-regexp file))
        (ignore text)
        (push (format "%s:%d" (file-name-nondirectory file) line) found)))
    (should-not (reverse found))))

;;; Rules the chapters state

(ert-deftest kittymacs-lint-no-condition-beside-ensure ()
  "`use-package' installs before it reads `:if', so the condition guards nothing.
Literate/44-exwm.org has the case that showed it; a `when' around the
declaration is what stops an install."
  (let (found)
    (kittymacs-lint--walk-modules
     (lambda (list file)
       (when (and (eq (car list) 'use-package)
                  (eq (cadr (memq :ensure (cddr list))) t)
                  (seq-some (lambda (keyword) (memq keyword (cddr list)))
                            '(:if :when :unless)))
         (push (format "%s: %s" (file-name-nondirectory file) (cadr list)) found))))
    (should-not (reverse found))))

(defconst kittymacs-lint-after-init-exempt '("kittymacs-defaults.el")
  "Modules that may use `add-hook' on `after-init-hook' directly.
Other modules require the defaults while byte-compiling alone, before init.el
has defined `kittymacs-after-init', so a call at its top level would fail.")

(ert-deftest kittymacs-lint-after-init-goes-through-the-guard ()
  "literate/10-startup.org: an uncaught error there ends startup, or the daemon."
  (let (found)
    (kittymacs-lint--walk-modules
     (lambda (list file)
       (when (and (eq (car list) 'add-hook)
                  (equal (cadr list) ''after-init-hook)
                  (not (member (file-name-nondirectory file)
                               kittymacs-lint-after-init-exempt)))
         (push (format "%s: %S" (file-name-nondirectory file) (nth 2 list)) found))))
    (should-not (reverse found))))

(ert-deftest kittymacs-lint-private-example-names-real-options ()
  "An option the template offers must exist, or following it does nothing."
  (let ((known (make-hash-table :test #'eq))
        (offered (mapcar
                  (lambda (line)
                    (string-match "(setopt \\(kittymacs-[[:alnum:]-]+\\)" (cdr line))
                    (intern (match-string 1 (cdr line))))
                  (kittymacs-lint--lines-matching
                   "^;+ *(setopt kittymacs-"
                   (kittymacs-lint--path "lisp/private.example.el")))))
    (kittymacs-lint--walk-modules
     (lambda (list _file)
       (when (eq (car list) 'defcustom)
         (puthash (cadr list) t known))))
    (should (> (length offered) 5))
    (should-not (seq-remove (lambda (name) (gethash name known)) offered))))

(ert-deftest kittymacs-lint-headers-name-the-chapter-that-writes-the-file ()
  (dolist (file (append (kittymacs-lint--modules)
                        (list (kittymacs-lint--path "init.el")
                              (kittymacs-lint--path "early-init.el"))))
    (let* ((relative (file-relative-name file kittymacs-lint-root))
           (header (kittymacs-lint--lines-matching "Generated from literate/" file))
           (chapter (and header
                         (string-match "literate/[^ ;]+\\.org" (cdar header))
                         (match-string 0 (cdar header)))))
      (should (equal (list relative t) (list relative (and chapter t))))
      (should (equal (list relative chapter t)
                     (list relative chapter
                           (and (kittymacs-lint--lines-matching
                                 (concat ":tangle \\.\\./" (regexp-quote relative))
                                 (kittymacs-lint--path chapter))
                                t)))))))

;;; kittymacs-lint-tests.el ends here
