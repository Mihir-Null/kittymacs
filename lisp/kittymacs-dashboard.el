;;; kittymacs-dashboard.el --- Doom-like home page -*- lexical-binding: t; -*-
;; Generated from literate/55-dashboard.org; edit the Org source, then tangle.

;;; Commentary:
;; A small home page using dashboard, project.el, recentf and bookmarks.
;; Fonts are established before dashboard measures the banner and buttons.

;;; Code:

(require 'kittymacs-ui)
(defun kittymacs-dashboard-open-cheatsheet (&rest _)
  "Open the local keybindings and commands cheat sheet."
  (interactive)
  (find-file (expand-file-name "keybindings.org" kittymacs-lisp-dir)))
(defun kittymacs-dashboard-open-tutor (&rest _)
  "Start Meow's interactive tutorial."
  (interactive)
  (call-interactively #'meow-tutor))

(defun kittymacs-dashboard-open-keys-chapter (&rest _)
  "Open the keys chapter: the whole SPC tree, group by group."
  (interactive)
  (find-file (expand-file-name "literate/42-keys.org" user-emacs-directory)))
(defun kittymacs-dashboard-open-file (&rest _)
  "Prompt for a file from a dashboard button."
  (interactive)
  (call-interactively #'find-file))
(defun kittymacs-dashboard-open-config (&rest _)
  "Open the documented literate configuration."
  (interactive)
  (kittymacs-literate-open))
(defun kittymacs-dashboard-open-project (&rest _)
  "Choose a project using Emacs project.el."
  (interactive)
  (call-interactively #'project-switch-project))
(defun kittymacs-dashboard-open-recent (&rest _)
  "Choose a recently opened file."
  (interactive)
  (if (fboundp 'consult-recent-file)
      (call-interactively #'consult-recent-file)
    (call-interactively #'recentf-open-files)))
(defun kittymacs-dashboard-open-agenda (&rest _)
  "Open the Org agenda."
  (interactive)
  (call-interactively #'org-agenda))
(defun kittymacs-dashboard-center-lines ()
  "Center each visible dashboard line using its rendered pixel width.
Measure the actual buffer so heading display overlays and icon faces count.
Exclude trailing padding and compensate for leading indentation."
  (let ((inhibit-read-only t)
        (inhibit-redisplay t)
        (buffer (current-buffer)))
    (save-window-excursion
      ;; During after-init this buffer may not have been displayed yet.
      (set-window-buffer (selected-window) buffer)
      (with-current-buffer buffer
        (remove-text-properties (point-min) (point-max)
                                '(line-prefix nil wrap-prefix nil indent-prefix nil))
        (save-excursion
          (goto-char (point-min))
          (while (not (eobp))
            (let* ((start (line-beginning-position))
                   (end (line-end-position))
                   (first (progn (skip-chars-forward " \t" end) (point)))
                   (last (save-excursion
                           (goto-char end)
                           (skip-chars-backward " \t" start)
                           (point))))
              (when (< first last)
                (let* ((width (car (window-text-pixel-size
                                    (selected-window) start last t)))
                       (indent (car (window-text-pixel-size
                                     (selected-window) start first t)))
                       (offset (/ (+ width indent) 2.0))
                       (prefix (propertize
                                " " 'display
                                `(space :align-to (- center (,offset))))))
                  (add-text-properties start end
                                       `(line-prefix ,prefix wrap-prefix ,prefix)))))
            (forward-line)))))))
(defun kittymacs-dashboard-recenter (&rest _)
  "Recompute visible dashboard text metrics after a font or theme change."
  (when-let* ((window (get-buffer-window dashboard-buffer-name t)))
    (with-selected-window window
      (with-current-buffer dashboard-buffer-name
        (kittymacs-dashboard-center-lines)))))
(defvar kittymacs-dashboard-key-guide
  '(("SPC SPC" "run a command by name" "SPC h ?" "the cheat sheet")
    ("SPC f f" "open a file"           "SPC h t" "Meow's tutorial")
    ("SPC m"   "menu for this mode"    "SPC C c" "the reading guide"))
  "Rows of (KEY WHAT KEY WHAT) shown at the bottom of the home page.")

(defun kittymacs-dashboard-insert-key-guide ()
  "Insert the short guide to the first keys."
  (insert "\n")
  (dolist (row kittymacs-dashboard-key-guide)
    (pcase-let ((`(,left-key ,left-what ,right-key ,right-what) row))
      (insert (propertize (format "%-8s" left-key) 'face 'dashboard-navigator)
              (propertize (format "%-24s" left-what) 'face 'font-lock-comment-face)
              (propertize (format "%-8s" right-key) 'face 'dashboard-navigator)
              (propertize right-what 'face 'font-lock-comment-face)
              "\n"))))
(use-package dashboard
  :ensure t
  :demand t
  :init
  (setq dashboard-buffer-name "*home*"
        dashboard-startup-banner 'ascii
        dashboard-banner-ascii
        (mapconcat #'identity
                   '("╭────────────────────────────╮"
                     "│                            │"
                     "│   k i t t y m a c s   :3   │"
                     "│                            │"
                     "╰────────────────────────────╯")
                   "\n")
        dashboard-banner-logo-title "select · extend · act"
        dashboard-center-content t
        dashboard-vertically-center-content nil
        dashboard-navigation-cycle t
        dashboard-hide-cursor t
        dashboard-icon-type 'nerd-icons
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-display-icons-p #'kittymacs-icons-available-p
        dashboard-heading-icon-height 1.0
        dashboard-show-shortcuts t
        dashboard-projects-backend 'project-el
        dashboard-path-style 'truncate-middle
        dashboard-path-max-length 48
        dashboard-items '((recents . 5)
                          (projects . 5)
                          (bookmarks . 3))
        dashboard-item-shortcuts '((recents . "r")
                                   (projects . "p")
                                   (bookmarks . "b"))
        dashboard-item-names '(("Recent Files:" . "Recent")
                               ("Projects:" . "Projects")
                               ("Bookmarks:" . "Bookmarks"))
        dashboard-startupify-list '(dashboard-insert-banner
                                    dashboard-insert-banner-title
                                    dashboard-insert-newline
                                    dashboard-insert-navigator
                                    dashboard-insert-newline
                                    dashboard-insert-init-info
                                    dashboard-insert-items
                                    kittymacs-dashboard-insert-key-guide
                                    kittymacs-dashboard-center-lines)
        dashboard-init-info
        (lambda ()
          (format "Emacs %s · ready in %s"
                  emacs-version
                  (emacs-init-time)))
        dashboard-navigator-buttons
        '((("+" "File" "Open a file" kittymacs-dashboard-open-file)
           ("◆" "Project" "Switch project" kittymacs-dashboard-open-project)
           ("↺" "Recent" "Open a recent file" kittymacs-dashboard-open-recent))
          (("◎" "Agenda" "Open the Org agenda" kittymacs-dashboard-open-agenda)
           ("*" "Scratch" "Open the scratch buffer"
            (lambda (&rest _) (switch-to-buffer "*scratch*")))
           ("λ" "Config" "Open the kittymacs reading guide (SPC C c)"
            kittymacs-dashboard-open-config))
          (("?" "Keys & commands" "Open the local cheat sheet (SPC h ?, or ? here)"
            kittymacs-dashboard-open-cheatsheet)
           ("»" "Meow tutor" "Learn select, extend, act (SPC h t)"
            kittymacs-dashboard-open-tutor)
           ("§" "Leader tree" "Every SPC key, group by group"
            kittymacs-dashboard-open-keys-chapter))))
  :config
  (set-face-attribute 'dashboard-text-banner nil
                      :inherit 'font-lock-keyword-face
                      :weight 'bold)
  (set-face-attribute 'dashboard-banner-logo-title nil
                      :inherit 'font-lock-comment-face
                      :height 1.05)
  (set-face-attribute 'dashboard-heading nil
                      :inherit 'font-lock-function-name-face
                      :weight 'bold)
  (set-face-attribute 'dashboard-navigator nil
                      :inherit 'font-lock-keyword-face
                      :weight 'semi-bold)

  (define-key dashboard-mode-map (kbd "?") #'kittymacs-dashboard-open-cheatsheet)

  (add-hook 'window-setup-hook #'kittymacs-dashboard-recenter 100)
  (add-hook 'after-setting-font-hook #'kittymacs-dashboard-recenter 100)
  (add-hook 'enable-theme-functions #'kittymacs-dashboard-recenter 100)

  ;; Skip the home page when Emacs was invoked with a file argument.
  (dashboard-setup-startup-hook))
;; Keep r/p/b/? and dashboard item shortcuts alongside Meow j/k and SPC.
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(dashboard-mode . motion)))
(provide 'kittymacs-dashboard)
;;; kittymacs-dashboard.el ends here
