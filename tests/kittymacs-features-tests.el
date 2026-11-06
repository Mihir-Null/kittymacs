;;; kittymacs-features-tests.el --- From the options to the features that are on -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-features-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages.  Nothing here starts the configuration: every gate in every
;; chapter asks this one module, so its rules are tested on their own.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst kittymacs-features-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(add-to-list 'load-path (expand-file-name "lisp" kittymacs-features-test-root))
(require 'kittymacs-features)

(defvar kittymacs-lisp-dir)
(defvar package-alist)
(defvar package-activated-list)
(defvar kittymacs-language-packages)
(defvar kittymacs-notebooks-jupyter)
(defvar kittymacs-exwm)
(defvar kittymacs-terminal-ghostel)

(defmacro kittymacs-features-test-with (settings warnings &rest body)
  "Run BODY with the options in SETTINGS, collecting warning texts in WARNINGS.
Nothing the older options set is bound, and no machine has run kittymacs yet."
  (declare (indent 2))
  `(let ((kittymacs-profile nil)
         (kittymacs-features nil)
         (kittymacs-features-excluded nil)
         (kittymacs-features--enabled 'unresolved)
         (kittymacs-features--profile nil)
         (package-alist nil)
         (package-activated-list nil)
         (system-type 'gnu/linux)
         (window-system nil)
         (,warnings nil))
     (let ,settings
       (cl-letf (((symbol-function 'display-warning)
                  (lambda (_type message &rest _) (push message ,warnings))))
         ,@body))))

(defun kittymacs-features-test--names (profile)
  "Return the catalogue's features whose `:profile' is PROFILE."
  (mapcar #'car (seq-filter (lambda (entry) (eq (plist-get (cdr entry) :profile) profile))
                            kittymacs-catalogue)))

(ert-deftest kittymacs-features-default-to-full ()
  "The default stays `full' until a later change moves it."
  (kittymacs-features-test-with () warnings
    (should (eq (kittymacs-features-profile) 'full))
    (should-not warnings)
    (should (kittymacs-feature-p 'jump))
    (should-not (kittymacs-feature-p 'jupyter))))

(ert-deftest kittymacs-features-minimal-turns-on-the-minimal-features-alone ()
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)) warnings
    (should (equal (kittymacs-features-enabled) (kittymacs-features-test--names 'minimal)))
    (should-not warnings)))

(ert-deftest kittymacs-features-full-leaves-out-what-the-catalogue-calls-optional ()
  (kittymacs-features-test-with ((kittymacs-profile 'full)) warnings
    (let ((enabled (kittymacs-features-enabled)))
      (dolist (feature (kittymacs-features-test--names 'minimal))
        (should (memq feature enabled)))
      (dolist (feature (kittymacs-features-test--names 'full))
        (unless (memq 'gnu/linux (kittymacs-features--property feature :not-on))
          (should (memq feature enabled))))
      (dolist (feature (kittymacs-features-test--names 'optional))
        (should-not (memq feature enabled))))
    (should-not warnings)))

(ert-deftest kittymacs-features-come-in-the-catalogue-order ()
  (kittymacs-features-test-with ((kittymacs-features '(window-manager jump lang-nix))) _warnings
    (let* ((enabled (kittymacs-features-enabled))
           (order (mapcar #'car kittymacs-catalogue)))
      (should (equal enabled (seq-filter (lambda (name) (memq name enabled)) order))))))

(ert-deftest kittymacs-features-selecting-a-feature-brings-what-it-needs ()
  "`file-tree' needs `icons', and `jupyter' needs `notebooks'."
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)
                                 (kittymacs-features '(file-tree jupyter)))
      warnings
    (dolist (feature '(file-tree icons version-control jupyter notebooks))
      (should (kittymacs-feature-p feature)))
    (should-not (kittymacs-feature-p 'jump))
    (should-not warnings)))

(ert-deftest kittymacs-features-excluding-a-feature-takes-what-needs-it-quietly ()
  (kittymacs-features-test-with ((kittymacs-features-excluded '(icons))) warnings
    (dolist (feature '(icons doom-look file-tree))
      (should-not (kittymacs-feature-p feature)))
    (should (kittymacs-feature-p 'jump))
    (should-not warnings)))

(ert-deftest kittymacs-features-dropping-follows-a-chain ()
  "A feature that lost its dependency takes its own dependents with it."
  (let ((kittymacs-catalogue '((a :profile full)
                               (b :profile full :deps (a))
                               (c :profile full :deps (b)))))
    (kittymacs-features-test-with ((kittymacs-features-excluded '(a))) warnings
      (should-not (kittymacs-features-enabled))
      (should-not warnings))))

(ert-deftest kittymacs-features-exclusion-beats-selection-and-says-so ()
  (kittymacs-features-test-with ((kittymacs-features '(jump))
                                 (kittymacs-features-excluded '(jump)))
      warnings
    (should-not (kittymacs-feature-p 'jump))
    (should (= (length warnings) 1))
    (should (string-match-p "jump is selected" (car warnings)))))

(ert-deftest kittymacs-features-a-selected-feature-that-lost-a-dependency-says-so ()
  (kittymacs-features-test-with ((kittymacs-features '(doom-look))
                                 (kittymacs-features-excluded '(icons)))
      warnings
    (should-not (kittymacs-feature-p 'doom-look))
    (should (= (length warnings) 1))
    (should (string-match-p "doom-look is selected" (car warnings)))))

(ert-deftest kittymacs-features-the-minimal-profile-cannot-be-excluded ()
  (kittymacs-features-test-with ((kittymacs-features-excluded '(meow))) warnings
    (should (kittymacs-feature-p 'meow))
    (should (= (length warnings) 1))
    (should (string-match-p "meow is part of the minimal profile" (car warnings)))))

(ert-deftest kittymacs-features-an-unknown-name-warns-and-the-rest-carry-on ()
  "A checkout and a host's settings drift apart; that must not end startup."
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)
                                 (kittymacs-features '(no-such-feature jump))
                                 (kittymacs-features-excluded '(no-other-feature)))
      warnings
    (should (kittymacs-feature-p 'jump))
    (should-not (kittymacs-feature-p 'no-such-feature))
    (should (= (length warnings) 2))
    (should (seq-some (lambda (w) (string-match-p "kittymacs-features names no-such-feature" w))
                      warnings))
    (should (seq-some (lambda (w) (string-match-p "excluded names no-other-feature" w))
                      warnings))))

(ert-deftest kittymacs-features-a-value-of-the-wrong-shape-warns ()
  (kittymacs-features-test-with ((kittymacs-features 'jump)
                                 (kittymacs-profile 'everything))
      warnings
    (should (eq (kittymacs-features-profile) 'full))
    (should (= (length warnings) 2))))

(ert-deftest kittymacs-features-not-on-rules-a-feature-out-without-a-warning ()
  "One private.el can serve several machines."
  (kittymacs-features-test-with ((system-type 'android)
                                 (kittymacs-features '(terminal window-manager)))
      warnings
    (should-not (kittymacs-feature-p 'terminal))
    (should-not (kittymacs-feature-p 'window-manager))
    (should-not warnings))
  (kittymacs-features-test-with ((system-type 'darwin)) warnings
    (should (kittymacs-feature-p 'terminal))
    (should-not warnings))
  (kittymacs-features-test-with ((system-type 'windows-nt)) _warnings
    (should-not (kittymacs-feature-p 'shell-path))))

;;; The options that came before the catalogue

(ert-deftest kittymacs-features-older-options-still-select ()
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)
                                 (kittymacs-language-packages '(nix guile))
                                 (kittymacs-notebooks-jupyter t))
      warnings
    (dolist (feature '(lang-nix lang-guile jupyter notebooks))
      (should (kittymacs-feature-p feature)))
    (should-not (kittymacs-feature-p 'lang-racket))
    (should-not warnings)))

(ert-deftest kittymacs-features-an-unsupported-language-is-left-to-its-option ()
  (kittymacs-features-test-with ((kittymacs-language-packages '(cobol))) warnings
    (should-not (kittymacs-feature-p 'lang-cobol))
    (should-not warnings)))

(ert-deftest kittymacs-features-exwm-follows-the-variable-on-x-alone ()
  "KITTYMACS_EXWM stays public: it installs the window manager when it asks for it."
  (let ((process-environment (cons "KITTYMACS_EXWM=1" process-environment)))
    (kittymacs-features-test-with ((window-system 'x)) warnings
      (should (kittymacs-feature-p 'window-manager))
      (should-not warnings))
    (kittymacs-features-test-with () _warnings
      (should-not (kittymacs-feature-p 'window-manager))))
  (let ((process-environment (cons "KITTYMACS_EXWM=0" process-environment)))
    (kittymacs-features-test-with ((window-system 'x)) _warnings
      (should-not (kittymacs-feature-p 'window-manager))))
  (kittymacs-features-test-with ((kittymacs-exwm t)) _warnings
    (should (kittymacs-feature-p 'window-manager))))

(ert-deftest kittymacs-features-the-terminal-option-works-both-ways ()
  (kittymacs-features-test-with ((kittymacs-terminal-ghostel nil)) warnings
    (should-not (kittymacs-feature-p 'terminal))
    (should-not warnings))
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)
                                 (kittymacs-terminal-ghostel t))
      warnings
    (should (kittymacs-feature-p 'terminal))
    (should-not warnings)))

;;; A machine with no choice

(ert-deftest kittymacs-features-a-machine-in-use-keeps-full-after-the-default-moves ()
  "The rule for the day the default becomes `minimal': nobody shrinks unannounced."
  (let ((kittymacs-default-profile 'minimal)
        (root (make-temp-file "kittymacs-features-" t)))
    (unwind-protect
        (let ((kittymacs-lisp-dir (file-name-as-directory root)))
          (kittymacs-features-test-with () warnings
            (should (eq (kittymacs-features-profile) 'minimal))
            (should-not warnings))
          (kittymacs-features-test-with ((package-alist '((meow)))) warnings
            (should (eq (kittymacs-features-profile) 'full))
            (should (= (length warnings) 1))
            (should (string-match-p "No profile is chosen" (car warnings))))
          ;; A start from the quickstart file activates packages and leaves the list empty.
          (kittymacs-features-test-with ((package-activated-list '(meow))) warnings
            (should (eq (kittymacs-features-profile) 'full))
            (should (= (length warnings) 1)))
          (with-temp-file (expand-file-name "private.el" root) (insert ";; Mine.\n"))
          (kittymacs-features-test-with () warnings
            (should (eq (kittymacs-features-profile) 'full))
            (should (= (length warnings) 1)))
          (kittymacs-features-test-with ((kittymacs-profile 'minimal)) warnings
            (should (eq (kittymacs-features-profile) 'minimal))
            (should-not warnings)))
      (delete-directory root t))))

(ert-deftest kittymacs-features-resolve-happens-once-unless-asked-again ()
  (kittymacs-features-test-with ((kittymacs-features '(no-such-feature))) warnings
    (kittymacs-feature-p 'jump)
    (kittymacs-feature-p 'jump)
    (should (= (length warnings) 1))
    (kittymacs-features-resolve)
    (should (= (length warnings) 2))))

;;; The installer

(defvar use-package-ensure-function nil)

(defmacro kittymacs-features-test-installing (installed attempts &rest body)
  "Run BODY as if only INSTALLED were installed, collecting requests in ATTEMPTS.
A request installs the package it names."
  (declare (indent 2))
  `(let* ((,attempts nil)
          (kittymacs-features--failed nil)
          (use-package-ensure-function
           (lambda (name args _state)
             (should (equal args '(t)))
             (push name ,attempts)
             (push name ,installed))))
     (cl-letf (((symbol-function 'package-installed-p)
                (lambda (package &rest _) (memq package ,installed))))
       ,@body)))

(ert-deftest kittymacs-features-installer-fetches-what-is-missing-and-nothing-else ()
  "A later opt-in installs on the next start, without a declaration's help."
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)
                                 (kittymacs-features '(jump)))
      warnings
    (let ((installed (copy-sequence (kittymacs-features-packages))))
      (setq installed (delq 'avy installed))
      (kittymacs-features-test-installing installed attempts
        (kittymacs-features-install)
        (should (equal attempts '(avy)))
        (should-not kittymacs-features--failed)))
    (should-not warnings)))

(ert-deftest kittymacs-features-installer-touches-nothing-when-all-is-there ()
  (kittymacs-features-test-with () _warnings
    (let ((installed (copy-sequence (kittymacs-features-packages))))
      (kittymacs-features-test-installing installed attempts
        (kittymacs-features-install)
        (should-not attempts)))))

(ert-deftest kittymacs-features-installer-leaves-out-features-that-are-off ()
  (kittymacs-features-test-with ((kittymacs-profile 'minimal)) _warnings
    (let ((packages (kittymacs-features-packages)))
      (should (memq 'meow packages))
      (should (memq 'magit packages))
      (dolist (package '(avy org-roam doom-themes nerd-icons exwm))
        (should-not (memq package packages))))))

(ert-deftest kittymacs-features-installer-leaves-git-packages-to-their-declarations ()
  "`:vc' packages install as they always have: from their chapters' declarations."
  (kittymacs-features-test-with ((kittymacs-features '(pdf-reading agents org-extras))) _warnings
    (let ((packages (kittymacs-features-packages)))
      (should (memq 'pdf-tools packages))
      (dolist (package '(pdf-text agent-shell-attention org-modern-indent))
        (should-not (memq package packages))))))

(ert-deftest kittymacs-features-installer-carries-on-past-a-failure ()
  (let ((debug-on-error nil))
    (kittymacs-features-test-with ((kittymacs-profile 'minimal)
                                   (kittymacs-features '(jump visual-replace)))
        warnings
      (let* ((kittymacs-features--failed nil)
             (missing (list 'avy 'visual-regexp))
             (attempts nil)
             (use-package-ensure-function
              (lambda (name &rest _)
                (push name attempts)
                (when (eq name 'avy) (error "Offline"))
                (setq missing (delq name missing)))))
        (cl-letf (((symbol-function 'package-installed-p)
                   (lambda (package &rest _) (not (memq package missing)))))
          (kittymacs-features-install)
          (should (equal (sort attempts #'string<) '(avy visual-regexp)))
          (should (equal kittymacs-features--failed '(avy)))
          (should (= (length warnings) 1))
          (should (string-match-p "Could not install avy: Offline" (car warnings))))))))

;;; kittymacs-features-tests.el ends here
