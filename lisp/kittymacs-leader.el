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
