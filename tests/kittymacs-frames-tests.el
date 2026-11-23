;;; kittymacs-frames-tests.el --- Frame policy integration checks -*- lexical-binding: t; -*-
;; Load after ordinary graphical startup, then run selector "^kittymacs-frames-".
(require 'ert)
(require 'cl-lib)

(defmacro kittymacs-frames-test-with-buffer (&rest body)
  "Run BODY with an isolated BUFFER and clean up only its new frames."
  (declare (indent 0) (debug t))
  `(let ((original (selected-frame))
         (before (frame-list))
         (buffer (generate-new-buffer " *kittymacs-frames-test*")))
     (unwind-protect
         (save-window-excursion (delete-other-windows) ,@body)
       (select-frame original)
       (dolist (frame (seq-difference (frame-list) before))
         (when (frame-live-p frame) (delete-frame frame t)))
       (when (buffer-live-p buffer) (kill-buffer buffer)))))

(ert-deftest kittymacs-frames-auxiliary-display-and-quit ()
  "Ordinary auxiliary buffers get an OS frame that quit-window closes."
  (skip-unless (display-graphic-p))
  (kittymacs-frames-test-with-buffer
    (with-current-buffer buffer (help-mode))
    (let* ((window (display-buffer buffer))
           (frame (window-frame window)))
      (should-not (eq frame original))
      (should (= (length (window-list original 'no-minibuf)) 1))
      (quit-window nil window)
      (should-not (frame-live-p frame)))))

(ert-deftest kittymacs-frames-completion-stays-in-editor ()
  "The existing Vertico panel stays inside its initiating frame."
  (skip-unless (display-graphic-p))
  (kittymacs-frames-test-with-buffer
    (let ((window (display-buffer buffer vertico-buffer-display-action)))
      (should (eq (window-frame window) original))
      (should (eq (window-parameter window 'window-side) 'top))
      (delete-window window))))

(ert-deftest kittymacs-frames-magit-lazy-load-and-toggle ()
  "Lazy Magit loading must not reintroduce splits; disabling restores them."
  (skip-unless (display-graphic-p))
  (require 'magit)
  (kittymacs-frames-test-with-buffer
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

(ert-deftest kittymacs-frames-magit-status-quit ()
  "Quitting a real Magit status frame leaves the original editor alive."
  (skip-unless (display-graphic-p))
  (require 'magit)
  (kittymacs-frames-test-with-buffer
    (magit-status (expand-file-name "../" (file-name-directory (locate-library "kittymacs-frames"))))
    (let ((frame (selected-frame)))
      (should-not (eq frame original))
      (should (derived-mode-p 'magit-status-mode))
      (magit-mode-bury-buffer)
      (should-not (frame-live-p frame))
      (should (frame-live-p original)))))
(ert-deftest kittymacs-frames-split-command-remaps ()
  "Both ordinary split keys and the leader's split keys create OS frames."
  (skip-unless (display-graphic-p))
  (kittymacs-frames-test-with-buffer
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


(ert-deftest kittymacs-frames-org-noter-reuses-only-local-notes-windows ()
  "Notes visible elsewhere must not suppress the document's notes pane."
  (skip-unless (and (display-graphic-p)
                    (fboundp 'kittymacs-reading--noter-local-notes-window)
                    (locate-library "org-noter")))
  (require 'org-noter)
  (kittymacs-frames-test-with-buffer
    (let ((notes (generate-new-buffer " *kittymacs-noter-test-notes*")))
      (unwind-protect
          (progn
            (switch-to-buffer buffer)
            (let* ((foreign (make-frame '((name . "Kittymacs org-noter test"))))
                   (session (make-org-noter--session
                             :frame original
                             :doc-buffer buffer
                             :notes-buffer notes
                             :window-location 'horizontal-split
                             :window-behavior '(start scroll)
                             :doc-split-fraction '(0.5 . 0.5))))
              (set-window-buffer (frame-selected-window foreign) notes)
              (select-frame original)
              (with-current-buffer notes
                (setq-local org-noter--session session)
                (let ((window (org-noter--get-notes-window 'start)))
                  (should (window-live-p window))
                  (should (eq (window-frame window) original))
                  (should (eq (window-buffer window) notes))
                  (should (= (length (window-list original 'no-minibuf)) 2)))
                ;; A deliberate other-frame layout may still reuse that frame.
                (with-selected-frame original
                  (delete-other-windows)
                  (set-window-buffer (selected-window) buffer))
                (setf (org-noter--session-window-location session) 'other-frame)
                (should (eq (window-frame (org-noter--get-notes-window 'start))
                            foreign))
                ;; Disabling frames-only also restores upstream global reuse.
                (setf (org-noter--session-window-location session) 'horizontal-split)
                (let ((frames-only-mode nil))
                  (should (eq (window-frame (org-noter--get-notes-window 'start))
                              foreign))))))
        (when (buffer-live-p notes) (kill-buffer notes))))))

(provide 'kittymacs-frames-tests)
