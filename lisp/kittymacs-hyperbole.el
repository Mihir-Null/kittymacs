;;; kittymacs-hyperbole.el --- Hyperbole: buttons, HyWiki, HyRolo, Koutliner -*- lexical-binding: t; -*-
;; Generated from literate/85-hyperbole.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-platform)
(require 'kittymacs-leader)

(defvar hyperbole-mode)
(defvar hyperbole-mode-map)
(defvar hywiki-default-mode)
(defvar hywiki-mode)
(defvar hywiki-directory)
(defvar hyrolo-file-list)
(defvar hsys-org-enable-smart-keys)
(defvar meow-mode-state-list)
(declare-function hyperbole-mode "hyperbole" (&optional arg))
(declare-function hywiki-mode "hywiki" (&optional arg))
(declare-function hkey-help-show "hmouse-drv" (&optional buffer current-window))
(declare-function kotl-mode "kotl-mode" ())
(declare-function hkey-either "hmouse-drv" (&optional arg))
(declare-function assist-key "hmouse-drv" ())
(declare-function hkey-help "hmouse-drv" (&optional assisting))
(declare-function hyperbole "hui-mini" (&optional menu menu-list doc-flag help-string-flag))
(declare-function hui:ebut-create "hui" (&optional start end))
(declare-function hui:ebut-link-directly "hui" (&optional depress-window release-window))
(declare-function hywiki-insert-link "hywiki" (&optional arg))
(declare-function hywiki-publish-to-html "hywiki" (&optional all-pages-flag))
(declare-function hyrolo-fgrep "hyrolo" (string &optional max-matches hyrolo-files-or-bufs
                                                count-only headline-only no-display
                                                interactive-flag))
(declare-function hyrolo-find-file "hyrolo" (&optional file find-function &rest args))
(declare-function hyrolo-next-match "hyrolo")
(declare-function hyrolo-previous-match "hyrolo")
(declare-function hyrolo-edit-entry "hyrolo")
(declare-function hyrolo-add "hyrolo" (name &optional file))
(declare-function hyrolo-quit "hyrolo")
(declare-function kfile:find "kfile" (file-name))
(declare-function kotl-mode:add-cell "kotl-mode")
(declare-function kotl-mode:add-child "kotl-mode")
(declare-function kotl-mode:demote-tree "kotl-mode")
(declare-function kotl-mode:promote-tree "kotl-mode")
(declare-function kotl-mode:hide-tree "kotl-mode")
(declare-function kotl-mode:show-tree "kotl-mode")
(declare-function kotl-mode:show-all "kotl-mode")
(declare-function kotl-mode:goto-cell "kotl-mode")
(declare-function kotl-mode:kill-tree "kotl-mode")
(declare-function klink:create "klink")
(declare-function kvspec:activate "kvspec")
(declare-function kexport:html "kexport")
(declare-function hywiki-add-page "hywiki" (page-name &optional force-flag debug-flag))
(declare-function hywiki-find-page "hywiki" (&optional wikiword))
(declare-function hywiki-get-singular-wikiword "hywiki" (wikiword))
(declare-function hywiki-page-read-new "hywiki" (&optional prompt initial))

(setopt package-pinned-packages
        (append '((hyperbole . "gnu")) (bound-and-true-p package-pinned-packages)))
(use-package hyperbole :ensure t :defer t)

(defgroup kittymacs-hyperbole nil
  "GNU Hyperbole: buttons, HyWiki, HyRolo and the Koutliner."
  :group 'kittymacs)

(defcustom kittymacs-hyperbole-after-org-delay 1
  "Idle seconds after Org loads before Hyperbole loads and turns on.
Nil leaves Hyperbole unloaded until a Hyperbole key asks for it."
  :type '(choice (const :tag "Only when a Hyperbole key asks" nil) number))

(defun kittymacs-hyperbole-enable ()
  "Load Hyperbole if it has not loaded, and turn its global mode on."
  (interactive)
  (unless (require 'hyperbole nil t)
    (user-error "Hyperbole is not installed; restart to install it, or M-x package-install"))
  (unless hyperbole-mode
    (hyperbole-mode 1)))

(defun kittymacs-hyperbole--call (command)
  "Turn Hyperbole on, then run its COMMAND as if its key had been pressed."
  (kittymacs-hyperbole-enable)
  (call-interactively command))

(defun kittymacs-hyperbole--enable-when-idle ()
  "Turn Hyperbole on after `kittymacs-hyperbole-after-org-delay' idle seconds.
A batch Emacs, such as a test or a build, never turns it on this way."
  (when (and kittymacs-hyperbole-after-org-delay (not noninteractive))
    (run-with-idle-timer kittymacs-hyperbole-after-org-delay nil
                         (lambda ()
                           (with-demoted-errors "Hyperbole did not turn on: %S"
                             (kittymacs-hyperbole-enable))))))

(with-eval-after-load 'org
  (kittymacs-hyperbole--enable-when-idle))

(defun kittymacs-hyperbole-kotl-mode ()
  "Turn Hyperbole on, then edit this buffer as a Koutline."
  (kittymacs-hyperbole-enable)
  (kotl-mode))

(add-to-list 'auto-mode-alist '("\\.kotl?\\'" . kittymacs-hyperbole-kotl-mode))

(defcustom kittymacs-hywiki-directory
  (expand-file-name "hywiki/" kittymacs-org-directory)
  "HyWiki's pages: every Org file directly in this directory is one page."
  :type 'directory)

(defcustom kittymacs-hyperbole-directory
  (expand-file-name "hyperbole/" kittymacs-org-directory)
  "Where the HyRolo file lives and where new Koutlines are offered."
  :type 'directory)

(defcustom kittymacs-hyrolo-files
  (list (expand-file-name "rolo.org" kittymacs-hyperbole-directory))
  "HyRolo's files; new entries go in the first."
  :type '(repeat file))

(defun kittymacs-hyperbole--hand-over ()
  "Give Hyperbole kittymacs's places and Org policy, unless already set.
Runs before Hyperbole loads, while its options are still unbound."
  (unless (boundp 'hywiki-directory)
    (setq hywiki-directory kittymacs-hywiki-directory))
  (unless (boundp 'hyrolo-file-list)
    (setq hyrolo-file-list kittymacs-hyrolo-files))
  (when (or (not (boundp 'hsys-org-enable-smart-keys))
            (eq hsys-org-enable-smart-keys 'unset))
    (setq hsys-org-enable-smart-keys 'buttons)))

(kittymacs-hyperbole--hand-over)

(defun kittymacs-hyperbole--release-keys ()
  "Take out of Hyperbole's map the keys that would hide Org's and Outline's."
  (dolist (key '("C-c @" "C-c \\"))
    (when (keymap-lookup hyperbole-mode-map key)
      (keymap-unset hyperbole-mode-map key t))))

(advice-add 'hkey-initialize :after #'kittymacs-hyperbole--release-keys)

(defun kittymacs-hyperbole--start-hywiki ()
  "Start HyWiki in `hywiki-default-mode' when Hyperbole turns on.
Turning Hyperbole off turns HyWiki off, so turning it on brings it back."
  (when (and hyperbole-mode (not hywiki-mode))
    (hywiki-mode hywiki-default-mode)))

(defun kittymacs-hyperbole--settle ()
  "Fit Hyperbole to kittymacs once it has loaded, and turn it on."
  (remove-hook 'temp-buffer-show-hook #'hkey-help-show)
  (when (eq temp-buffer-show-function #'hkey-help-show)
    (setq temp-buffer-show-function nil))
  (dolist (key '("M-RET" "C-h h"))
    (when (memq (keymap-lookup global-map key)
                '(kittymacs-hyperbole-action-key kittymacs-hyperbole-menu))
      (keymap-global-unset key t)))
  (add-hook 'hyperbole-mode-hook #'kittymacs-hyperbole--start-hywiki)
  (if hyperbole-mode
      (kittymacs-hyperbole--start-hywiki)
    (hyperbole-mode 1)))

(with-eval-after-load 'hyperbole
  (kittymacs-hyperbole--settle))

(defun kittymacs-hyperbole-action-key ()
  "Run the Action Key at point; with \\[universal-argument], the Assist Key."
  (interactive)
  (kittymacs-hyperbole--call #'hkey-either))

(defun kittymacs-hyperbole-assist-key ()
  "Run the Assist Key at point."
  (interactive)
  (kittymacs-hyperbole--call #'assist-key))

(defun kittymacs-hyperbole-help ()
  "Say what the Action Key would do at point; with a prefix, the Assist Key."
  (interactive)
  (kittymacs-hyperbole--call #'hkey-help))

(defun kittymacs-hyperbole-menu ()
  "Open Hyperbole's menu in the minibuffer."
  (interactive)
  (kittymacs-hyperbole--call #'hyperbole))

(defun kittymacs-hyperbole-button-create ()
  "Make an explicit button: `hui:ebut-create'."
  (interactive)
  (kittymacs-hyperbole--call #'hui:ebut-create))

(defun kittymacs-hyperbole-button-link ()
  "Make an explicit button that links to point in the other window."
  (interactive)
  (kittymacs-hyperbole--call #'hui:ebut-link-directly))

(defun kittymacs-hywiki-find (page)
  "Find the HyWiki PAGE, making it first if it is new.
Interactively, read its name, offering the existing pages."
  (interactive (progn (kittymacs-hyperbole-enable)
                      (list (hywiki-page-read-new "HyWiki page: "))))
  (kittymacs-hyperbole-enable)
  (unless (hywiki-add-page page)
    (user-error "Not a HyWikiWord, which is capitalized letters only: %s" page))
  ;; A plural names its singular's page, as `hywiki-add-page' made it.
  (hywiki-find-page (hywiki-get-singular-wikiword page)))

(defun kittymacs-hywiki-insert ()
  "Insert a HyWiki page reference at point: `hywiki-insert-link'."
  (interactive)
  (kittymacs-hyperbole--call #'hywiki-insert-link))

(defun kittymacs-hywiki-publish ()
  "Publish changed HyWiki pages as HTML; with a prefix, every page."
  (interactive)
  (kittymacs-hyperbole--call #'hywiki-publish-to-html))

(defun kittymacs-hyrolo-search ()
  "Search the HyRolo files for a string: `hyrolo-fgrep'."
  (interactive)
  (kittymacs-hyperbole--call #'hyrolo-fgrep))

(defun kittymacs-hyrolo-open ()
  "Open the first HyRolo file, making its directory if needed."
  (interactive)
  (kittymacs-hyperbole-enable)
  (when-let* ((file (car hyrolo-file-list)))
    (make-directory (file-name-directory (expand-file-name file)) t))
  (call-interactively #'hyrolo-find-file))

(defun kittymacs-hyperbole-koutline ()
  "Find or make a Koutline, offering `kittymacs-hyperbole-directory'."
  (interactive)
  (kittymacs-hyperbole-enable)
  (make-directory kittymacs-hyperbole-directory t)
  (let ((default-directory (file-name-as-directory kittymacs-hyperbole-directory)))
    (call-interactively #'kfile:find)))

(defun kittymacs-hyperbole-toggle ()
  "Turn Hyperbole off, or load it and turn it on."
  (interactive)
  (if (bound-and-true-p hyperbole-mode)
      (hyperbole-mode 0)
    (kittymacs-hyperbole-enable))
  (message "Hyperbole is %s" (if hyperbole-mode "on" "off")))

(keymap-set kittymacs-hyperbole-map "h" (cons "menu" #'kittymacs-hyperbole-menu))
(keymap-set kittymacs-hyperbole-map "a" (cons "action key" #'kittymacs-hyperbole-action-key))
(keymap-set kittymacs-hyperbole-map "A" (cons "assist key" #'kittymacs-hyperbole-assist-key))
(keymap-set kittymacs-hyperbole-map "?" (cons "what would it do" #'kittymacs-hyperbole-help))
(keymap-set kittymacs-hyperbole-map "b" (cons "explicit button" #'kittymacs-hyperbole-button-create))
(keymap-set kittymacs-hyperbole-map "l" (cons "link button" #'kittymacs-hyperbole-button-link))
(keymap-set kittymacs-hyperbole-map "w" (cons "hywiki page" #'kittymacs-hywiki-find))
(keymap-set kittymacs-hyperbole-map "i" (cons "insert hywiki ref" #'kittymacs-hywiki-insert))
(keymap-set kittymacs-hyperbole-map "p" (cons "publish hywiki" #'kittymacs-hywiki-publish))
(keymap-set kittymacs-hyperbole-map "r" (cons "search rolo" #'kittymacs-hyrolo-search))
(keymap-set kittymacs-hyperbole-map "R" (cons "open rolo" #'kittymacs-hyrolo-open))
(keymap-set kittymacs-hyperbole-map "k" (cons "koutline" #'kittymacs-hyperbole-koutline))
(keymap-set kittymacs-hyperbole-map "t" (cons "hyperbole on/off" #'kittymacs-hyperbole-toggle))

(keymap-global-set "M-RET" #'kittymacs-hyperbole-action-key)
(keymap-global-set "C-h h" #'kittymacs-hyperbole-menu)

(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(kotl-mode . normal))
  (add-to-list 'meow-mode-state-list '(hyrolo-mode . motion)))

(kittymacs-define-localleader 'kotl-mode
  "i" (cons "add cell" #'kotl-mode:add-cell)
  "c" (cons "add child" #'kotl-mode:add-child)
  ">" (cons "demote tree" #'kotl-mode:demote-tree)
  "<" (cons "promote tree" #'kotl-mode:promote-tree)
  "h" (cons "hide tree" #'kotl-mode:hide-tree)
  "s" (cons "show tree" #'kotl-mode:show-tree)
  "S" (cons "show all" #'kotl-mode:show-all)
  "j" (cons "jump to cell" #'kotl-mode:goto-cell)
  "l" (cons "link to cell" #'klink:create)
  "v" (cons "view spec" #'kvspec:activate)
  "k" (cons "kill tree" #'kotl-mode:kill-tree)
  "e" (cons "export to html" #'kexport:html))

(kittymacs-define-localleader 'hyrolo-mode
  "n" (cons "next match" #'hyrolo-next-match)
  "p" (cons "previous match" #'hyrolo-previous-match)
  "e" (cons "edit entry" #'hyrolo-edit-entry)
  "a" (cons "add entry" #'hyrolo-add)
  "s" (cons "search again" #'hyrolo-fgrep)
  "q" (cons "quit" #'hyrolo-quit))

(provide 'kittymacs-hyperbole)
;;; kittymacs-hyperbole.el ends here
