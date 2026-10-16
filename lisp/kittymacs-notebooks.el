;;; kittymacs-notebooks.el --- Jupytext scripts, cells, kernels and math -*- lexical-binding: t; -*-
;; Generated from literate/76-notebooks.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)

(declare-function jupyter-available-kernelspecs "jupyter-kernelspec" (&optional refresh))
(declare-function jupyter-run-repl "jupyter-repl"
                  (kernel-name &optional repl-name associate-buffer client-class display))
(declare-function jupyter-connect-repl "jupyter-repl"
                  (file &optional repl-name associate-buffer client-class display))
(declare-function math-preview-region "math-preview" (beg end))
(defvar math-preview-command)
(defvar code-cells-boundary-regexp)
(use-package code-cells
  :ensure t
  :hook (python-base-mode . code-cells-mode-maybe)
  :commands (code-cells-eval-and-step code-cells-eval-above code-cells-eval-whole-buffer
             code-cells-mark-cell code-cells-write-ipynb)
  :bind (:map code-cells-mode-map
              ("M-n" . code-cells-forward-cell)
              ("M-p" . code-cells-backward-cell)
              ("C-c C-c" . code-cells-eval)
              ("<remap> <jupyter-eval-line-or-region>" . code-cells-eval)))
(defgroup kittymacs-notebooks nil
  "Notebooks as Jupytext scripts."
  :group 'kittymacs)

(defcustom kittymacs-notebooks-jupyter nil
  "Whether to install emacs-jupyter, for Jupyter kernels.
It needs emacs-zmq's native module.  With Nix the module comes ready-built
from the tool list; without, emacs-zmq downloads or builds one the first
time it loads.  Set this in private.el; it takes effect at the next start."
  :type 'boolean)
(defun kittymacs-notebooks--zmq-module ()
  "Return the store path of the ZeroMQ module the Nix tools provide, or nil."
  (when-let* ((helper (executable-find "kittymacs-zmq-module"))
              (module (car (ignore-errors (process-lines helper)))))
    (and (file-exists-p module) module)))

(defun kittymacs-notebooks--link-zmq-module (&rest _)
  "Link the Nix-built ZeroMQ module beside zmq.el, before `zmq-load' looks.
Every Emacs that loads zmq.el looks there, including emacs-jupyter's
subprocesses, which do not read this configuration."
  (unless (featurep 'zmq-core)
    (when-let* ((module (kittymacs-notebooks--zmq-module))
                (library (locate-library "zmq.el"))
                (link (expand-file-name (file-name-nondirectory module)
                                        (file-name-directory library))))
      (unless (or (equal (file-symlink-p link) module)
                  (and (file-exists-p link) (not (file-symlink-p link))))
        (condition-case err
            (make-symbolic-link module link t)
          (file-error
           (message "Could not link the ZeroMQ module beside zmq.el: %s"
                    (error-message-string err))))))))
(when kittymacs-notebooks-jupyter
  (advice-add 'zmq-load :before #'kittymacs-notebooks--link-zmq-module)
  (use-package jupyter
    :ensure t
    :defer t
    :commands (jupyter-run-repl jupyter-connect-repl jupyter-refresh-kernelspecs)
    :config
    (advice-add 'jupyter-session-with-random-ports :around #'inheritenv-apply)))

(defun kittymacs-notebooks--require-jupyter ()
  "Load emacs-jupyter, or explain how to turn it on."
  (unless kittymacs-notebooks-jupyter
    (user-error "Jupyter kernels are off: (setopt kittymacs-notebooks-jupyter t) in private.el, then restart"))
  (require 'jupyter))

(defun kittymacs-notebooks-run-kernel ()
  "Start a Jupyter kernel in this project's environment and attach this buffer.
Reads the list of kernels again first: emacs-jupyter's cache cannot tell
two Nix shells apart."
  (interactive)
  (kittymacs-notebooks--require-jupyter)
  (jupyter-available-kernelspecs t)
  (call-interactively #'jupyter-run-repl))

(defun kittymacs-notebooks-connect-kernel ()
  "Attach this buffer to a running kernel, chosen by its connection file."
  (interactive)
  (kittymacs-notebooks--require-jupyter)
  (call-interactively #'jupyter-connect-repl))
(use-package math-preview
  :ensure t
  :commands (math-preview-region math-preview-all math-preview-at-point
             math-preview-clear-all math-preview-clear-region math-preview-clear-at-point))

(defun kittymacs-notebooks--markdown-cells (beg end)
  "Return the Markdown cells that overlap BEG..END, as (START . END) pairs.
A cell starts after its `# %% [markdown]' line and ends at the next cell
marker; each pair is clipped to BEG..END."
  (require 'code-cells)
  (save-excursion
    (goto-char (point-min))
    (let (cells)
      (while (re-search-forward code-cells-boundary-regexp nil t)
        (when (looking-at-p ".*\[markdown\]")
          (let ((start (line-beginning-position 2))
                (stop (save-excursion
                        (forward-line 1)
                        (if (re-search-forward code-cells-boundary-regexp nil t)
                            (line-beginning-position)
                          (point-max)))))
            (when (and (< start end) (> stop beg))
              (push (cons (max start beg) (min stop end)) cells)))))
      (nreverse cells))))

(defun kittymacs-notebooks-preview-math (beg end)
  "Draw the LaTeX in the Markdown cells between BEG and END.
Interactively, the region when it is active, otherwise the whole buffer.
Code cells are left alone, so a `$' in a string of code stays text."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (list (point-min) (point-max))))
  (require 'math-preview)
  (unless (executable-find math-preview-command)
    (user-error "math-preview needs its program on PATH: the Nix tools, or npm install -g git+https://gitlab.com/matsievskiysv/math-preview"))
  (let ((cells (kittymacs-notebooks--markdown-cells beg end)))
    (unless cells
      (user-error "No Markdown cells (# %%%% [markdown]) here"))
    (pcase-dolist (`(,start . ,stop) cells)
      (math-preview-region start stop))))
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(jupyter-repl-mode . insert)))

(defvar-keymap kittymacs-notebooks-map
  :doc "Notebook keys in Python buffers."
  "n" (cons "next cell" #'code-cells-forward-cell)
  "p" (cons "previous cell" #'code-cells-backward-cell)
  "e" (cons "run cell" #'code-cells-eval)
  "s" (cons "run cell, go to next" #'code-cells-eval-and-step)
  "a" (cons "run cells above" #'code-cells-eval-above)
  "b" (cons "run buffer" #'code-cells-eval-whole-buffer)
  "@" (cons "mark cell" #'code-cells-mark-cell)
  "j" (cons "start kernel" #'kittymacs-notebooks-run-kernel)
  "J" (cons "attach to kernel" #'kittymacs-notebooks-connect-kernel)
  "R" (cons "Python shell" #'run-python)
  "m" (cons "draw math" #'kittymacs-notebooks-preview-math)
  "M" (cons "clear math" #'math-preview-clear-all)
  "w" (cons "write .ipynb" #'code-cells-write-ipynb))

(kittymacs-define-localleader 'python-base-mode
  "n" (cons "notebook" kittymacs-notebooks-map))

(provide 'kittymacs-notebooks)
;;; kittymacs-notebooks.el ends here
