;;; kittymacs-literate.el --- Edit and build the literate source -*- lexical-binding: t; -*-
;; Generated from literate/80-maintenance.org; edit the Org source, then tangle.
;;; Commentary:
;; Development addition: keep authoring explicit and startup independent of Org.
;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-features)
(require 'kittymacs-leader)

(autoload 'kittymacs-onboard "kittymacs-onboard"
  "Choose what kittymacs installs, and write it to `private.el'." t)

(defun kittymacs-onboard-hint ()
  "Say where to choose features, on a machine that has chosen none."
  (unless (or noninteractive (daemonp)
              kittymacs-profile kittymacs-features kittymacs-features-excluded)
    (message "kittymacs: no features chosen yet.  SPC C o chooses them, or `just onboard' in a terminal.")))

(add-hook 'emacs-startup-hook #'kittymacs-onboard-hint 90)

(defun kittymacs-literate-open (&rest _)
  "Open the literate configuration's reading guide."
  (interactive)
  (find-file (expand-file-name "literate/index.org" user-emacs-directory)))
(defun kittymacs-find-config-file ()
  "Open one of the literate chapters."
  (interactive)
  (let ((default-directory (expand-file-name "literate/" user-emacs-directory)))
    (call-interactively #'find-file)))

(defun kittymacs-search-config ()
  "Search the configuration sources with ripgrep."
  (interactive)
  (consult-ripgrep (expand-file-name "literate/" user-emacs-directory)))

(defun kittymacs-open-private-file ()
  "Open private.el, creating it from the example if needed."
  (interactive)
  (let ((private (expand-file-name "private.el" kittymacs-lisp-dir))
        (example (expand-file-name "private.example.el" kittymacs-lisp-dir)))
    (when (and (not (file-exists-p private)) (file-exists-p example))
      (copy-file example private))
    (find-file private)))

(defun kittymacs-open-custom-file ()
  "Open the file where Customize saves settings."
  (interactive)
  (find-file custom-file))

(defun kittymacs-open-architecture ()
  "Open ARCHITECTURE.md, the design record."
  (interactive)
  (find-file (expand-file-name "ARCHITECTURE.md" user-emacs-directory)))
(defun kittymacs-literate--build (write)
  "Run the isolated literate builder; WRITE selects generation over checking."
  (let ((source-dir (expand-file-name "literate/" user-emacs-directory))
        (output (get-buffer-create "*kittymacs literate build*")))
    (dolist (buffer (buffer-list))
      (when-let* ((file (buffer-file-name buffer)))
        (when (and (file-in-directory-p file source-dir)
                   (buffer-modified-p buffer))
          (user-error "Save %s before building the literate configuration" file))))
    (with-current-buffer output
      (let ((inhibit-read-only t)) (erase-buffer)))
    (let ((status
           (call-process (expand-file-name invocation-name invocation-directory)
                         nil (list output t) nil
                         "-Q" "--batch" "-l"
                         (expand-file-name "tools/tangle.el" user-emacs-directory)
                         "--" (if write "--write" "--check"))))
      (display-buffer output)
      (unless (equal status 0)
        (user-error "Literate build failed; see %s" (buffer-name output)))
      (message (if write
                   "Lisp regenerated. Restart Emacs to apply configuration changes."
                 "Literate sources and deployed Lisp agree.")))))
(defun kittymacs-literate-tangle ()
  "Regenerate deployed Lisp from saved literate sources."
  (interactive)
  (kittymacs-literate--build t))
(defun kittymacs-literate-check ()
  "Check that deployed Lisp matches saved literate sources without writing it."
  (interactive)
  (kittymacs-literate--build nil))

(keymap-set kittymacs-config-map "c" (cons "reading guide" #'kittymacs-literate-open))
(keymap-set kittymacs-config-map "f" (cons "find chapter" #'kittymacs-find-config-file))
(keymap-set kittymacs-config-map "s" (cons "search config" #'kittymacs-search-config))
(keymap-set kittymacs-config-map "t" (cons "tangle" #'kittymacs-literate-tangle))
(keymap-set kittymacs-config-map "k" (cons "check tangle" #'kittymacs-literate-check))
(keymap-set kittymacs-config-map "p" (cons "private.el" #'kittymacs-open-private-file))
(keymap-set kittymacs-config-map "o" (cons "onboarding" #'kittymacs-onboard))
(keymap-set kittymacs-config-map "u" (cons "custom.el" #'kittymacs-open-custom-file))
(keymap-set kittymacs-config-map "a" (cons "architecture" #'kittymacs-open-architecture))
(keymap-set kittymacs-config-map "r" (cons "restart Emacs" #'restart-emacs))

(provide 'kittymacs-literate)
;;; kittymacs-literate.el ends here
