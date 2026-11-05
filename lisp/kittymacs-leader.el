;;; kittymacs-leader.el --- A literal leader and localleaders for Meow -*- lexical-binding: t; -*-
;; Generated from literate/41-leader.org; edit the Org source, then tangle.

;;; Commentary:
;; SPC becomes an ordinary prefix keymap in Meow's Normal and Motion states,
;; and every major mode gets its own map under SPC m.  Everything is a native
;; keymap, so C-h k, C-h b, which-key and Marginalia see the real keys.

;;; Code:

(declare-function meow-normal-define-key "meow-helpers" (&rest keybinds))
(declare-function meow-motion-define-key "meow-helpers" (&rest keybinds))

(defcustom kittymacs-leader-key "SPC"
  "Key that opens `kittymacs-leader-map' in Meow's Normal and Motion states."
  :type 'key
  :group 'kittymacs)

(defcustom kittymacs-localleader-key "m"
  "Key below the leader that opens the current major mode's localleader map."
  :type 'key
  :group 'kittymacs)

(defcustom kittymacs-keypad-key nil
  "Optional key below the leader that starts Meow's keypad translation loop.
Nil leaves `meow-keypad' unbound; it stays available as a command."
  :type '(choice (const :tag "Unbound" nil) key)
  :group 'kittymacs)
(defvar kittymacs-leader-map (make-sparse-keymap)
  "The leader map, opened by `kittymacs-leader-key' in Normal and Motion states.
Add a command with `keymap-set'.  Add a labelled group with
  (keymap-set kittymacs-leader-map \"f\" (cons \"files\" my-file-map)).")
(defvar-keymap kittymacs-buffer-map :doc "Buffers.")
(defvar-keymap kittymacs-file-map :doc "Files.")
(defvar-keymap kittymacs-search-map :doc "Search.")
(defvar-keymap kittymacs-jump-map :doc "Jump with on-screen hints.")
(defvar-keymap kittymacs-project-map
  :doc "Project commands: Emacs's `project-prefix-map' plus a few more."
  :parent project-prefix-map)
(defvar-keymap kittymacs-vc-map :doc "Version control.")
(defvar-keymap kittymacs-window-map :doc "Windows and frames.")
(defvar-keymap kittymacs-workspace-map :doc "Workspaces (tabs with their own buffers).")
(defvar-keymap kittymacs-code-map :doc "Change code.")
(defvar-keymap kittymacs-eval-map :doc "Evaluate Lisp.")
(defvar-keymap kittymacs-lsp-map :doc "Language server and code intelligence.")
(defvar-keymap kittymacs-diagnostics-map :doc "Diagnostics (Flymake).")
(defvar-keymap kittymacs-insert-map :doc "Insert.")
(defvar-keymap kittymacs-notes-map :doc "Linked notes in the current graph.")
(defvar-keymap kittymacs-agent-map :doc "Coding agents (agent-shell), and a suggestion at point.")
(defvar-keymap kittymacs-open-map :doc "Open applications.")
(defvar-keymap kittymacs-toggle-map :doc "Toggles.")
(defvar-keymap kittymacs-config-map :doc "This configuration.")
(defvar-keymap kittymacs-quit-map :doc "Quit.")
(defvar-keymap kittymacs-help-map :doc "Help, documentation and tutorials.")
(defvar-keymap kittymacs-user-map :doc "Your own keys. Add them here or in private.el.")

(keymap-set kittymacs-leader-map "b" (cons "buffers" kittymacs-buffer-map))
(keymap-set kittymacs-leader-map "f" (cons "files" kittymacs-file-map))
(keymap-set kittymacs-leader-map "s" (cons "search" kittymacs-search-map))
(keymap-set kittymacs-leader-map "j" (cons "jump" kittymacs-jump-map))
(keymap-set kittymacs-leader-map "p" (cons "project" kittymacs-project-map))
(keymap-set kittymacs-leader-map "v" (cons "version control" kittymacs-vc-map))
(keymap-set kittymacs-leader-map "w" (cons "windows" kittymacs-window-map))
(keymap-set kittymacs-leader-map "W" (cons "workspaces" kittymacs-workspace-map))
(keymap-set kittymacs-leader-map "c" (cons "code" kittymacs-code-map))
(keymap-set kittymacs-leader-map "e" (cons "eval" kittymacs-eval-map))
(keymap-set kittymacs-leader-map "l" (cons "language server" kittymacs-lsp-map))
(keymap-set kittymacs-leader-map "F" (cons "diagnostics" kittymacs-diagnostics-map))
(keymap-set kittymacs-leader-map "i" (cons "insert" kittymacs-insert-map))
(keymap-set kittymacs-leader-map "n" (cons "notes" kittymacs-notes-map))
(keymap-set kittymacs-leader-map "a" (cons "agent" kittymacs-agent-map))
(keymap-set kittymacs-leader-map "o" (cons "open" kittymacs-open-map))
(keymap-set kittymacs-leader-map "t" (cons "toggle" kittymacs-toggle-map))
(keymap-set kittymacs-leader-map "C" (cons "config" kittymacs-config-map))
(keymap-set kittymacs-leader-map "q" (cons "quit" kittymacs-quit-map))
(keymap-set kittymacs-leader-map "h" (cons "help" kittymacs-help-map))
(keymap-set kittymacs-leader-map "u" (cons "user" kittymacs-user-map))
(defvar kittymacs-localleader-alist nil
  "Alist of (MAJOR-MODE . KEYMAP) localleader maps.
Maps compose along the mode's parents, most specific first, so a map for
`prog-mode' is inherited by every programming mode.")

(defvar-local kittymacs--localleader-alist nil
  "This buffer's emulation-map entry: its composed localleader under the leader.")

(defun kittymacs-localleader-map (&optional mode)
  "Return the composed localleader keymap for MODE, or nil if none applies.
MODE defaults to the current major mode."
  (let ((maps (delq nil (mapcar (lambda (parent)
                                  (alist-get parent kittymacs-localleader-alist))
                                (derived-mode-all-parents (or mode major-mode))))))
    (when maps (make-composed-keymap maps))))

(defun kittymacs--install-localleader ()
  "Point this buffer's emulation entry at its localleader, if it has one."
  (setq kittymacs--localleader-alist
        (when-let* ((local (kittymacs-localleader-map))
                    (wrapper (define-keymap
                               kittymacs-leader-key
                               (define-keymap kittymacs-localleader-key
                                 (cons "mode" local)))))
          `((meow-normal-mode . ,wrapper) (meow-motion-mode . ,wrapper)))))

