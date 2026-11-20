;;; kittymacs-languages.el --- Selective language tooling -*- lexical-binding: t; -*-
;; Generated from literate/74-languages.org; edit the Org source, then tangle.

;;; Commentary:
;; Supply a small built-in Eglot command surface without assuming which language
;; servers each machine owns.  Language packages and automatic LSP startup remain
;; explicit opt-ins that can be set in private.el before this module loads.

;;; Code:

(require 'kittymacs-leader)
(require 'kittymacs-treesit)
(defgroup kittymacs-languages nil
  "Selective language tooling for the starter configuration."
  :group 'kittymacs)
(defcustom kittymacs-language-packages nil
  "Optional language packages to install and configure.

Supported values are `nix', `racket', and `guile'.  Built-in modes and Eglot do
not need to be listed here."
  :type '(set (const nix) (const racket) (const guile))
  :group 'kittymacs-languages)
(defcustom kittymacs-eglot-auto-start-modes nil
  "Major modes in which `eglot-ensure' should run automatically.

The default is nil: start Eglot explicitly with `M-x eglot' (SPC l e)
until the language server for a mode is deliberately installed on each machine."
  :type '(repeat symbol)
  :group 'kittymacs-languages)
(use-package eglot
  :ensure nil
  :commands (eglot eglot-ensure eglot-shutdown eglot-reconnect
                   eglot-rename eglot-code-actions eglot-format
                   eglot-format-buffer eglot-find-declaration
                   eglot-find-implementation eglot-find-typeDefinition)
  :custom
  (eglot-autoshutdown t))

(keymap-set kittymacs-lsp-map "e" (cons "start or manage" #'eglot))
(keymap-set kittymacs-lsp-map "q" (cons "shut down" #'eglot-shutdown))
(keymap-set kittymacs-lsp-map "=" (cons "reconnect" #'eglot-reconnect))
(keymap-set kittymacs-lsp-map "a" (cons "code actions" #'eglot-code-actions))
(keymap-set kittymacs-lsp-map "R" (cons "rename" #'eglot-rename))
(keymap-set kittymacs-lsp-map "d" (cons "definition" #'xref-find-definitions))
(keymap-set kittymacs-lsp-map "r" (cons "references" #'xref-find-references))
(keymap-set kittymacs-lsp-map "D" (cons "declaration" #'eglot-find-declaration))
(keymap-set kittymacs-lsp-map "i" (cons "implementation" #'eglot-find-implementation))
(keymap-set kittymacs-lsp-map "t" (cons "type definition" #'eglot-find-typeDefinition))
(keymap-set kittymacs-lsp-map "h" (cons "documentation" #'eldoc-doc-buffer))
(defvar kittymacs--eglot-auto-start-hooks nil
  "Mode hooks currently managed by `kittymacs-eglot-apply-auto-start-modes'.")
(defun kittymacs-eglot-apply-auto-start-modes ()
  "Apply `kittymacs-eglot-auto-start-modes' to their corresponding hooks."
  (interactive)
  (dolist (hook kittymacs--eglot-auto-start-hooks)
    (remove-hook hook #'eglot-ensure))
  (setq kittymacs--eglot-auto-start-hooks nil)
  (dolist (mode kittymacs-eglot-auto-start-modes)
    (let ((hook (intern (format "%s-hook" mode))))
      (add-hook hook #'eglot-ensure)
      (push hook kittymacs--eglot-auto-start-hooks))))
(kittymacs-eglot-apply-auto-start-modes)
;; Keep non-built-in language modes deliberate.  Set
;; `kittymacs-language-packages' in private.el before startup to enable these.
(when (kittymacs-feature-p 'lang-nix)
  (use-package nix-mode
    :ensure t
    :mode "\\.nix\\'")
  (use-package nix-ts-mode
    :ensure t
    :defer t
    :init
    (kittymacs-treesit-register-mode 'nix-mode 'nix-ts-mode 'nix)))
(when (kittymacs-feature-p 'lang-racket)
  (use-package racket-mode
    :ensure t
    :mode "\\.rkt\\'"))
(when (kittymacs-feature-p 'lang-guile)
  (use-package geiser
    :ensure t
    :defer t)
  (use-package geiser-guile
    :ensure t
    :after geiser))
(defcustom kittymacs-typst-math-syntax 'typst
  "Math syntax for Org Typst export and inline equation previews.
Set to `latex' in file or directory locals for legacy equations.  This does
not translate the buffer or alter TeX documents and notebook math."
  :type '(choice (const typst) (const latex))
  :safe (lambda (value) (memq value '(typst latex)))
  :group 'kittymacs-languages)
(make-variable-buffer-local 'kittymacs-typst-math-syntax)
(defcustom kittymacs-typst-inline-preview t
  "Automatically render Typst equations in supported buffers.
Set to nil in private.el or file/directory locals to keep source visible.
Needs SVG display, the Typst compiler and its Tree-sitter grammar."
  :type 'boolean :safe #'booleanp :group 'kittymacs-languages)
(make-variable-buffer-local 'kittymacs-typst-inline-preview)
(defvar typst-overlay-mode)
(defvar org-src-lang-modes)
(declare-function typst-overlay-mode "typst-overlay" (&optional arg))
(declare-function typst-overlay-refresh "typst-overlay" (&optional force))
(defvar org-typst-from-latex-fragment)
(defvar org-typst-from-latex-environment)
(declare-function org-typst-from-latex-with-naive "ox-typst" (fragment))
(declare-function org-typst-export-to-pdf "ox-typst" (&optional async subtreep visible-only body-only ext-plist))

(defun kittymacs-typst-convert-tex-math (fragment)
  "Convert TeX FRAGMENT through Pandoc, reporting missing tools or failures."
  (unless (executable-find "pandoc")
    (user-error "TeX math compatibility needs pandoc on PATH"))
  (with-temp-buffer
    (insert fragment)
    (let ((status (call-process-region (point-min) (point-max)
                                      "pandoc" t t nil "-f" "latex" "-t" "typst")))
      (unless (eq status 0)
        (user-error "Pandoc math conversion failed: %s" (buffer-string))))
    (string-trim-right (buffer-string))))

(defun kittymacs-typst-overlay-setup ()
  "Synchronize inline previews with this buffer's settings and capabilities.
File buffers call this after local variables; non-file buffers use mode hooks.
Do not install tools or grammars merely to display an Org document."
  (when (derived-mode-p 'org-mode 'typst-ts-mode)
    (if (and kittymacs-typst-inline-preview
             (or (derived-mode-p 'typst-ts-mode)
                 (eq kittymacs-typst-math-syntax 'typst))
             (not (file-remote-p default-directory))
             (display-images-p)
             (image-type-available-p 'svg)
             (executable-find "typst")
             (treesit-ready-p 'typst t)
             (require 'typst-overlay nil t))
        (unless (bound-and-true-p typst-overlay-mode)
          (typst-overlay-mode 1)
          (unless (bound-and-true-p flymake-mode)
            (flymake-mode 1)))
      (when (bound-and-true-p typst-overlay-mode)
        (typst-overlay-mode -1)))))

(defun kittymacs-typst-overlay-non-file-setup ()
  "Enable previews in non-file buffers, including Org capture and src edits."
  (unless buffer-file-name
    (kittymacs-typst-overlay-setup)))

(defun kittymacs-typst-apply-math-syntax ()
  "Apply this document's math convention to the Typst exporter."
  (setq-local org-typst-from-latex-fragment
              (if (eq kittymacs-typst-math-syntax 'latex)
                  #'kittymacs-typst-convert-tex-math
                #'org-typst-from-latex-with-naive))
  (setq-local org-typst-from-latex-environment org-typst-from-latex-fragment))

(defun kittymacs-typst-tex-compatibility ()
  "Toggle TeX math compatibility in this Org buffer.
Persist with `add-file-local-variable' or `add-dir-local-variable', setting
`kittymacs-typst-math-syntax' to `latex'.  Conversion requires Pandoc."
  (interactive)
  (setq-local kittymacs-typst-math-syntax
              (if (eq kittymacs-typst-math-syntax 'latex) 'typst 'latex))
  (kittymacs-typst-apply-math-syntax)
  (kittymacs-typst-overlay-setup)
  (message "Typst export math: %s%s" kittymacs-typst-math-syntax
           (if (eq kittymacs-typst-math-syntax 'latex) " (requires pandoc)" "")))

(defun kittymacs-typst-org-setup ()
  "Configure Typst math after document and project local variables."
  (when (derived-mode-p 'org-mode)
    (kittymacs-typst-apply-math-syntax)
    (when (and (eq kittymacs-typst-math-syntax 'typst)
               (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "\\\\\\(?:frac\\|begin\\|sqrt\\)\\b" nil t)))
      (message "TeX-style math detected; M-x kittymacs-typst-tex-compatibility enables Pandoc conversion for this document"))))

(defun kittymacs-typst-mode ()
  "Open Typst with its parser when available, otherwise as editable text."
  (interactive)
  (require 'typst-ts-mode)
  (treesit-ensure-installed 'typst)
  (if (treesit-ready-p 'typst t) (typst-ts-mode) (text-mode)))

(when (kittymacs-feature-p 'lang-typst)
  (add-to-list 'kittymacs-treesit-language-source-alist
               '(typst "https://github.com/Ziqi-Yang/tree-sitter-typst"
                       :commit "46cf4ded12ee974a70bf8457263b67ad7ee0379d"))
  (kittymacs-treesit-apply-pinned-sources)
  (add-to-list 'kittymacs-treesit-languages 'typst)
  (use-package typst-ts-mode
    :ensure t
    :commands (typst-ts-mode typst-ts-compile typst-ts-preview typst-ts-watch-mode)
    :init
    (add-to-list 'auto-mode-alist '("\\.typ\\'" . kittymacs-typst-mode)))
  ;; The package also registers .typ when loaded; keep the guarded entry first.
  (with-eval-after-load 'typst-ts-mode
    (setq auto-mode-alist
          (delete '("\\.typ\\'" . typst-ts-mode) auto-mode-alist))
    (add-to-list 'auto-mode-alist '("\\.typ\\'" . kittymacs-typst-mode)))
  (with-eval-after-load 'eglot
    (add-to-list 'eglot-server-programs '(typst-ts-mode . ("tinymist"))))
  (use-package typst-overlay
    :vc (:url "https://github.com/hesampakdaman/typst-overlay"
         :rev "3b69366a435a9b4df45ed8fda01af3fca511e999")
    :commands (typst-overlay-mode typst-overlay-refresh)
    :custom
    (typst-overlay-use-flymake 'org)
    (typst-overlay-idle-refresh-delay 0.25)
    (typst-overlay-cache-directory
     (expand-file-name "typst-overlay/" kittymacs-cache-dir)))
  ;; File-local syntax and opt-out settings must precede the first render.
  (add-hook 'hack-local-variables-hook #'kittymacs-typst-overlay-setup)
  (add-hook 'org-mode-hook #'kittymacs-typst-overlay-non-file-setup)
  (add-hook 'typst-ts-mode-hook #'kittymacs-typst-overlay-non-file-setup)
  (with-eval-after-load 'org-src
    (add-to-list 'org-src-lang-modes '("typst" . kittymacs-typst)))
  (use-package ox-typst
    :ensure t :after ox
    :commands (org-typst-export-to-pdf org-typst-export-to-typst))
  (with-eval-after-load 'kittymacs-org
    (kittymacs-define-localleader 'org-mode
      "Y" (cons "export Typst PDF" #'org-typst-export-to-pdf)
      "M" (cons "toggle TeX math compatibility" #'kittymacs-typst-tex-compatibility)))
  (add-hook 'hack-local-variables-hook #'kittymacs-typst-org-setup)
  (kittymacs-define-localleader 'typst-ts-mode
    "c" (cons "compile" #'typst-ts-compile)
    "w" (cons "watch" #'typst-ts-watch-mode)
    "p" (cons "open PDF" #'typst-ts-preview)))
(when (kittymacs-feature-p 'typst-preview)
  (use-package typst-preview
    :ensure t :commands (typst-preview-mode typst-preview-send-position))
  (kittymacs-define-localleader 'typst-ts-mode
    "v" (cons "live preview" #'typst-preview-mode)
    "j" (cons "jump to preview" #'typst-preview-send-position)))

(provide 'kittymacs-languages)
;;; kittymacs-languages.el ends here
