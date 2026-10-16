;;; kittymacs-reading.el --- PDFs and the notes beside them -*- lexical-binding: t; -*-
;; Generated from literate/75-reading.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)
(require 'kittymacs-org-node)
(use-package pdf-tools
  :ensure t
  :defer t
  :init
  (pdf-loader-install t)
  :custom
  (pdf-view-display-size 'fit-page)
  (pdf-annot-activate-created-annotations t))
(use-package org-noter
  :ensure t
  :commands (org-noter org-noter-insert-note org-noter-insert-precise-note org-noter-kill-session
             org-noter-sync-current-note org-noter-sync-next-note org-noter-sync-prev-note)
  :custom
  (org-noter-default-notes-file-names nil)
  (org-noter-notes-search-path (list kittymacs-org-node-directory))
  (org-noter-always-create-frame 'reuse-if-free))
(declare-function org-pdftools-open "org-pdftools" (link &optional arg))

(defun kittymacs-reading-follow-pdf-link (link arg)
  "Open the pdf: LINK, loading org-pdftools first; ARG as for `org-open-at-point'."
  (require 'org-pdftools)
  (org-pdftools-open link arg))

(with-eval-after-load 'ol
  (org-link-set-parameters "pdf" :follow #'kittymacs-reading-follow-pdf-link))

(use-package org-pdftools
  :ensure t
  :hook (pdf-view-mode . org-pdftools-setup-link))
(use-package org-noter-pdftools
  :ensure t
  :after (org-noter pdf-tools)
  :demand t
  :config
  (with-eval-after-load 'pdf-annot
    (add-hook 'pdf-annot-activate-handler-functions #'org-noter-pdftools-jump-to-note)))
(defvar pdf-text-kill-together)

(condition-case err
    (use-package pdf-text
      :vc (:url "https://github.com/agzam/pdf-text"
           :rev "f844d72cad81114fcce7806c1dac72d855639f89")
      :commands pdf-view-as-text
      :bind (:map pdf-text-mode-map
             ("RET" . pdf-text-show-in-pdf))
      :config
      (setq pdf-text-kill-together 'from-pdf))
  (error
   (display-warning 'kittymacs
                    (format "pdf-text was not installed: %s
Check that `git clone https://github.com/agzam/pdf-text' works from a terminal, and which git Emacs runs: %s"
                            (error-message-string err) (executable-find "git"))
                    :warning)))
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(pdf-view-mode . motion)))

(kittymacs-define-localleader 'pdf-view-mode
  "n" (cons "org-noter session" #'org-noter)
  "i" (cons "note for this page" #'org-noter-insert-note)
  "I" (cons "note at a spot" #'org-noter-insert-precise-note)
  "k" (cons "end session" #'org-noter-kill-session)
  "h" (cons "highlight selection" #'pdf-annot-add-highlight-markup-annotation)
  "a" (cons "text annotation" #'pdf-annot-add-text-annotation)
  "A" (cons "list annotations" #'pdf-annot-list-annotations)
  "o" (cons "outline" #'pdf-outline)
  "g" (cons "go to page" #'pdf-view-goto-page)
  "/" (cons "search" #'pdf-occur)
  "w" (cons "fit width" #'pdf-view-fit-width-to-window)
  "W" (cons "fit page" #'pdf-view-fit-page-to-window)
  "t" (cons "theme colours" #'pdf-view-themed-minor-mode)
  "l" (cons "store pdf: link" #'org-store-link)
  "s" (cons "save annotations" #'save-buffer)
  "r" (cons "read as text" #'pdf-view-as-text))

(defvar-keymap kittymacs-reading-org-map
  :doc "Reading-session keys in Org buffers."
  "n" (cons "start or resume" #'org-noter)
  "i" (cons "note for this page" #'org-noter-insert-note)
  "s" (cons "sync to this note" #'org-noter-sync-current-note)
  "]" (cons "next note" #'org-noter-sync-next-note)
  "[" (cons "previous note" #'org-noter-sync-prev-note)
  "k" (cons "end session" #'org-noter-kill-session))

;; `kittymacs-define-localleader' replaces a mode's whole map, and Org's
;; belongs to the Org chapter, so add a group to the map it built.
(with-eval-after-load 'kittymacs-org
  (when-let* ((map (alist-get 'org-mode kittymacs-localleader-alist)))
    (keymap-set map "N" (cons "noter (reading)" kittymacs-reading-org-map))
    (kittymacs-refresh-localleaders)))

(provide 'kittymacs-reading)
;;; kittymacs-reading.el ends here
