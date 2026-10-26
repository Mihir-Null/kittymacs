;;; kittymacs-treesit-tests.el --- Tree-sitter policy -*- lexical-binding: t; -*-
;; Run: NIX_GRAMMAR_TEST_DIR=/path/to/build emacs -Q --batch -l tests/kittymacs-treesit-tests.el -f ert-run-tests-batch-and-exit

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'treesit)

;; Native compilation of temporary CL function replacements is irrelevant to
;; this batch-only test harness and can write trampolines outside its fixture.
(when (boundp 'native-comp-enable-subr-trampolines)
  (setq native-comp-enable-subr-trampolines nil))

(defconst kittymacs-treesit-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(defconst kittymacs-treesit-test-library
  (expand-file-name "lisp/kittymacs-treesit.el" kittymacs-treesit-test-root))

;; Ordinary startup defines these before loading the Tree-sitter module.  Give
;; the focused test the same contract without loading the rest of kittymacs.
(defvar kittymacs-cache-dir
  (expand-file-name "var/cache/" kittymacs-treesit-test-root))
(defvar kittymacs-msys2-root "C:/msys64/")

(add-to-list 'load-path (expand-file-name "lisp" kittymacs-treesit-test-root))
(require 'kittymacs-treesit)

;; Stand-ins for a classic mode and the Tree-sitter mode that replaces it.
(define-derived-mode kittymacs-treesit-test-classic-mode prog-mode "Classic")
(define-derived-mode kittymacs-treesit-test-ts-mode prog-mode "TS")

(defmacro kittymacs-treesit-test-with-remap (classic &rest body)
  "Run BODY with CLASSIC remapped to `kittymacs-treesit-test-ts-mode'.
The remap tables and `treesit-enabled-modes' are restored afterwards."
  (declare (indent 1))
  `(let ((treesit-major-mode-remap-alist
          (list (cons ,classic 'kittymacs-treesit-test-ts-mode)))
         (major-mode-remap-alist
          (list (cons ,classic 'kittymacs-treesit-test-ts-mode)))
         (treesit-enabled-modes t))
     (cl-letf (((symbol-function 'treesit-available-p) (lambda () t)))
       ,@body)))

(ert-deftest kittymacs-treesit-grammar-directory-defaults-under-cache ()
  "A fresh configuration keeps compiled grammars in the writable cache."
  (should (equal kittymacs-treesit-grammar-directory
                 (expand-file-name "tree-sitter/" kittymacs-cache-dir)))
  (should (custom-variable-p 'kittymacs-treesit-grammar-directory)))

(ert-deftest kittymacs-treesit-load-honours-override-and-builds-nothing ()
  "Loading puts a private override first and starts no build or process."
  (let ((custom-directory (make-temp-file "kittymacs-grammar-custom" t))
        (kittymacs-treesit-grammar-directory nil)
        (treesit-extra-load-path nil)
        (treesit-language-source-alist nil)
        (major-mode-remap-alist nil)
        (treesit-enabled-modes nil)
        (original-path (getenv "PATH"))
        (original-exec-path (copy-sequence exec-path))
        install-called external-called)
    (setq kittymacs-treesit-grammar-directory custom-directory)
    (unwind-protect
        (cl-letf (((symbol-function 'treesit-install-language-grammar)
                   (lambda (&rest _) (setq install-called t)))
                  ((symbol-function 'call-process)
                   (lambda (&rest _) (setq external-called t)))
                  ((symbol-function 'make-process)
                   (lambda (&rest _) (setq external-called t)))
                  ((symbol-function 'url-retrieve-synchronously)
                   (lambda (&rest _) (setq external-called t))))
          (load kittymacs-treesit-test-library nil nil t))
      (delete-directory custom-directory t))
    (should (equal (car treesit-extra-load-path) custom-directory))
    (should (equal kittymacs-treesit-grammar-directory custom-directory))
    (should (assq 'nix treesit-language-source-alist))
    (should (equal (getenv "PATH") original-path))
    (should (equal exec-path original-exec-path))
    (should-not install-called)
    (should-not external-called)))

(ert-deftest kittymacs-treesit-enables-every-mode-and-asks-for-grammars ()
  "Every Tree-sitter mode Emacs ships is on, and a missing grammar is offered."
  (should (eq treesit-enabled-modes t))
  (should (eq treesit-auto-install-grammar 'ask))
  (when (treesit-available-p)
    (should (eq (alist-get 'python-mode major-mode-remap-alist)
                'python-ts-mode))
    (should (eq (alist-get 'sh-mode major-mode-remap-alist)
                'bash-ts-mode)))
  (should (advice-member-p #'kittymacs-treesit--fall-back #'set-auto-mode-0)))

(ert-deftest kittymacs-treesit-nix-source-is-pinned-to-a-commit ()
  "The Nix recipe names an exact commit, in Emacs 31's keyword form."
  (let ((recipe (assq 'nix kittymacs-treesit-language-source-alist)))
    (should (equal (nth 1 recipe)
                   "https://github.com/nix-community/tree-sitter-nix"))
    (should (string-match-p (rx string-start (= 40 xdigit) string-end)
                            (plist-get (cddr recipe) :commit)))))

(ert-deftest kittymacs-treesit-windows-nix-recipe-uses-msys2-gcc ()
  "Windows grammar builds use an absolute compiler without changing PATH."
  (let ((system-type 'windows-nt)
        (kittymacs-msys2-root "D:/tools/msys64/"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_) t)))
      (should (equal (plist-get (cddr (kittymacs-treesit--nix-source)) :cc)
                     "D:/tools/msys64/ucrt64/bin/gcc.exe"))))
  (let ((system-type 'gnu/linux))
    (should-not (plist-member (cddr (kittymacs-treesit--nix-source)) :cc))))

(ert-deftest kittymacs-treesit-registered-mode-remaps-and-offers-its-grammar ()
  "A package's mode is remapped like Emacs's own and asks for its grammar."
  (let ((treesit-major-mode-remap-alist nil)
        (major-mode-remap-alist nil)
        (treesit-enabled-modes t)
        ensured)
    (unwind-protect
        (progn
          (kittymacs-treesit-register-mode 'kittymacs-treesit-test-classic-mode
                                           'kittymacs-treesit-test-ts-mode 'nix)
          (kittymacs-treesit-register-mode 'kittymacs-treesit-test-classic-mode
                                           'kittymacs-treesit-test-ts-mode 'nix)
          (should (equal treesit-major-mode-remap-alist
                         '((kittymacs-treesit-test-classic-mode
                            . kittymacs-treesit-test-ts-mode))))
          (should (equal major-mode-remap-alist treesit-major-mode-remap-alist))
          (cl-letf (((symbol-function 'treesit-ensure-installed)
                     (lambda (language) (push language ensured))))
            (with-temp-buffer (kittymacs-treesit-test-ts-mode)))
          ;; Registered twice, advised once.
          (should (equal ensured '(nix))))
      (advice-remove 'kittymacs-treesit-test-ts-mode
                     'kittymacs-treesit-ensure-grammar)))
  (let ((treesit-major-mode-remap-alist nil)
        (major-mode-remap-alist nil)
        (treesit-enabled-modes '(python-ts-mode)))
    (unwind-protect
        (progn
          (kittymacs-treesit-register-mode 'kittymacs-treesit-test-classic-mode
                                           'kittymacs-treesit-test-ts-mode 'nix)
          (should treesit-major-mode-remap-alist)
          (should-not major-mode-remap-alist))
      (advice-remove 'kittymacs-treesit-test-ts-mode
                     'kittymacs-treesit-ensure-grammar))))

(ert-deftest kittymacs-treesit-missing-grammar-falls-back-to-classic-mode ()
  "A Tree-sitter mode with no parser hands the file to its classic mode,
and is left out for the rest of the session."
  (kittymacs-treesit-test-with-remap 'kittymacs-treesit-test-classic-mode
    (with-temp-buffer
      (let ((inhibit-message t))
        (set-auto-mode-0 'kittymacs-treesit-test-classic-mode))
      (should (eq major-mode 'kittymacs-treesit-test-classic-mode)))
    (should (listp treesit-enabled-modes))
    (should-not (memq 'kittymacs-treesit-test-ts-mode treesit-enabled-modes))
    (should-not (assq 'kittymacs-treesit-test-classic-mode
                      major-mode-remap-alist))))

(ert-deftest kittymacs-treesit-missing-grammar-without-classic-mode ()
  "A Tree-sitter mode whose classic mode is not installed falls back to
`fundamental-mode', as Emacs does for a mode that is not enabled."
  (kittymacs-treesit-test-with-remap 'kittymacs-treesit-test-absent-mode
    (with-temp-buffer
      (let ((inhibit-message t))
        (set-auto-mode-0 'kittymacs-treesit-test-ts-mode))
      (should (eq major-mode 'fundamental-mode)))))

(ert-deftest kittymacs-treesit-markdown-files-open-in-markdown-ts-mode ()
  "Markdown files reach `markdown-ts-mode', which Emacs 31.1 leaves unmapped."
  (should (eq (assoc-default "README.md" auto-mode-alist #'string-match-p)
              'markdown-ts-mode-maybe))
  (should (fboundp 'markdown-ts-mode-maybe))
  (should (eq (alist-get 'markdown-mode treesit-major-mode-remap-alist)
              'markdown-ts-mode))
  (should (eq (alist-get 'markdown-mode major-mode-remap-alist)
              'markdown-ts-mode)))

(ert-deftest kittymacs-treesit-missing-markdown-grammar-gives-text-mode ()
  "Markdown with no grammar and no `markdown-mode' falls back to `text-mode'."
  (let ((treesit-major-mode-remap-alist
         '((kittymacs-treesit-test-absent-mode . markdown-ts-mode))))
    (should (eq (kittymacs-treesit--classic-mode 'markdown-ts-mode)
                'text-mode))))

(define-derived-mode kittymacs-treesit-test-failing-ts-mode prog-mode "TS!"
  (error "Tree-sitter for TEST isn't available"))

(ert-deftest kittymacs-treesit-failing-mode-falls-back-to-classic-mode ()
  "A Tree-sitter mode that signals an error is replaced like one with no
parser, while an error from any other mode is passed on."
  (let ((treesit-major-mode-remap-alist
         '((kittymacs-treesit-test-classic-mode
            . kittymacs-treesit-test-failing-ts-mode)))
        (major-mode-remap-alist
         '((kittymacs-treesit-test-classic-mode
            . kittymacs-treesit-test-failing-ts-mode)))
        (treesit-enabled-modes t))
    (cl-letf (((symbol-function 'treesit-available-p) (lambda () t)))
      (with-temp-buffer
        (let ((inhibit-message t))
          (set-auto-mode-0 'kittymacs-treesit-test-classic-mode))
        (should (eq major-mode 'kittymacs-treesit-test-classic-mode)))
      (should-not (memq 'kittymacs-treesit-test-failing-ts-mode
                        treesit-enabled-modes))))
  (let ((treesit-major-mode-remap-alist nil)
        (major-mode-remap-alist nil))
    (with-temp-buffer
      (should-error (set-auto-mode-0 'kittymacs-treesit-test-failing-ts-mode)))))

(ert-deftest kittymacs-treesit-oversized-file-keeps-the-mode-enabled ()
  "A file too large for Tree-sitter gets the classic mode for itself only."
  (kittymacs-treesit-test-with-remap 'kittymacs-treesit-test-classic-mode
    (let ((treesit-max-buffer-size 1))
      (with-temp-buffer
        (insert "a large file")
        (let ((inhibit-message t))
          (set-auto-mode-0 'kittymacs-treesit-test-classic-mode))
        (should (eq major-mode 'kittymacs-treesit-test-classic-mode))))
    (should (eq treesit-enabled-modes t))))

(ert-deftest kittymacs-treesit-mode-with-a-parser-is-kept ()
  "A Tree-sitter mode whose parser was created stays."
  (kittymacs-treesit-test-with-remap 'kittymacs-treesit-test-classic-mode
    (cl-letf (((symbol-function 'treesit-parser-list)
               (lambda (&rest _) '(parser))))
      (with-temp-buffer
        (set-auto-mode-0 'kittymacs-treesit-test-classic-mode)
        (should (eq major-mode 'kittymacs-treesit-test-ts-mode))))
    (should (eq treesit-enabled-modes t))))

(ert-deftest kittymacs-treesit-installer-builds-what-is-missing ()
  "The installer builds missing grammars into the directory chosen after
load, rebuilds on request, and enables every mode again."
  (let ((initial-directory "/tmp/kittymacs-initial-grammars/")
        (selected-directory "/tmp/kittymacs-selected-grammars/")
        (kittymacs-treesit-grammar-directory
         "/tmp/kittymacs-initial-grammars/")
        (treesit-extra-load-path '("/tmp/kittymacs-initial-grammars/"))
        (treesit-language-source-alist
         '((bash "https://example.invalid/bash")
           (python "https://example.invalid/python")))
        (kittymacs-treesit-language-source-alist
         '((nix "https://example.invalid/nix" :commit "b")))
        (treesit-enabled-modes '(python-ts-mode))
        installed paths-at-install)
    (setopt kittymacs-treesit-grammar-directory selected-directory)
    (cl-letf (((symbol-function 'treesit-available-p) (lambda () t))
              ((symbol-function 'kittymacs-treesit--load-recipes)
               #'kittymacs-treesit-apply-pinned-sources)
              ((symbol-function 'treesit-language-available-p)
               (lambda (language &rest _) (eq language 'python)))
              ((symbol-function 'treesit-install-language-grammar)
               (lambda (&rest arguments)
                 (push arguments installed)
                 (push (car treesit-extra-load-path) paths-at-install))))
      (should (equal (kittymacs-treesit-install-grammars '(bash python nix))
                     '(bash nix)))
      (should (equal (nreverse installed)
                     (list (list 'bash selected-directory)
                           (list 'nix selected-directory))))
      (should (eq treesit-enabled-modes t))
      (setq installed nil)
      (should (equal (kittymacs-treesit-install-grammars '(python) t)
                     '(python)))
      (should-error (kittymacs-treesit-install-grammars '(cobol))
                    :type 'user-error))
    (should (cl-every (lambda (path) (equal path selected-directory))
                      paths-at-install))
    (should (member initial-directory treesit-extra-load-path))))

(ert-deftest kittymacs-treesit-installer-reports-missing-capability ()
  "The installer explains when this Emacs cannot build grammars."
  (cl-letf (((symbol-function 'treesit-available-p) (lambda () nil))
            ((symbol-function 'treesit-install-language-grammar)
             (lambda (&rest _) (ert-fail "installer must not run"))))
    (let ((error (should-error (kittymacs-treesit-install-grammars '(nix))
                               :type 'user-error)))
      (should (string-match-p "does not include Tree-sitter"
                              (error-message-string error))))))

(ert-deftest kittymacs-treesit-real-nix-fixture-parses-without-errors ()
  "The separately compiled pinned artifact parses a real Nix import."
  (let ((fixture (getenv "NIX_GRAMMAR_TEST_DIR")))
    (skip-unless (and fixture (file-directory-p fixture) (treesit-available-p)))
    (let ((treesit-extra-load-path (list fixture)))
      (should (treesit-language-available-p 'nix))
      (with-temp-buffer
        (insert "{ imports = [ ./base.nix ]; }")
        (treesit-parser-create 'nix)
        (let ((root (treesit-buffer-root-node 'nix)))
          (should (equal (treesit-node-type root) "source_code"))
          (should-not (treesit-node-check root 'has-error)))))))

(provide 'kittymacs-treesit-tests)
;;; kittymacs-treesit-tests.el ends here
