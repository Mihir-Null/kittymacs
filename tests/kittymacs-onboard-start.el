;;; kittymacs-onboard-start.el --- What onboarding writes starts cleanly -*- lexical-binding: t; -*-
;; Run: KITTYMACS_TEST_PACKAGES=<dir> emacs -Q --batch -l tests/kittymacs-onboard-start.el
;; or `just test-onboard-start'.  <dir> holds every feature's packages:
;; KITTYMACS_TEST_PROFILE=every just install makes one.
;;
;; For each selection this answers the real screens with scripted keys, so the
;; real writer makes a private.el, then runs tests/verify-config.el on it, which
;; fails on any warning.  The verifier then asks `kittymacs-feature-p' about each
;; feature the answers named.  One start at a time, because each is a whole Emacs.
;;
;; `minimal' has nothing to exclude, since its features always stay on and the
;; writer leaves out an exclusion that changes nothing, so the selection that adds
;; and excludes at once starts from `full'.

;;; Code:
(require 'seq)

(load (expand-file-name "kittymacs-onboard-tests.el" (file-name-directory load-file-name)) nil t)

(defconst kittymacs-onboard-start-selections
  `(("minimal"
     ,(lambda () (kittymacs-onboard-test--keys ?m nil))
     ((meow . t) (completion . t) (jump . nil) (agents . nil) (lang-nix . nil)))
    ("minimal, adding two features"
     ,(lambda () (kittymacs-onboard-test--keys ?m '(jump surround)))
     ((meow . t) (jump . t) (surround . t) (agents . nil) (lang-nix . nil)))
    ("minimal, naming a backend"
     ,(lambda () (kittymacs-onboard-test--keys ?m nil nil nil kittymacs-onboard-test-build-keys))
     ((meow . t) (jump . nil)))
    ("full, adding one and excluding one"
     ,(lambda () (kittymacs-onboard-test--keys ?f '(color-names lang-nix) '(?n ?y ?N ?\r)))
     ((meow . t) (jump . t) (lang-nix . t) (color-names . nil))))
  "Each selection: its name, a function returning its keys, and what must be on.")

(defun kittymacs-onboard-start--one (selection)
  "Write a private.el for SELECTION and start the verifier on it.  Return non-nil on success."
  (pcase-let ((`(,name ,keys ,expected) selection))
    (kittymacs-onboard-test-with-machine
      (let ((result (kittymacs-onboard-test--run (funcall keys))))
        (unless (= 0 (car result))
          (error "%s: onboarding did not write: %s" name (cdr result))))
      (with-temp-buffer
        (let* ((process-environment
                (append (list (concat "KITTYMACS_TEST_PRIVATE=" private)
                              (format "KITTYMACS_TEST_EXPECT=%S" expected)
                              ;; The file says which profile; the variable would add a second say.
                              "KITTYMACS_TEST_PROFILE")
                        process-environment))
               (status (call-process
                        (expand-file-name invocation-name invocation-directory) nil t nil
                        "-Q" "--batch" "-l"
                        (kittymacs-onboard-test--path "tests/verify-config.el")))
               (output (buffer-string))
               (passed (and (eql status 0) (string-search "KITTYMACS-VERIFY PASS" output))))
          (princ (format "%s %s\n%s" (if passed "ok  " "FAIL") name
                         (kittymacs-onboard-test--file-string private)))
          (unless passed
            (princ (substring output (max 0 (- (length output) 2000)))))
          passed)))))

(let ((failures (seq-remove #'kittymacs-onboard-start--one kittymacs-onboard-start-selections)))
  (princ (format "\nKITTYMACS-ONBOARD-START %s: %d selections, %d failed\n"
                 (if failures "FAIL" "PASS")
                 (length kittymacs-onboard-start-selections) (length failures)))
  (kill-emacs (if failures 1 0)))

;;; kittymacs-onboard-start.el ends here
