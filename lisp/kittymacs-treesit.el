;;; kittymacs-treesit.el --- Tree-sitter on Emacs's own machinery -*- lexical-binding: t; -*-
;; Generated from literate/74-languages.org; edit the Org source, then tangle.

;;; Commentary:
;; Emacs 31's Tree-sitter modes map their own file types, pin their own
;; grammars and offer to install a missing one.  Turn them all on, keep their
;; grammars in the cache, register the modes that come from packages the same
;; way, and leave the classic mode in charge while a grammar is missing.

;;; Code:

(require 'seq)
(require 'treesit)
(defgroup kittymacs-treesit nil
  "Tree-sitter modes and grammars."
  :group 'kittymacs)
(defcustom kittymacs-treesit-grammar-directory
  (expand-file-name "tree-sitter/" kittymacs-cache-dir)
  "Writable directory for compiled Tree-sitter grammar libraries."
  :type 'directory
  :group 'kittymacs-treesit)

(defun kittymacs-treesit--sync-grammar-directory ()
  "Put the currently configured grammar directory first in the search path."
  (setq treesit-extra-load-path
        (cons kittymacs-treesit-grammar-directory
              (delete kittymacs-treesit-grammar-directory
                      treesit-extra-load-path))))

(kittymacs-treesit--sync-grammar-directory)
(setopt treesit-auto-install-grammar 'ask)
(setopt treesit-enabled-modes t)
(defun kittymacs-treesit--nix-source ()
  "Return the pinned Nix recipe, with a local Windows compiler when present."
  (let ((compiler
         (when (and (eq system-type 'windows-nt)
                    (boundp 'kittymacs-msys2-root))
           (file-name-concat kittymacs-msys2-root "ucrt64" "bin" "gcc.exe"))))
    (append
     '(nix "https://github.com/nix-community/tree-sitter-nix"
           :commit "ea1d87f7996be1329ef6555dcacfa63a69bd55c6")
     (when (and compiler (file-executable-p compiler))
       (list :cc compiler)))))
(defcustom kittymacs-treesit-language-source-alist
  `(,(kittymacs-treesit--nix-source))
  "Pinned grammar recipes for Tree-sitter modes that Emacs does not ship.

Each entry has the shape accepted by `treesit-language-source-alist':
\(LANGUAGE REPOSITORY [KEYWORD VALUE]...), with :commit naming an exact
commit."
  :type '(repeat sexp)
  :group 'kittymacs-treesit)
(defun kittymacs-treesit-apply-pinned-sources ()
  "Put the pinned recipes into `treesit-language-source-alist'."
  (dolist (source kittymacs-treesit-language-source-alist)
    (setf (alist-get (car source) treesit-language-source-alist)
          (cdr source))))
(defun kittymacs-treesit-register-mode (classic-mode treesit-mode language)
  "Treat TREESIT-MODE, from a package, like a Tree-sitter mode Emacs ships.
Files that open in CLASSIC-MODE open in TREESIT-MODE while
`treesit-enabled-modes' enables it, and TREESIT-MODE offers to build the
grammar for LANGUAGE before it starts, as `treesit-auto-install-grammar'
says."
  (add-to-list 'treesit-major-mode-remap-alist
               (cons classic-mode treesit-mode))
  (when (or (eq treesit-enabled-modes t)
            (memq treesit-mode treesit-enabled-modes))
    (add-to-list 'major-mode-remap-alist (cons classic-mode treesit-mode)))
  (advice-add treesit-mode :before
              (lambda (&rest _) (treesit-ensure-installed language))
              '((name . kittymacs-treesit-ensure-grammar))))
(defun kittymacs-treesit--classic-mode (treesit-mode)
  "Return the mode to use instead of TREESIT-MODE while its grammar is missing."
  (let ((classic (car (rassq treesit-mode treesit-major-mode-remap-alist))))
    (if (and classic (fboundp classic)) classic #'fundamental-mode)))
(defun kittymacs-treesit--disable (treesit-mode)
  "Leave TREESIT-MODE out of `treesit-enabled-modes' for this session."
  (customize-set-variable
   'treesit-enabled-modes
   (remq treesit-mode
         (if (eq treesit-enabled-modes t)
             (seq-uniq (mapcar #'cdr treesit-major-mode-remap-alist))
           treesit-enabled-modes))))
(defun kittymacs-treesit--fall-back
    (set-auto-mode-0 mode &optional keep-mode-if-same)
  "Apply MODE with SET-AUTO-MODE-0; leave a Tree-sitter mode with no parser.
KEEP-MODE-IF-SAME is passed on.  Return what SET-AUTO-MODE-0 returns, or
the mode that replaced the Tree-sitter one."
  (let* ((warning-suppress-types (cons '(treesit) warning-suppress-types))
         (target (major-mode-remap mode))
         failure
         (applied
          (condition-case err
              (funcall set-auto-mode-0 mode keep-mode-if-same)
            (error (if (rassq target treesit-major-mode-remap-alist)
                       (progn (setq failure err) nil)
                     (signal (car err) (cdr err))))))
         (treesit-mode
          (seq-find (lambda (m) (rassq m treesit-major-mode-remap-alist))
                    (if failure (list major-mode target) (list major-mode)))))
    (cond
     ((and treesit-mode
           (or failure (and applied (not (eq applied :keep))))
           (null (treesit-parser-list)))
      (let ((classic (kittymacs-treesit--classic-mode treesit-mode)))
        (unless (> (buffer-size) treesit-max-buffer-size)
          (kittymacs-treesit--disable treesit-mode))
        (funcall classic)
        (message "%s: no Tree-sitter grammar loaded, using %s"
                 treesit-mode classic)
        major-mode))
     (failure (signal (car failure) (cdr failure)))
     (t applied))))
(defcustom kittymacs-treesit-languages
  '(bash cmake css dockerfile go gomod html javascript jsdoc json nix python
         rust toml tsx typescript yaml)
  "Grammars that `kittymacs-treesit-install-grammars' builds by default."
  :type '(repeat symbol)
  :group 'kittymacs-treesit)
(defun kittymacs-treesit--load-recipes ()
  "Load every Tree-sitter mode's library, so its grammar recipe is known."
  (dolist (mode (seq-uniq (mapcar #'cdr treesit-major-mode-remap-alist)))
    (when (autoloadp (symbol-function mode))
      (autoload-do-load (symbol-function mode) mode)))
  (kittymacs-treesit-apply-pinned-sources))
(defun kittymacs-treesit-install-grammars (languages &optional rebuild)
  "Build the grammars for LANGUAGES into `kittymacs-treesit-grammar-directory'.
A grammar that already loads is skipped unless REBUILD is non-nil.
Interactively, build `kittymacs-treesit-languages'; with a prefix argument,
choose the languages and rebuild them.  Return the languages built."
  (interactive
   (progn
     (kittymacs-treesit--load-recipes)
     (if current-prefix-arg
         (list (mapcar #'intern
                       (completing-read-multiple
                        "Build grammars: "
                        (mapcar (lambda (source) (symbol-name (car source)))
                                treesit-language-source-alist)
                        nil t))
               t)
       (list kittymacs-treesit-languages nil))))
  (kittymacs-treesit--sync-grammar-directory)
  (unless (treesit-available-p)
    (user-error "This Emacs build does not include Tree-sitter support"))
  (kittymacs-treesit--load-recipes)
  (let (built)
    (dolist (language languages)
      (unless (assq language treesit-language-source-alist)
        (user-error "No grammar recipe for %s" language))
      (when (or rebuild (not (treesit-language-available-p language)))
        (treesit-install-language-grammar
         language kittymacs-treesit-grammar-directory)
        (push language built)))
    (setopt treesit-enabled-modes t)
    (nreverse built)))
(kittymacs-treesit-apply-pinned-sources)
(unless (advice-member-p #'kittymacs-treesit--fall-back #'set-auto-mode-0)
  (advice-add #'set-auto-mode-0 :around #'kittymacs-treesit--fall-back))
(provide 'kittymacs-treesit)
;;; kittymacs-treesit.el ends here