(defun kittymacs-refresh-localleaders ()
  "Recompute the localleader of every live buffer."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer (kittymacs--install-localleader))))

(defun kittymacs-define-localleader (mode &rest definitions)
  "Give MODE a localleader built from DEFINITIONS and refresh live buffers.
DEFINITIONS are `define-keymap' arguments: KEY DEFINITION pairs, where a
definition may be (cons \"label\" COMMAND) to label it for which-key.
Calling this again for MODE replaces its map."
  (declare (indent 1))
  (setf (alist-get mode kittymacs-localleader-alist) (apply #'define-keymap definitions))
  (kittymacs-refresh-localleaders)
  mode)
(defun kittymacs-describe-leader ()
  "Describe the leader bindings, including this buffer's localleader."
  (interactive)
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map kittymacs-leader-map)
    (when-let* ((local (kittymacs-localleader-map)))
      (keymap-set map kittymacs-localleader-key (cons "mode" local)))
    (describe-keymap map)))

(defun kittymacs-leader-enable ()
  "Bind the leader in Meow's Normal and Motion states and start localleaders.
Safe to call more than once."
  (require 'meow)
  (meow-normal-define-key (cons kittymacs-leader-key kittymacs-leader-map))
  (meow-motion-define-key (cons kittymacs-leader-key kittymacs-leader-map))
  (when kittymacs-keypad-key
    (keymap-set kittymacs-leader-map kittymacs-keypad-key #'meow-keypad))
  (add-to-list 'emulation-mode-map-alists 'kittymacs--localleader-alist)
  (add-hook 'after-change-major-mode-hook #'kittymacs--install-localleader)
  (kittymacs-refresh-localleaders))

(provide 'kittymacs-leader)
;;; kittymacs-leader.el ends here
