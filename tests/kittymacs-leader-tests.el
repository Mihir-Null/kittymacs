;;; kittymacs-leader-tests.el --- Leader and localleader behaviour -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=/path/to/var/elpa emacs -Q --batch -l tests/kittymacs-leader-tests.el -f ert-run-tests-batch-and-exit
;; Loads only Meow, kittymacs-leader.el and kittymacs-keys.el; the personal
;; configuration is not loaded.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'package)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(add-to-list 'load-path
             (expand-file-name "../lisp"
                               (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-leader)
(require 'kittymacs-keys)

(keymap-set kittymacs-leader-map "f f" #'find-file)
(kittymacs-leader-enable)
(meow-global-mode 1)

(defmacro kittymacs-test-with-mode (mode state &rest body)
  "Run BODY in a fresh buffer in MODE after switching Meow to STATE."
  (declare (indent 2))
  `(with-temp-buffer
     (funcall ,mode)
     (meow--switch-state ,state)
     ,@body))

(ert-deftest kittymacs-leader-is-a-prefix-in-normal-and-motion ()
  (kittymacs-test-with-mode #'text-mode 'normal
    (should (meow-normal-mode-p))
    ;; `key-binding' merges every active map's prefix, so check identity on
    ;; Meow's own state map and effect on the merged result.
    (should (eq (keymap-lookup meow-normal-state-keymap "SPC") kittymacs-leader-map))
    (should (keymapp (key-binding (kbd "SPC"))))
    (should (eq (key-binding (kbd "SPC f f")) #'find-file)))
  (kittymacs-test-with-mode #'special-mode 'motion
    (should (meow-motion-mode-p))
    (should (eq (keymap-lookup meow-motion-state-keymap "SPC") kittymacs-leader-map))
    (should (eq (key-binding (kbd "SPC f f")) #'find-file))))

(ert-deftest kittymacs-leader-groups-exist-with-no-other-chapter-loaded ()
  "A chapter that binds into a group needs nothing but this module first."
  (should (eq (keymap-lookup kittymacs-leader-map "p") kittymacs-project-map))
  (should (eq (keymap-lookup kittymacs-leader-map "u") kittymacs-user-map))
  (should (eq (keymap-lookup kittymacs-leader-map "p f") #'project-find-file)))

(ert-deftest kittymacs-leader-insert-state-still-inserts-spaces ()
  (kittymacs-test-with-mode #'text-mode 'insert
    (should (eq (key-binding (kbd "SPC")) #'self-insert-command))))

(ert-deftest kittymacs-localleader-composes-along-the-mode-lineage ()
  (let ((kittymacs-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile "r" #'recompile)
    (kittymacs-define-localleader 'emacs-lisp-mode "e" #'eval-buffer "c" #'byte-compile-file)
    (kittymacs-test-with-mode #'emacs-lisp-mode 'normal
      (should (eq (key-binding (kbd "SPC m e")) #'eval-buffer))
      (should (eq (key-binding (kbd "SPC m c")) #'byte-compile-file))
      (should (eq (key-binding (kbd "SPC m r")) #'recompile))
      (should (member "SPC m e" (mapcar #'key-description (where-is-internal #'eval-buffer)))))
    (kittymacs-test-with-mode #'text-mode 'normal
      (should-not (key-binding (kbd "SPC m")))
      (should-not kittymacs--localleader-alist))))

(ert-deftest kittymacs-localleader-leaves-out-a-nil-definition ()
  "A menu names an optional command in place, and a feature that is off shows nothing."
  (let ((kittymacs-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile "r" nil "e" (cons "eval" #'eval-buffer))
    (kittymacs-test-with-mode #'emacs-lisp-mode 'normal
      (should (eq (key-binding (kbd "SPC m c")) #'compile))
      (should (eq (key-binding (kbd "SPC m e")) #'eval-buffer))
      (should-not (key-binding (kbd "SPC m r"))))))

(ert-deftest kittymacs-localleader-with-nothing-left-is-no-menu ()
  (let ((kittymacs-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile)
    (kittymacs-define-localleader 'prog-mode "c" nil)
    (should-not (assq 'prog-mode kittymacs-localleader-alist))
    (kittymacs-test-with-mode #'emacs-lisp-mode 'normal
      (should-not (key-binding (kbd "SPC m"))))))

;;; Minor-mode groups

(define-minor-mode kittymacs-test-review-mode
  "A stand-in for a minor mode that turns on over any file, as a review does.")

(ert-deftest kittymacs-minor-localleader-group-follows-its-mode ()
  "The group is there while the mode is on and gone once it is off."
  (let ((kittymacs-localleader-alist nil)
        (kittymacs-minor-localleader-alist nil))
    (kittymacs-define-minor-localleader 'kittymacs-test-review-mode "R" "review"
      "n" (cons "next" #'next-line))
    (kittymacs-test-with-mode #'text-mode 'normal
      (should-not (key-binding (kbd "SPC m")))
      (kittymacs-test-review-mode 1)
      (should (eq (key-binding (kbd "SPC m R n")) #'next-line))
      (should (member "SPC m R n" (mapcar #'key-description (where-is-internal #'next-line))))
      (kittymacs-test-review-mode -1)
      (should-not (key-binding (kbd "SPC m R")))
      (should-not kittymacs--localleader-alist))))

(ert-deftest kittymacs-minor-localleader-leaves-the-major-menu-alone ()
  "Only the group's own key changes; every other key of the major menu stays."
  (let ((kittymacs-localleader-alist nil)
        (kittymacs-minor-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile "r" #'recompile)
    (kittymacs-define-minor-localleader 'kittymacs-test-review-mode "R" "review"
      "n" #'next-line)
    (kittymacs-test-with-mode #'emacs-lisp-mode 'normal
      (kittymacs-test-review-mode 1)
      (should (eq (key-binding (kbd "SPC m c")) #'compile))
      (should (eq (key-binding (kbd "SPC m r")) #'recompile))
      (should (eq (key-binding (kbd "SPC m R n")) #'next-line))
      (kittymacs-test-review-mode -1)
      (should (eq (key-binding (kbd "SPC m c")) #'compile))
      (should-not (key-binding (kbd "SPC m R"))))))

(ert-deftest kittymacs-minor-localleader-takes-a-keymap-as-it-is ()
  "A package's own prefix map serves as the group, and later changes to it show."
  (let ((kittymacs-localleader-alist nil)
        (kittymacs-minor-localleader-alist nil)
        (map (define-keymap "n" #'next-line)))
    (kittymacs-define-minor-localleader 'kittymacs-test-review-mode "R" "review" map)
    (keymap-set map "p" #'previous-line)
    (kittymacs-test-with-mode #'text-mode 'normal
      (kittymacs-test-review-mode 1)
      (should (eq (key-binding (kbd "SPC m R n")) #'next-line))
      (should (eq (key-binding (kbd "SPC m R p")) #'previous-line)))))

(ert-deftest kittymacs-minor-localleader-leaves-out-a-nil-definition ()
  "A nil definition leaves its key out, and nothing left means no group."
  (let ((kittymacs-localleader-alist nil)
        (kittymacs-minor-localleader-alist nil))
    (kittymacs-define-minor-localleader 'kittymacs-test-review-mode "R" "review"
      "n" #'next-line "x" nil)
    (kittymacs-test-with-mode #'text-mode 'normal
      (kittymacs-test-review-mode 1)
      (should (eq (key-binding (kbd "SPC m R n")) #'next-line))
      (should-not (key-binding (kbd "SPC m R x"))))
    (kittymacs-define-minor-localleader 'kittymacs-test-review-mode "R" "review" "x" nil)
    (should-not (assq 'kittymacs-test-review-mode kittymacs-minor-localleader-alist))
    (kittymacs-test-with-mode #'text-mode 'normal
      (kittymacs-test-review-mode 1)
      (should-not (key-binding (kbd "SPC m"))))))

(ert-deftest kittymacs-leader-drops-a-group-nothing-bound-a-key-in ()
  "An empty group would show in which-key and lead nowhere."
  (let* ((kittymacs-leader-map (make-sparse-keymap))
         (kept (make-sparse-keymap))
         (dropped (make-sparse-keymap))
         (kittymacs-features--enabled '(meow))
         (kittymacs-features--profile 'minimal))
    (keymap-set kept "x" #'ignore)
    (keymap-set kittymacs-leader-map "k" (cons "kept" kept))
    (keymap-set kittymacs-leader-map "d" (cons "dropped" dropped))
    (keymap-set kittymacs-leader-map "u" (cons "user" kittymacs-user-map))
    (keymap-set kittymacs-leader-map "p" (cons "project" kittymacs-project-map))
    (keymap-set kittymacs-leader-map "c" #'ignore)
    (kittymacs-leader-drop-empty-groups)
    (should (keymap-lookup kittymacs-leader-map "k x"))
    (should (keymap-lookup kittymacs-leader-map "p f"))
    (should (eq (keymap-lookup kittymacs-leader-map "c") #'ignore))
    (should-not (keymap-lookup kittymacs-leader-map "d"))
    (should-not (keymap-lookup kittymacs-leader-map "u"))))

(ert-deftest kittymacs-leader-keeps-your-own-group-under-the-full-profile ()
  "`SPC u' has always been there under full, which must not change."
  (let* ((kittymacs-leader-map (make-sparse-keymap))
         (kittymacs-features--enabled '(meow))
         (kittymacs-features--profile 'full))
    (keymap-set kittymacs-leader-map "u" (cons "user" kittymacs-user-map))
    (kittymacs-leader-drop-empty-groups)
    (should (keymap-lookup kittymacs-leader-map "u"))))

(ert-deftest kittymacs-localleader-is-gone-in-insert-state ()
  (let ((kittymacs-localleader-alist nil))
    (kittymacs-define-localleader 'prog-mode "c" #'compile)
    (kittymacs-test-with-mode #'emacs-lisp-mode 'insert
      (should (eq (key-binding (kbd "SPC")) #'self-insert-command)))))

(ert-deftest kittymacs-keypad-is-unbound-unless-requested ()
  (should-not (where-is-internal #'meow-keypad kittymacs-leader-map))
  (let ((kittymacs-keypad-key "K"))
    (unwind-protect
        (progn
          (kittymacs-leader-enable)
          (should (eq (keymap-lookup kittymacs-leader-map "K") #'meow-keypad)))
      (keymap-unset kittymacs-leader-map "K" t)))
  (should-not (where-is-internal #'meow-keypad kittymacs-leader-map)))

(ert-deftest kittymacs-leader-enable-is-idempotent ()
  (let ((entries (seq-count (lambda (entry) (eq entry 'kittymacs--localleader-alist))
                            emulation-mode-map-alists)))
    (kittymacs-leader-enable)
    (should (= entries 1))
    (should (= 1 (seq-count (lambda (entry) (eq entry 'kittymacs--localleader-alist))
                            emulation-mode-map-alists)))))

(defun kittymacs-test-quit-key (key client)
  "Run `SPC q' KEY with the frame's client parameter CLIENT; return what it called."
  (let ((saved (frame-parameter nil 'client))
        called)
    (set-frame-parameter nil 'client client)
    (unwind-protect
        (cl-letf (((symbol-function 'server-save-buffers-kill-terminal)
                   (lambda (&rest _) (interactive) (push 'kill-terminal called)))
                  ((symbol-function 'server-delete-client)
                   (lambda (&rest _) (interactive) (push 'delete-client called)))
                  ((symbol-function 'save-buffers-kill-emacs)
                   (lambda (&rest _) (interactive) (push 'save-buffers-kill-emacs called)))
                  ((symbol-function 'kill-emacs)
                   (lambda (&rest _) (interactive) (push 'kill-emacs called))))
          (call-interactively (keymap-lookup kittymacs-leader-map (concat "q " key))))
      (set-frame-parameter nil 'client saved))
    called))

(ert-deftest kittymacs-quit-in-a-client-frame-closes-only-the-client ()
  "A daemon under systemd that exits cleanly is not restarted."
  (let ((client (make-pipe-process :name "kittymacs-test-client" :noquery t)))
    (unwind-protect
        (progn
          (should (equal (kittymacs-test-quit-key "q" client) '(kill-terminal)))
          (should (equal (kittymacs-test-quit-key "Q" client) '(delete-client))))
      (delete-process client))))

(ert-deftest kittymacs-quit-in-a-standalone-frame-quits-emacs ()
  (should (equal (kittymacs-test-quit-key "q" nil) '(save-buffers-kill-emacs)))
  (should (equal (kittymacs-test-quit-key "Q" nil) '(kill-emacs))))

(ert-deftest kittymacs-quit-stops-the-daemon-only-on-its-own-key ()
  (let ((client (make-pipe-process :name "kittymacs-test-client" :noquery t)))
    (unwind-protect
        (should (equal (kittymacs-test-quit-key "K" client) '(save-buffers-kill-emacs)))
      (delete-process client))))

(provide 'kittymacs-leader-tests)
;;; kittymacs-leader-tests.el ends here
