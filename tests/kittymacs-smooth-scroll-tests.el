;;; kittymacs-smooth-scroll-tests.el --- Smooth scrolling, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-smooth-scroll-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages, and no display: stubs stand for `ultra-scroll-mode', the
;; interpolation and a graphical frame, and the tests read what each one was asked.
(require 'ert)
(require 'cl-lib)
(require 'mwheel)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(defvar kittymacs-features-excluded nil)
(require 'kittymacs-catalogue)
(defvar use-package-ensure-function)
(setq use-package-ensure-function #'ignore)

;; What the module calls in the chapters that load before it.
(defvar kittymacs-smooth-scroll-test-pulses 0)
(defun kittymacs--pulse-line (&rest _) (cl-incf kittymacs-smooth-scroll-test-pulses))
(defun kittymacs-remote-buffer-p (&rest _) (file-remote-p default-directory))
(defvar ultra-scroll-mode nil)
(defvar meow-normal-mode)
(defvar kittymacs-smooth-scroll-test-ultra nil)
(defun ultra-scroll-mode (&optional arg)
  (push arg kittymacs-smooth-scroll-test-ultra)
  (setq ultra-scroll-mode (and arg (> arg 0))))

(require 'use-package)
(require 'kittymacs-features)
(require 'kittymacs-smooth-scroll)

(defmacro kittymacs-smooth-scroll-test-graphical (&rest body)
  "Run BODY with every frame graphical, recording the animation in `animated'."
  (declare (indent 0))
  `(let (animated)
     (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t))
               ((symbol-function 'default-line-height) (lambda () 20))
               ((symbol-function 'window-text-height) (lambda (&rest _) 800))
               ((symbol-function 'pixel-scroll-precision-interpolate)
                (lambda (pixels &rest _) (push pixels animated))))
       ,@body)))

(defmacro kittymacs-smooth-scroll-test-plain-commands (&rest body)
  "Run BODY recording what the plain scrolling commands were asked, in `plain'."
  (declare (indent 0))
  `(let (plain)
     (cl-letf (((symbol-function 'scroll-up-command) (lambda (&optional n) (push (cons 'up n) plain)))
               ((symbol-function 'scroll-down-command) (lambda (&optional n) (push (cons 'down n) plain))))
       ,@body)))

(ert-deftest kittymacs-smooth-scroll-full-has-it-and-minimal-does-not ()
  (let ((entry (alist-get 'smooth-scroll kittymacs-catalogue)))
    (should (eq (plist-get entry :profile) 'full))
    (should (eq (plist-get entry :group) 'look))
    (should (equal (plist-get entry :packages) '(ultra-scroll)))
    (should-not (memq 'smooth-scroll (kittymacs-features--compute 'minimal nil nil)))
    (should (memq 'smooth-scroll (kittymacs-features--compute 'full nil nil)))
    (should-not (memq 'smooth-scroll (kittymacs-features--compute 'full nil '(smooth-scroll))))
    (should (memq 'smooth-scroll (kittymacs-features--compute 'minimal '(smooth-scroll) nil)))))

(ert-deftest kittymacs-smooth-scroll-a-terminal-keeps-plain-scrolling ()
  ;; Batch has only a terminal frame.
  (should (kittymacs-smooth-scroll--plain-p))
  (kittymacs-smooth-scroll-test-plain-commands
    (let ((kittymacs-smooth-scroll-test-pulses 0))
      (cl-letf (((symbol-function 'pixel-scroll-precision-interpolate)
                 (lambda (&rest _) (error "Animated in a terminal"))))
        (kittymacs-smooth-scroll-page-down)
        (kittymacs-smooth-scroll-page-up)
        (kittymacs-smooth-scroll-half-page-down))
      (should (equal (mapcar #'car (reverse plain)) '(up down up))))))

(ert-deftest kittymacs-smooth-scroll-no-graphical-frame-loads-nothing ()
  (let ((kittymacs-smooth-scroll-test-ultra nil)
        (ultra-scroll-mode nil))
    (kittymacs-smooth-scroll-mode -1)
    (kittymacs-smooth-scroll-mode 1)
    (should-not kittymacs-smooth-scroll-test-ultra)
    (should (memq #'kittymacs-smooth-scroll--apply after-make-frame-functions))))

(ert-deftest kittymacs-smooth-scroll-a-graphical-frame-turns-it-on-and-off ()
  (kittymacs-smooth-scroll-test-graphical
    (let ((kittymacs-smooth-scroll-test-ultra nil)
          (ultra-scroll-mode nil))
      (kittymacs-smooth-scroll-mode 1)
      (kittymacs-smooth-scroll--apply (selected-frame))
      (should (equal (car kittymacs-smooth-scroll-test-ultra) 1))
      (kittymacs-smooth-scroll-mode -1)
      (should (equal (car kittymacs-smooth-scroll-test-ultra) -1))
      (should-not (memq #'kittymacs-smooth-scroll--apply after-make-frame-functions))
      (kittymacs-smooth-scroll-mode 1))))

(ert-deftest kittymacs-smooth-scroll-a-page-moves-what-the-plain-command-moves ()
  (kittymacs-smooth-scroll-test-graphical
    (let ((kittymacs-smooth-scroll-test-pulses 0)
          (next-screen-context-lines 2))
      (kittymacs-smooth-scroll-page-down)
      (kittymacs-smooth-scroll-page-up)
      (kittymacs-smooth-scroll-half-page-down)
      (kittymacs-smooth-scroll-half-page-up)
      (should (equal (reverse animated) '(-760 760 -400 400)))
      (should (= kittymacs-smooth-scroll-test-pulses 4)))))

(ert-deftest kittymacs-smooth-scroll-the-end-of-the-buffer-is-no-error ()
  (kittymacs-smooth-scroll-test-graphical
    (cl-letf (((symbol-function 'pixel-scroll-precision-interpolate)
               (lambda (&rest _) (signal 'end-of-buffer nil))))
      (kittymacs-smooth-scroll-page-down))))

(ert-deftest kittymacs-smooth-scroll-a-prefix-counts-lines ()
  (kittymacs-smooth-scroll-test-graphical
    (kittymacs-smooth-scroll-test-plain-commands
      (kittymacs-smooth-scroll-page-down 3)
      (should (equal plain '((up . 3))))
      (should-not animated))))

(ert-deftest kittymacs-smooth-scroll-a-remote-buffer-keeps-plain-scrolling ()
  (kittymacs-smooth-scroll-test-graphical
    (kittymacs-smooth-scroll-test-plain-commands
      (with-temp-buffer
        (setq default-directory "/ssh:nobody@nowhere:/")
        (set-window-buffer (selected-window) (current-buffer))
        (should (kittymacs-smooth-scroll--plain-p))
        (kittymacs-smooth-scroll-page-down)
        (kittymacs-smooth-scroll-half-page-up)
        (should-not animated)
        (should (equal (mapcar #'car (reverse plain)) '(up down)))
        (setq default-directory "/tmp/")
        (should-not (kittymacs-smooth-scroll--plain-p))))))

(ert-deftest kittymacs-smooth-scroll-a-remote-window-under-the-wheel-stays-plain ()
  "The wheel goes by the window under the pointer, not the selected one."
  (kittymacs-smooth-scroll-test-graphical
    (let ((called nil))
      (with-temp-buffer
        (setq default-directory "/ssh:nobody@nowhere:/")
        (set-window-buffer (selected-window) (current-buffer))
        (cl-letf (((symbol-function 'mwheel-event-window) (lambda (_) (selected-window)))
                  ((symbol-function 'scroll-up) (lambda (n) (push (cons 'up n) called)))
                  ((symbol-function 'mwheel-scroll) (lambda (&rest _) (push 'mwheel called))))
          (let ((kittymacs-smooth-scroll--rest 0.0)
                (scroll (lambda (&rest _) (error "Smooth in a remote buffer"))))
            ;; Eight pixels add nothing, so nothing moves until a line is whole.
            (kittymacs-smooth-scroll--wheel scroll '(wheel-down nil 0 (nil 0.0 . -8.0) (0.0 . -8.0)))
            (should-not called)
            (kittymacs-smooth-scroll--wheel scroll '(wheel-down nil 0 (nil 0.0 . -36.0) (0.0 . -36.0)))
            (should (equal called '((up . 2))))
            (should (= kittymacs-smooth-scroll--rest -4.0))
            ;; A wheel with no pixel data is `mwheel-scroll''s.
            (setq called nil)
            (kittymacs-smooth-scroll--wheel scroll '(wheel-down nil))
            (should (equal called '(mwheel)))))))))

(ert-deftest kittymacs-smooth-scroll-a-local-graphical-window-goes-smooth ()
  (kittymacs-smooth-scroll-test-graphical
    (with-temp-buffer
      (setq default-directory "/tmp/")
      (set-window-buffer (selected-window) (current-buffer))
      (let (smooth)
        (cl-letf (((symbol-function 'mwheel-event-window) (lambda (_) (selected-frame))))
          (kittymacs-smooth-scroll--wheel (lambda (event _arg) (push event smooth)) '(wheel-down nil))
          (should (equal smooth '((wheel-down nil)))))))))

(ert-deftest kittymacs-smooth-scroll-the-half-page-keys-are-normal-state-only ()
  (let ((meow-normal-mode nil))
    (should-not (kittymacs-smooth-scroll--in-normal-state 'command))
    (should-not (eq (key-binding (kbd "C-d")) 'kittymacs-smooth-scroll-half-page-down))
    (should (eq (key-binding (kbd "C-d")) 'delete-char))
    (should (eq (key-binding (kbd "C-u")) 'universal-argument)))
  (let ((meow-normal-mode t))
    (should (eq (key-binding (kbd "C-d")) 'kittymacs-smooth-scroll-half-page-down))
    (should (eq (key-binding (kbd "C-u")) 'kittymacs-smooth-scroll-half-page-up))))

(ert-deftest kittymacs-smooth-scroll-keeps-the-page-keys-where-they-are ()
  (should (eq (key-binding (kbd "C-v") nil nil) 'kittymacs-smooth-scroll-page-down))
  (should (eq (key-binding (kbd "M-v") nil nil) 'kittymacs-smooth-scroll-page-up))
  (should (eq (key-binding (kbd "<next>")) 'kittymacs-smooth-scroll-page-down))
  (should (eq (command-remapping 'pixel-scroll-interpolate-up) 'kittymacs-smooth-scroll-page-up)))

(ert-deftest kittymacs-smooth-scroll-turning-it-off-leaves-the-keys-as-they-were ()
  (let ((meow-normal-mode t))
    (kittymacs-smooth-scroll-mode -1)
    (unwind-protect
        (progn
          (should (eq (key-binding (kbd "C-v")) 'scroll-up-command))
          (should (eq (key-binding (kbd "C-d")) 'delete-char))
          (should (eq (key-binding (kbd "C-u")) 'universal-argument)))
      (kittymacs-smooth-scroll-mode 1))))

(ert-deftest kittymacs-smooth-scroll-has-its-toggle ()
  (should (eq (keymap-lookup kittymacs-toggle-map "S") 'kittymacs-smooth-scroll-mode)))

;;; kittymacs-smooth-scroll-tests.el ends here
