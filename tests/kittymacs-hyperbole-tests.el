;;; kittymacs-hyperbole-tests.el --- Hyperbole fits Org, Meow and the leader -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-hyperbole-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages: what needs Hyperbole or Meow is skipped where they are
;; missing.  `just test' runs it so; `just test-packages' runs it again with
;; KITTYMACS_TEST_PACKAGES, where Hyperbole and Meow are installed and their
;; absence fails, and so checks M-RET in a real Org buffer.  HOME and the Org directory are temporary, so
;; Hyperbole's ~/.hyperb/ and the notes directories land nowhere real.

;;; Code:
(require 'ert)
(require 'package)
(require 'seq)
(require 'cl-lib)

;; Spell the checkout without "~" before HOME moves: a checkout under the real
;; HOME starts with `default-directory' as "~/...", which would then name a
;; directory inside the temporary HOME.
(setq default-directory (expand-file-name default-directory))
;; Windows' runners name the temporary directory in 8.3 form (RUNNER~1),
;; while a visited file's name is the long one: use the long one throughout.
(setq temporary-file-directory
      (file-name-as-directory (file-truename temporary-file-directory)))
(defconst kittymacs-hyperbole-test-root
  (expand-file-name
   (file-name-directory
    (directory-file-name
     (file-name-directory (or load-file-name buffer-file-name))))))

(defconst kittymacs-hyperbole-test-home (make-temp-file "kittymacs-hyperbole-home-" t))
(setenv "HOME" kittymacs-hyperbole-test-home)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path (expand-file-name "lisp" kittymacs-hyperbole-test-root))
(require 'use-package)

(defvar kittymacs-profile)
(defvar kittymacs-org-directory)
(defvar hsys-org-enable-smart-keys)
(defvar hyperbole-mode)
(defvar hyperbole-mode-map)
(defvar hyrolo-file-list)
(defvar hywiki-directory)
(defvar hywiki-mode)
(defvar meow-mode-state-list)
(defvar org-link-frame-setup)
(setq kittymacs-profile 'full
      kittymacs-org-directory (expand-file-name "org/" kittymacs-hyperbole-test-home))
(require 'kittymacs-features)
(let ((use-package-ensure-function #'ignore))
  (require 'kittymacs-hyperbole))

(defconst kittymacs-hyperbole-test-loaded-at-start
  (list :hyperbole (featurep 'hyperbole) :org (featurep 'org)
        :m-ret (keymap-lookup global-map "M-RET")
        :c-h-h (keymap-lookup global-map "C-h h")
        :org-m-ret (lookup-key global-map [remap org-meta-return])
        :directories (seq-filter #'file-exists-p
                                 (list kittymacs-org-directory
                                       (file-name-directory (car hyrolo-file-list))
                                       hywiki-directory)))
  "What loading the module loaded or made, before any test could do more.")

(defconst kittymacs-hyperbole-test-file (or load-file-name buffer-file-name))

(defun kittymacs-hyperbole-test--installed-p (library)
  "Return non-nil if LIBRARY can be loaded here.
`just test-packages' runs under the full profile, which installs Hyperbole and
Meow, so there a missing one is a failure, not a skip."
  (or (locate-library library)
      (and (equal (getenv "KITTYMACS_TEST_PROFILE") "full")
           (getenv "KITTYMACS_TEST_PACKAGES")
           (error "%s is not installed in %s" library (getenv "KITTYMACS_TEST_PACKAGES")))))

(defun kittymacs-hyperbole-test--available-p ()
  "Return non-nil if Hyperbole can be loaded here."
  (kittymacs-hyperbole-test--installed-p "hyperbole"))

;;; Without Hyperbole

(ert-deftest kittymacs-hyperbole-module-loads-neither-hyperbole-nor-org ()
  "Hyperbole loads Org, and Org waits for its first use; no directory is made."
  (let ((start kittymacs-hyperbole-test-loaded-at-start))
    (should-not (plist-get start :hyperbole))
    (should-not (plist-get start :org))
    (should-not (plist-get start :directories))))

(defun kittymacs-hyperbole-test--leader (keys)
  "Return what KEYS under the leader run, without which-key's label."
  (let ((binding (keymap-lookup kittymacs-leader-map keys)))
    (if (and (consp binding) (stringp (car binding))) (cdr binding) binding)))

(ert-deftest kittymacs-hyperbole-leader-group-runs-commands ()
  (should (eq (kittymacs-hyperbole-test--leader "H") kittymacs-hyperbole-map))
  (dolist (key '("h" "a" "A" "?" "b" "l" "w" "i" "p" "r" "R" "k" "t"))
    (let ((command (kittymacs-hyperbole-test--leader (concat "H " key))))
      (should (equal (list key t) (list key (and (symbolp command) (commandp command))))))))

(ert-deftest kittymacs-hyperbole-global-keys-wait-for-hyperbole ()
  "Before Hyperbole loads, M-RET, in Org too, and C-h h load it first."
  (let ((start kittymacs-hyperbole-test-loaded-at-start))
    (should (eq (plist-get start :m-ret) #'kittymacs-hyperbole-action-key))
    (should (eq (plist-get start :org-m-ret) #'kittymacs-hyperbole-org-meta-return))
    (should (eq (plist-get start :c-h-h) #'kittymacs-hyperbole-menu))))

(defun kittymacs-hyperbole-test--first-m-ret ()
  "Press M-RET in a fresh Emacs's first Org buffer, on a heading, then a link.
Print RESULT: what the key ran first, the headings after it, whether
Hyperbole loaded, and whether the link was followed.  The subprocess test
calls this after loading this file, which loads nothing else."
  (require 'org)
  (let ((target (make-temp-file "kittymacs-hyperbole-target-" nil ".txt" "target\n"))
        (org-link-frame-setup '((file . find-file))))
    (switch-to-buffer (generate-new-buffer "first.org"))
    (org-mode)
    (insert (format "* First\nSee [[file:%s][the target]].\n" target))
    (goto-char (point-min))
    (end-of-line)
    (let ((first (key-binding (kbd "M-RET"))))
      (call-interactively first)
      (let ((headings (count-matches "^\\* " (point-min) (point-max)))
            (loaded (featurep 'hyperbole)))
        (search-forward "the target")
        (backward-char 3)
        (call-interactively (key-binding (kbd "M-RET")))
        (princ (format "RESULT: %S\n" (list first headings loaded
                                            (equal buffer-file-name target))))))))

(defun kittymacs-hyperbole-test--first-m-ret-in (delay)
  "Run `kittymacs-hyperbole-test--first-m-ret' in a fresh Emacs with DELAY."
  (with-temp-buffer
    (let ((status (call-process
                   (expand-file-name invocation-name invocation-directory) nil t nil
                   "-Q" "--batch" "-l" kittymacs-hyperbole-test-file
                   "--eval" (format "(setq kittymacs-hyperbole-after-org-delay %S)" delay)
                   "-f" "kittymacs-hyperbole-test--first-m-ret")))
      (should (equal status 0))
      (goto-char (point-min))
      (should (re-search-forward "^RESULT: \\(.*\\)$" nil t))
      (car (read-from-string (match-string 1))))))

(ert-deftest kittymacs-hyperbole-first-m-ret-in-org-loads-hyperbole ()
  "Org's own M-RET hides the global loader, so Org's command is remapped to it.
Before the idle second, the first M-RET on a heading makes one and the next,
on a link, follows it; with the delay nil, M-RET in Org stays Org's."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (should (equal (kittymacs-hyperbole-test--first-m-ret-in 1)
                 '(kittymacs-hyperbole-org-meta-return 2 t t)))
  (should (equal (kittymacs-hyperbole-test--first-m-ret-in nil)
                 '(kittymacs-hyperbole-org-meta-return 2 nil nil))))

(ert-deftest kittymacs-hyperbole-org-keeps-m-ret-on-structure ()
  "Hyperbole's Org option is `buttons' unless something set it first."
  (should (eq hsys-org-enable-smart-keys 'buttons))
  (let ((hsys-org-enable-smart-keys nil))
    (kittymacs-hyperbole--hand-over)
    (should (eq hsys-org-enable-smart-keys nil)))
  (let ((hsys-org-enable-smart-keys 'unset))
    (kittymacs-hyperbole--hand-over)
    (should (eq hsys-org-enable-smart-keys 'buttons))))

(ert-deftest kittymacs-hyperbole-files-live-under-the-org-directory ()
  (should (equal kittymacs-hywiki-directory
                 (expand-file-name "hywiki/" kittymacs-org-directory)))
  (should (equal kittymacs-hyrolo-files
                 (list (expand-file-name "hyperbole/rolo.org" kittymacs-org-directory))))
  (should (equal hywiki-directory kittymacs-hywiki-directory))
  (should (equal hyrolo-file-list kittymacs-hyrolo-files)))

(ert-deftest kittymacs-hyperbole-init-loads-the-module-only-for-its-feature ()
  (let ((forms (with-temp-buffer
                 (insert-file-contents (expand-file-name "init.el" kittymacs-hyperbole-test-root))
                 (let (forms form)
                   (while (setq form (ignore-errors (read (current-buffer))))
                     (push form forms))
                   forms))))
    (should (member '(when (kittymacs-feature-p 'hyperbole)
                       (kittymacs-require-module 'kittymacs-hyperbole))
                    forms))
    (should (eq (plist-get (alist-get 'hyperbole kittymacs-catalogue) :profile) 'full))))

(ert-deftest kittymacs-hyperbole-off-leaves-no-trace ()
  "With the feature off, the leader has no SPC H and M-RET is Emacs's."
  (with-temp-buffer
    (let ((status (call-process
                   (expand-file-name invocation-name invocation-directory) nil t nil
                   "-Q" "--batch" "-L" (expand-file-name "lisp" kittymacs-hyperbole-test-root)
                   "--eval"
                   (prin1-to-string
                    '(progn
                       (setq kittymacs-profile 'full
                             kittymacs-features-excluded '(hyperbole))
                       (require 'kittymacs-features)
                       (require 'kittymacs-leader)
                       (when (kittymacs-feature-p 'hyperbole)
                         (require 'kittymacs-hyperbole))
                       (kittymacs-leader-drop-empty-groups)
                       (princ (format "%S" (list (kittymacs-feature-p 'hyperbole)
                                                 (featurep 'kittymacs-hyperbole)
                                                 (keymap-lookup kittymacs-leader-map "H")
                                                 (keymap-lookup global-map "M-RET")))))))))
      (should (equal status 0))
      (should (equal (car (last (split-string (buffer-string) "\n" t)))
                     "(nil nil nil nil)")))))

(ert-deftest kittymacs-hyperbole-meow-starts-koutlines-in-normal ()
  (skip-unless (kittymacs-hyperbole-test--installed-p "meow"))
  (require 'meow)
  (should (eq (alist-get 'kotl-mode meow-mode-state-list) 'normal))
  (should (eq (alist-get 'hyrolo-mode meow-mode-state-list) 'motion)))

(ert-deftest kittymacs-hyperbole-localleaders-exist ()
  (should (keymap-lookup (alist-get 'kotl-mode kittymacs-localleader-alist) "i"))
  (should (keymap-lookup (alist-get 'hyrolo-mode kittymacs-localleader-alist) "q")))

;;; With Hyperbole

(defmacro kittymacs-hyperbole-test-with-org (text &rest body)
  "Run BODY in an Org buffer holding TEXT, with Hyperbole on.
The buffer is in the selected window, as one you type in is: the Action
Key acts on the buffer of the window it was pressed in."
  (declare (indent 1))
  `(progn
     (skip-unless (kittymacs-hyperbole-test--available-p))
     (kittymacs-hyperbole-enable)
     (let ((buffer (generate-new-buffer "kittymacs-hyperbole-test.org")))
       (unwind-protect
           (progn
             (switch-to-buffer buffer)
             (org-mode)
             (insert ,text)
             (goto-char (point-min))
             ,@body)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(ert-deftest kittymacs-hyperbole-turns-on-and-fits-in ()
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (kittymacs-hyperbole-enable)
  (should hyperbole-mode)
  (should (eq hywiki-mode :pages))
  (should (eq hsys-org-enable-smart-keys 'buttons))
  ;; Hyperbole's map answers now, and the loaders are gone.
  (should (eq (keymap-lookup hyperbole-mode-map "M-RET") #'hkey-either))
  (should-not (keymap-lookup global-map "M-RET"))
  (should (eq (keymap-lookup global-map "C-h h") #'hyperbole))
  ;; Org's and Outline's C-c keys stay theirs, even after a second start.
  (should-not (keymap-lookup hyperbole-mode-map "C-c @"))
  (should-not (keymap-lookup hyperbole-mode-map "C-c \\"))
  (hyperbole-mode 0)
  (hyperbole-mode 1)
  (should-not (keymap-lookup hyperbole-mode-map "C-c @"))
  (should-not (keymap-lookup hyperbole-mode-map "C-c \\"))
  ;; Org's M-RET is Org's again, for Hyperbole to fall back on.
  (should-not (commandp (lookup-key global-map [remap org-meta-return])))
  (should (eq hywiki-mode :pages))
  (should-not temp-buffer-show-function)
  (should-not (memq #'hkey-help-show temp-buffer-show-hook))
  (should (equal hywiki-directory kittymacs-hywiki-directory)))

(ert-deftest kittymacs-hyperbole-commands-under-spc-m-exist ()
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (kittymacs-hyperbole-enable)
  (require 'kotl-mode)
  (require 'hyrolo)
  (dolist (mode '(kotl-mode hyrolo-mode))
    (map-keymap (lambda (key binding)
                  (let ((command (if (consp binding) (cdr binding) binding)))
                    (should (equal (list mode key t) (list mode key (commandp command))))))
                (alist-get mode kittymacs-localleader-alist))))

(ert-deftest kittymacs-hyperbole-m-ret-on-a-heading-makes-a-heading ()
  (kittymacs-hyperbole-test-with-org "* First\n"
    (end-of-line)
    (should (eq (key-binding (kbd "M-RET")) #'hkey-either))
    (call-interactively #'hkey-either)
    (should (equal (count-matches "^\\* " (point-min) (point-max)) 2))))

(ert-deftest kittymacs-hyperbole-m-ret-in-a-list-makes-an-item ()
  (kittymacs-hyperbole-test-with-org "- one\n"
    (end-of-line)
    (call-interactively #'hkey-either)
    (should (equal (count-matches "^- " (point-min) (point-max)) 2))))

(ert-deftest kittymacs-hyperbole-m-ret-on-a-link-follows-it ()
  (let ((target (make-temp-file "kittymacs-hyperbole-target-" nil ".txt" "target\n"))
        (org-link-frame-setup '((file . find-file))))
    (unwind-protect
        (kittymacs-hyperbole-test-with-org (format "* Heading\nSee [[file:%s][the target]].\n" target)
          (search-forward "the target")
          (backward-char 3)
          (let ((origin (current-buffer)))
            (call-interactively #'hkey-either)
            (should (equal (buffer-file-name) target))
            (should (equal (count-matches "^\\* " (point-min) (point-max)) 0))
            (kill-buffer (current-buffer))
            (should (buffer-live-p origin))))
      (delete-file target))))

(ert-deftest kittymacs-hyperbole-spc-h-w-makes-a-new-page ()
  "Hyperbole's own `hywiki-find-page' opens only a page that exists."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "GardenPlans")))
    (call-interactively #'kittymacs-hywiki-find))
  (unwind-protect
      (progn
        (should (derived-mode-p 'org-mode))
        (should (equal buffer-file-name
                       (expand-file-name "GardenPlan.org" kittymacs-hywiki-directory))))
    (kill-buffer (current-buffer))))

(ert-deftest kittymacs-hyperbole-off-gives-m-ret-back-to-org ()
  (kittymacs-hyperbole-test-with-org "* First\n"
    (kittymacs-hyperbole-toggle)
    (unwind-protect
        (progn
          (should-not hyperbole-mode)
          (should (eq (key-binding (kbd "M-RET")) #'org-meta-return)))
      (kittymacs-hyperbole-toggle))
    (should hyperbole-mode)))

(ert-deftest kittymacs-hyperbole-m-ret-in-a-hywiki-page-makes-no-page ()
  "A HyWiki page is Org: M-RET on a new word makes a heading, on a page's opens it."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (kittymacs-hyperbole-enable)
  (make-directory hywiki-directory t)
  (let ((page (expand-file-name "Garden.org" hywiki-directory))
        (other (expand-file-name "Compost.org" hywiki-directory))
        (unwanted (expand-file-name "Tomatoes.org" hywiki-directory)))
    (with-temp-file page (insert "* Tomatoes\nFeed them Compost.\n"))
    (with-temp-file other (insert "* Heaps\n"))
    (hywiki-make-referent-hasht)
    (unwind-protect
        ;; Were a page to be made, Hyperbole would ask first: say yes.
        (cl-letf (((symbol-function 'y-or-n-p) #'always)
                  ((symbol-function 'yes-or-no-p) #'always))
          (find-file page)
          (should (hywiki-in-page-p))
          (search-forward "Toma")
          (call-interactively #'hkey-either)
          (should-not (file-exists-p unwanted))
          (should (equal buffer-file-name page))
          (should (equal (count-matches "^\\* " (point-min) (point-max)) 2))
          (search-forward "Compo")
          (call-interactively #'hkey-either)
          (should (get-file-buffer other))
          (should (equal (buffer-file-name (window-buffer)) other)))
      (dolist (file (list page other unwanted))
        (when-let* ((buffer (get-file-buffer file)))
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer))
        (when (file-exists-p file) (delete-file file))))))

(defun kittymacs-hyperbole-test--cells ()
  "Return each cell of this Koutline's view as (LABEL . FIRST-LINE)."
  (save-excursion
    (goto-char (point-min))
    (let (cells)
      (while (re-search-forward "^ *\\([0-9]+\\)\\. \\(.*\\)$" nil t)
        (push (cons (match-string-no-properties 1) (match-string-no-properties 2)) cells))
      (nreverse cells))))

(ert-deftest kittymacs-hyperbole-meow-keeps-koutline-labels ()
  "Meow's line kill and change take a cell's text, never its label."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (skip-unless (kittymacs-hyperbole-test--installed-p "meow"))
  (kittymacs-hyperbole-enable)
  (require 'meow)
  (let ((file (make-temp-file "kittymacs-koutline-" nil ".kotl"))
        (meow-was-on (bound-and-true-p meow-global-mode)))
    (delete-file file)
    (meow-global-mode 1)
    (unwind-protect
        (progn
          (find-file file)
          (should (derived-mode-p 'kotl-mode))
          (should meow-normal-mode)
          (insert "first")
          (kotl-mode:add-cell 1 "second")
          (kotl-mode:add-cell 1 "third")
          (kotl-mode:goto-cell "2")
          (kotl-mode:beginning-of-cell)
          (meow-line 1)
          (meow-kill)
          ;; The command loop deactivates the mark after a kill; batch has none.
          (deactivate-mark)
          (should (equal (kittymacs-hyperbole-test--cells)
                         '(("1" . "first") ("2" . "") ("3" . "third"))))
          (kotl-mode:goto-cell "3")
          (kotl-mode:beginning-of-cell)
          (meow-line 1)
          (meow-change)
          (insert "THIRD")
          (meow-insert-exit)
          (deactivate-mark)
          (should (equal (kittymacs-hyperbole-test--cells)
                         '(("1" . "first") ("2" . "") ("3" . "THIRD"))))
          ;; A selection across cells is refused, and changes nothing.
          (kotl-mode:goto-cell "1")
          (kotl-mode:beginning-of-cell)
          (dotimes (_ 4) (meow-line 1))
          (should-error (meow-kill))
          (should-error (meow-change))
          (meow-normal-mode 1)
          (should (equal (kittymacs-hyperbole-test--cells)
                         '(("1" . "first") ("2" . "") ("3" . "THIRD"))))
          (save-buffer)
          (kill-buffer)
          (find-file file)
          (should (equal (kittymacs-hyperbole-test--cells)
                         '(("1" . "first") ("2" . "") ("3" . "THIRD")))))
      (when-let* ((buffer (get-file-buffer file)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (when (file-exists-p file) (delete-file file))
      (unless meow-was-on (meow-global-mode 0)))))

(ert-deftest kittymacs-hyperbole-turning-on-makes-only-the-wiki-directory ()
  "HyWiki lists its pages as it starts, which makes its directory; the rest waits."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (kittymacs-hyperbole-enable)
  (should (file-directory-p hywiki-directory))
  (should-not (file-exists-p kittymacs-hyperbole-directory)))

(defvar dired-mode-map)

(ert-deftest kittymacs-hyperbole-dired-keeps-its-at-key ()
  "Hyperbole binds Dired's @ to HyControl as the package activates and as it loads."
  (skip-unless (kittymacs-hyperbole-test--available-p))
  (require 'dired)
  (kittymacs-hyperbole-enable)
  (let ((buffer (dired-noselect temporary-file-directory)))
    (unwind-protect
        (with-current-buffer buffer
          (should (eq (key-binding "@") #'tramp-dired-find-file-with-sudo)))
      (kill-buffer buffer))))

;;; kittymacs-hyperbole-tests.el ends here
