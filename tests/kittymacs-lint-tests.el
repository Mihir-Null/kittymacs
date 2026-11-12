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

(defun kittymacs-lint--shipped-files ()
  "Every file a machine runs or a reader follows, besides the pages."
  (append (kittymacs-lint--modules)
          (directory-files (kittymacs-lint--path "nix") t "\\.nix\\'")
          (list (kittymacs-lint--path "init.el")
                (kittymacs-lint--path "early-init.el")
                (kittymacs-lint--path "lisp/keybindings.org")
                (kittymacs-lint--path "lisp/private.example.el"))))

(ert-deftest kittymacs-lint-removed-packages-are-not-mentioned ()
  (let ((names (kittymacs-lint--removed-packages))
        (files (append (kittymacs-lint--pages) (kittymacs-lint--shipped-files)))
        found)
    (should (> (length names) 10))
    (dolist (name names)
      (dolist (file files)
        (pcase-dolist (`(,line . ,text)
                       (kittymacs-lint--lines-matching (kittymacs-lint--name-regexp name) file))
          (unless (kittymacs-lint--history-line-p text)
            (push (format "%s:%d: %s" (file-name-nondirectory file) line name) found)))))
    (should-not (reverse found))))

(defun kittymacs-lint--atoms (form)
  "Every symbol and string in FORM, however deep."
  (cond ((consp form) (append (kittymacs-lint--atoms (car form))
                              (kittymacs-lint--atoms (cdr form))))
        ((or (stringp form) (and form (symbolp form))) (list form))))

(defun kittymacs-lint--asks-for-msys2-p (atom)
  "Return non-nil if ATOM, from code, reaches for MSYS2.
A symbol asks for the feature or the module.  A string naming a directory looks
for an installation.  Any other string may mention it: a message on Windows does."
  (if (symbolp atom)
      (string-match-p "msys2" (symbol-name atom))
    (string-match-p "msys64\\|ucrt64" atom)))

(ert-deftest kittymacs-lint-msys2-stays-separable ()
  "Code outside the module and the catalogue does not ask for it."
  (let (found)
    (dolist (file (kittymacs-lint--modules))
      (unless (member (file-name-nondirectory file)
                      '("kittymacs-msys2.el" "kittymacs-catalogue.el"))
        (dolist (form (kittymacs-lint--forms file))
          (when-let* ((atoms (seq-filter #'kittymacs-lint--asks-for-msys2-p
                                         (kittymacs-lint--atoms form))))
            (push (format "%s: %S" (file-name-nondirectory file) atoms) found)))))
    (should-not (reverse found))))

(ert-deftest kittymacs-lint-msys2-has-one-gate-in-init ()
  "The module loads from one place, and only when its feature is on."
  (let ((forms (seq-filter (lambda (form)
                             (seq-some #'kittymacs-lint--asks-for-msys2-p
                                       (kittymacs-lint--atoms form)))
                           (kittymacs-lint--forms (kittymacs-lint--path "init.el")))))
    (should (equal forms
                   '((when (kittymacs-feature-p 'msys2-fallback)
                       (kittymacs-require-module 'kittymacs-msys2)))))))

;;; Host names

(defconst kittymacs-lint-host-name-regexp
  (concat "\\b"
          (regexp-opt '("EmptyNet" "NixNet" "cc-agentic-stack" "Sandia" "sandia"
                        "McQueenix" "mcqueenix" "McMissile" "mcmissile"
                        "Mack" "mack" "ChickHicks" "chickhicks"
                        "Radiator Springs" "radiator-springs" "mmtalat")
                      t)
          "\\b")
  "One person's machines and their configuration.  A host plugs in through
`kittymacs-host-directories', so nothing shipped needs to name one.")

(ert-deftest kittymacs-lint-host-name-regexp-matches-whole-names-only ()
  (let ((case-fold-search nil))
    (should (string-match-p kittymacs-lint-host-name-regexp "(on EmptyNet, Caps Lock)"))
    (should (string-match-p kittymacs-lint-host-name-regexp "~/.local/share/cc-agentic-stack/"))
    (should-not (string-match-p kittymacs-lint-host-name-regexp "a mackerel"))
    (should-not (string-match-p kittymacs-lint-host-name-regexp "the Mac"))))

(defun kittymacs-lint--host-name-files ()
  "Every file the host-name lint reads.
This file holds the names, so it is the one test left out."
  (append (kittymacs-lint--pages)
          (kittymacs-lint--shipped-files)
          (remove (kittymacs-lint--path "tests/kittymacs-lint-tests.el")
                  (directory-files (kittymacs-lint--path "tests") t "\\.el\\'"))
          (directory-files-recursively (kittymacs-lint--path "tools") "")
          (directory-files-recursively (kittymacs-lint--path ".github") "")
          (list (kittymacs-lint--path "AGENTS.md")
                (kittymacs-lint--path ".dir-locals.el")
                (kittymacs-lint--path "justfile")
                (kittymacs-lint--path "flake.nix"))))

(ert-deftest kittymacs-lint-host-name-scope-holds-what-it-names ()
  "A moved file or an empty directory must not narrow the scan unnoticed."
  (let ((files (kittymacs-lint--host-name-files)))
    (dolist (name '("AGENTS.md" ".dir-locals.el" "tools/tangle.el"
                    ".github/dependabot.yml" ".github/workflows/ci.yml"))
      (should (member (kittymacs-lint--path name) files))
      (should (file-regular-p (kittymacs-lint--path name))))
    (should-not (member (kittymacs-lint--path "tests/kittymacs-lint-tests.el") files))))

(ert-deftest kittymacs-lint-nothing-shipped-names-a-host ()
  (let ((files (kittymacs-lint--host-name-files))
        found)
    (should (> (length files) 50))
    (dolist (file files)
      (pcase-dolist (`(,line . ,_text)
                     (kittymacs-lint--lines-matching kittymacs-lint-host-name-regexp file))
        (push (format "%s:%d" (file-name-nondirectory file) line) found)))
    (should-not (reverse found))))

(ert-deftest kittymacs-lint-agent-mcp-servers-default-to-none ()
  "A host chooses the servers, so a fresh install starts none of them."
  (let (defaults)
    (kittymacs-lint--walk-modules
     (lambda (list _file)
       (when (and (eq (car list) 'defcustom)
                  (eq (cadr list) 'kittymacs-agent-mcp-servers))
         (push (nth 2 list) defaults))))
    (should (equal defaults '(nil)))))

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

(ert-deftest kittymacs-lint-nothing-before-private-declares-a-package ()
  "These load before host files and private.el, too early for them to choose."
  (dolist (name '("kittymacs-catalogue" "kittymacs-features" "kittymacs-defaults" "kittymacs-platform"))
    (let (found)
      (dolist (form (kittymacs-lint--forms (kittymacs-lint--path (format "lisp/%s.el" name))))
        (kittymacs-lint--walk
         form
         (lambda (list)
           (when (eq (car list) 'use-package)
             (push (cadr list) found)))))
      (should (equal (list name nil) (list name found))))))

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

;;; Modules a later change gates apart

(defconst kittymacs-lint-separable-modules
  '((kittymacs-org)
    (kittymacs-org-extras kittymacs-org)
    (kittymacs-org-roam)
    (kittymacs-reading))
  "Each module and the others of this list it may lean on.
`init.el' decides per feature whether each of them loads, so one must not
need another that may be off.  `bound-and-true-p' and its like ask first, which
is allowed; so does waiting for the other with `with-eval-after-load'.")

(defconst kittymacs-lint-definers
  '(defun defmacro defcustom defconst defvar defvar-local defvar-keymap
          define-minor-mode defgroup defface)
  "What makes a name belong to the module that writes it.")

(defun kittymacs-lint--symbols (form skip)
  "Return the symbols in FORM, leaving out each list SKIP returns non-nil for."
  (cond ((symbolp form) (and form (list form)))
        ((and (consp form) (not (funcall skip form)))
         (let (symbols)
           (while (consp form)
             (setq symbols (nconc (kittymacs-lint--symbols (car form) skip) symbols)
                   form (cdr form)))
           (nconc (kittymacs-lint--symbols form skip) symbols)))))

(defun kittymacs-lint--defined-names (forms)
  "Return the names FORMS define; a `defvar' without a value only declares."
  (let (names)
    (dolist (form forms)
      (kittymacs-lint--walk
       form
       (lambda (list)
         (when (and (memq (car list) kittymacs-lint-definers)
                    (symbolp (cadr list))
                    (or (not (eq (car list) 'defvar)) (cddr list)))
           (push (cadr list) names)))))
    names))

(defun kittymacs-lint--foreign-uses (forms foreign)
  "Return the names of the list FOREIGN that FORMS use without asking first."
  (seq-uniq
   (seq-filter
    (lambda (symbol) (memq symbol foreign))
    (seq-mapcat
     (lambda (form)
       (kittymacs-lint--symbols
        form
        (lambda (list)
          (pcase list
            (`(,(or 'bound-and-true-p 'boundp 'fboundp 'featurep 'declare-function) . ,_) t)
            (`(defvar ,_) t)
            (`(with-eval-after-load ',feature . ,_) (memq feature foreign))))))
     forms))))

(defun kittymacs-lint--catalogue ()
  "Return the catalogue, read but not evaluated."
  (let ((definition (car (kittymacs-lint--forms (kittymacs-lint--path "lisp/kittymacs-catalogue.el")))))
    (cadr (nth 2 definition))))

(defun kittymacs-lint--module-names (module)
  "Return what belongs to MODULE: the module, its names and its packages."
  (cons module
        (append (kittymacs-lint--defined-names
                 (kittymacs-lint--forms (kittymacs-lint--path (format "lisp/%s.el" module))))
                (seq-mapcat (lambda (entry)
                              (when (eq (plist-get (cdr entry) :module) module)
                                (plist-get (cdr entry) :packages)))
                            (kittymacs-lint--catalogue)))))

(ert-deftest kittymacs-lint-foreign-uses-tells-asking-from-using ()
  (let ((foreign '(other-fn other-var other-module)))
    (should (equal (kittymacs-lint--foreign-uses '((require 'other-module)) foreign)
                   '(other-module)))
    (should (equal (kittymacs-lint--foreign-uses '((defun mine () (other-fn))) foreign)
                   '(other-fn)))
    (should (equal (kittymacs-lint--foreign-uses '((keymap-set m "a" (cons "a" #'other-fn))) foreign)
                   '(other-fn)))
    (should (equal (kittymacs-lint--foreign-uses '((setq a (cons 1 other-var))) foreign)
                   '(other-var)))
    (should-not (kittymacs-lint--foreign-uses
                 '((defvar other-var)
                   (declare-function other-fn "other")
                   (when (fboundp 'other-fn) (ignore))
                   (setq a (bound-and-true-p other-var))
                   (with-eval-after-load 'other-module (other-fn)))
                 foreign))))

(ert-deftest kittymacs-lint-defined-names-leave-out-declarations ()
  (should (equal (sort (kittymacs-lint--defined-names
                        '((defvar declared)
                          (defvar defined nil)
                          (defun my-fn ())
                          (when gate (defcustom my-option t "Doc."))))
                       #'string<)
                 '(defined my-fn my-option))))

(ert-deftest kittymacs-lint-separable-modules-do-not-need-each-other ()
  (pcase-dolist (`(,module . ,allowed) kittymacs-lint-separable-modules)
    (let* ((others (seq-remove (lambda (other) (or (eq other module) (memq other allowed)))
                               (mapcar #'car kittymacs-lint-separable-modules)))
           (foreign (seq-mapcat #'kittymacs-lint--module-names others))
           (forms (kittymacs-lint--forms (kittymacs-lint--path (format "lisp/%s.el" module)))))
      (should (> (length foreign) 10))
      (should (equal (list module nil)
                     (list module (kittymacs-lint--foreign-uses forms foreign)))))))

(ert-deftest kittymacs-lint-catalogue-says-the-separable-features-stand-alone ()
  (let ((features (seq-filter
                   (lambda (entry)
                     (assq (plist-get (cdr entry) :module) kittymacs-lint-separable-modules))
                   (kittymacs-lint--catalogue))))
    (should (>= (length features) 3))
    (dolist (entry features)
      (should (equal (list (car entry) nil)
                     (list (car entry)
                           (seq-filter (lambda (dep) (assq dep features))
                                       (plist-get (cdr entry) :deps))))))))

;;; Load order: nothing hooks a function that loads later

(defun kittymacs-lint--module-order ()
  "The modules `init.el' loads, in the order it loads them."
  (let (order)
    (dolist (form (kittymacs-lint--forms (kittymacs-lint--path "init.el")))
      (kittymacs-lint--walk
       form
       (lambda (list)
         (pcase list
           (`(,(or 'require 'kittymacs-require-module) ',(and module (pred symbolp)))
            (when (and (file-exists-p (kittymacs-lint--path (format "lisp/%s.el" module)))
                       (not (memq module order)))
              (push module order)))))))
    (nreverse order)))

(defun kittymacs-lint--hooked-functions (forms modules)
  "Return the named functions FORMS hand to `advice-add' or `add-hook'.
A use behind `fboundp', or inside `with-eval-after-load' of one of MODULES,
waits for the function, so it is left out."
  (let (found)
    (dolist (form forms)
      (kittymacs-lint--symbols
       form
       (lambda (list)
         (pcase list
           (`(,(or 'when 'if 'and) (fboundp . ,_) . ,_) t)
           (`(with-eval-after-load ',(pred (lambda (feature) (memq feature modules))) . ,_) t)
           ((or `(advice-add ,_ ,_ ,reference . ,_) `(add-hook ,_ ,reference . ,_))
            (pcase reference
              ((or `(function ,(and name (pred symbolp))) `(quote ,(and name (pred symbolp))))
               (push name found)))
            nil)))))
    (seq-uniq found)))

(defun kittymacs-lint--load-order-hazards (modules)
  "Return (MODULE FUNCTION HOME) for each function MODULE hooks before HOME defines it.
MODULES is a list of (MODULE . FORMS), in load order."
  (let ((homes (make-hash-table :test #'eq))
        (names (mapcar #'car modules))
        hazards)
    (pcase-dolist (`(,module . ,forms) modules)
      (dolist (name (kittymacs-lint--defined-names forms))
        (unless (gethash name homes) (puthash name module homes))))
    (pcase-dolist (`(,module . ,forms) modules)
      (dolist (function (kittymacs-lint--hooked-functions forms names))
        (when-let* ((home (gethash function homes))
                    ((memq home (cdr (memq module names)))))
          (push (list module function home) hazards))))
    (nreverse hazards)))

(ert-deftest kittymacs-lint-load-order-hazards-find-the-doom-modeline-advice ()
  "The shape kittymacs #121 fixed by hand: the look advised with a remote predicate."
  (let ((ui '((with-eval-after-load 'doom-modeline
                (advice-add 'doom-modeline-update-env :before-until
                            #'kittymacs-remote-buffer-p))))
        (remote '((defun kittymacs-remote-buffer-p (&rest _) nil))))
    (should (equal (kittymacs-lint--load-order-hazards
                    `((kittymacs-ui . ,ui) (kittymacs-remote . ,remote)))
                   '((kittymacs-ui kittymacs-remote-buffer-p kittymacs-remote))))
    (should-not (kittymacs-lint--load-order-hazards
                 `((kittymacs-remote . ,remote) (kittymacs-ui . ,ui))))))

(ert-deftest kittymacs-lint-hooked-functions-tell-waiting-from-hooking ()
  (should (equal (sort (kittymacs-lint--hooked-functions
                        '((add-hook 'a-hook #'by-function)
                          (add-hook 'a-hook 'by-quote 90)
                          (advice-add 'f :around #'advised)
                          (add-hook 'a-hook (lambda () (inner)))
                          (when (fboundp 'guarded) (add-hook 'a-hook #'guarded))
                          (with-eval-after-load 'later (add-hook 'a-hook #'waits))
                          (with-eval-after-load 'other-package (add-hook 'a-hook #'counted)))
                        '(later))
                       #'string<)
                 '(advised by-function by-quote counted))))

(ert-deftest kittymacs-lint-no-module-hooks-a-function-that-loads-later ()
  "Advice or a hook that names a later module's function fails until that module loads."
  (let ((order (kittymacs-lint--module-order)))
    (should (> (length order) 20))
    (should (equal (kittymacs-lint--load-order-hazards
                    (mapcar (lambda (module)
                              (cons module (kittymacs-lint--forms
                                            (kittymacs-lint--path (format "lisp/%s.el" module)))))
                            order))
                   nil))))

;;; Org waits for its first use

(defconst kittymacs-lint-org-library-regexp "\\`\\(?:org\\|ol\\|ox\\)\\(?:-\\|\\'\\)"
  "Names of Org's libraries and of the packages that load them.")

(defconst kittymacs-lint-later-forms
  '(defun defmacro lambda function define-minor-mode define-derived-mode
          with-eval-after-load eval-after-load use-package)
  "Forms whose body does not run as the module loads.
`eval-when-compile' is not one of them: a module that loads as source, as these
do, runs its body at once.")

(defun kittymacs-lint--eager-org-requires (form)
  "Return the Org libraries FORM requires as it is evaluated."
  (let (found)
    (kittymacs-lint--symbols
     form
     (lambda (list)
       (pcase list
         (`(require ',(and library (pred symbolp)) . ,_)
          (when (string-match-p kittymacs-lint-org-library-regexp (symbol-name library))
            (push library found))
          t)
         (`(,(pred (lambda (head) (memq head kittymacs-lint-later-forms))) . ,_) t))))
    found))

(defun kittymacs-lint--org-package-loads-at-once-p (form)
  "Return non-nil if the `use-package' FORM names Org's world and would load it."
  (pcase form
    (`(use-package ,(and name (pred symbolp)) . ,body)
     (and (string-match-p kittymacs-lint-org-library-regexp (symbol-name name))
          (if (memq :demand body)
              (not (memq :after body))
            (not (seq-some (lambda (keyword) (memq keyword body))
                           '(:after :defer :hook :commands))))))))

(ert-deftest kittymacs-lint-org-rules-tell-waiting-from-loading ()
  (should (equal (kittymacs-lint--eager-org-requires '(require 'org)) '(org)))
  (should (equal (kittymacs-lint--eager-org-requires '(eval-when-compile (require 'org-id)))
                 '(org-id)))
  (should (equal (kittymacs-lint--eager-org-requires '(when gate (require 'ox-html))) '(ox-html)))
  (should-not (kittymacs-lint--eager-org-requires '(defun f () (require 'org))))
  (should-not (kittymacs-lint--eager-org-requires '(with-eval-after-load 'x (require 'org))))
  (should-not (kittymacs-lint--eager-org-requires '(require 'organic)))
  (should (kittymacs-lint--org-package-loads-at-once-p '(use-package org-x :ensure t)))
  (should (kittymacs-lint--org-package-loads-at-once-p '(use-package org-x :demand t)))
  (should-not (kittymacs-lint--org-package-loads-at-once-p '(use-package org-x :after org :demand t)))
  (should-not (kittymacs-lint--org-package-loads-at-once-p '(use-package org-x :hook (a . b))))
  (should-not (kittymacs-lint--org-package-loads-at-once-p '(use-package meow :ensure t))))

(ert-deftest kittymacs-lint-no-module-loads-org-as-it-loads ()
  (let (found)
    (dolist (file (kittymacs-lint--modules))
      (dolist (form (kittymacs-lint--forms file))
        (when-let* ((libraries (kittymacs-lint--eager-org-requires form)))
          (push (format "%s: %S" (file-name-nondirectory file) libraries) found))
        (kittymacs-lint--walk
         form
         (lambda (list)
           (when (kittymacs-lint--org-package-loads-at-once-p list)
             (push (format "%s: %s" (file-name-nondirectory file) (cadr list)) found))))))
    (should-not (reverse found))))

(ert-deftest kittymacs-lint-setopt-does-not-load-org ()
  "`setopt' calls `custom-load-symbol', which loads what Customize's index lists.
For these names that is an Org library, so `setq' sets them instead."
  (require 'cus-load)
  (let (found checked)
    (kittymacs-lint--walk-modules
     (lambda (list file)
       (when (eq (car list) 'setopt)
         (let ((rest (cdr list)))
           (while (consp rest)
             (when (and (symbolp (car rest))
                        (string-match-p kittymacs-lint-org-library-regexp
                                        (symbol-name (car rest))))
               (push (car rest) checked)
               (when (get (car rest) 'custom-loads)
                 (push (format "%s: %s" (file-name-nondirectory file) (car rest)) found)))
             (setq rest (cddr rest)))))))
    (should (> (length checked) 20))
    (should-not (reverse found))))

;;; The look without doom

(defun kittymacs-lint--doom-names (forms)
  "Return the doom names in FORMS that a gate on the declarations would leave."
  (seq-filter
   (lambda (symbol) (string-prefix-p "doom-" (symbol-name symbol)))
   (seq-mapcat
    (lambda (form)
      (kittymacs-lint--symbols
       form
       (lambda (list)
         (pcase list
           ;; A theme's name is data; only a package can make it work.
           (`(defcustom . ,_) t)
           (`(featurep . ,_) t)
           (`(kittymacs-feature-p . ,_) t)
           (`(when (featurep . ,_) . ,_) t)
           (`(use-package ,(and name (pred symbolp)) . ,_)
            (string-prefix-p "doom-" (symbol-name name)))))))
    forms)))

(ert-deftest kittymacs-lint-doom-names-tell-a-guard-from-a-use ()
  (should (equal (kittymacs-lint--doom-names '((defun f () (doom-themes-org-config))))
                 '(doom-themes-org-config)))
  (should (equal (kittymacs-lint--doom-names '((use-package nerd-icons :config (doom-modeline-mode 1))))
                 '(doom-modeline-mode)))
  (should-not (kittymacs-lint--doom-names
               '((defcustom my-theme 'doom-one "Doc.")
                 (when (kittymacs-feature-p 'doom-look) (use-package doom-modeline))
                 (when (featurep 'doom-themes) (doom-themes-org-config))
                 (use-package doom-modeline :config (doom-modeline-mode 1))))))

(ert-deftest kittymacs-lint-only-the-doom-declarations-name-doom ()
  "A later change gates doom-themes and doom-modeline by their declarations alone."
  (let (found)
    (dolist (file (remove (kittymacs-lint--path "lisp/kittymacs-catalogue.el")
                          (kittymacs-lint--modules)))
      (when-let* ((names (kittymacs-lint--doom-names (kittymacs-lint--forms file))))
        (push (format "%s: %S" (file-name-nondirectory file) (seq-uniq names)) found)))
    (should-not (reverse found))))

;;; Backends

(ert-deftest kittymacs-lint-backend-keys-belong-to-the-remote-module ()
  "A key belongs to the module that owns its feature, and core keys are always there."
  (let ((remote (kittymacs-lint--path "lisp/kittymacs-remote.el"))
        (keys '("b" "B")))
    (dolist (key keys)
      (should (assoc key (alist-get 'kittymacs-open-map
                                    (kittymacs-lint--collect-bindings (kittymacs-lint--forms remote))))))
    (dolist (file (remove remote (kittymacs-lint--modules)))
      (let ((bound (alist-get 'kittymacs-open-map
                              (kittymacs-lint--collect-bindings (kittymacs-lint--forms file)))))
        (should-not (seq-some (lambda (key) (assoc key bound)) keys))))))

;;; kittymacs-lint-tests.el ends here
