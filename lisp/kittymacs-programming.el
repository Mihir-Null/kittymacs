;;; kittymacs-programming.el --- What every programming buffer gets -*- lexical-binding: t; -*-
;; Generated from literate/72-programming.org; edit the Org source, then tangle.

;; Distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'seq)
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


(use-package puni
  :ensure t
  :hook ((prog-mode tex-mode org-mode markdown-mode markdown-ts-mode eval-expression-minibuffer-setup) . puni-mode)
  :bind (:map puni-mode-map
         ("C-(" . puni-slurp-backward)
         ("C-)" . puni-slurp-forward)
         ("C-{" . puni-barf-backward)
         ("C-}" . puni-barf-forward)))

(keymap-set kittymacs-toggle-map "p" (cons "structural editing" #'puni-mode))

(defun kittymacs--embrace-markdown ()
  "Markdown pairs for Embrace."
  (dolist (pair '((?* "*" . "*") (?_ "_" . "_") (?` "`" . "`") (?$ "$" . "$")))
    (embrace-add-pair (car pair) (cadr pair) (cddr pair))))

(use-package embrace
  :ensure t
  :commands (embrace-commander embrace-add embrace-change embrace-delete)
  :hook (org-mode . embrace-org-mode-hook)
  :config
  (add-hook 'markdown-mode-hook #'kittymacs--embrace-markdown)
  (add-hook 'markdown-ts-mode-hook #'kittymacs--embrace-markdown))

(keymap-set kittymacs-code-map "s" (cons "surround" #'embrace-commander))
(defun kittymacs--indent-guides ()
  "Show indent guides in graphical frames.
The package cannot derive its faces without a display."
  (when (display-graphic-p)
    (highlight-indent-guides-mode 1)))

(use-package highlight-indent-guides
  :ensure t
  :hook (prog-mode . kittymacs--indent-guides)
  :custom
  (highlight-indent-guides-method 'character)
  (highlight-indent-guides-character ?│)
  (highlight-indent-guides-responsive nil)
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
  :commands (flymake-start flymake-goto-next-error flymake-goto-prev-error
             flymake-show-buffer-diagnostics flymake-show-project-diagnostics)
  :custom
  (flymake-fringe-indicator-position 'left-fringe)
  (flymake-suppress-zero-counters t)
  (flymake-no-changes-timeout nil)
  (flymake-start-on-save-buffer t)
  (flymake-wrap-around nil)
  (flymake-mode-line-counter-format '("" flymake-mode-line-error-counter flymake-mode-line-warning-counter flymake-mode-line-note-counter ""))
  (flymake-mode-line-format '(" " flymake-mode-line-exception flymake-mode-line-counters)))

(keymap-set kittymacs-diagnostics-map "n" (cons "next" #'flymake-goto-next-error))
(keymap-set kittymacs-diagnostics-map "p" (cons "previous" #'flymake-goto-prev-error))
(keymap-set kittymacs-diagnostics-map "d" (cons "list buffer" #'flymake-show-buffer-diagnostics))
(keymap-set kittymacs-diagnostics-map "D" (cons "list project" #'flymake-show-project-diagnostics))
(keymap-set kittymacs-diagnostics-map "c" (cons "choose" #'consult-flymake))
(keymap-set kittymacs-diagnostics-map "s" (cons "start check" #'flymake-start))
(keymap-set kittymacs-toggle-map "F" (cons "flymake" #'flymake-mode))

(use-package flymake-collection
  :ensure t
  :demand t
  :config
  (flymake-collection-hook-setup))
(setopt compilation-always-kill t
        compilation-ask-about-save nil
        compilation-scroll-output 'first-error)
(with-eval-after-load 'compile
  (add-hook 'compilation-filter-hook #'comint-truncate-buffer))

(keymap-set kittymacs-project-map "C" (cons "recompile" #'recompile))
(setopt eldoc-idle-delay 0)

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
  "m" (cons "macroexpand" #'pp-macroexpand-last-sexp)
  "?" (cons "menu" #'casual-elisp-tmenu))

(provide 'kittymacs-programming)
;;; kittymacs-programming.el ends here
