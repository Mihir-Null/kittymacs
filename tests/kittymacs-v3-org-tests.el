;;; kittymacs-v3-org-tests.el --- Executable Org and publishing -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path (expand-file-name "../lisp" (file-name-directory load-file-name)))
(require 'kittymacs-features)
(require 'kittymacs-org-babel)
(require 'kittymacs-org-workflows)
(require 'ox-html)

(ert-deftest kittymacs-babel-loads-core-backends ()
  (dolist (language '(emacs-lisp shell python js))
    (should (alist-get language org-babel-load-languages))))

(ert-deftest kittymacs-babel-exports-results-without-running-block ()
  (with-temp-buffer
    (insert "#+begin_src emacs-lisp :eval never-export :exports results\n"
            "(error \"The exporter executed code\")\n"
            "#+end_src\n\n#+RESULTS:\n: Saved result\n")
    (org-mode)
    (should (string-match-p "Saved result" (org-export-as 'html nil nil t)))))

(ert-deftest kittymacs-org-press-runs-the-project-cli ()
  (let* ((root (file-name-as-directory (make-temp-file "Org Press test " t)))
         (default-directory (expand-file-name "content/" root))
         (cli (expand-file-name "node_modules/org-press/dist/bin/orgp.js" root)))
    (unwind-protect
        (progn
          (make-directory default-directory t)
          (make-directory (file-name-directory cli) t)
          (with-temp-file cli)
          (with-temp-file (expand-file-name "org-press.config.ts" root))
          (cl-letf (((symbol-function 'executable-find) (lambda (_) "/opt/node"))
                    ((symbol-function 'compilation-start)
                     (lambda (command mode _)
                       (should (equal root default-directory))
                       (should (eq mode 'compilation-mode))
                       (should (equal command
                                      (mapconcat #'shell-quote-argument
                                                 (list "/opt/node" cli "build") " "))))))
            (kittymacs-org-press-build)))
      (delete-directory root t))))
