;;; kittymacs-treesit-tests.el --- Reproducible grammar policy -*- lexical-binding: t; -*-
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

(ert-deftest kittymacs-treesit-grammar-directory-defaults-under-cache ()
  "A fresh configuration keeps compiled grammars in the writable cache."
  (should (equal kittymacs-treesit-grammar-directory
                 (expand-file-name "tree-sitter/" kittymacs-cache-dir)))
  (should (custom-variable-p 'kittymacs-treesit-grammar-directory)))

(ert-deftest kittymacs-treesit-load-honours-override-before-probing ()
  "Loading preserves private overrides and exposes them before any probe."
  (let ((custom-directory (make-temp-file "kittymacs-grammar-custom" t))
        (kittymacs-treesit-grammar-directory nil)
        (treesit-extra-load-path nil)
        (treesit-language-source-alist nil)
        (major-mode-remap-alist nil)
        (original-default-directory default-directory)
        (original-path (getenv "PATH"))
        (original-exec-path (copy-sequence exec-path))
        checked saw-custom-path install-called external-called)
    (setq kittymacs-treesit-grammar-directory custom-directory)
    (unwind-protect
        (cl-letf (((symbol-function 'treesit-available-p) (lambda () t))
                  ((symbol-function 'treesit-language-available-p)
                   (lambda (&rest _)
                     (setq checked t)
                     (push (member custom-directory treesit-extra-load-path)
                           saw-custom-path)
                     nil))
                  ((symbol-function 'treesit-install-language-grammar)
                   (lambda (&rest _) (setq install-called t)))
                  ((symbol-function 'call-process)
                   (lambda (&rest _) (setq external-called t)))
                  ((symbol-function 'make-process)
                   (lambda (&rest _) (setq external-called t)))
                  ((symbol-function 'url-retrieve-synchronously)
                   (lambda (&rest _) (setq external-called t))))
          (load kittymacs-treesit-test-library nil nil t))
      (delete-directory custom-directory t))
    (should checked)
    (should (cl-every #'identity saw-custom-path))
    (should (member custom-directory treesit-extra-load-path))
    (should (equal kittymacs-treesit-grammar-directory custom-directory))
    (should (equal default-directory original-default-directory))
    (should (equal (getenv "PATH") original-path))
    (should (equal exec-path original-exec-path))
    (should-not install-called)
    (should-not external-called)))

(ert-deftest kittymacs-treesit-nix-source-is-exactly-pinned ()
  "The Nix recipe remains reproducible."
  (let ((recipe (assq 'nix kittymacs-treesit-language-source-alist)))
    (should (equal (nth 1 recipe)
                   "https://github.com/nix-community/tree-sitter-nix"))
    (should (equal (nth 2 recipe)
                   "ea1d87f7996be1329ef6555dcacfa63a69bd55c6"))))

(ert-deftest kittymacs-treesit-every-remap-has-a-recipe ()
  "Installing every pinned grammar makes every remap possible."
  (dolist (spec kittymacs-treesit-mode-remaps)
    (should (assq (nth 2 spec) kittymacs-treesit-language-source-alist))))

(ert-deftest kittymacs-treesit-remaps-the-modes-emacs-chooses ()
  "With grammars present, files opened in built-in modes reach Tree-sitter.
The classic side of each remap must be the mode `auto-mode-alist'
really selects, or the remap never fires."
  (let ((major-mode-remap-alist nil))
    (cl-letf (((symbol-function 'kittymacs-treesit--language-available-p)
               (lambda (_) t)))
      (kittymacs-treesit-refresh-mode-remaps))
    (pcase-dolist (`(,file . ,mode) '(("build.sh" . bash-ts-mode)
                                      ("package.json" . json-ts-mode)
                                      ("style.css" . css-ts-mode)
                                      ("main.py" . python-ts-mode)))
      (let ((classic (assoc-default file auto-mode-alist #'string-match-p)))
        (should (eq (alist-get classic major-mode-remap-alist) mode))))))

(ert-deftest kittymacs-treesit-windows-nix-recipe-uses-msys2-gcc ()
  "Windows grammar builds use an absolute compiler without changing PATH."
  (let ((system-type 'windows-nt)
        (kittymacs-msys2-root "D:/tools/msys64/"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_) t)))
      (should (equal (kittymacs-treesit--nix-source)
                     '(nix
                       "https://github.com/nix-community/tree-sitter-nix"
                       "ea1d87f7996be1329ef6555dcacfa63a69bd55c6"
                       "src" "D:/tools/msys64/ucrt64/bin/gcc.exe")))))
  (let ((system-type 'gnu/linux))
    (should (= (length (kittymacs-treesit--nix-source)) 3))))

(ert-deftest kittymacs-treesit-single-install-syncs-post-load-directory ()
  "A post-load option change is searched before installing and refreshing."
  (let ((initial-directory "/tmp/kittymacs-initial-grammars/")
        (selected-directory "/tmp/kittymacs-selected-grammars/")
        (kittymacs-treesit-grammar-directory
         "/tmp/kittymacs-initial-grammars/")
        (kittymacs-treesit-mode-remaps '((nix-mode nix-ts-mode nix)))
        (treesit-extra-load-path '("/tmp/kittymacs-initial-grammars/"))
        (treesit-language-source-alist nil)
        installed path-at-install paths-at-probe)
    (setopt kittymacs-treesit-grammar-directory selected-directory)
    (cl-letf (((symbol-function 'treesit-available-p) (lambda () t))
              ((symbol-function 'treesit-language-available-p)
               (lambda (&rest _)
                 (push (car treesit-extra-load-path) paths-at-probe)
                 nil))
              ((symbol-function 'treesit-install-language-grammar)
               (lambda (&rest arguments)
                 (setq installed arguments
                       path-at-install (car treesit-extra-load-path))))
              ((symbol-function 'nix-ts-mode) #'ignore))
      (kittymacs-treesit-install-language-grammar 'nix))
    (should (equal installed (list 'nix selected-directory)))
    (should (equal path-at-install selected-directory))
    (should paths-at-probe)
    (should (cl-every (lambda (path) (equal path selected-directory))
                      paths-at-probe))
    (should (member initial-directory treesit-extra-load-path))
    (should (equal (alist-get 'nix treesit-language-source-alist)
                   (cdr (assq 'nix kittymacs-treesit-language-source-alist))))))

(ert-deftest kittymacs-treesit-installer-reports-missing-capability ()
  "The explicit installer explains when this Emacs cannot build grammars."
  (let ((kittymacs-treesit-language-source-alist
         '((nix "https://example.invalid/nix"
                "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"))))
    (cl-letf (((symbol-function 'treesit-available-p) (lambda () nil))
              ((symbol-function 'treesit-install-language-grammar)
               (lambda (&rest _) (ert-fail "installer must not run"))))
      (let ((error (should-error
                    (kittymacs-treesit-install-language-grammar 'nix)
                    :type 'user-error)))
        (should (string-match-p "does not include Tree-sitter"
                                (error-message-string error)))))))

(ert-deftest kittymacs-treesit-install-all-syncs-post-load-directory ()
  "Bulk probes and installs use the directory selected after module load."
  (let ((initial-directory "/tmp/kittymacs-initial-grammars/")
        (selected-directory "/tmp/kittymacs-selected-grammars/")
        (kittymacs-treesit-grammar-directory
         "/tmp/kittymacs-initial-grammars/")
        (kittymacs-treesit-language-source-alist
         '((bash "https://example.invalid/bash" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
           (nix "https://example.invalid/nix" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")))
        (kittymacs-treesit-mode-remaps '((nix-mode nix-ts-mode nix)))
        (treesit-extra-load-path '("/tmp/kittymacs-initial-grammars/"))
        installed paths-at-install paths-at-probe)
    (setopt kittymacs-treesit-grammar-directory selected-directory)
    (cl-letf (((symbol-function 'treesit-available-p) (lambda () t))
              ((symbol-function 'treesit-language-available-p)
               (lambda (&rest _)
                 (push (car treesit-extra-load-path) paths-at-probe)
                 nil))
              ((symbol-function 'treesit-install-language-grammar)
               (lambda (&rest arguments)
                 (push arguments installed)
                 (push (car treesit-extra-load-path) paths-at-install)))
              ((symbol-function 'nix-ts-mode) #'ignore))
      (kittymacs-treesit-install-all-grammars))
    (should (equal (nreverse installed)
                   (list (list 'bash selected-directory)
                         (list 'nix selected-directory))))
    (should paths-at-probe)
    (should (cl-every (lambda (path) (equal path selected-directory))
                      paths-at-probe))
    (should (cl-every (lambda (path) (equal path selected-directory))
                      paths-at-install))
    (should (member initial-directory treesit-extra-load-path))))

(ert-deftest kittymacs-treesit-nix-remap-requires-mode-and-grammar ()
  "Nix remains usable without nix-mode, and remaps only with both capabilities."
  (let ((kittymacs-treesit-mode-remaps '((nix-mode nix-ts-mode nix)))
        (major-mode-remap-alist nil)
        (real-fboundp (symbol-function 'fboundp)))
    (cl-letf (((symbol-function 'fboundp)
               (lambda (symbol)
                 (if (eq symbol 'nix-ts-mode) nil
                   (funcall real-fboundp symbol))))
              ((symbol-function 'kittymacs-treesit--language-available-p)
               (lambda (_) t)))
      (kittymacs-treesit-refresh-mode-remaps))
    (should-not (assq 'nix-mode major-mode-remap-alist)))
  (let ((kittymacs-treesit-mode-remaps '((nix-mode nix-ts-mode nix)))
        (major-mode-remap-alist nil))
    (cl-letf (((symbol-function 'nix-ts-mode) #'ignore)
              ((symbol-function 'kittymacs-treesit--language-available-p)
               (lambda (_) nil)))
      (kittymacs-treesit-refresh-mode-remaps))
    (should-not (assq 'nix-mode major-mode-remap-alist)))
  (let ((kittymacs-treesit-mode-remaps '((nix-mode nix-ts-mode nix)))
        (major-mode-remap-alist nil))
    (cl-letf (((symbol-function 'nix-ts-mode) #'ignore)
              ((symbol-function 'kittymacs-treesit--language-available-p)
               (lambda (_) t)))
      (kittymacs-treesit-refresh-mode-remaps))
    (should (equal (alist-get 'nix-mode major-mode-remap-alist)
                   'nix-ts-mode))))

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
