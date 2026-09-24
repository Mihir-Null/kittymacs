;;; kittymacs-ui.el --- Fonts, theme, mode line and icons -*- lexical-binding: t; -*-
;; Generated from literate/50-appearance.org; edit the Org source, then tangle.

;; Highlighting defaults distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'seq)
(require 'kittymacs-defaults)

(defgroup kittymacs-ui nil
  "Fonts, theme and presentation."
  :group 'kittymacs)

(defcustom kittymacs-font-family "GoogleSansCode Nerd Font"
  "Preferred editing font family; the platform default is used if it is absent."
  :type 'string)

(defcustom kittymacs-font-size 14
  "Default editing font size, in points."
  :type 'natnum)

(defcustom kittymacs-nerd-font "Symbols Nerd Font Mono"
  "Font family used for Nerd Font icons."
  :type 'string)

(defcustom kittymacs-icons 'auto
  "Whether to render Nerd Font icons.
With `auto', require a graphical frame and an installed icon font.
Use t for a terminal configured with a Nerd Font, or nil to disable icons."
  :type '(choice (const auto) (const t) (const nil)))

(defcustom kittymacs-theme 'doom-sonokai
  "Default theme."
  :type 'symbol)

(defcustom kittymacs-light-theme 'doom-one-light
  "Theme used by `kittymacs-toggle-theme'."
  :type 'symbol)

(defcustom kittymacs-line-numbers-in-programming t
  "Whether programming buffers show line numbers."
  :type 'boolean)
(defun kittymacs-resolve-font-family ()
  "Return the installed family for `kittymacs-font-family', or nil."
  (when (display-graphic-p)
    (seq-find (lambda (family) (find-font (font-spec :family family)))
              (if (equal kittymacs-font-family "GoogleSansCode Nerd Font")
                  (list kittymacs-font-family "GoogleSansCode NF")
                (list kittymacs-font-family)))))

(defun kittymacs-icons-available-p ()
  "Return non-nil when Nerd Font icons should be rendered."
  (pcase kittymacs-icons
    ('t t)
    ('nil nil)
    ('auto (and (display-graphic-p)
                (find-font (font-spec :family kittymacs-nerd-font))
                t))))

(defun kittymacs--apply-icon-font (&optional frame)
  "Map Nerd icon ranges to `kittymacs-nerd-font' in graphical FRAME."
  (with-selected-frame (or frame (selected-frame))
    (when (kittymacs-icons-available-p)
      (nerd-icons-set-font kittymacs-nerd-font (selected-frame)))))

(defun kittymacs--apply-font (&optional frame)
  "Apply the editing, symbol and icon fonts to FRAME."
  (with-selected-frame (or frame (selected-frame))
    (when (display-graphic-p)
      (when-let* ((family (kittymacs-resolve-font-family)))
        (set-face-attribute 'default (selected-frame) :family family))
      (set-face-attribute 'default (selected-frame) :height (* 10 kittymacs-font-size))
      (when-let* ((symbols (seq-find (lambda (family) (find-font (font-spec :family family)))
                                     '("Segoe UI Symbol" "Symbola" "Apple Symbols" "Symbol"))))
        (set-fontset-font t 'symbol symbols nil))
      (kittymacs--apply-icon-font))))

(setopt line-spacing 0.1
        text-scale-mode-step 1.08)

(use-package nerd-icons
  :ensure t
  :demand t
  :custom
  (nerd-icons-font-family kittymacs-nerd-font))

(add-hook 'after-setting-font-hook #'kittymacs--apply-icon-font)
(add-hook 'after-make-frame-functions #'kittymacs--apply-font)
(kittymacs--apply-font)
(setopt custom-safe-themes t)
(add-to-list 'custom-theme-load-path
             (expand-file-name "themes/" (file-name-directory (or load-file-name buffer-file-name))))

(defun kittymacs-load-theme (theme)
  "Disable active themes and load THEME."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t)
  (when (fboundp 'doom-themes-org-config)
    (doom-themes-org-config)))

(defun kittymacs-toggle-theme ()
  "Toggle between `kittymacs-theme' and `kittymacs-light-theme'."
  (interactive)
  (kittymacs-load-theme (if (memq kittymacs-theme custom-enabled-themes)
                          kittymacs-light-theme
                        kittymacs-theme)))

(use-package doom-themes
  :ensure t
  :custom
  (doom-themes-enable-bold t)
  (doom-themes-enable-italic t)
  :config
  (kittymacs-load-theme kittymacs-theme))
(use-package doom-modeline
  :ensure t
  :custom
  (doom-modeline-height 28)
  (doom-modeline-project-detection 'project)
  (doom-modeline-buffer-file-name-style 'truncate-upto-project)
  (doom-modeline-icon (kittymacs-icons-available-p))
  (doom-modeline-major-mode-icon t)
  (doom-modeline-buffer-state-icon t)
  :config
  (doom-modeline-mode 1))

(use-package hide-mode-line
  :ensure t
  :commands hide-mode-line-mode)

(defun kittymacs--tab-bar-faces (&rest _)
  "Give the tab bar a compact, mode-line-like look."
  (set-face-attribute 'tab-bar nil :inherit 'default :box nil)
  (set-face-attribute 'tab-bar-tab nil :inherit 'mode-line :weight 'bold :box nil)
  (set-face-attribute 'tab-bar-tab-inactive nil :inherit 'mode-line-inactive :weight 'normal :box nil))

(with-eval-after-load 'tab-bar
  (setopt tab-bar-show 1)
  (kittymacs--tab-bar-faces)
  (add-hook 'enable-theme-functions #'kittymacs--tab-bar-faces))
(use-package nerd-icons-completion
  :ensure t
  :after marginalia
  :config
  (when (kittymacs-icons-available-p)
    (nerd-icons-completion-mode 1)
    (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup)))

(use-package nerd-icons-corfu
  :ensure t
  :after corfu
  :config
  (when (kittymacs-icons-available-p)
    (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter)))

(defun kittymacs--maybe-dired-icons ()
  "Enable Dired icons when their font is usable."
  (when (kittymacs-icons-available-p)
    (nerd-icons-dired-mode 1)))

(use-package nerd-icons-dired
  :ensure t
  :commands nerd-icons-dired-mode
  :hook (dired-mode . kittymacs--maybe-dired-icons))
(use-package spacious-padding
  :ensure t
  :custom
  (spacious-padding-widths '(:internal-border-width 8
                             :header-line-width 2
                             :mode-line-width 4
                             :tab-width 2
                             :right-divider-width 1
                             :scroll-bar-width 0
                             :fringe-width 6))
  :config
  (spacious-padding-mode 1))

(setopt x-underline-at-descent-line t
        cursor-in-non-selected-windows nil
        widget-image-enable nil
        pulse-delay 0.08)

(use-package dimmer
  :ensure t
  :custom
  (dimmer-fraction 0.3)
  (dimmer-adjustment-mode :foreground)
  (dimmer-watch-frame-focus-events nil)
  (dimmer-prevent-dimming-predicates '(window-minibuffer-p))
  :config
  (dimmer-configure-which-key)
  (dimmer-configure-magit)
  (dimmer-configure-posframe)
  (add-to-list 'dimmer-buffer-exclusion-regexps "^ \\*Vertico\\*$")
  (dimmer-mode 1))

(defun kittymacs--pulse-line (&rest _)
  "Briefly highlight the current line."
  (pulse-momentary-highlight-one-line (point)))
(dolist (command '(scroll-up-command scroll-down-command recenter-top-bottom))
  (advice-add command :after #'kittymacs--pulse-line))
;; Every change of window, by `other-window', a mouse click or a leader key.
(add-hook 'window-selection-change-functions #'kittymacs--pulse-line)

(use-package hl-todo
  :ensure t
  :hook ((prog-mode markdown-mode) . hl-todo-mode))

(use-package highlight-numbers
  :ensure t
  :hook (prog-mode . highlight-numbers-mode))

(use-package goggles
  :ensure t
  :hook ((prog-mode text-mode) . goggles-mode)
  :custom
  (goggles-pulse t))

(use-package outline-minor-faces
  :ensure t
  :hook ((emacs-lisp-mode lisp-interaction-mode lisp-mode) . outline-minor-faces-mode))
(use-package writeroom-mode
  :ensure t
  :commands writeroom-mode)
(defun kittymacs--programming-presentation ()
  "Visual aids for programming buffers."
  (when kittymacs-line-numbers-in-programming
    (setq-local display-line-numbers-type t)
    (display-line-numbers-mode 1))
  (hl-line-mode 1))
(add-hook 'prog-mode-hook #'kittymacs--programming-presentation)

(provide 'kittymacs-ui)
;;; kittymacs-ui.el ends here
