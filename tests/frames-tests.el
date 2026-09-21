;;; frames-tests.el --- Frame policy integration checks -*- lexical-binding: t; -*-
;; Load after ordinary graphical startup, then run selector "^dots-frames-".
(require 'ert)
(require 'cl-lib)

(defmacro dots-frames-with-buffer (&rest body)
  "Run BODY with an isolated BUFFER and clean up only its new frames."
  (declare (indent 0) (debug t))
  `(let ((original (selected-frame))
         (before (frame-list))
         (buffer (generate-new-buffer " *dots-frames-test*")))
     (unwind-protect
         (save-window-excursion (delete-other-windows) ,@body)
       (select-frame original)
       (dolist (frame (seq-difference (frame-list) before))
         (when (frame-live-p frame) (delete-frame frame t)))
       (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest dots-frames-auxiliary-display-and-quit ()
  "Ordinary auxiliary buffers get an OS frame that quit-window closes."
  (skip-unless (display-graphic-p))
  (dots-frames-with-buffer
    (with-current-buffer buffer (help-mode))
    (let* ((window (display-buffer buffer))
           (frame (window-frame window)))
      (should-not (eq frame original))
      (should (= (length (window-list original 'no-minibuf)) 1))
      (quit-window nil window)
      (should-not (frame-live-p frame)))))

(ert-deftest dots-frames-completion-stays-in-editor ()
  "The existing Vertico panel stays inside its initiating frame."
  (skip-unless (display-graphic-p))
  (dots-frames-with-buffer
    (let ((window (display-buffer buffer vertico-buffer-display-action)))
      (should (eq (window-frame window) original))
      (should (eq (window-parameter window 'window-side) 'top))
      (delete-window window))))

(ert-deftest dots-frames-magit-lazy-load-and-toggle ()
  "Lazy Magit loading must not reintroduce splits; disabling restores them."
  (skip-unless (display-graphic-p))
  (require 'magit)
  (dots-frames-with-buffer
    (let* ((window (funcall magit-display-buffer-function buffer))
           (frame (window-frame window)))
      (should-not (eq frame original))
      (should (eq window (funcall magit-display-buffer-function buffer)))
      (delete-frame frame t))
    (unwind-protect
        (progn
          (frames-only-mode -1)
          (should (boundp 'magit-bury-buffer-function))
          (should (boundp 'magit-commit-show-diff))
          (let ((window (funcall magit-display-buffer-function buffer)))
            (should (eq (window-frame window) original))
            (should (> (length (window-list original 'no-minibuf)) 1))))
      (delete-other-windows)
      (frames-only-mode 1))))

(ert-deftest dots-frames-magit-status-quit ()
  "Quitting a real Magit status frame leaves the original editor alive."
  (skip-unless (display-graphic-p))
  (require 'magit)
  (dots-frames-with-buffer
    (magit-status (expand-file-name "../" (file-name-directory (locate-library "kittymacs-frames"))))
    (let ((frame (selected-frame)))
      (should-not (eq frame original))
      (should (derived-mode-p 'magit-status-mode))
      (magit-mode-bury-buffer)
      (should-not (frame-live-p frame))
      (should (frame-live-p original)))))
(ert-deftest dots-frames-split-command-remaps ()
  "Both ordinary split keys and Lambda split-and-focus keys create OS frames."
  (skip-unless (display-graphic-p))
  (dots-frames-with-buffer
    (switch-to-buffer buffer)
    (dolist (key '("C-x 2" "C-x 3" "C-c C-SPC w h" "C-c C-SPC w v"))
      (select-frame original)
      (let ((existing (frame-list)))
        (call-interactively (key-binding (kbd key)))
        ;; Focus delivery belongs to the OS and may be asynchronous on Windows.
        (let ((created (seq-difference (frame-list) existing)))
          (should (= (length created) 1))
          (let ((frame (car created)))
            (should-not (frame-parameter frame 'parent-frame))
            (should-not (frame-parameter frame 'undecorated))
            (delete-frame frame t)))))))
(provide 'frames-tests)
