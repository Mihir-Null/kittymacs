;;; kittymacs-treesit.el --- Portable Tree-sitter policy -*- lexical-binding: t; -*-
;; Generated from literate/74-languages.org; edit the Org source, then tangle.

;;; Commentary:
;; Lambda supplies useful grammar recipes, but moving repository heads can start
;; emitting a parser ABI newer than an older supported Emacs release can load.
;; Keep the recipes reproducible here and only remap a classic major mode after
;; Emacs has successfully loaded the corresponding grammar.

;;; Code:

(require 'cl-lib)
(require 'rx)
(require 'treesit)
(defgroup kittymacs-treesit nil
  "Portable Tree-sitter policy for the starter configuration."
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
(defun kittymacs-treesit--nix-source ()
  "Return the pinned Nix recipe, with a local Windows compiler when present."
  (let ((compiler
         (when (and (eq system-type 'windows-nt)
                    (boundp 'kittymacs-msys2-root))
           (file-name-concat kittymacs-msys2-root "ucrt64" "bin" "gcc.exe"))))
    (append
     '(nix "https://github.com/nix-community/tree-sitter-nix"
           "ea1d87f7996be1329ef6555dcacfa63a69bd55c6")
     (when (and compiler (file-executable-p compiler))
       (list "src" compiler)))))
(defcustom kittymacs-treesit-language-source-alist
  `((bash "https://github.com/tree-sitter/tree-sitter-bash"
          "8509e3229b863c255ab6b61f3bf74ad0bf14e8bc")
    (cmake "https://github.com/uyha/tree-sitter-cmake"
           "ca627bb5828616b6246aafdc3c3222789e728e37")
    (css "https://github.com/tree-sitter/tree-sitter-css"
         "4a9aab1668bf13d024710420648ef9a9ee6ccc17")
    (elisp "https://github.com/Wilfred/tree-sitter-elisp"
           "3a8f590258404ae955d46149edaaa5028078c6bc")
    (go "https://github.com/tree-sitter/tree-sitter-go"
        "c350fa54d38af725c40d061a602ee3205ef1e072")
    (html "https://github.com/tree-sitter/tree-sitter-html"
          "73a3947324f6efddf9e17c0ea58d454843590cc0")
    (javascript "https://github.com/tree-sitter/tree-sitter-javascript"
                "39798e26b6d4dbcee8e522b8db83f8b2df33a5ea" "src")
    (json "https://github.com/tree-sitter/tree-sitter-json"
          "254c42a6476413b776221e03982ac8ae159eeb72")
    (make "https://github.com/alemuller/tree-sitter-make"
          "a4b9187417d6be349ee5fd4b6e77b4172c6827dd")
    (markdown "https://github.com/ikatyang/tree-sitter-markdown"
              "8b8b77af0493e26d378135a3e7f5ae25b555b375")
    ,(kittymacs-treesit--nix-source)
    (python "https://github.com/tree-sitter/tree-sitter-python"
            "c5fca1a186e8e528115196178c28eefa8d86b0b0")
    (toml "https://github.com/tree-sitter/tree-sitter-toml"
          "342d9be207c2dba869b9967124c679b5e6fd0ebe")
    (tsx "https://github.com/tree-sitter/tree-sitter-typescript"
         "75b3874edb2dc714fb1fd77a32013d0f8699989f" "tsx/src")
    (typescript "https://github.com/tree-sitter/tree-sitter-typescript"
                "75b3874edb2dc714fb1fd77a32013d0f8699989f"
                "typescript/src")
    (typst "https://github.com/Ziqi-Yang/tree-sitter-typst"
           "46cf4ded12ee974a70bf8457263b67ad7ee0379d")
    (yaml "https://github.com/ikatyang/tree-sitter-yaml"
          "0e36bed171768908f331ff7dff9d956bae016efb"))
  "Pinned grammar recipes whose generated parsers use ABI 13 or 14.

Those ABIs are loadable by Emacs 30 as well as newer Emacs releases.  Each
entry has the same shape accepted by `treesit-language-source-alist':
(LANGUAGE REPOSITORY REVISION &optional SOURCE-DIRECTORY CC CXX)."
  :type '(repeat sexp)
  :group 'kittymacs-treesit)
(defconst kittymacs-treesit-mode-remaps
  '((yaml-mode yaml-ts-mode yaml)
    (bash-mode bash-ts-mode bash)
    (typescript-mode typescript-ts-mode typescript)
    (json-mode json-ts-mode json)
    (css-mode css-ts-mode css)
    (python-mode python-ts-mode python)
    (typst-mode typst-ts-mode typst)
    (nix-mode nix-ts-mode nix))
  "Classic mode, Tree-sitter mode, and grammar triples managed here.")
(defun kittymacs-treesit--language-available-p (language)
  "Return non-nil when LANGUAGE can be loaded by this Emacs build."
  (kittymacs-treesit--sync-grammar-directory)
  (and (treesit-available-p)
       (condition-case nil
           (treesit-language-available-p language)
         (error nil))))
(defun kittymacs-treesit-apply-pinned-sources ()
  "Replace Lambda's moving grammar recipes with pinned recipes."
  (dolist (source kittymacs-treesit-language-source-alist)
    (setf (alist-get (car source) treesit-language-source-alist)
          (cdr source))))
(defun kittymacs-treesit--git-clone-revision
    (original-function url revision workdir)
  "Clone URL at exact REVISION into WORKDIR for `treesit'.

Emacs 30 documents REVISION as a tag or branch and implements it with
`git clone --branch', which cannot accept a raw commit hash.  Exact commits are
the reproducible unit needed here, so fetch a single detached commit when the
recipe contains a 40-character hash.  Delegate every other recipe to
ORIGINAL-FUNCTION unchanged."
  (if (and (stringp revision)
           (string-match-p (rx string-start (= 40 xdigit) string-end)
                           revision))
      (progn
        (message "Cloning pinned Tree-sitter revision")
        (treesit--call-process-signal
         "git" nil t nil "init" "--quiet" workdir)
        (treesit--call-process-signal
         "git" nil t nil "-C" workdir "remote" "add" "origin" url)
        (treesit--call-process-signal
         "git" nil t nil "-C" workdir "fetch" "--depth" "1" "--quiet"
         "origin" revision)
        (treesit--call-process-signal
         "git" nil t nil "-C" workdir "checkout" "--detach" "--quiet"
         "FETCH_HEAD"))
    (funcall original-function url revision workdir)))
(defun kittymacs-treesit-refresh-mode-remaps (&rest _)
  "Refresh managed mode remaps for the grammars available right now.

Any unconditional remaps inherited from Lambda are removed first.  A remap is
then added only when its target mode exists and its grammar loads successfully."
  (interactive)
  (let ((managed-modes (mapcar #'car kittymacs-treesit-mode-remaps)))
    (setq major-mode-remap-alist
          (cl-remove-if
           (lambda (remap) (memq (car remap) managed-modes))
           major-mode-remap-alist)))
  (dolist (spec kittymacs-treesit-mode-remaps)
    (pcase-let ((`(,classic-mode ,treesit-mode ,language) spec))
      (when (and (fboundp treesit-mode)
                 (kittymacs-treesit--language-available-p language))
        (add-to-list 'major-mode-remap-alist
                     (cons classic-mode treesit-mode) t))))
  major-mode-remap-alist)
(defun kittymacs-treesit-install-language-grammar (language)
  "Install pinned grammar LANGUAGE, then refresh conditional remaps."
  (interactive
   (list
    (intern
     (completing-read
      "Install pinned grammar: "
      (mapcar (lambda (source) (symbol-name (car source)))
              kittymacs-treesit-language-source-alist)
      nil t))))
  (unless (assq language kittymacs-treesit-language-source-alist)
    (user-error "No pinned Tree-sitter recipe for %s" language))
  (kittymacs-treesit--sync-grammar-directory)
  (unless (treesit-available-p)
    (user-error "This Emacs build does not include Tree-sitter support"))
  (kittymacs-treesit-apply-pinned-sources)
  (treesit-install-language-grammar
   language kittymacs-treesit-grammar-directory)
  (kittymacs-treesit-refresh-mode-remaps))
(defun kittymacs-treesit-install-all-grammars ()
  "Install every missing pinned grammar and refresh mode remaps."
  (interactive)
  (kittymacs-treesit--sync-grammar-directory)
  (unless (treesit-available-p)
    (user-error "This Emacs build does not include Tree-sitter support"))
  (kittymacs-treesit-apply-pinned-sources)
  (dolist (source kittymacs-treesit-language-source-alist)
    (let ((language (car source)))
      (unless (kittymacs-treesit--language-available-p language)
        (treesit-install-language-grammar
         language kittymacs-treesit-grammar-directory))))
  (kittymacs-treesit-refresh-mode-remaps))
(kittymacs-treesit-apply-pinned-sources)
(kittymacs-treesit-refresh-mode-remaps)
(unless (advice-member-p #'kittymacs-treesit--git-clone-revision
                         #'treesit--git-clone-repo)
  (advice-add #'treesit--git-clone-repo :around
              #'kittymacs-treesit--git-clone-revision))
;; Lambda's bulk command calls the built-in installer directly.  Refresh after
;; each successful installation so a restart is not required before the remap
;; becomes active.
(unless (advice-member-p #'kittymacs-treesit-refresh-mode-remaps
                         #'treesit-install-language-grammar)
  (advice-add #'treesit-install-language-grammar :after
              #'kittymacs-treesit-refresh-mode-remaps))
(provide 'kittymacs-treesit)
;;; kittymacs-treesit.el ends here
