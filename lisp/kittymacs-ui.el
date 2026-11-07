;;; kittymacs-ui.el --- Fonts, theme, mode line and icons -*- lexical-binding: t; -*-
;; Generated from literate/50-appearance.org; edit the Org source, then tangle.

;; Highlighting defaults distilled from Lambda-Emacs by Colin McLear (GPL-3.0-or-later).

;;; Code:

(require 'seq)
(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(defgroup kittymacs-ui nil
  "Fonts, theme and presentation."
  :group 'kittymacs)

(defcustom kittymacs-font-family "GoogleSansCode Nerd Font"
  "Preferred editing font family; the platform default is used if it is absent."
  :type 'string)

(defcustom kittymacs-font-size 14
  "Default editing font size, in points."
  :type 'natnum)

(defcustom kittymacs-prose-font-family "Google Sans Flex"
  "Proportional font for prose; the platform's sans is used if it is absent."
  :type 'string)

(defcustom kittymacs-nerd-font "Symbols Nerd Font Mono"
  "Font family used for Nerd Font icons."
  :type 'string)

(defcustom kittymacs-icons 'auto
  "Whether to render Nerd Font icons.
With `auto', require a graphical frame and an installed icon font.
Use t for a terminal configured with a Nerd Font, or nil to disable icons."
  :type '(choice (const auto) (const t) (const nil)))

(defcustom kittymacs-theme 'doom-sonokai
  "The dark theme.
A `doom-' theme needs the `doom-look' feature; without it, `modus-vivendi'."
  :type 'symbol)

(defcustom kittymacs-light-theme 'doom-one-light
  "The theme `kittymacs-toggle-theme' switches to.
A `doom-' theme needs the `doom-look' feature; without it, `modus-operandi'."
  :type 'symbol)

(defcustom kittymacs-line-numbers-in-programming t
  "Whether programming buffers show line numbers."
  :type 'boolean)
(defun kittymacs-resolve-font-family ()
  "Return the installed family for `kittymacs-font-family', or nil."
  (when (display-graphic-p)
    (seq-find (lambda (family) (find-font (font-spec :family family)))
              (if (equal kittymacs-font-family "GoogleSansCode Nerd Font")
                  (list kittymacs-font-family "GoogleSansCode NF" "Google Sans Code")
                (list kittymacs-font-family)))))

(defun kittymacs-resolve-prose-font-family ()
  "Return `kittymacs-prose-font-family' if it is installed, or nil."
  (when (and (display-graphic-p)
             (find-font (font-spec :family kittymacs-prose-font-family)))
    kittymacs-prose-font-family))

(defun kittymacs-icons-available-p ()
  "Return non-nil when Nerd Font icons should be rendered."
  (and (kittymacs-feature-p 'icons)
       (pcase kittymacs-icons
         ('t t)
         ('nil nil)
         ('auto (and (display-graphic-p)
                     (find-font (font-spec :family kittymacs-nerd-font))
                     t)))))

(defun kittymacs--apply-icon-font (&optional frame)
  "Map Nerd icon ranges to `kittymacs-nerd-font' in graphical FRAME."
  (with-selected-frame (or frame (selected-frame))
    (when (kittymacs-icons-available-p)
      (nerd-icons-set-font kittymacs-nerd-font (selected-frame)))))

(defun kittymacs--apply-font (&optional frame)
  "Apply the editing, prose, symbol and icon fonts to FRAME."
  (with-selected-frame (or frame (selected-frame))
    (when (display-graphic-p)
      (when-let* ((family (kittymacs-resolve-font-family)))
        (set-face-attribute 'default (selected-frame) :family family)
        (set-face-attribute 'fixed-pitch (selected-frame) :family family))
      (when-let* ((prose (kittymacs-resolve-prose-font-family)))
        (set-face-attribute 'variable-pitch (selected-frame) :family prose))
      (set-face-attribute 'default (selected-frame) :height (* 10 kittymacs-font-size))
      (when-let* ((symbols (seq-find (lambda (family) (find-font (font-spec :family family)))
                                     '("Segoe UI Symbol" "Symbola" "Apple Symbols" "Symbol"))))
        (set-fontset-font t 'symbol symbols nil))
      (kittymacs--apply-icon-font))))

(setopt line-spacing 0.1
        text-scale-mode-step 1.08)

(when (kittymacs-feature-p 'icons)
  (use-package nerd-icons
    :ensure t
    :demand t
    :custom
    (nerd-icons-font-family kittymacs-nerd-font)))

(add-hook 'after-setting-font-hook #'kittymacs--apply-icon-font)
(add-hook 'after-make-frame-functions #'kittymacs--apply-font)
(kittymacs--apply-font)
(setopt custom-safe-themes t)
(add-to-list 'custom-theme-load-path
             (expand-file-name "themes/" (file-name-directory (or load-file-name buffer-file-name))))

(defun kittymacs--theme-or-builtin (theme builtin)
  "Return THEME, or BUILTIN when THEME needs doom-themes and that is not loaded."
  (if (and (string-prefix-p "doom-" (symbol-name theme))
           (not (featurep 'doom-themes)))
      builtin
    theme))

(defun kittymacs--default-theme ()
  "Return the theme to use for `kittymacs-theme'."
  (kittymacs--theme-or-builtin kittymacs-theme 'modus-vivendi))

(defun kittymacs--other-theme ()
  "Return the theme to use for `kittymacs-light-theme'."
  (kittymacs--theme-or-builtin kittymacs-light-theme 'modus-operandi))

(defun kittymacs-load-theme (theme)
  "Disable active themes and load THEME."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t)
  (when (featurep 'doom-themes)
    (doom-themes-org-config)))

(defun kittymacs-toggle-theme ()
  "Toggle between `kittymacs-theme' and `kittymacs-light-theme'."
  (interactive)
  (kittymacs-load-theme (if (memq (kittymacs--default-theme) custom-enabled-themes)
                            (kittymacs--other-theme)
                          (kittymacs--default-theme))))

(keymap-set kittymacs-toggle-map "t" (cons "light/dark theme" #'kittymacs-toggle-theme))
(keymap-set kittymacs-toggle-map "T" (cons "choose theme" #'load-theme))

(when (kittymacs-feature-p 'doom-look)
  (use-package doom-themes
    :ensure t
    :custom
    (doom-themes-enable-bold t)
    (doom-themes-enable-italic t)))

(condition-case-unless-debug err
    (kittymacs-load-theme (kittymacs--default-theme))
  (error
   (display-warning 'kittymacs
                    (format "Theme %s did not load: %s"
                            (kittymacs--default-theme) (error-message-string err))
                    :error)))
;; The remote chapter's, which loads later than this one.
(declare-function kittymacs-remote-buffer-p "kittymacs-remote" (&rest _))

(defvar envrc-lighter)
(unless (or (kittymacs-feature-p 'doom-look) mode-line-collapse-minor-modes)
  (setq mode-line-collapse-minor-modes
        '(not meow-normal-mode meow-insert-mode meow-motion-mode meow-keypad-mode
              meow-beacon-mode overwrite-mode defining-kbd-macro flymake-mode envrc-mode)
        ;; `defcustom' keeps this when envrc loads.
        envrc-lighter '(:eval (unless (eq envrc--status 'none) (envrc--lighter)))))

(when (kittymacs-feature-p 'doom-look)
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
    (doom-modeline-mode 1)
    (with-eval-after-load 'doom-modeline-env
      (dolist (update '(doom-modeline-update-env
                        doom-modeline-env-update-python doom-modeline-env-update-ruby
                        doom-modeline-env-update-perl doom-modeline-env-update-go
                        doom-modeline-env-update-elixir doom-modeline-env-update-rust))
        (advice-add update :before-until #'kittymacs-remote-buffer-p)))))

(when (kittymacs-feature-p 'focus-mode)
  (use-package hide-mode-line
    :ensure t
    :commands hide-mode-line-mode)

  (keymap-set kittymacs-toggle-map "H" (cons "hide mode line" #'hide-mode-line-mode)))

(defun kittymacs--tab-bar-faces (&rest _)
  "Give the tab bar a compact, mode-line-like look."
  (set-face-attribute 'tab-bar nil :inherit 'default :box nil)
  (set-face-attribute 'tab-bar-tab nil :inherit 'mode-line :weight 'bold :box nil)
  (set-face-attribute 'tab-bar-tab-inactive nil :inherit 'mode-line-inactive :weight 'normal :box nil))

(with-eval-after-load 'tab-bar
  (setopt tab-bar-show 1)
  (kittymacs--tab-bar-faces)
  (add-hook 'enable-theme-functions #'kittymacs--tab-bar-faces))
(when (kittymacs-feature-p 'icons)
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
      (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))))

(defun kittymacs--maybe-dired-icons ()
  "Enable Dired icons when their font is usable."
  (when (kittymacs-icons-available-p)
    (nerd-icons-dired-mode 1)))

(when (kittymacs-feature-p 'icons)
  (use-package nerd-icons-dired
    :ensure t
    :commands nerd-icons-dired-mode
    :hook (dired-mode . kittymacs--maybe-dired-icons)))
(when (kittymacs-feature-p 'ui-polish)
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
    (spacious-padding-mode 1)))

(setopt x-underline-at-descent-line t
        cursor-in-non-selected-windows nil
        widget-image-enable nil
        pulse-delay 0.08)

(defun kittymacs--pulse-line (&rest _)
  "Briefly highlight the current line."
  (pulse-momentary-highlight-one-line (point)))
(dolist (command '(scroll-up-command scroll-down-command recenter-top-bottom))
  (advice-add command :after #'kittymacs--pulse-line))
;; Every change of window, by `other-window', a mouse click or a leader key.
(add-hook 'window-selection-change-functions #'kittymacs--pulse-line)

(defconst kittymacs-pulse-jump-commands
  '(avy-goto-char-timer avy-goto-line avy-goto-word-1 avy-goto-symbol-1
    avy-goto-end-of-line avy-goto-char-in-line
    consult-line consult-line-multi consult-goto-line consult-imenu consult-outline
    consult-mark consult-global-mark consult-ripgrep consult-flymake consult-org-heading
    pop-to-mark-command pop-global-mark)
  "The commands after which `kittymacs-pulse-jumps-mode' pulses the line.")

(define-minor-mode kittymacs-pulse-jumps-mode
  "Pulse the current line after a jump, so you can see where it landed."
  :global t
  :group 'kittymacs-ui
  (dolist (command kittymacs-pulse-jump-commands)
    (if kittymacs-pulse-jumps-mode
        (advice-add command :after #'kittymacs--pulse-line)
      (advice-remove command #'kittymacs--pulse-line)))
  (if kittymacs-pulse-jumps-mode
      (add-hook 'next-error-hook #'kittymacs--pulse-line)
    (remove-hook 'next-error-hook #'kittymacs--pulse-line)))

(when (kittymacs-feature-p 'ui-polish)
  (kittymacs-pulse-jumps-mode 1)
  (keymap-set kittymacs-toggle-map "j" (cons "pulse after jumps" #'kittymacs-pulse-jumps-mode))

  (use-package hl-todo
    :ensure t
    :hook ((prog-mode markdown-mode markdown-ts-mode) . hl-todo-mode))

  (keymap-set kittymacs-search-map "t" (cons "todo keywords" #'hl-todo-occur))

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
    :hook ((emacs-lisp-mode lisp-interaction-mode lisp-mode) . outline-minor-faces-mode)))
(when (kittymacs-feature-p 'focus-mode)
  (use-package writeroom-mode
    :ensure t
    :commands writeroom-mode)

  (keymap-set kittymacs-toggle-map "w" (cons "writeroom" #'writeroom-mode)))
(defconst kittymacs--scratch-pointer ";; SPC opens the menu.  SPC C o chooses features."
  "The line that tells a new reader where the menu is.")

(unless (or (kittymacs-feature-p 'home-page)
            initial-scratch-message
            (file-exists-p kittymacs-scratch-file))
  (setq initial-scratch-message (concat kittymacs--scratch-pointer "\n\n")))

(defun kittymacs--scratch-pointer-word-p (start _end _corrections)
  "Return non-nil when the word at START is on the pointer's line in *scratch*.
A function on `flyspell-incorrect-hook': non-nil leaves the word unmarked."
  (and (equal (buffer-name) "*scratch*")
       (save-excursion
         (goto-char start)
         (equal (buffer-substring-no-properties (pos-bol) (pos-eol))
                kittymacs--scratch-pointer))))
(add-hook 'flyspell-incorrect-hook #'kittymacs--scratch-pointer-word-p)
(defun kittymacs--programming-presentation ()
  "Visual aids for programming buffers."
  (when kittymacs-line-numbers-in-programming
    (setq-local display-line-numbers-type t)
    (display-line-numbers-mode 1))
  (hl-line-mode 1))
(add-hook 'prog-mode-hook #'kittymacs--programming-presentation)

(provide 'kittymacs-ui)
;;; kittymacs-ui.el ends here
