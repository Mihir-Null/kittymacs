;;; kittymacs-programming.el --- What every programming buffer gets -*- lexical-binding: t; -*-
;; Generated from literate/72-programming.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)
(setopt prettify-symbols-unprettify-at-point t
        show-paren-delay 0
        show-paren-context-when-offscreen t)
(global-prettify-symbols-mode 1)
(electric-pair-mode 1)

(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package rainbow-identifiers
  :ensure t
  :commands rainbow-identifiers-mode)

(use-package puni
  :ensure t
  :hook ((prog-mode tex-mode org-mode markdown-mode eval-expression-minibuffer-setup) . puni-mode)
  :bind (:map puni-mode-map
         ("C-(" . puni-slurp-backward)
         ("C-)" . puni-slurp-forward)
         ("C-{" . puni-barf-backward)
         ("C-}" . puni-barf-forward)))

(use-package embrace
  :ensure t
  :commands (embrace-commander embrace-add embrace-change embrace-delete)
  :hook (org-mode . embrace-org-mode-hook)
  :config
  (defun kittymacs--embrace-markdown ()
    "Markdown pairs for Embrace."
    (dolist (pair '((?* "*" . "*") (?_ "_" . "_") (?` "`" . "`") (?$ "$" . "$")))
      (embrace-add-pair (car pair) (cadr pair) (cddr pair))))
  (add-hook 'markdown-mode-hook #'kittymacs--embrace-markdown))

(use-package iedit
  :ensure t
  :commands iedit-mode)
(defun kittymacs--indent-guides ()
  "Indent guides in graphical frames; the package cannot derive faces without a display."
  (when (display-graphic-p)
    (highlight-indent-guides-mode 1)))

(use-package highlight-indent-guides
  :ensure t
  :hook (prog-mode . kittymacs--indent-guides)
  :custom
  (highlight-indent-guides-method 'character)
  (highlight-indent-guides-character ?│)
  (highlight-indent-guides-responsive 'top)
  (highlight-indent-guides-auto-odd-face-perc 5)
  (highlight-indent-guides-auto-even-face-perc 5)
  (highlight-indent-guides-auto-character-face-perc 15))

(use-package aggressive-indent
  :ensure t
  :hook ((emacs-lisp-mode lisp-interaction-mode lisp-mode) . aggressive-indent-mode)
  :custom
  (aggressive-indent-comments-too nil)
  :config
  (add-to-list 'aggressive-indent-protected-commands 'comment-dwim))
(use-package flymake
  :ensure nil
  :hook (prog-mode . flymake-mode)
  :custom
  (flymake-fringe-indicator-position 'left-fringe)
  (flymake-suppress-zero-counters t)
  (flymake-no-changes-timeout nil)
  (flymake-start-on-save-buffer t)
  (flymake-wrap-around nil)
  (flymake-mode-line-counter-format '("" flymake-mode-line-error-counter flymake-mode-line-warning-counter flymake-mode-line-note-counter ""))
  (flymake-mode-line-format '(" " flymake-mode-line-exception flymake-mode-line-counters)))

(use-package package-lint
  :ensure t
  :commands (package-lint-current-buffer package-lint-buffer)
  :config
  (with-eval-after-load 'savehist
    (add-to-list 'savehist-additional-variables 'package-archive-contents)))

(use-package flymake-collection
  :ensure t
  :hook (after-init . flymake-collection-hook-setup))
(setopt compilation-always-kill t
        compilation-ask-about-save nil
        compilation-scroll-output 'first-error)
(with-eval-after-load 'compile
  (add-hook 'compilation-filter-hook #'comint-truncate-buffer))
(setopt eldoc-idle-delay 0)

(use-package elisp-def
  :ensure t
  :hook ((emacs-lisp-mode ielm-mode lisp-interaction-mode) . elisp-def-mode))

(defun kittymacs--show-trailing-whitespace ()
  "Mark trailing whitespace in this buffer."
  (setq show-trailing-whitespace t))
(dolist (hook '(emacs-lisp-mode-hook ielm-mode-hook lisp-interaction-mode-hook))
  (add-hook hook #'kittymacs--show-trailing-whitespace))

(dolist (pattern '("\\.zsh\\'" "zlogin\\'" "zlogout\\'" "zprofile\\'" "zshenv\\'" "zshrc\\'"))
  (add-to-list 'auto-mode-alist (cons pattern 'sh-mode)))
(kittymacs-define-localleader 'prog-mode
  "c" (cons "compile" #'compile)
  "r" (cons "recompile" #'recompile)
  "e" (cons "errors" #'consult-flymake)
  "E" (cons "error list" #'flymake-show-buffer-diagnostics)
  "f" (cons "format" #'indent-region)
  ";" (cons "comment" #'comment-dwim)
  "s" (cons "surround" #'embrace-commander)
  "i" (cons "edit all occurrences" #'iedit-mode)
  "d" (cons "definition" #'xref-find-definitions)
  "D" (cons "references" #'xref-find-references))

(kittymacs-define-localleader 'emacs-lisp-mode
  "e" (cons "eval last sexp" #'eval-last-sexp)
  "d" (cons "eval defun" #'eval-defun)
  "b" (cons "eval buffer" #'eval-buffer)
  "r" (cons "eval region" #'eval-region)
  "x" (cons "eval expression" #'eval-expression)
  "i" (cons "ielm" #'ielm)
  "g" (cons "edebug defun" #'edebug-defun)
  "c" (cons "byte compile" #'emacs-lisp-byte-compile)
  "l" (cons "package lint" #'package-lint-current-buffer)
  "m" (cons "macroexpand" #'pp-macroexpand-last-sexp)
  "D" (cons "find definition" #'elisp-def)
  "?" (cons "menu" #'casual-elisp-tmenu))

(provide 'kittymacs-programming)
;;; kittymacs-programming.el ends here
