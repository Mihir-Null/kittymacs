;;; kittymacs-which-key-frame-tests.el --- which-key in a child frame, on any machine -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-which-key-frame-tests.el -f ert-run-tests-batch-and-exit
;; Needs no packages, and no display: stubs stand for the package's two functions
;; and for a graphical frame, and the tests read what each one was asked.
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "../lisp" (file-name-directory (or load-file-name buffer-file-name))))
(require 'kittymacs-catalogue)
(defvar use-package-ensure-function)
(setq use-package-ensure-function #'ignore)
(require 'use-package)
(require 'which-key)
(require 'kittymacs-features)

(defconst kittymacs-which-key-frame-test-before
  (mapcar (lambda (name) (cons name (symbol-value name)))
          '(which-key-popup-type
            which-key-custom-show-popup-function
            which-key-custom-hide-popup-function
            which-key-custom-popup-max-dimensions-function))
  "The settings before the mode first turned on.")

(require 'kittymacs-which-key-frame)

(defmacro kittymacs-which-key-frame-test-with (graphical &rest body)
  "Run BODY with a frame that is GRAPHICAL or not, recording calls in `calls'."
  (declare (indent 1))
  `(let ((calls nil)
         (which-key--buffer (get-buffer-create " *which-key-test*")))
     (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) ,graphical))
               ((symbol-function 'require)
                (lambda (feature &rest _) (push (list 'require feature) calls)))
               ((symbol-function 'which-key-posframe--show-buffer)
                (lambda (dimensions) (push (list 'frame dimensions) calls)))
               ((symbol-function 'which-key-posframe--hide)
                (lambda () (push 'frame-hide calls)))
               ((symbol-function 'which-key--show-buffer-side-window)
                (lambda (dimensions) (push (list 'side dimensions) calls)))
               ((symbol-function 'which-key--hide-buffer-side-window)
                (lambda () (push 'side-hide calls)))
               ((symbol-function 'which-key--side-window-max-dimensions)
                (lambda () '(side-height . side-width))))
       ,@body)))

(ert-deftest kittymacs-which-key-frame-the-catalogue-keeps-it-off-and-hidden ()
  (let ((entry (alist-get 'which-key-frame kittymacs-catalogue)))
    (should (eq (plist-get entry :hidden) t))
    (should (eq (plist-get entry :profile) 'optional))
    (should (eq (plist-get entry :group) 'look))
    (should (equal (plist-get entry :packages) '(which-key-posframe)))
    (should-not (memq 'which-key-frame (kittymacs-features--compute 'minimal nil nil)))
    (should-not (memq 'which-key-frame (kittymacs-features--compute 'full nil nil)))))

(ert-deftest kittymacs-which-key-frame-loading-it-loads-no-package ()
  (should-not (featurep 'which-key-posframe))
  (should-not (featurep 'posframe)))

(ert-deftest kittymacs-which-key-frame-a-graphical-frame-gets-the-child-frame ()
  (kittymacs-which-key-frame-test-with t
    (kittymacs-which-key-frame--show '(10 . 40))
    (should (equal (reverse calls) '((require which-key-posframe) (frame (10 . 40)))))
    (kill-buffer which-key--buffer)))

(ert-deftest kittymacs-which-key-frame-a-terminal-gets-the-side-window ()
  (kittymacs-which-key-frame-test-with nil
    (kittymacs-which-key-frame--show '(10 . 40))
    (should (equal calls '((side (10 . 40)))))
    (should (equal (kittymacs-which-key-frame--max-dimensions 80) '(side-height . side-width)))
    (setq calls nil)
    (kittymacs-which-key-frame--hide)
    (should (memq 'side-hide calls))
    (kill-buffer which-key--buffer)))

(ert-deftest kittymacs-which-key-frame-takes-the-height-the-side-window-would ()
  (kittymacs-which-key-frame-test-with t
    (cl-letf (((symbol-function 'frame-height) (lambda (&rest _) 40))
              ((symbol-function 'frame-width) (lambda (&rest _) 100)))
      (let ((which-key-side-window-max-height 0.5))
        (should (equal (kittymacs-which-key-frame--max-dimensions 80) '(20 . 100)))))
    (kill-buffer which-key--buffer)))

(ert-deftest kittymacs-which-key-frame-sits-above-the-mode-line-in-plain-pixels ()
  (should (equal (kittymacs-which-key-frame--position
                  '(:parent-frame-width 1000 :parent-frame-height 700 :posframe-width 400
                    :posframe-height 100 :mode-line-height 24 :minibuffer-height 24))
                 '(600 . 552)))
  ;; A menu wider or taller than the frame stays on it.
  (should (equal (kittymacs-which-key-frame--position
                  '(:parent-frame-width 300 :parent-frame-height 100 :posframe-width 400
                    :posframe-height 100 :mode-line-height 24 :minibuffer-height 24))
                 '(0 . 0))))

(ert-deftest kittymacs-which-key-frame-the-exact-fit-stays-as-the-keys-chapter-set-it ()
  "The side window's function is the only reader of this option, and it stays reached."
  (setq which-key-allow-imprecise-window-fit nil)
  (let ((source (with-temp-buffer
                  (insert-file-contents (locate-library "kittymacs-which-key-frame.el"))
                  (buffer-string))))
    (should-not (string-search "(setq which-key-allow-imprecise-window-fit" source))
    (should-not (string-search "(setopt which-key-allow-imprecise-window-fit" source)))
  (kittymacs-which-key-frame-test-with nil
    (kittymacs-which-key-frame--show '(3 . 3))
    (should (equal calls '((side (3 . 3)))))
    (kill-buffer which-key--buffer)))

(ert-deftest kittymacs-which-key-frame-turning-it-off-restores-every-setting ()
  (should (eq which-key-popup-type 'custom))
  (kittymacs-which-key-frame-mode -1)
  (unwind-protect
      (pcase-dolist (`(,name . ,value) kittymacs-which-key-frame-test-before)
        (should (equal (list name (symbol-value name)) (list name value))))
    (kittymacs-which-key-frame-mode 1))
  (should (eq which-key-popup-type 'custom))
  (should (eq which-key-custom-show-popup-function #'kittymacs-which-key-frame--show)))

(ert-deftest kittymacs-which-key-frame-turning-it-on-twice-keeps-what-it-saved ()
  (kittymacs-which-key-frame-mode 1)
  (kittymacs-which-key-frame-mode -1)
  (unwind-protect
      (should (equal which-key-popup-type
                     (alist-get 'which-key-popup-type kittymacs-which-key-frame-test-before)))
    (kittymacs-which-key-frame-mode 1)))

(ert-deftest kittymacs-which-key-frame-has-its-toggle ()
  (should (eq (keymap-lookup kittymacs-toggle-map "W") 'kittymacs-which-key-frame-mode)))

;;; kittymacs-which-key-frame-tests.el ends here
