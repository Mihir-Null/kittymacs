;;; kittymacs-buffer-tabs.el --- Grouped buffer tabs in each window -*- lexical-binding: t; -*-
;; Generated from literate/69-buffer-tabs.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'tab-line)
(require 'kittymacs-leader)

(declare-function tabspaces--local-buffer-p "tabspaces" (buffer))

(defconst kittymacs-buffer-tabs-groups
  '(("Tools" dired-mode magit-mode help-mode helpful-mode Info-mode compilation-mode special-mode)
    ("Terminal" eshell-mode shell-mode term-mode comint-mode ghostel-mode)
    ("Config" conf-mode)
    ("Docs" org-mode markdown-mode text-mode)
    ("Code" prog-mode))
  "Each group's name and its major modes; the first that fits wins.")

(defun kittymacs-buffer-tabs-group (&optional buffer)
  "Return the group of BUFFER, or of the current buffer."
  (let ((mode (buffer-local-value 'major-mode (or buffer (current-buffer)))))
    (or (car (seq-find (lambda (group) (provided-mode-derived-p mode (cdr group)))
                       kittymacs-buffer-tabs-groups))
        "Buffers")))

(defconst kittymacs-buffer-tabs--cycling
  '(tab-line-switch-to-next-tab tab-line-switch-to-prev-tab)
  "The commands that move along the tabs, during which the order stays.")

(defun kittymacs-buffer-tabs--fresh ()
  "Return the buffers that get a tab, starting from this window's own history."
  (seq-filter (lambda (buffer)
                (and (not (member (buffer-name buffer) '("*Messages*" "*Completions*")))
                     (or (not (bound-and-true-p tabspaces-mode))
                         (tabspaces--local-buffer-p buffer))))
              (tab-line-tabs-buffer-list)))

(defun kittymacs-buffer-tabs-list ()
  "Return this window's tabs, in the order they had if a tab move is under way."
  (let ((kept (window-parameter nil 'kittymacs-buffer-tabs-order)))
    (if (and kept (or (memq this-command kittymacs-buffer-tabs--cycling)
                      (and (null this-command)
                           (memq last-command kittymacs-buffer-tabs--cycling))))
        (seq-filter #'buffer-live-p kept)
      (set-window-parameter nil 'kittymacs-buffer-tabs-order (kittymacs-buffer-tabs--fresh)))))

(setopt tab-line-tabs-function #'tab-line-tabs-buffer-groups
        tab-line-tabs-buffer-list-function #'kittymacs-buffer-tabs-list
        tab-line-tabs-buffer-group-function #'kittymacs-buffer-tabs-group
        tab-line-tabs-buffer-group-sort-function nil
        tab-line-tabs-buffer-groups-sort-function nil
        tab-line-tab-name-function #'tab-line-tab-name-truncated-buffer
        tab-line-tab-name-truncated-max 24
        tab-line-close-button-show nil
        tab-line-new-button-show nil
        tab-line-exclude-modes (append '(dashboard-mode) tab-line-exclude-modes))
(keymap-set tab-line-mode-map "C-<tab>" #'tab-line-switch-to-next-tab)
(keymap-set tab-line-mode-map "C-S-<tab>" #'tab-line-switch-to-prev-tab)
(keymap-set tab-line-mode-map "C-<iso-lefttab>" #'tab-line-switch-to-prev-tab)
(keymap-set tab-line-mode-map "C-S-<iso-lefttab>" #'tab-line-switch-to-prev-tab)

(keymap-set kittymacs-toggle-map "b" (cons "buffer tabs" #'global-tab-line-mode))
(global-tab-line-mode 1)

(provide 'kittymacs-buffer-tabs)
;;; kittymacs-buffer-tabs.el ends here
