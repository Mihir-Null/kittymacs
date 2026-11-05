;;; kittymacs-onboard-tests.el --- Onboarding asks, writes and refuses as it says -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l tests/kittymacs-onboard-tests.el -f ert-run-tests-batch-and-exit
;;
;; Needs no packages.  Keys are scripted, by replacing the two functions that read
;; from the keyboard, except in the tests at the end, which drive a real terminal
;; through a pty.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst kittymacs-onboard-test-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(load (expand-file-name "lisp/kittymacs-onboard.el" kittymacs-onboard-test-root) nil t)

(defvar kittymacs-onboard-test-evaluated nil
  "Set by a form that onboarding must read and never run.")

(defun kittymacs-onboard-test--path (relative)
  "Return RELATIVE inside the repository."
  (expand-file-name relative kittymacs-onboard-test-root))

(defun kittymacs-onboard-test--file-string (file)
  "Return the bytes of FILE."
  (kittymacs-onboard--file-bytes file))

(defun kittymacs-onboard-test--write-bytes (file bytes)
  "Write the string BYTES to FILE as they are."
  (let ((coding-system-for-write 'no-conversion))
    (write-region bytes nil file nil 'silent)))

(defmacro kittymacs-onboard-test-with-machine (&rest body)
  "Run BODY on an empty machine: a temporary `private.el', host directory and store.
Inside, `root', `private' and `host' name them."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "kittymacs-onboard-" t)))
          (private (expand-file-name "lisp/private.el" root))
          (host (expand-file-name "conf.d/" root))
          (kittymacs-onboard-private-file private)
          (kittymacs-onboard-host-directories (list host))
          (kittymacs-onboard-store-directory (expand-file-name "no-store/" root))
          (kittymacs-default-profile 'full)
          (system-type 'gnu/linux))
     (ignore host)
     (make-directory (file-name-directory private) t)
     (unwind-protect (progn ,@body)
       (set-file-modes (file-name-directory private) #o755)
       (delete-directory root t))))

(defun kittymacs-onboard-test--group-keys (group toggled)
  "Return the keys that toggle the features in TOGGLED on the screen of GROUP."
  (let ((cursor 0) (index 0) keys)
    (dolist (feature (kittymacs-onboard--features-in group))
      (when (memq feature toggled)
        (dotimes (_ (- index cursor)) (push ?n keys))
        (setq cursor index)
        (push ?\s keys))
      (setq index (1+ index)))
    (nreverse (cons ?\r keys))))

(defun kittymacs-onboard-test--keys (profile toggled &optional structural options)
  "Return a whole flow: the key PROFILE, TOGGLED features, then STRUCTURAL and OPTIONS keys."
  (append (list profile)
          (seq-mapcat (lambda (group) (kittymacs-onboard-test--group-keys group toggled))
                      (kittymacs-onboard--groups))
          structural
          (or options '(?\r))
          '(?w)))

(defvar kittymacs-onboard-test-screens nil
  "The screens the last scripted run showed, newest first.")

(defun kittymacs-onboard-test--screen ()
  "Return the text on screen now."
  (with-current-buffer kittymacs-onboard--buffer-name
    (buffer-substring-no-properties (point-min) (point-max))))

(defun kittymacs-onboard-test--run (keys)
  "Run onboarding with the scripted KEYS, and return its status and text as a pair.
A string in KEYS answers a text prompt.  An event of the symbol `signal-quit'
quits as a minibuffer would."
  (setq kittymacs-onboard-test-screens nil)
  (let ((next (lambda ()
                (push (kittymacs-onboard-test--screen) kittymacs-onboard-test-screens)
                (unless keys (error "The script ran out of keys"))
                (let ((key (pop keys)))
                  (when (eq key 'signal-quit) (signal 'quit nil))
                  key))))
    (cl-letf (((symbol-function 'kittymacs-onboard--can-ask-p) (lambda () t))
              ((symbol-function 'kittymacs-onboard--read-event)
               (lambda (_prompt) (funcall next)))
              ((symbol-function 'kittymacs-onboard--read-text)
               (lambda (_prompt _initial) (funcall next))))
      (kittymacs-onboard--run))))

(defun kittymacs-onboard-test--forms (file)
  "Return the forms in FILE, read and never run."
  (mapcar #'car (kittymacs-onboard--read-forms
                 (kittymacs-onboard--text (kittymacs-onboard-test--file-string file)))))

(defun kittymacs-onboard-test--value (file option)
  "Return a list of the value form the last `setopt' of OPTION in FILE has."
  (let (value)
    (dolist (form (kittymacs-onboard-test--forms file))
      (when (and (eq (car-safe form) 'setopt) (eq (nth 1 form) option))
        (setq value (list (nth 2 form)))))
    value))

(defun kittymacs-onboard-test--files-in (directory)
  "Return what DIRECTORY holds."
  (directory-files directory nil directory-files-no-dot-files-regexp))

;;; The marked block

(ert-deftest kittymacs-onboard-new-file-has-the-cookie-and-a-block ()
  (kittymacs-onboard-test-with-machine
    (should (equal (car (kittymacs-onboard-test--run
                         (kittymacs-onboard-test--keys ?m nil)))
                   0))
    (let ((text (kittymacs-onboard-test--file-string private)))
      (should (string-match-p "\\`[^\n]*-\\*- lexical-binding: t; -\\*-" text))
      (should (string-search kittymacs-onboard--begin text))
      (should (string-search kittymacs-onboard--end text)))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-profile) '('minimal)))
    (should-not (file-exists-p (concat private "~")))))

(ert-deftest kittymacs-onboard-a-new-file-has-the-usual-mode ()
  (kittymacs-onboard-test-with-machine
    (let ((umask (default-file-modes)))
      (unwind-protect
          (progn
            (set-default-file-modes #o755)
            (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
            (should (= (file-modes private) #o644)))
        (set-default-file-modes umask)))))

(ert-deftest kittymacs-onboard-hand-edits-survive-byte-for-byte ()
  "Everything outside the block stays, including odd bytes, line endings and the mode."
  (kittymacs-onboard-test-with-machine
    (let* ((before (concat ";;; -*- lexical-binding: t; -*-\r\n"
                           ";; caf\xc3\xa9 and a raw byte \xff in a comment\n"
                           "(setq user-full-name \"Ada\")\n\n\n"))
           (after (concat "\n;; after the block, with no final newline\n"
                          "(setq user-mail-address \"a@example.com\")")))
      (kittymacs-onboard-test--write-bytes private before)
      (set-file-modes private #o640)
      (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
      ;; The first write appends.
      (let ((text (kittymacs-onboard-test--file-string private)))
        (should (string-prefix-p before text))
        (kittymacs-onboard-test--write-bytes private (concat text after)))
      ;; The second replaces the block and nothing else.
      (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?f '(jump)
                                                                 '(?N ?\r)))
      (let ((text (kittymacs-onboard-test--file-string private)))
        (should (string-prefix-p before text))
        (should (string-suffix-p after text))
        (should (string-search "(setopt kittymacs-profile 'full)" text))
        (should-not (string-search "(setopt kittymacs-profile 'minimal)" text)))
      (should (= (file-modes private) #o640))
      (should (= (file-modes (concat private "~")) #o640)))))

(ert-deftest kittymacs-onboard-a-file-with-no-final-newline-is-appended-to-safely ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes private "(setq user-full-name \"Ada\") ; no newline")
    (should (= 0 (car (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil)))))
    (should (equal (car (kittymacs-onboard-test--forms private))
                   '(setq user-full-name "Ada")))
    (should (string-prefix-p "(setq user-full-name \"Ada\") ; no newline\n"
                             (kittymacs-onboard-test--file-string private)))))

(ert-deftest kittymacs-onboard-keeps-a-backup-of-what-it-replaced ()
  (kittymacs-onboard-test-with-machine
    (let ((old ";;; -*- lexical-binding: t; -*-\n(setq a 1)\n"))
      (kittymacs-onboard-test--write-bytes private old)
      (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
      (should (equal (kittymacs-onboard-test--file-string (concat private "~")) old)))))

(ert-deftest kittymacs-onboard-the-same-answer-touches-nothing ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
    (let ((before (file-attribute-modification-time (file-attributes private))))
      (let ((result (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))))
        (should (= 0 (car result)))
        (should (string-search "nothing changed" (cdr result))))
      (should (equal before (file-attribute-modification-time (file-attributes private))))
      (should-not (file-exists-p (concat private "~"))))))

(ert-deftest kittymacs-onboard-the-proposed-text-must-read-back ()
  (kittymacs-onboard-test-with-machine
    ;; One prints as a name that reads as another symbol, one cannot read at all.
    (should-error (kittymacs-onboard--proposed
                   "(setq a 1)\n" (list (list 'setopt (make-symbol "uninterned") 1)) private)
                  :type 'kittymacs-onboard-refused)
    (with-temp-buffer
      (should-error (kittymacs-onboard--proposed
                     "(setq a 1)\n" (list (list 'setopt 'a (point-marker))) private)
                    :type 'kittymacs-onboard-refused))))

;;; Refusals

(defun kittymacs-onboard-test--refuses (text pattern)
  "Check that a `private.el' of TEXT is refused with PATTERN and stays as it was."
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes private text)
    (set-file-times private (seconds-to-time 1000000))
    (let ((result (kittymacs-onboard-test--run nil)))
      (should (= (car result) 1))
      (should (string-match-p pattern (cdr result))))
    (should (equal (kittymacs-onboard-test--file-string private) text))
    (should (time-equal-p (file-attribute-modification-time (file-attributes private))
                          (seconds-to-time 1000000)))
    (should (equal (kittymacs-onboard-test--files-in (file-name-directory private))
                   '("private.el")))))

(ert-deftest kittymacs-onboard-refuses-a-file-that-does-not-read ()
  (kittymacs-onboard-test--refuses ";;; -*- lexical-binding: t; -*-\n(setq a 1\n" "does not read as Lisp")
  (kittymacs-onboard-test--refuses "(setq a 1))\n" "does not read as Lisp"))

(ert-deftest kittymacs-onboard-refuses-markers-without-a-partner ()
  (kittymacs-onboard-test--refuses (concat kittymacs-onboard--begin "\n(setq a 1)\n")
                                   "without its partner")
  (kittymacs-onboard-test--refuses (concat "(setq a 1)\n" kittymacs-onboard--end "\n")
                                   "without its partner"))

(ert-deftest kittymacs-onboard-refuses-markers-that-appear-twice ()
  (let ((block (concat kittymacs-onboard--begin "\n" kittymacs-onboard--end "\n")))
    (kittymacs-onboard-test--refuses (concat block "(setq a 1)\n" block) "marker twice"))
  (kittymacs-onboard-test--refuses
   (concat kittymacs-onboard--begin "\n" kittymacs-onboard--begin "\n" kittymacs-onboard--end "\n")
   "marker twice"))

(ert-deftest kittymacs-onboard-refuses-markers-in-the-wrong-order ()
  (kittymacs-onboard-test--refuses
   (concat kittymacs-onboard--end "\n(setq a 1)\n" kittymacs-onboard--begin "\n")
   "wrong order"))

(ert-deftest kittymacs-onboard-refuses-a-block-inside-a-form-or-a-string ()
  (kittymacs-onboard-test--refuses
   (concat "(progn\n" kittymacs-onboard--begin "\n" kittymacs-onboard--end "\n)\n")
   "inside a form")
  (kittymacs-onboard-test--refuses
   (concat "(defvar a \"\n" kittymacs-onboard--begin "\n" kittymacs-onboard--end "\n\")\n")
   "inside a form"))

(ert-deftest kittymacs-onboard-refuses-a-read-only-file ()
  (skip-unless (not (zerop (user-uid))))
  (kittymacs-onboard-test-with-machine
    (let ((text "(setq a 1)\n"))
      (kittymacs-onboard-test--write-bytes private text)
      (set-file-modes private #o444)
      (let ((result (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))))
        (should (= (car result) 1))
        (should (string-search "not writable" (cdr result))))
      (should (equal (kittymacs-onboard-test--file-string private) text))
      (should (equal (kittymacs-onboard-test--files-in (file-name-directory private))
                     '("private.el"))))))

(ert-deftest kittymacs-onboard-refuses-a-read-only-directory ()
  "An atomic rename needs the directory, whatever the file's own mode says."
  (skip-unless (not (zerop (user-uid))))
  (kittymacs-onboard-test-with-machine
    (let ((text "(setq a 1)\n")
          (directory (file-name-directory private)))
      (kittymacs-onboard-test--write-bytes private text)
      (set-file-modes directory #o555)
      (let ((result (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))))
        (should (= (car result) 1))
        (should (string-search "not writable" (cdr result))))
      (should (equal (kittymacs-onboard-test--file-string private) text))
      (should (equal (kittymacs-onboard-test--files-in directory) '("private.el"))))))

(ert-deftest kittymacs-onboard-refuses-the-nix-store ()
  "A link into the store refuses even when the file's modes would let it be written."
  (kittymacs-onboard-test-with-machine
    (let* ((store (file-name-as-directory (expand-file-name "store/" root)))
           (kittymacs-onboard-store-directory store)
           (target (expand-file-name "abc-private.el" store))
           (text "(setq a 1)\n"))
      (make-directory store t)
      (kittymacs-onboard-test--write-bytes target text)
      (make-symbolic-link target private)
      (let ((result (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))))
        (should (= (car result) 1))
        (should (string-search "Nix store" (cdr result)))
        ;; It still walked to the end, whose Nix options are the useful answer there.
        (should (string-search "programs.kittymacs" (car kittymacs-onboard-test-screens))))
      (should (equal (kittymacs-onboard-test--file-string target) text))
      (should (file-symlink-p private)))))

;;; Links

(ert-deftest kittymacs-onboard-a-link-stays-a-link ()
  (kittymacs-onboard-test-with-machine
    (let* ((elsewhere (expand-file-name "dotfiles/" root))
           (target (expand-file-name "my-private.el" elsewhere))
           (text ";;; -*- lexical-binding: t; -*-\n(setq a 1)\n"))
      (make-directory elsewhere t)
      (kittymacs-onboard-test--write-bytes target text)
      (make-symbolic-link target private)
      (should (= 0 (car (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil)))))
      (should (file-symlink-p private))
      (should (equal (file-truename private) (file-truename target)))
      (should (string-prefix-p text (kittymacs-onboard-test--file-string target)))
      (should (string-search "(setopt kittymacs-profile 'minimal)"
                             (kittymacs-onboard-test--file-string target)))
      ;; The backup and any temporary file belong beside the real file.
      (should (equal (kittymacs-onboard-test--file-string (concat target "~")) text))
      (should-not (file-exists-p (concat private "~")))
      (should (equal (kittymacs-onboard-test--files-in (file-name-directory private))
                     '("private.el"))))))

(ert-deftest kittymacs-onboard-a-dangling-link-is-written-through ()
  (kittymacs-onboard-test-with-machine
    (let ((target (expand-file-name "not-yet.el" root)))
      (make-symbolic-link target private)
      (should (= 0 (car (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil)))))
      (should (file-symlink-p private))
      (should (file-exists-p target)))))

;;; Later settings

(ert-deftest kittymacs-onboard-reports-settings-after-the-block ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
    (let ((after (concat
                  ";; (setopt kittymacs-features-excluded '(in-a-comment))\n"
                  "(defvar my-text \"(setopt kittymacs-font-family \\\"in a string\\\")\")\n"
                  "(setopt kittymacs-features '(jump))\n"
                  "(when window-system (setq kittymacs-project-directory \"~/nested/\"))\n")))
      (kittymacs-onboard-test--write-bytes
       private (concat (kittymacs-onboard-test--file-string private) after))
      (let* ((result (kittymacs-onboard-test--run
                      (kittymacs-onboard-test--keys ?\r nil)))
             (preview (car kittymacs-onboard-test-screens)))
        (should (= 0 (car result)))
        (should (string-search "come after the block" preview))
        (should (string-match-p "private\\.el line [0-9]+: kittymacs-features$" preview))
        (should (string-match-p "private\\.el line [0-9]+: kittymacs-project-directory$" preview))
        (should-not (string-match-p "line [0-9]+: kittymacs-features-excluded" preview))
        (should-not (string-match-p "line [0-9]+: kittymacs-font-family" preview))
        ;; Reported in the result too, and left alone.
        (should (string-search "come after the block" (cdr result)))
        (should (string-suffix-p after (kittymacs-onboard-test--file-string private)))))))

(ert-deftest kittymacs-onboard-settings-before-the-block-are-not-reported-as-later ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes private "(setopt kittymacs-profile 'full)\n")
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
    (let ((preview (car kittymacs-onboard-test-screens)))
      (should-not (string-search "come after the block" preview))
      (should (string-search "come before the block" preview)))))

;;; Quitting

(ert-deftest kittymacs-onboard-c-g-at-any-stage-writes-nothing ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes private "(setq a 1)\n")
    (let* ((whole (kittymacs-onboard-test--keys ?f '(jump)
                                                '(?N ?\r)))
           (screens 0))
      (dotimes (stop (length whole))
        (let ((result (kittymacs-onboard-test--run
                       (append (seq-take whole stop) (list ?\C-g)))))
          (should (equal (car result) 2))
          (should (string-search "wrote nothing" (cdr result))))
        (setq screens (1+ screens))
        (should (equal (kittymacs-onboard-test--file-string private) "(setq a 1)\n"))
        (should (equal (kittymacs-onboard-test--files-in (file-name-directory private))
                       '("private.el"))))
      (should (> screens 10)))))

(ert-deftest kittymacs-onboard-quitting-a-prompt-writes-nothing ()
  (kittymacs-onboard-test-with-machine
    (let ((result (kittymacs-onboard-test--run
                   (append (list ?m)
                           (mapcar (lambda (_) ?\r) (kittymacs-onboard--groups))
                           '(?\s signal-quit)))))
      (should (equal (car result) 2))
      (should-not (file-exists-p private)))))

(ert-deftest kittymacs-onboard-without-a-terminal-says-what-to-set-by-hand ()
  (kittymacs-onboard-test-with-machine
    (with-temp-buffer
      (let* ((code (call-process (expand-file-name invocation-name invocation-directory)
                                 nil t nil "-Q" "--batch"
                                 "-l" (kittymacs-onboard-test--path "lisp/kittymacs-onboard.el")
                                 "-f" "kittymacs-onboard-main"))
             (output (buffer-string)))
        (should (= code 3))
        (should (string-search "(setopt kittymacs-profile" output))
        (should (string-search "next start" output))))))

(ert-deftest kittymacs-onboard-the-recipe-without-a-terminal-says-what-to-set-by-hand ()
  "Emacs refuses a dumb terminal before any Lisp runs, so the recipe has to look first."
  (skip-unless (executable-find "just"))
  (let ((default-directory kittymacs-onboard-test-root)
        (process-environment (cons "TERM=dumb" process-environment)))
    (with-temp-buffer
      (should (= 3 (call-process "just" nil t nil "onboard")))
      (should (string-search "(setopt kittymacs-profile" (buffer-string))))))

(ert-deftest kittymacs-onboard-term-in-a-started-emacs-does-not-stop-it ()
  "A started Emacs can hold TERM=dumb for its subprocesses, and draw perfectly well."
  (let ((noninteractive nil)
        (process-environment (cons "TERM=dumb" process-environment)))
    (should (kittymacs-onboard--can-ask-p))))

;;; One source of truth

(ert-deftest kittymacs-onboard-every-feature-is-on-a-screen-with-its-words ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (dolist (group (kittymacs-onboard--groups))
        (should (alist-get group kittymacs-onboard--group-titles))
        (let ((screen (kittymacs-onboard--render-features state group '(1 . 1) 0 nil)))
          (dolist (feature (kittymacs-onboard--features-in group))
            (should (string-search (format "%s" feature) screen))
            (should (string-search (kittymacs-onboard--plain
                                    (plist-get (alist-get feature kittymacs-catalogue) :summary))
                                   screen))
            (should (string-search (kittymacs-onboard--plain
                                    (plist-get (alist-get feature kittymacs-catalogue) :example))
                                   screen)))))
      (should (= (length kittymacs-catalogue)
                 (seq-reduce #'+ (mapcar (lambda (group)
                                           (length (kittymacs-onboard--features-in group)))
                                         (kittymacs-onboard--groups))
                             0))))))

(ert-deftest kittymacs-onboard-strips-only-the-markup ()
  (should (equal (kittymacs-onboard--plain "=SPC b b= switches, and =KITTYMACS_EXWM=1= runs (=x=).")
                 "SPC b b switches, and KITTYMACS_EXWM=1 runs (x).")))

(ert-deftest kittymacs-onboard-shows-why-a-feature-is-as-it-is ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (setf (kittymacs-onboard--profile state) 'minimal)
      (should (equal (kittymacs-onboard--status state 'meow) '("[=]" . "always on")))
      (should (equal (kittymacs-onboard--status state 'lang-nix)
                     '("[ ]" . "optional: off until you choose it")))
      (should (equal (kittymacs-onboard--status state 'jump) '("[ ]" . "")))
      (let ((system-type 'darwin))
        (should (equal (kittymacs-onboard--status state 'window-manager)
                       '("[-]" . "not available on this system"))))
      (kittymacs-onboard--toggle state 'file-tree)
      (should (equal (kittymacs-onboard--status state 'icons)
                     '("[x]" . "pulled in: file-tree needs it"))))))

(ert-deftest kittymacs-onboard-toggling-pulls-in-and-takes-away-what-deps-say ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (setf (kittymacs-onboard--profile state) 'minimal)
      (should (string-search "icons" (kittymacs-onboard--toggle state 'file-tree)))
      (should (memq 'icons (kittymacs-onboard--on state)))
      (should (equal (car (kittymacs-onboard--written-selection state)) '(file-tree)))
      ;; Off with a dependency: what needs it leaves as well, and warns about nothing.
      (should (string-search "file-tree" (kittymacs-onboard--toggle state 'icons)))
      (should-not (memq 'file-tree (kittymacs-onboard--on state)))
      (should-not (memq 'icons (kittymacs-onboard--on state)))
      (should (equal (kittymacs-onboard--written-selection state) '(nil)))
      (should (string-search "always on" (kittymacs-onboard--toggle state 'meow)))
      (should (memq 'meow (kittymacs-onboard--on state)))
      (let ((system-type 'darwin))
        (should (string-search "not available" (kittymacs-onboard--toggle state 'window-manager)))
        (should-not (memq 'window-manager (kittymacs-onboard--on state)))))))

(ert-deftest kittymacs-onboard-the-optional-profile-stays-off-until-chosen ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (setf (kittymacs-onboard--profile state) 'full)
      (should-not (memq 'lang-nix (kittymacs-onboard--on state)))
      (kittymacs-onboard--toggle state 'lang-nix)
      (should (memq 'lang-nix (kittymacs-onboard--on state)))
      (should (equal (car (kittymacs-onboard--written-selection state)) '(lang-nix))))))

(ert-deftest kittymacs-onboard-writes-only-the-differences-from-the-profile ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (setf (kittymacs-onboard--profile state) 'full)
      (kittymacs-onboard--toggle state 'jump)
      (kittymacs-onboard--toggle state 'lang-nix)
      (should (equal (kittymacs-onboard--written-selection state)
                     '((lang-nix) jump)))
      ;; A change of profile leaves nothing behind that no longer differs.
      (setf (kittymacs-onboard--profile state) 'minimal)
      (should (equal (kittymacs-onboard--written-selection state) '((lang-nix))))
      (kittymacs-onboard--toggle state 'jump)
      (setf (kittymacs-onboard--profile state) 'full)
      (should (equal (kittymacs-onboard--written-selection state) '((lang-nix)))))))

(ert-deftest kittymacs-onboard-what-it-writes-needs-no-warning-and-means-what-it-showed ()
  "Whatever the toggles, the options written give the same answer, and no warning."
  (kittymacs-onboard-test-with-machine
    (dolist (profile '(minimal full))
      (dolist (toggles '(() (jump) (file-tree icons) (icons file-tree)
                         (lang-nix jupyter) (agents suggestions) (meow) (window-manager)
                         (notebooks jupyter notebooks)))
        (let ((state (kittymacs-onboard--initial-state))
              warnings)
          (setf (kittymacs-onboard--profile state) profile)
          (dolist (feature toggles)
            (kittymacs-onboard--toggle state feature))
          (pcase-let ((`(,selected . ,excluded) (kittymacs-onboard--written-selection state)))
            (let ((kittymacs-profile profile)
                  (kittymacs-features selected)
                  (kittymacs-features-excluded excluded)
                  (kittymacs-features--enabled 'unresolved)
                  (kittymacs-features--profile nil))
              (cl-letf (((symbol-function 'display-warning)
                         (lambda (_type message &rest _) (push message warnings))))
                (should (equal (kittymacs-features-resolve)
                               (kittymacs-onboard--on state)))
                (should-not warnings)))))))))

(ert-deftest kittymacs-onboard-keeps-a-feature-this-system-cannot-see ()
  "One private.el can serve several machines."
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes
     private "(setopt kittymacs-profile 'minimal)\n(setopt kittymacs-features '(window-manager))\n")
    (let* ((system-type 'darwin)
           (state (kittymacs-onboard--initial-state)))
      (should (equal (car (kittymacs-onboard--written-selection state)) '(window-manager))))))

(ert-deftest kittymacs-onboard-an-unknown-name-is-named-and-left-out ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes
     private "(setopt kittymacs-features '(jump no-such-feature))\n")
    (let ((state (kittymacs-onboard--initial-state)))
      (should (equal (kittymacs-onboard--selected state) '(jump)))
      (should (seq-some (lambda (note) (string-search "no-such-feature" note))
                        (kittymacs-onboard--notes state))))))

(ert-deftest kittymacs-onboard-older-options-count-through-the-features-chapter ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes
     private (concat "(setopt kittymacs-profile 'minimal)\n"
                     "(setopt kittymacs-language-packages '(nix))\n"
                     "(setopt kittymacs-terminal-ghostel nil)\n"))
    (let ((state (kittymacs-onboard--initial-state)))
      (should (memq 'lang-nix (kittymacs-onboard--on state)))
      (should (equal (kittymacs-onboard--older-selected state) '(lang-nix)))
      (should (equal (kittymacs-onboard--older-excluded state) '(terminal)))
      (should (string-search "older option" (kittymacs-onboard--toggle state 'terminal)))
      (should-not (memq 'terminal (kittymacs-onboard--on state))))
    (should-not (boundp 'kittymacs-terminal-ghostel))))

(ert-deftest kittymacs-onboard-a-started-emacs-does-not-colour-the-answer ()
  "A started Emacs has its own values, which what is on disk must decide alone."
  (kittymacs-onboard-test-with-machine
    (cl-progv '(kittymacs-terminal-ghostel kittymacs-language-packages) '(t (nix))
      (let ((state (kittymacs-onboard--initial-state)))
        (should-not (kittymacs-onboard--older-selected state))
        (should-not (kittymacs-onboard--older-excluded state))))))

;;; Reading what the machine chose

(defconst kittymacs-onboard-test-nix-file
  ";;; 10-nix.el --- What programs.kittymacs chose -*- lexical-binding: t; -*-
;; Generated by the kittymacs Home Manager module; change its options instead.
(setopt kittymacs-profile 'minimal)
(setopt kittymacs-features '(jump lang-nix))
(setopt kittymacs-features-excluded '(meow-not-really))
(setopt kittymacs-font-family \"Iosevka\")
(setopt kittymacs-structural-editing-modes '(emacs-lisp-mode my-mode))
(setq kittymacs-onboard-test-evaluated t)
(error \"This file was run\")
"
  "What `nix/selection.nix' writes, and two forms that must never run.")

(ert-deftest kittymacs-onboard-preselects-what-the-nix-file-chose-without-running-it ()
  (kittymacs-onboard-test-with-machine
    (make-directory host t)
    (kittymacs-onboard-test--write-bytes (expand-file-name "10-nix.el" host)
                                         kittymacs-onboard-test-nix-file)
    (setq kittymacs-onboard-test-evaluated nil)
    (let ((state (kittymacs-onboard--initial-state)))
      (should-not kittymacs-onboard-test-evaluated)
      (should (eq (kittymacs-onboard--profile state) 'minimal))
      (should (equal (kittymacs-onboard--selected state) '(jump lang-nix)))
      ;; What a host chose shows as set there, and does not move to the block.
      (should-not (kittymacs-onboard--options state))
      (should (equal (kittymacs-onboard--option-shown state 'kittymacs-font-family)
                     "set in 10-nix.el"))
      (should (string-search "chosen in 10-nix.el"
                             (kittymacs-onboard--render-profile state '(1 . 1))))
      (should (member '("Emacs Lisp" . yes) (kittymacs-onboard--answers state)))
      (should (member '("Python" . no) (kittymacs-onboard--answers state)))
      (should (equal (kittymacs-onboard--extra-modes state) '(my-mode)))
      (should (member 'my-mode (kittymacs-onboard--chosen-modes state))))))

(ert-deftest kittymacs-onboard-private-el-wins-over-the-host-layer-as-at-startup ()
  (kittymacs-onboard-test-with-machine
    (make-directory host t)
    (kittymacs-onboard-test--write-bytes (expand-file-name "10-nix.el" host)
                                         "(setopt kittymacs-profile 'minimal)\n")
    (kittymacs-onboard-test--write-bytes private "(setopt kittymacs-profile 'full)\n")
    (should (eq (kittymacs-onboard--profile (kittymacs-onboard--initial-state)) 'full))))

(ert-deftest kittymacs-onboard-a-broken-host-file-is-named-and-skipped ()
  (kittymacs-onboard-test-with-machine
    (make-directory host t)
    (kittymacs-onboard-test--write-bytes (expand-file-name "20-broken.el" host) "(setq a")
    (let ((state (kittymacs-onboard--initial-state)))
      (should (seq-some (lambda (note) (string-search "20-broken.el" note))
                        (kittymacs-onboard--notes state))))))

(ert-deftest kittymacs-onboard-names-a-value-it-would-have-to-run ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--write-bytes
     private "(setopt kittymacs-features (append '(jump) my-list))\n")
    (let ((state (kittymacs-onboard--initial-state)))
      (should-not (kittymacs-onboard--selected state))
      (should (seq-some (lambda (note) (string-search "does not run" note))
                        (kittymacs-onboard--notes state))))))

(ert-deftest kittymacs-onboard-reads-the-shapes-people-and-nix-write ()
  (should (equal (kittymacs-onboard--literal ''minimal) '(minimal)))
  (should (equal (kittymacs-onboard--literal nil) '(nil)))
  (should (equal (kittymacs-onboard--literal t) '(t)))
  (should (equal (kittymacs-onboard--literal "a") '("a")))
  (should (equal (kittymacs-onboard--literal 3) '(3)))
  (should (equal (kittymacs-onboard--literal '(list "a" 'b)) '(("a" b))))
  (should (equal (kittymacs-onboard--literal '(expand-file-name "~/a/")) '("~/a/")))
  (should-not (kittymacs-onboard--literal 'a-variable))
  (should-not (kittymacs-onboard--literal '(list a-variable)))
  (should-not (kittymacs-onboard--literal '(expand-file-name a-variable)))
  (should-not (kittymacs-onboard--literal '(getenv "HOME"))))

(ert-deftest kittymacs-onboard-finds-settings-at-any-depth ()
  (should (equal (kittymacs-onboard--setters '(setopt a 1 b 2)) '((a 1 nil) (b 2 nil))))
  (should (equal (kittymacs-onboard--setters '(setq a 1)) '((a 1 nil))))
  (should (equal (kittymacs-onboard--setters '(customize-set-variable 'a 1)) '((a 1 nil))))
  (should (equal (kittymacs-onboard--setters '(when x (setopt a 1))) '((a 1 t))))
  (should (equal (kittymacs-onboard--setters
                  '(add-hook 'after-init-hook (lambda () (setopt a 1)) 90))
                 '((a 1 t))))
  (should-not (kittymacs-onboard--setters '(quote (setopt a 1))))
  (should-not (kittymacs-onboard--setters '(a . b))))

(ert-deftest kittymacs-onboard-host-directories-match-init ()
  "Under -Q the module holds its own copy of what `init.el' reads."
  (let* ((forms (kittymacs-onboard-test--forms (kittymacs-onboard-test--path "init.el")))
         (defvar-form (seq-find (lambda (form)
                                  (and (eq (car-safe form) 'defvar)
                                       (eq (nth 1 form) 'kittymacs-host-directories)))
                                forms)))
    (should defvar-form)
    (should (equal (eval (nth 2 defvar-form) t)
                   (let ((module (kittymacs-onboard-test--forms
                                  (kittymacs-onboard-test--path "lisp/kittymacs-onboard.el"))))
                     (eval (nth 3 (nth 2 (seq-find
                                          (lambda (form)
                                            (and (eq (car-safe form) 'defvar)
                                                 (eq (nth 1 form) 'kittymacs-onboard-host-directories)))
                                          module)))
                           t))))
    ;; The same file names, too.
    (with-temp-buffer
      (insert-file-contents (kittymacs-onboard-test--path "init.el"))
      (should (search-forward "\"\\\\`[^.#].*\\\\.el\\\\'\"" nil t)))))

;;; Options

(defun kittymacs-onboard-test--defcustoms ()
  "Return every `defcustom' in the modules' source, as an alist of its name and :type."
  (let (found)
    (cl-labels ((walk (form)
                  (when (consp form)
                    (when (eq (car form) 'defcustom)
                      (push (cons (nth 1 form) (plist-get (nthcdr 4 form) :type)) found))
                    (let ((tail form))
                      (while (consp tail)
                        (walk (car tail))
                        (setq tail (cdr tail)))))))
      (dolist (file (directory-files (kittymacs-onboard-test--path "lisp") t "\\`kittymacs-.*\\.el\\'"))
        (mapc #'walk (kittymacs-onboard-test--forms file))))
    found))

(ert-deftest kittymacs-onboard-options-are-real-and-the-example-offers-them ()
  (let ((defcustoms (kittymacs-onboard-test--defcustoms))
        (example (kittymacs-onboard-test--file-string
                  (kittymacs-onboard-test--path "lisp/private.example.el"))))
    (should (> (length defcustoms) 20))
    (should (<= (length kittymacs-onboard-options) 8))
    (pcase-dolist (`(,option . ,row) kittymacs-onboard-options)
      (should (assq option defcustoms))
      (should (equal (list option (alist-get option defcustoms))
                     (list option (list 'quote (plist-get row :type)))))
      (should (string-search (symbol-name option) example))
      (should (stringp (plist-get row :label)))
      (when-let* ((feature (plist-get row :feature)))
        (should (assq feature kittymacs-catalogue))))))

(ert-deftest kittymacs-onboard-the-selection-options-are-real ()
  (let ((defcustoms (kittymacs-onboard-test--defcustoms)))
    (dolist (option (cons 'kittymacs-structural-editing-modes
                          (append kittymacs-onboard--selection-options
                                  kittymacs-onboard--older-options)))
      (should (or (assq option defcustoms)
                  (eq option 'kittymacs-exwm))))))

(ert-deftest kittymacs-onboard-sets-an-option-and-writes-it ()
  (kittymacs-onboard-test-with-machine
    (let ((result (kittymacs-onboard-test--run
                   (kittymacs-onboard-test--keys
                    ?m nil nil
                    '(?\s "~/src" ?n ?\s "/abs/org/" ?\r)))))
      (should (= 0 (car result))))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-project-directory)
                   '((expand-file-name "~/src/"))))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-org-directory)
                   '("/abs/org/")))
    ;; The next run starts from the block, and d takes one out again.
    (should (= 0 (car (kittymacs-onboard-test--run
                       (kittymacs-onboard-test--keys ?m nil nil '(?d ?\r))))))
    (should-not (kittymacs-onboard-test--value private 'kittymacs-project-directory))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-org-directory)
                   '("/abs/org/")))))

(ert-deftest kittymacs-onboard-keeps-non-ascii-settings ()
  (kittymacs-onboard-test-with-machine
    (should (= 0 (car (kittymacs-onboard-test--run
                       (kittymacs-onboard-test--keys
                        ?m nil nil (list ?\s "/home/ada/Проекты" ?\r))))))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-project-directory)
                   '("/home/ada/Проекты/")))))

(ert-deftest kittymacs-onboard-asks-about-an-option-only-with-its-feature ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (setf (kittymacs-onboard--profile state) 'minimal)
      (should-not (assq 'kittymacs-org-roam-directory (kittymacs-onboard--options-here state)))
      (setf (kittymacs-onboard--profile state) 'full)
      (should (assq 'kittymacs-org-roam-directory (kittymacs-onboard--options-here state))))))

;;; Structural editing

(ert-deftest kittymacs-onboard-structural-editing-has-no-preselected-answer ()
  (kittymacs-onboard-test-with-machine
    (let ((state (kittymacs-onboard--initial-state)))
      (should (= (length (kittymacs-onboard--unanswered state))
                 (length kittymacs-onboard-structural-languages)))
      (let ((screen (kittymacs-onboard--render-structural state '(1 . 1) 0 nil)))
        (should-not (string-match-p "\\[[yn~]\\]" screen))
        (should (string-search "[?] Python" screen))
        (should (string-search "nothing here starts answered" screen))))))

(ert-deftest kittymacs-onboard-structural-editing-waits-for-every-answer ()
  (kittymacs-onboard-test-with-machine
    (let ((result (kittymacs-onboard-test--run
                   (append (list ?f)
                           (mapcar (lambda (_) ?\r) (kittymacs-onboard--groups))
                           (list ?\r ?\C-g)))))
      (should (= (car result) 2))
      (should (string-search "Still open" (car kittymacs-onboard-test-screens)))
      (should (string-search "Structural editing" (car kittymacs-onboard-test-screens))))))

(ert-deftest kittymacs-onboard-says-plainly-what-declining-means ()
  (kittymacs-onboard-test-with-machine
    (let ((screen (kittymacs-onboard--render-structural
                   (kittymacs-onboard--initial-state) '(1 . 1) 0 nil)))
      (should (string-search "No to a line" screen))
      (should (string-search "No to every line leaves Puni installed and on in no buffer" screen)))))

(ert-deftest kittymacs-onboard-writes-the-answers-by-language ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run
     (kittymacs-onboard-test--keys ?f nil '(?n ?y ?y ?N ?\r)))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-structural-editing-modes)
                   '('(emacs-lisp-mode lisp-mode scheme-mode))))))

(ert-deftest kittymacs-onboard-declining-every-language-writes-an-empty-list ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?f nil '(?N ?\r)))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-structural-editing-modes)
                   '(nil)))))

(ert-deftest kittymacs-onboard-every-programming-language-covers-the-code-rows ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?f nil '(?y ?N ?\r)))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-structural-editing-modes)
                   '('(prog-mode))))))

(ert-deftest kittymacs-onboard-no-screen-for-structural-editing-while-it-is-off ()
  (kittymacs-onboard-test-with-machine
    (should (= 0 (car (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil)))))
    (should-not (kittymacs-onboard-test--value private 'kittymacs-structural-editing-modes))
    (should-not (seq-some (lambda (screen) (string-search "Structural editing, by" screen))
                          kittymacs-onboard-test-screens))))

(ert-deftest kittymacs-onboard-an-answer-in-the-block-outlives-the-feature-going-off ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?f nil '(?n ?y ?N ?\r)))
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
    (should (equal (kittymacs-onboard-test--value private 'kittymacs-structural-editing-modes)
                   '('(emacs-lisp-mode))))))

(ert-deftest kittymacs-onboard-the-language-rows-name-what-exists ()
  "Every row can be attached to, and the option's default can be expressed."
  (let* ((known (seq-mapcat (lambda (row) (plist-get (cdr row) :modes))
                            kittymacs-onboard-structural-languages))
         (programming (kittymacs-onboard-test--forms
                       (kittymacs-onboard-test--path "lisp/kittymacs-programming.el")))
         (default (cadr (nth 2 (seq-find (lambda (form)
                                           (and (eq (car-safe form) 'defcustom)
                                                (eq (nth 1 form) 'kittymacs-structural-editing-modes)))
                                         programming)))))
    (should (> (length default) 3))
    (should-not (seq-difference default known))
    (mapc #'require '(python sh-script js c-ts-mode typescript-ts-mode cc-mode scheme tex-mode
                             org lisp-mode))
    (dolist (mode (seq-difference known '(markdown-mode markdown-ts-mode)))
      (should (equal (list mode t)
                     (list mode (and (or (fboundp mode)
                                         (boundp (intern (format "%s-hook" mode))))
                                     t)))))))

;;; The Nix options

(ert-deftest kittymacs-onboard-the-nix-options-use-the-real-names ()
  (kittymacs-onboard-test-with-machine
    (make-directory kittymacs-onboard-store-directory t)
    (let* ((state (kittymacs-onboard--initial-state))
           (selection (with-temp-buffer
                        (insert-file-contents (kittymacs-onboard-test--path "nix/selection.nix"))
                        (buffer-string)))
           (features (with-temp-buffer
                       (insert-file-contents (kittymacs-onboard-test--path "nix/features.json"))
                       (json-parse-buffer :object-type 'alist))))
      (setf (kittymacs-onboard--profile state) 'full)
      (kittymacs-onboard--toggle state 'lang-nix)
      (kittymacs-onboard--toggle state 'agents)
      (kittymacs-onboard--answer state (assoc "Emacs Lisp" kittymacs-onboard-structural-languages) 'yes)
      (setf (alist-get 'kittymacs-suggestions (kittymacs-onboard--options state)) t)
      (setf (alist-get 'kittymacs-font-family (kittymacs-onboard--options state)) "Iosevka")
      (setf (alist-get 'kittymacs-project-directory (kittymacs-onboard--options state)) "~/src/")
      (let ((text (kittymacs-onboard--nix-text state)))
        (should (string-search "profile = \"full\";" text))
        (should (string-search "features.lang-nix.enable = true;" text))
        (should (string-search "features.agents.enable = false;" text))
        (should (string-search "settings.kittymacs-suggestions = true;" text))
        (should (string-search "settings.kittymacs-font-family = \"Iosevka\";" text))
        (should (string-search
                 "settings.kittymacs-structural-editing-modes.elisp = \"'(emacs-lisp-mode)\";" text))
        (should (string-search
                 "settings.kittymacs-project-directory.elisp = \"(expand-file-name \\\"~/src/\\\")\";"
                 text))
        (should (string-search "private.el loads after the host layer" text)))
      ;; The module has the options that text names, and the features.
      (should (string-match-p "^ +profile = lib\\.mkOption" selection))
      (should (string-match-p "^ +features = lib\\.mapAttrs" selection))
      (should (string-match-p "^ +enable = lib\\.mkOption" selection))
      (should (string-match-p "^ +settings = lib\\.mkOption" selection))
      (should (string-search "value.elisp" selection))
      (dolist (entry kittymacs-catalogue)
        (should (assq (car entry) features))))))

(ert-deftest kittymacs-onboard-the-nix-options-print-on-a-nix-host-only ()
  (kittymacs-onboard-test-with-machine
    (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))
    (should-not (string-search "programs.kittymacs" (car kittymacs-onboard-test-screens)))
    (make-directory host t)
    (kittymacs-onboard-test--write-bytes (expand-file-name "10-nix.el" host)
                                         "(setopt kittymacs-profile 'minimal)\n")
    (let ((result (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))))
      (should (string-search "programs.kittymacs" (car kittymacs-onboard-test-screens)))
      (should (string-search "programs.kittymacs" (cdr result))))))

;;; Saying when it counts

(ert-deftest kittymacs-onboard-says-a-change-takes-effect-at-the-next-start ()
  (kittymacs-onboard-test-with-machine
    (let ((result (kittymacs-onboard-test--run (kittymacs-onboard-test--keys ?m nil))))
      (should (string-search "takes effect at the next start" (car kittymacs-onboard-test-screens)))
      (should (string-search "takes effect at the next start" (cdr result))))))

;;; How it is reached

(ert-deftest kittymacs-onboard-nothing-loads-the-module-at-startup ()
  (dolist (file (cons (kittymacs-onboard-test--path "init.el")
                      (directory-files (kittymacs-onboard-test--path "lisp") t "\\`kittymacs-.*\\.el\\'")))
    (unless (string-suffix-p "kittymacs-onboard.el" file)
      (with-temp-buffer
        (insert-file-contents file)
        (should (equal (list file nil)
                       (list file (search-forward "(require 'kittymacs-onboard" nil t)))))))
  (let ((forms (kittymacs-onboard-test--forms (kittymacs-onboard-test--path "lisp/kittymacs-literate.el"))))
    (should (seq-some (lambda (form)
                        (and (eq (car-safe form) 'autoload)
                             (equal (nth 1 form) ''kittymacs-onboard)))
                      forms))))

(ert-deftest kittymacs-onboard-the-command-leaves-emacs-running ()
  (kittymacs-onboard-test-with-machine
    (let ((keys (kittymacs-onboard-test--keys ?m nil)))
      (cl-letf (((symbol-function 'kittymacs-onboard--can-ask-p) (lambda () t))
                ((symbol-function 'kittymacs-onboard--read-event)
                 (lambda (_prompt) (pop keys)))
                ((symbol-function 'kill-emacs)
                 (lambda (&rest _) (error "The command must not end Emacs"))))
        (kittymacs-onboard)
        (should (file-exists-p private))
        (should (string-search "takes effect at the next start"
                               (kittymacs-onboard-test--screen)))))))

(ert-deftest kittymacs-onboard-just-has-the-recipe ()
  (with-temp-buffer
    (insert-file-contents (kittymacs-onboard-test--path "justfile"))
    (should (re-search-forward "^onboard:" nil t))
    (should (search-forward "emacs -nw -Q -l lisp/kittymacs-onboard.el -f kittymacs-onboard-main" nil t))
    (should (search-forward "emacs -Q --batch -l lisp/kittymacs-onboard.el -f kittymacs-onboard-main" nil t))))

;;; A real terminal

(defun kittymacs-onboard-test--pty (keys wait-for)
  "Run onboarding on a pty in a copy of the modules; send KEYS once WAIT-FOR shows.
Return its exit status, what it drew, and the directory it ran in, as a list."
  (let* ((root (file-name-as-directory (make-temp-file "kittymacs-onboard-pty-" t)))
         (lisp (expand-file-name "lisp/" root))
         (buffer (generate-new-buffer " *onboard pty*"))
         (lisp-source (kittymacs-onboard-test--path "lisp/"))
         (default-directory root)
         (process-environment
          (append (list "TERM=linux"
                        (concat "HOME=" root)
                        (concat "XDG_CONFIG_HOME=" root "config"))
                  process-environment)))
    (make-directory lisp)
    (dolist (file '("kittymacs-onboard.el" "kittymacs-catalogue.el" "kittymacs-features.el"))
      (copy-file (expand-file-name file lisp-source) (expand-file-name file lisp)))
    (let ((process (make-process
                    :name "onboard" :buffer buffer :noquery t :sentinel #'ignore
                    :connection-type 'pty
                    :command (list (expand-file-name invocation-name invocation-directory)
                                   "-nw" "-Q"
                                   "-l" (expand-file-name "kittymacs-onboard.el" lisp)
                                   "-f" "kittymacs-onboard-main")))
          (limit (+ (float-time) 60))
          sent)
      (set-process-window-size process 40 120)
      (while (and (process-live-p process) (< (float-time) limit))
        (accept-process-output process 0.1)
        (when (and (not sent)
                   (with-current-buffer buffer
                     (save-excursion (goto-char (point-min)) (search-forward wait-for nil t))))
          (setq sent t)
          (process-send-string process keys)))
      (when (process-live-p process)
        (delete-process process)
        (error "No exit in time; sent: %S; screen: %s" sent
               (with-current-buffer buffer (buffer-string))))
      (accept-process-output process 0.2)
      (list (process-exit-status process)
            (prog1 (with-current-buffer buffer (buffer-string)) (kill-buffer buffer))
            root))))

(ert-deftest kittymacs-onboard-a-real-terminal-writes-the-whole-flow ()
  (skip-unless (not (memq system-type '(windows-nt ms-dos))))
  (pcase-let* ((returns (make-string (length (kittymacs-onboard--groups)) ?\r))
               (`(,status ,screen ,root)
                (kittymacs-onboard-test--pty (concat "m" returns "\rw") "Where to start"))
               (file (expand-file-name "lisp/private.el" root)))
    (unwind-protect
        (progn
          (should (equal status 0))
          (should (file-exists-p file))
          (should (equal (kittymacs-onboard-test--value file 'kittymacs-profile) '('minimal)))
          (should (string-search "takes effect at the next start" screen)))
      (delete-directory root t))))

(ert-deftest kittymacs-onboard-c-g-in-a-real-terminal-writes-nothing ()
  (skip-unless (not (memq system-type '(windows-nt ms-dos))))
  (pcase-let ((`(,status ,screen ,root) (kittymacs-onboard-test--pty "\r\a" "Where to start")))
    (unwind-protect
        (progn
          (should (equal status 2))
          (should-not (file-exists-p (expand-file-name "lisp/private.el" root)))
          (should (string-search "wrote nothing" screen)))
      (delete-directory root t))))

;;; kittymacs-onboard-tests.el ends here
