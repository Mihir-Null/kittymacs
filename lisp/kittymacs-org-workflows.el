;;; kittymacs-org-workflows.el --- Research and publishing -*- lexical-binding: t; -*-
;; Generated from literate/84-org-workflows.org; edit the Org source, then tangle.

(require 'kittymacs-leader)
(require 'compile)

(defvar org-cite-insert-processor)
(defvar org-cite-follow-processor)
(defvar org-cite-activate-processor)

(when (kittymacs-feature-p 'org-citations)
  (use-package citar
    :ensure t
    :commands (citar-open citar-insert-citation)
    :init
    (setq org-cite-insert-processor 'citar
          org-cite-follow-processor 'citar
          org-cite-activate-processor 'citar)))

(when (kittymacs-feature-p 'org-transclusion)
  (use-package org-transclusion
    :ensure t
    :commands (org-transclusion-add org-transclusion-refresh)))

(when (kittymacs-feature-p 'org-annotations)
  (use-package org-remark
    :ensure t
    :commands (org-remark-mark org-remark-global-tracking-mode)))

(when (kittymacs-feature-p 'org-web-capture)
  (use-package org-web-tools
    :ensure t
    :commands (org-web-tools-insert-web-page-as-entry org-web-tools-archive-attach)))

(defun kittymacs-org-press--root ()
  "Find the nearest local Org Press configuration."
  (unless (file-remote-p default-directory)
    (locate-dominating-file
     default-directory
     (lambda (directory)
       (seq-some (lambda (file)
                   (file-regular-p (expand-file-name file directory)))
                 '(".org-press/config.ts" ".org-press/config.js"
                   "org-press.config.ts" "org-press.config.js"))))))

(defun kittymacs-org-press--run (action &optional target)
  "Run project-local Org Press ACTION, optionally on TARGET."
  (let* ((root (or (kittymacs-org-press--root)
                   (user-error "Open a local project with an Org Press config")))
         (default-directory root)
         (cli (expand-file-name "node_modules/org-press/dist/bin/orgp.js"))
         (node (or (executable-find "node")
                   (user-error "Install Node.js in the project environment")))
         (name (format "*Org Press %s: %s*" action (abbreviate-file-name root))))
    (unless (file-regular-p cli)
      (user-error "Install Org Press in %s with npm install --save-exact org-press@0.9.14 react react-dom"
                  root))
    (when (process-live-p (get-buffer-process name))
      (user-error "Org Press %s is already running in this project" action))
    (compilation-start
     (mapconcat #'shell-quote-argument
                (append (list node cli action) (and target (list target))) " ")
     'compilation-mode (lambda (_) name))))

(defun kittymacs-org-press-preview ()
  "Start the project's Org Press development server."
  (interactive)
  (kittymacs-org-press--run "dev"))

(defun kittymacs-org-press-build ()
  "Build the project with Org Press."
  (interactive)
  (kittymacs-org-press--run "build"))

(defun kittymacs-org-press-run-file ()
  "Execute the current saved Org file through Org Press."
  (interactive)
  (unless (and buffer-file-name (derived-mode-p 'org-mode) (not (buffer-modified-p)))
    (user-error "Save the Org file before running it"))
  (kittymacs-org-press--run "run" buffer-file-name))

(let ((menu (make-sparse-keymap))
      (org-map (alist-get 'org-mode kittymacs-localleader-alist)))
  (keymap-set menu "a" (cons "attach file" #'org-attach))
  (when (kittymacs-feature-p 'org-citations)
    (keymap-set menu "c" (cons "insert citation" #'citar-insert-citation))
    (keymap-set menu "o" (cons "open reference" #'citar-open)))
  (when (kittymacs-feature-p 'org-transclusion)
    (keymap-set menu "i" (cons "insert transclusion" #'org-transclusion-add))
    (keymap-set menu "r" (cons "refresh transclusion" #'org-transclusion-refresh)))
  (when (kittymacs-feature-p 'org-annotations)
    (keymap-set menu "m" (cons "mark passage" #'org-remark-mark)))
  (when (kittymacs-feature-p 'org-web-capture)
    (keymap-set menu "w" (cons "capture web page" #'org-web-tools-insert-web-page-as-entry))
    (keymap-set menu "s" (cons "attach web snapshot" #'org-web-tools-archive-attach)))
  (when (kittymacs-feature-p 'org-press)
    (keymap-set menu "p" (cons "preview website" #'kittymacs-org-press-preview))
    (keymap-set menu "b" (cons "build website" #'kittymacs-org-press-build))
    (keymap-set menu "x" (cons "run Org Press file" #'kittymacs-org-press-run-file)))
  (when org-map
    (keymap-set org-map "R" (cons "research and publishing" menu))
    (kittymacs-refresh-localleaders)))

(provide 'kittymacs-org-workflows)
;;; kittymacs-org-workflows.el ends here
