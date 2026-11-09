;;; kittymacs-exwm.el --- Emacs as the X window manager -*- lexical-binding: t; -*-
;; Generated from literate/44-exwm.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'kittymacs-features)

(defcustom kittymacs-exwm
  (kittymacs-exwm-session-p)
  "Whether this Emacs is the X session's window manager, through EXWM.
On when the program starting Emacs sets KITTYMACS_EXWM=1 and the first
frame is on X.  Frames-only mode is off by default while it is on."
  :type 'boolean
  :group 'kittymacs)
(defcustom kittymacs-wm-keys
  (append
   '(("H-h" focus-left) ("H-j" focus-down) ("H-k" focus-up) ("H-l" focus-right)
     ("H-H" move-column-left) ("H-J" move-window-down)
     ("H-K" move-window-up) ("H-L" move-column-right)
     ("H-[" move-window-left) ("H-]" move-window-right)
     ("H-<left>" workspace-prev) ("H-<right>" workspace-next)
     ("H-S-<left>" move-to-workspace-prev) ("H-S-<right>" move-to-workspace-next)
     ("H-w" close-window)
     ("H-f" toggle-floating) ("H-F" toggle-fullscreen)
     ("H-m" maximize-column)
     ("H-=" cycle-width-up) ("H--" cycle-width-down)
     ("H-+" cycle-height-up) ("H-_" cycle-height-down)
     ("H-0" equalize-widths) ("H-)" equalize-heights)
     ("H-SPC" toggle-overview)
     ("H-s" scratchpad-toggle) ("H-S" scratchpad-stash)
     ("H-t" toggle-tabbed)
     ("H-r" refresh) ("H-R" reload))
   ;; H-1 … H-9 switch workspace; H-! … H-( (Shift+1 … Shift+9) move there.
   (seq-map-indexed (lambda (key i) (list key 'move-to-workspace (1+ i)))
                    '("H-!" "H-@" "H-#" "H-$" "H-%" "H-^" "H-&" "H-*" "H-("))
   (mapcar (lambda (n) (list (format "H-%d" n) 'switch-workspace n))
           (number-sequence 1 9)))
  "The window manager's keys: a list of (KEY ACTION . ARGS).
KEY is in `kbd' notation; ACTION is a key of `kittymacs-exwm-actions'.
Press \\`H-R' after changing it."
  :type '(repeat (cons string (cons symbol (repeat sexp))))
  :group 'kittymacs)

(defcustom kittymacs-wm-width-presets '(0.25 0.33 0.5 0.667 0.75)
  "Widths the width cycle steps through, as fractions of the frame."
  :type '(repeat number)
  :group 'kittymacs)

(defcustom kittymacs-wm-height-presets '(0.333 0.5 0.667)
  "Heights the height cycle steps through, as fractions of the frame."
  :type '(repeat number)
  :group 'kittymacs)
(declare-function exwm-workspace-switch "exwm-workspace" (frame-or-index &optional force))
(declare-function exwm-workspace-switch-create "exwm-workspace" (frame-or-index))
(declare-function exwm-workspace-move-window "exwm-workspace" (frame-or-index &optional id))
(declare-function exwm-workspace-add "exwm-workspace" (&optional index))
(declare-function exwm-workspace--count "exwm-workspace" ())
(declare-function exwm-workspace-rename-buffer "exwm-workspace" (newname))
(declare-function exwm-floating-toggle-floating "exwm-floating" ())
(declare-function exwm-floating-hide "exwm-floating" ())
(declare-function exwm-layout-toggle-fullscreen "exwm-layout" (&optional id))
(declare-function exwm-reset "exwm" ())
(declare-function exwm-wm-mode "exwm" (&optional arg))
(declare-function exwm-randr-mode "exwm-randr" (&optional arg))
(defvar exwm-workspace-current-index)
(defvar exwm-input-global-keys)
(defvar exwm--floating-frame)
(defvar exwm-class-name)
(defvar exwm-title)

(defun kittymacs-exwm--workspace-index (n)
  "The index of workspace N, counted from 1, made if it does not exist yet."
  (while (>= (1- n) (exwm-workspace--count))
    (exwm-workspace-add))
  (1- n))

(defun kittymacs-exwm-switch-workspace (n)
  "Show workspace N, counted from 1 as the keys are."
  (exwm-workspace-switch-create (1- n)))

(defun kittymacs-exwm-move-to-workspace (n)
  "Move the focused X window to workspace N, counted from 1."
  (exwm-workspace-move-window (kittymacs-exwm--workspace-index n)))

(defun kittymacs-exwm--neighbour (step)
  "The index STEP workspaces away from this one, wrapping at the ends."
  (mod (+ exwm-workspace-current-index step) (exwm-workspace--count)))

(defun kittymacs-exwm-workspace-step (step)
  "Show the workspace STEP away from this one."
  (exwm-workspace-switch (kittymacs-exwm--neighbour step)))

(defun kittymacs-exwm-move-step (step)
  "Move the focused X window to the workspace STEP away."
  (exwm-workspace-move-window (kittymacs-exwm--neighbour step)))

(defun kittymacs-exwm-close ()
  "Close the focused thing.
An X window's buffer is killed, which asks its program to close it; then
the Emacs window goes too, unless it is the frame's last."
  (interactive)
  (let ((window (selected-window)))
    (when (derived-mode-p 'exwm-mode)
      (kill-current-buffer))
    (when (and (window-live-p window) (not (one-window-p)))
      (delete-window window))))

(defun kittymacs-exwm-maximize ()
  "Show only the selected window; pressed again, bring the others back."
  (interactive)
  (if-let* ((saved (frame-parameter nil 'kittymacs-exwm-maximized)))
      (progn (set-frame-parameter nil 'kittymacs-exwm-maximized nil)
             (set-window-configuration saved))
    (unless (one-window-p)
      (set-frame-parameter nil 'kittymacs-exwm-maximized
                           (current-window-configuration))
      (delete-other-windows))))

(defun kittymacs-exwm--cycle (presets step horizontal)
  "Resize the selected window to the preset STEP (1 or -1) away in PRESETS.
PRESETS are fractions of the frame, in increasing order; HORIZONTAL
means widths.  Past the last preset, the first comes round again."
  (let* ((total (window-total-size (frame-root-window) horizontal))
         (now (/ (float (window-total-size nil horizontal)) total))
         (next (if (> step 0)
                   (or (seq-find (lambda (p) (> p (+ now 0.01))) presets)
                       (car presets))
                 (or (seq-find (lambda (p) (< p (- now 0.01))) (reverse presets))
                     (car (last presets))))))
    (condition-case err
        (window-resize nil (- (round (* next total))
                              (window-total-size nil horizontal))
                       horizontal)
      (error (message "%s" (error-message-string err))))))

(defvar kittymacs-exwm--scratchpad nil
  "The X window's buffer last stashed with `scratchpad-stash'.")

(defun kittymacs-exwm-scratchpad-stash ()
  "Float the focused X window and hide it, to call back with `scratchpad-toggle'."
  (interactive)
  (unless (derived-mode-p 'exwm-mode)
    (user-error "Only an X window can be stashed"))
  (setq kittymacs-exwm--scratchpad (current-buffer))
  (unless exwm--floating-frame
    (exwm-floating-toggle-floating))
  (exwm-floating-hide))

(defun kittymacs-exwm-scratchpad-toggle ()
  "Show the stashed X window, or hide it again if it is showing."
  (interactive)
  (let* ((buffer kittymacs-exwm--scratchpad)
         (window (and (buffer-live-p buffer) (get-buffer-window buffer t))))
    (cond ((not (buffer-live-p buffer))
           (user-error "Nothing is stashed: the stash key stashes an X window"))
          (window (with-selected-window window (exwm-floating-hide)))
          (t (switch-to-buffer buffer)))))

(defcustom kittymacs-exwm-actions
  `((focus-left . windmove-left) (focus-down . windmove-down)
    (focus-up . windmove-up) (focus-right . windmove-right)
    (move-column-left . windmove-swap-states-left)
    (move-column-right . windmove-swap-states-right)
    (move-window-left . windmove-swap-states-left)
    (move-window-right . windmove-swap-states-right)
    (move-window-up . windmove-swap-states-up)
    (move-window-down . windmove-swap-states-down)
    (switch-workspace . kittymacs-exwm-switch-workspace)
    (move-to-workspace . kittymacs-exwm-move-to-workspace)
    (workspace-prev . ,(lambda () (interactive) (kittymacs-exwm-workspace-step -1)))
    (workspace-next . ,(lambda () (interactive) (kittymacs-exwm-workspace-step 1)))
    (move-to-workspace-prev . ,(lambda () (interactive) (kittymacs-exwm-move-step -1)))
    (move-to-workspace-next . ,(lambda () (interactive) (kittymacs-exwm-move-step 1)))
    (close-window . kittymacs-exwm-close)
    (toggle-floating . exwm-floating-toggle-floating)
    (toggle-fullscreen . exwm-layout-toggle-fullscreen)
    (maximize-column . kittymacs-exwm-maximize)
    (cycle-width-up
     . ,(lambda () (interactive) (kittymacs-exwm--cycle kittymacs-wm-width-presets 1 t)))
    (cycle-width-down
     . ,(lambda () (interactive) (kittymacs-exwm--cycle kittymacs-wm-width-presets -1 t)))
    (cycle-height-up
     . ,(lambda () (interactive) (kittymacs-exwm--cycle kittymacs-wm-height-presets 1 nil)))
    (cycle-height-down
     . ,(lambda () (interactive) (kittymacs-exwm--cycle kittymacs-wm-height-presets -1 nil)))
    (equalize-widths . balance-windows)
    (equalize-heights . balance-windows)
    (toggle-overview . exwm-workspace-switch)
    (scratchpad-stash . kittymacs-exwm-scratchpad-stash)
    (scratchpad-toggle . kittymacs-exwm-scratchpad-toggle)
    (toggle-tabbed . global-tab-line-mode)
    (refresh . exwm-reset)
    (reload . kittymacs-exwm-apply-keys))
  "What each action in `kittymacs-wm-keys' does under EXWM.
A command, or a function taking the key's ARGS."
  :type '(alist :key-type symbol :value-type function)
  :group 'kittymacs)
(defun kittymacs-exwm--command (action args)
  "The command for ACTION, called with ARGS."
  (let ((function (alist-get action kittymacs-exwm-actions)))
    (unless function
      (error "`kittymacs-wm-keys' names %s, which `kittymacs-exwm-actions' lacks"
             action))
    (if args
        (lambda () (interactive) (apply function args))
      function)))

(defun kittymacs-exwm-apply-keys ()
  "Bind `kittymacs-wm-keys' everywhere, in Emacs buffers and X windows."
  (interactive)
  (setopt exwm-input-global-keys
          (mapcar (lambda (entry)
                    (cons (kbd (car entry))
                          (kittymacs-exwm--command (cadr entry) (cddr entry))))
                  kittymacs-wm-keys)))
(defun kittymacs-exwm--keysyms-or-failure (keysyms)
  "Return KEYSYMS, or what `xcb:keysyms:event->keysyms' documents for a failure."
  (or keysyms '((0 . 0))))

;; `when' rather than `:if': `use-package' installs before it reads `:if', so
;; every machine would download a window manager it cannot use.
(when (and kittymacs-exwm (kittymacs-feature-p 'window-manager))
  (defun kittymacs-exwm--warn-without-xauth ()
    "Warn if xelb cannot find the X server's cookie, because there is no xauth."
    (unless (executable-find "xauth")
      (display-warning
       'kittymacs
       "No xauth on PATH, so EXWM connects to X with no cookie, and a server that asks for one refuses it.
  If EXWM does not start, install xauth where this Emacs's PATH finds it, then start the session again."
       :warning)))
  (use-package exwm
    :ensure t
    :demand t
    :custom
    (exwm-workspace-number 4)
    :config
    (advice-add 'xcb:keysyms:event->keysyms :filter-return
                #'kittymacs-exwm--keysyms-or-failure)
    (kittymacs-exwm-apply-keys)
    (add-hook 'exwm-update-class-hook
              (lambda () (exwm-workspace-rename-buffer exwm-class-name)))
    (add-hook 'exwm-update-title-hook
              (lambda ()
                (exwm-workspace-rename-buffer
                 (format "%s: %s" exwm-class-name exwm-title))))
    (require 'exwm-randr)
    (exwm-randr-mode 1)
    (kittymacs-exwm--warn-without-xauth)
    (exwm-wm-mode 1)))
(defvar meow-mode-state-list)
(with-eval-after-load 'meow
  (add-to-list 'meow-mode-state-list '(exwm-mode . insert)))

(provide 'kittymacs-exwm)
;;; kittymacs-exwm.el ends here
