;;; kittymacs-org-extras.el --- Org queries, grouped lists and a document's look -*- lexical-binding: t; -*-
;; Generated from literate/73-org-extras.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)
(require 'kittymacs-org)
(declare-function org-ql-find "org-ql-find")
(declare-function org-ql-search "org-ql-search")
(declare-function project-files "project")
(defvar org-directory)

(use-package org-ql
  :ensure t
  :defer t)

(defun kittymacs--org-files-here ()
  "Return the Org files that a search started in this buffer covers.
In a project, the project's Org files; anywhere else, every Org file
under `org-directory'."
  (or (if-let* ((project (project-current)))
          (seq-filter (lambda (file) (string-suffix-p ".org" file))
                      (project-files project))
        (directory-files-recursively org-directory "\\.org\\'"))
      (user-error "No Org files here")))

(defvar kittymacs--org-ql-history nil
  "Queries given to `kittymacs-org-ql-search'.")

(defun kittymacs-org-ql-find ()
  "Jump to a heading in the Org files here, found with an Org QL query.
The files are the project's, or your notes' outside a project.  The
results follow the query as you type it: tags:decision, todo:NEXT, words."
  (interactive)
  (org-ql-find (kittymacs--org-files-here) :prompt "Org QL: "))

(defun kittymacs-org-ql-search (query)
  "List the headings in the Org files here that match QUERY, grouped by file.
In the list, RET visits a heading, g runs the search again, and v changes
the query, the files, the order or the grouping."
  (interactive (list (read-string "Org QL query: " nil 'kittymacs--org-ql-history)))
  (org-ql-search (kittymacs--org-files-here) query
    :super-groups '((:auto-category t))
    :title query))

(keymap-set kittymacs-search-map "q" (cons "org query, jump" #'kittymacs-org-ql-find))
(keymap-set kittymacs-search-map "Q" (cons "org query, list" #'kittymacs-org-ql-search))
(use-package org-super-agenda
  :ensure t
  :after org-agenda
  :custom
  (org-super-agenda-show-message nil)
  :config
  (setq org-super-agenda-header-map nil)
  (org-super-agenda-mode 1))
(defun kittymacs--peg-rules-lexically (expand &rest args)
  "Expand `with-peg-rules' ARGS with EXPAND, under lexical binding.
Code that is already lexical expands as before."
  (if lexical-binding
      (apply expand args)
    `(eval '(with-peg-rules ,@args) t)))

(with-eval-after-load 'peg
  (advice-add 'with-peg-rules :around #'kittymacs--peg-rules-lexically))
(declare-function ox-extras-activate "ox-extra")

(use-package org-contrib
  :ensure t
  :after org
  :config
  (require 'ox-extra)
  (ox-extras-activate '(ignore-headlines)))
(use-package org-modern
  :ensure t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :custom
  (org-modern-star 'replace)
  (org-modern-list '((?- . "•") (?+ . "◦") (?* . "▹"))))

(use-package org-appear
  :ensure t
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t)
  (org-appear-autoentities t))
(condition-case err
    (use-package org-modern-indent
      :vc (:url "https://github.com/jdtsmith/org-modern-indent"
           :rev "86bd83ee1ad95f123810eb3b116beb543db1960a")
      :commands org-modern-indent-mode
      :init
      (add-hook 'org-mode-hook #'org-modern-indent-mode 90))
  (error
   (kittymacs-features-vc-warning "org-modern-indent" "https://github.com/jdtsmith/org-modern-indent" err)))

(provide 'kittymacs-org-extras)
;;; kittymacs-org-extras.el ends here
