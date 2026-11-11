;;; kittymacs-features.el --- What this machine selected from the catalogue -*- lexical-binding: t; -*-
;; Generated from literate/21-features.org; edit the Org source, then tangle.

;;; Code:

(require 'seq)
(require 'kittymacs-catalogue)

(defvar kittymacs-lisp-dir)
(defvar kittymacs-var-dir)
(defvar package-alist)
(defvar package-activated-list)

(defconst kittymacs-default-profile 'minimal
  "The profile of a machine that chose none and started out on the default.")

(defcustom kittymacs-profile nil
  "Where this machine's features start: `minimal' or `full'.
`full' leaves out the features the catalogue marks `optional'.  Nil means no
choice yet, so `kittymacs-default-profile' decides, unless this machine ran
kittymacs before that default existed.  Set it with `setopt' in a host file or
private.el: Customize's file loads after every chapter has asked."
  :type '(choice (const :tag "Not chosen" nil) (const minimal) (const full))
  :group 'kittymacs)

(defcustom kittymacs-features nil
  "Features to turn on beyond `kittymacs-profile', by their catalogue names.
A feature brings the features it depends on.  Set it where `kittymacs-profile'
is set, for the same reason."
  :type '(repeat symbol)
  :group 'kittymacs)

(defcustom kittymacs-features-excluded nil
  "Features to turn off, by their catalogue names.
What depends on them goes too.  The `minimal' profile's features stay on.
Set it where `kittymacs-profile' is set, for the same reason."
  :type '(repeat symbol)
  :group 'kittymacs)
(defun kittymacs-features--warn (message &rest args)
  "Show the warning MESSAGE, formatted with ARGS."
  (display-warning 'kittymacs (apply #'format message args) :warning))

(defun kittymacs-features--in-use-p ()
  "Return non-nil on a machine with signs of having run kittymacs."
  (or (bound-and-true-p package-alist)
      (bound-and-true-p package-activated-list)
      (and (boundp 'kittymacs-lisp-dir)
           (file-exists-p (expand-file-name "private.el" kittymacs-lisp-dir)))
      (and (boundp 'kittymacs-var-dir)
           (file-directory-p kittymacs-var-dir)
           (directory-files-recursively
            kittymacs-var-dir "" nil
            (lambda (directory) (not (equal (file-name-nondirectory directory) "elpa")))))))

(defun kittymacs-features--stamp-file ()
  "Return the file saying this machine started on the default, or nil.
Nil where nothing has named the var directory, as under `emacs -Q'."
  (and (boundp 'kittymacs-var-dir)
       (expand-file-name "started-on-default" kittymacs-var-dir)))

(defun kittymacs-features--kept-on-full-p ()
  "Return non-nil on a machine that a missing choice keeps on `full'.
Only reads, so onboarding can ask."
  (let ((stamp (kittymacs-features--stamp-file)))
    (and (not (and stamp (file-exists-p stamp)))
         (kittymacs-features--in-use-p))))

(defun kittymacs-features--write-stamp ()
  "Record that this machine started on the default, unless that is known."
  (when-let* ((stamp (kittymacs-features--stamp-file)))
    (unless (file-exists-p stamp)
      (condition-case err
          (progn
            (make-directory (file-name-directory stamp) t)
            (write-region "This machine started on the default profile.\n" nil stamp nil 'silent))
        (file-error
         (kittymacs-features--warn
          "Could not write %s: %s
Without it, the next start takes this machine's packages for an older machine's, and moves it to `full'."
          stamp (error-message-string err)))))))

(defun kittymacs-features--choose-profile ()
  "Return the profile to start from, warning when it is not the one asked for."
  (when (and kittymacs-profile (not (memq kittymacs-profile '(minimal full))))
    (kittymacs-features--warn "kittymacs-profile is %S, which is neither `minimal' nor `full'; ignoring it"
                              kittymacs-profile))
  (cond ((memq kittymacs-profile '(minimal full)) kittymacs-profile)
        ((kittymacs-features--kept-on-full-p)
         (kittymacs-features--warn
          "No profile is chosen and this machine ran kittymacs before `minimal' became the default, so it stays on `full'.
Press SPC C o to choose, or set `kittymacs-profile' to `full' or `minimal' in private.el.  Either ends this warning.")
         'full)
        (t (kittymacs-features--write-stamp)
           kittymacs-default-profile)))
(defun kittymacs-exwm-session-p ()
  "Return non-nil when the program starting Emacs asked for EXWM, on X."
  (and (eq window-system 'x) (equal (getenv "KITTYMACS_EXWM") "1")))

(defun kittymacs-features--selected-by-older-options ()
  "Return the features that the options older than the catalogue turn on."
  (append (seq-filter (lambda (name) (assq name kittymacs-catalogue))
                      (mapcar (lambda (language) (intern (format "lang-%s" language)))
                              (bound-and-true-p kittymacs-language-packages)))
          (and (bound-and-true-p kittymacs-notebooks-jupyter) '(jupyter))
          (and (or (bound-and-true-p kittymacs-exwm) (kittymacs-exwm-session-p))
               '(window-manager))
          (and (bound-and-true-p kittymacs-terminal-ghostel) '(terminal))))

(defun kittymacs-features--excluded-by-older-options ()
  "Return the features that the options older than the catalogue turn off."
  (and (boundp 'kittymacs-terminal-ghostel)
       (not kittymacs-terminal-ghostel)
       '(terminal)))
(defvar kittymacs-features--enabled 'unresolved
  "The features that are on, or `unresolved' before the first answer.")

(defvar kittymacs-features--profile nil
  "The profile the last answer started from.")

(defun kittymacs-features--property (feature property)
  "Return PROPERTY of FEATURE in the catalogue."
  (plist-get (alist-get feature kittymacs-catalogue) property))

(defun kittymacs-features--known (names option)
  "Return the NAMES the catalogue lists, warning about the rest, which OPTION set."
  (cond ((not (listp names))
         (kittymacs-features--warn "%s must be a list of features; ignoring %S" option names)
         nil)
        (t
         (seq-filter (lambda (name)
                       (or (assq name kittymacs-catalogue)
                           (progn
                             (kittymacs-features--warn
                              "%s names %S, which the catalogue does not have; ignoring it"
                              option name)
                             nil)))
                     names))))

(defun kittymacs-features--in-profile (profile)
  "Return the features PROFILE turns on."
  (let ((profiles (if (eq profile 'full) '(minimal full) '(minimal))))
    (mapcar #'car (seq-filter (lambda (entry) (memq (plist-get (cdr entry) :profile) profiles))
                              kittymacs-catalogue))))

(defun kittymacs-features--with-deps (features)
  "Return FEATURES and everything they depend on, however indirectly.
FEATURES come first, then their dependencies, nearest first, as the Nix
module's `withDeps' orders them."
  (let ((grown (seq-uniq (append features
                                 (seq-mapcat (lambda (feature)
                                               (kittymacs-features--property feature :deps))
                                             features)))))
    (if (= (length grown) (length features))
        features
      (kittymacs-features--with-deps grown))))

(defun kittymacs-features--applies-p (feature)
  "Return non-nil unless the catalogue rules FEATURE out on this system."
  (not (memq system-type (kittymacs-features--property feature :not-on))))

(defun kittymacs-features--one-of-winner (feature features selected)
  "Return the member of FEATURE's `:one-of' set that stays among FEATURES.
That is the first of them in SELECTED, which holds what the selection names
and then what it needs, nearest first, or else the first in FEATURES."
  (let ((set (kittymacs-features--property feature :one-of)))
    (seq-find (lambda (name) (eq (kittymacs-features--property name :one-of) set))
              (append (seq-filter (lambda (name) (memq name features)) selected)
                      features))))

(defun kittymacs-features--keep-one-of-each (features selected)
  "Return FEATURES with one member left of each `:one-of' set.
SELECTED decides between members, as `kittymacs-features--one-of-winner' says."
  (seq-filter (lambda (feature)
                (or (not (kittymacs-features--property feature :one-of))
                    (eq feature (kittymacs-features--one-of-winner feature features selected))))
              features))

(defun kittymacs-features--drop-unmet (features)
  "Return FEATURES without any whose dependencies are not all among them."
  (let ((kept (seq-filter (lambda (feature)
                            (seq-every-p (lambda (dep) (memq dep features))
                                         (kittymacs-features--property feature :deps)))
                          features)))
    (if (= (length kept) (length features))
        kept
      (kittymacs-features--drop-unmet kept))))

(defun kittymacs-features--compute (profile selected excluded)
  "Return the features that are on, from PROFILE, SELECTED and EXCLUDED.
They come in the catalogue's order."
  (let* ((floor (kittymacs-features--in-profile 'minimal))
         (removed (seq-difference excluded floor))
         (wanted (append (kittymacs-features--in-profile profile)
                         (kittymacs-features--with-deps selected)))
         (on (kittymacs-features--drop-unmet
              (kittymacs-features--keep-one-of-each
               (seq-filter (lambda (feature)
                             (and (not (memq feature removed))
                                  (kittymacs-features--applies-p feature)))
                           wanted)
               (kittymacs-features--with-deps selected)))))
    (mapcar #'car (seq-filter (lambda (entry) (memq (car entry) on)) kittymacs-catalogue))))

(defun kittymacs-features-resolve ()
  "Work out which features are on from the options, and return them.
`init.el' calls this once, after host files and private.el; a warning here
names what was asked for and cannot be had."
  (let* ((asked (kittymacs-features--known kittymacs-features 'kittymacs-features))
         (refused (kittymacs-features--known kittymacs-features-excluded
                                             'kittymacs-features-excluded))
         (floor (kittymacs-features--in-profile 'minimal))
         (profile (kittymacs-features--choose-profile))
         (enabled (kittymacs-features--compute
                   profile
                   (append asked (kittymacs-features--selected-by-older-options))
                   (append refused (kittymacs-features--excluded-by-older-options)))))
    (dolist (feature (seq-intersection refused floor))
      (kittymacs-features--warn
       "%s is part of the minimal profile, which stays on; ignoring its exclusion" feature))
    (dolist (feature asked)
      (when (and (not (memq feature enabled))
                 (kittymacs-features--applies-p feature))
        (if-let* ((set (kittymacs-features--property feature :one-of))
                  (winner (seq-find (lambda (name)
                                      (eq (kittymacs-features--property name :one-of) set))
                                    (seq-intersection asked enabled))))
            (kittymacs-features--warn
             "%s is selected but stays off: %s, selected before it, is on, and only one of the %s set can be"
             feature winner set)
          (kittymacs-features--warn
           "%s is selected but stays off: it, or a feature it depends on, is excluded" feature))))
    (pcase-dolist (`(,feature . ,plist) kittymacs-catalogue)
      (let ((option (plist-get plist :option)))
        (when (and option (boundp option) (not (memq feature enabled))
                   (kittymacs-features--applies-p feature))
          (kittymacs-features--warn
           "`%s' does nothing while %s is off: add %s to `kittymacs-features', or delete the setting"
           option feature feature))))
    (setq kittymacs-features--profile profile
          kittymacs-features--enabled enabled)))

(defun kittymacs-features-enabled ()
  "Return the features that are on, working them out if nothing has yet."
  (if (eq kittymacs-features--enabled 'unresolved)
      (kittymacs-features-resolve)
    kittymacs-features--enabled))

(defun kittymacs-features-profile ()
  "Return the profile the features that are on started from."
  (kittymacs-features-enabled)
  kittymacs-features--profile)

(defun kittymacs-feature-p (feature)
  "Return non-nil if FEATURE, a name in the catalogue, is on."
  (and (memq feature (kittymacs-features-enabled)) t))
(defvar use-package-ensure-function)
(defvar package-user-dir)
(defvar package-directory-list)
(declare-function package-installed-p "package" (package &optional min-version))

(defvar kittymacs-features--failed nil
  "Packages the installer could not install in this session.")

(defun kittymacs-features-packages ()
  "Return the packages the features that are on install from an archive."
  (seq-mapcat (lambda (feature)
                (seq-difference (kittymacs-features--property feature :packages)
                                (kittymacs-features--property feature :vc)))
              (kittymacs-features-enabled)))

(defun kittymacs-features--hide-embark-reminder (show type message &rest args)
  "Call SHOW with TYPE, MESSAGE and ARGS, unless MESSAGE is Embark's reminder."
  (unless (equal message "The package embark-consult should be installed if you use both Embark and Consult")
    (apply show type message args)))

(defun kittymacs-features-install ()
  "Install what the features that are on need and this machine lacks.
A package that cannot be installed warns, and the rest carry on."
  (dolist (package (kittymacs-features-packages))
    (unless (package-installed-p package)
      (condition-case-unless-debug err
          (unwind-protect
              (progn
                (advice-add 'display-warning :around #'kittymacs-features--hide-embark-reminder)
                (funcall use-package-ensure-function package '(t) nil))
            (advice-remove 'display-warning #'kittymacs-features--hide-embark-reminder))
        (error
         (kittymacs-features--warn "Could not install %s: %s"
                                   package (error-message-string err))))
      (unless (package-installed-p package)
        (push package kittymacs-features--failed)))))

(defun kittymacs-features--native-report-on-others-p (warning)
  "Return non-nil if WARNING is a native compiler report on a package or Emacs."
  (and (eq (car warning) 'native-compiler)
       (string-match "\\`\\([^:\n]+\\.el\\)\\(?::[0-9]+:[0-9]+\\)?: " (cadr warning))
       (when-let* ((file (locate-library (match-string 1 (cadr warning)) t)))
         (require 'package)
         (seq-some (lambda (directory) (file-in-directory-p file directory))
                   (append (list package-user-dir lisp-directory) package-directory-list)))))

(defun kittymacs-features--log-compile-warnings ()
  "Write the compile warnings a start delayed to their logs, with no window."
  (let ((held (seq-filter (lambda (warning)
                            (or (equal (nth 3 warning) "*Compile-Log*")
                                (and (eq (bound-and-true-p native-comp-async-report-warnings-errors)
                                         'silent)
                                     (kittymacs-features--native-report-on-others-p warning))))
                          delayed-warnings-list))
        (warning-suppress-types (append '((bytecomp) (native-compiler)) warning-suppress-types)))
    (setq delayed-warnings-list (seq-difference delayed-warnings-list held))
    (dolist (warning (reverse held))
      (apply #'display-warning warning))))
(add-hook 'delayed-warnings-hook #'kittymacs-features--log-compile-warnings)
(defvar package--initialized)
(defvar kittymacs-quickstart-loaded)
(declare-function package-initialize "package" (&optional no-activate))

(define-error 'kittymacs-features-leftover-checkout
  "An install that did not finish left this checkout")

(defun kittymacs-features--leftover-checkout (package)
  "Return PACKAGE's directory if it is left from an install that did not finish.
That is a directory named PACKAGE under `package-user-dir' that package.el
does not count as installed."
  (require 'package)
  (let ((directory (file-name-as-directory
                    (expand-file-name (symbol-name package) package-user-dir))))
    (when (and (file-directory-p directory)
               (not (package-installed-p package))
               (not (and (bound-and-true-p kittymacs-quickstart-loaded)
                         (not (bound-and-true-p package--initialized))
                         (progn (package-initialize t)
                                (package-installed-p package)))))
      directory)))

(defun kittymacs-features--refuse-leftover-checkout (install arg &optional local-path)
  "Call INSTALL with ARG and LOCAL-PATH, unless ARG's package left a checkout.
Around `use-package-vc-install', whose ARG is (NAME OPTIONS REVISION).
package-vc would ask whether to overwrite the checkout, which a daemon with
no frame cannot answer; this signals `kittymacs-features-leftover-checkout'
instead, for the declaration's `condition-case' to report."
  (if-let* (((not local-path))
            (directory (kittymacs-features--leftover-checkout (car arg))))
      (signal 'kittymacs-features-leftover-checkout (list (car arg) directory))
    (funcall install arg local-path)))
(advice-add 'use-package-vc-install :around #'kittymacs-features--refuse-leftover-checkout)

(defun kittymacs-features-vc-warning (package url err)
  "Warn that PACKAGE, from the Git repository URL, did not install: ERR.
Every chapter's `:vc' declaration calls this from its `condition-case'."
  (display-warning
   'kittymacs
   (pcase err
     (`(kittymacs-features-leftover-checkout ,name ,directory)
      (format-message "%s was not installed: %s is left from an install of %s that did not finish.
Move it aside, with M-x kittymacs-features-move-leftovers or by hand, then restart Emacs: the restart installs %s afresh."
                      package (abbreviate-file-name directory) name name))
     (_
      (format-message "%s was not installed: %s
If that error comes from git, check that `git clone %s' works from a terminal, and which git Emacs runs: %s"
                      package (error-message-string err) url (executable-find "git"))))
   :warning))

(defun kittymacs-features--leftovers ()
  "Return the leftover checkouts of the Git packages of the features that are on."
  (delq nil (mapcar #'kittymacs-features--leftover-checkout
                    (delete-dups
                     (seq-mapcat (lambda (feature) (kittymacs-features--property feature :vc))
                                 (kittymacs-features-enabled))))))

(defun kittymacs-features-move-leftovers ()
  "Move aside each checkout a Git install that did not finish left, after asking.
Each becomes NAME.broken-TIMESTAMP beside it, so the next start installs
NAME afresh."
  (interactive)
  (let ((leftovers (kittymacs-features--leftovers))
        (stamp (format-time-string "%Y%m%d-%H%M%S")))
    (cond
     ((null leftovers)
      (message "No Git install has left a checkout behind"))
     ((yes-or-no-p (format "Move aside %s? "
                           (mapconcat #'abbreviate-file-name leftovers ", ")))
      (dolist (directory leftovers)
        (let ((directory (directory-file-name directory)))
          (rename-file directory (format "%s.broken-%s" directory stamp))))
      (message "Moved %d aside; restart Emacs to install them afresh" (length leftovers))))))
(put 'kittymacs-org-roam-project 'safe-local-variable #'booleanp)
(put 'kittymacs-org-roam-excluded-directories 'safe-local-variable #'list-of-strings-p)

(provide 'kittymacs-features)
;;; kittymacs-features.el ends here
