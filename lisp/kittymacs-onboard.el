;;; kittymacs-onboard.el --- Choose what kittymacs installs -*- lexical-binding: t; -*-
;; Generated from literate/22-onboarding.org; edit the Org source, then tangle.

;;; Code:

(require 'cl-lib)
(require 'seq)

(eval-and-compile
  (defconst kittymacs-onboard--directory
    (file-name-directory
     (or load-file-name (bound-and-true-p byte-compile-current-file) buffer-file-name))
    "Where this file and its neighbours live.")
  (add-to-list 'load-path kittymacs-onboard--directory))

(require 'kittymacs-features)
(require 'kittymacs-wsl)

(defvar kittymacs-host-directories)
(defvar kittymacs-lisp-dir)
(defvar kittymacs-var-dir)
(defvar package-alist)
(defvar package-user-dir)
(declare-function package-load-all-descriptors "package" ())

(defvar kittymacs-onboard-private-file
  (expand-file-name "private.el" kittymacs-onboard--directory)
  "The file onboarding writes, where `init.el' looks for it.")

(defvar kittymacs-onboard-host-directories
  (if (boundp 'kittymacs-host-directories)
      kittymacs-host-directories
    (list "/etc/kittymacs/conf.d/"
          (expand-file-name "kittymacs/conf.d/" (or (getenv "XDG_CONFIG_HOME") "~/.config"))))
  "The host layer's directories, in the order `init.el' reads them.")

(defvar kittymacs-onboard-var-directory
  (expand-file-name "../var/" kittymacs-onboard--directory)
  "Where a start of this checkout keeps its packages and its stamp.")

(defvar kittymacs-onboard-store-directory "/nix/store/"
  "Files under here are never written, whatever their modes say.")
(defconst kittymacs-onboard--group-titles
  '((editing . "Editing")
    (finding . "Finding things")
    (look . "How it looks")
    (help . "Help")
    (git . "Version control")
    (shells . "Shells and environments")
    (notes . "Notes")
    (programming . "Programming")
    (assistants . "Assistants")
    (desktop . "Window manager"))
  "What each `:group' in the catalogue is called on screen.")

(defconst kittymacs-onboard-options
  '((kittymacs-project-directory
     :type directory :label "Where your projects live")
    (kittymacs-org-directory
     :type directory :label "Where your Org files live")
    (kittymacs-org-roam-directory
     :type directory :feature linked-notes :label "Where your linked notes live")
    (kittymacs-font-family
     :type string :label "The font for code")
    (kittymacs-suggestions
     :type boolean :feature suggestions
     :label "Copilot suggests in every programming file, which sends those files to GitHub"))
  "Options to ask about: a name, its `:type', `:label' and maybe `:feature'.")

(defconst kittymacs-onboard-structural-languages
  '(("Every programming language" :modes (prog-mode))
    ("Emacs Lisp" :code t :modes (emacs-lisp-mode))
    ("Other Lisps" :code t :modes (lisp-mode scheme-mode))
    ("Python" :code t :modes (python-base-mode))
    ("C and C++" :code t :modes (c-mode-common c-ts-base-mode))
    ("JavaScript and TypeScript" :code t :modes (js-base-mode typescript-ts-base-mode))
    ("Shell scripts" :code t :modes (sh-base-mode))
    ("Org" :modes (org-mode))
    ("Markdown" :modes (markdown-mode markdown-ts-mode))
    ("LaTeX" :modes (tex-mode))
    ("The M-: prompt" :modes (eval-expression-minibuffer-setup)))
  "Each language to ask about, and the modes that answering yes adds.")

(defconst kittymacs-onboard--selection-options
  '(kittymacs-profile kittymacs-features kittymacs-features-excluded)
  "The options that say which features are on.")

(defconst kittymacs-onboard--older-options
  '(kittymacs-language-packages kittymacs-notebooks-jupyter
    kittymacs-exwm kittymacs-terminal-ghostel)
  "The options older than the catalogue, which also select features.")

(defun kittymacs-onboard--written-options ()
  "Return the options onboarding can write."
  (append kittymacs-onboard--selection-options
          '(kittymacs-structural-editing-modes kittymacs-backends)
          (mapcar #'car kittymacs-onboard-options)))
(define-error 'kittymacs-onboard-refused "Onboarding refused")

(defun kittymacs-onboard--refuse (message &rest args)
  "Stop onboarding with the reason MESSAGE, formatted with ARGS."
  (signal 'kittymacs-onboard-refused (list (apply #'format message args))))
(defun kittymacs-onboard--file-bytes (file)
  "Return the contents of FILE as a unibyte string."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defun kittymacs-onboard--text (bytes)
  "Return BYTES decoded for reading, each character keeping its place."
  (decode-coding-string bytes 'utf-8-unix))

(defun kittymacs-onboard--read-forms (text)
  "Return each form in TEXT as a list of the form, its position and its line."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (with-syntax-table emacs-lisp-mode-syntax-table
      (let (forms)
        (while (progn (forward-comment (buffer-size)) (not (eobp)))
          (let ((position (point))
                (line (line-number-at-pos)))
            (push (list (read (current-buffer)) position line) forms)))
        (nreverse forms)))))

(defun kittymacs-onboard--read-or-refuse (bytes file)
  "Return the forms in BYTES, or refuse because FILE does not read as Lisp."
  (condition-case err
      (kittymacs-onboard--read-forms (kittymacs-onboard--text bytes))
    (error
     (kittymacs-onboard--refuse "%s does not read as Lisp (%s).  Mend it, then run this again."
                                file (error-message-string err)))))

(defun kittymacs-onboard--setters (form &optional nested)
  "Return what FORM sets, as lists of an option, its value form and NESTED."
  (when (consp form)
    (pcase (car form)
      ('quote nil)
      ((or 'setopt 'setq 'setq-default)
       (let ((rest (cdr form)) found)
         (while (and (consp rest) (consp (cdr rest)))
           (push (list (car rest) (cadr rest) nested) found)
           (setq rest (cddr rest)))
         (nreverse found)))
      ('customize-set-variable
       (when (eq (car-safe (nth 1 form)) 'quote)
         (list (list (cadr (nth 1 form)) (nth 2 form) nested))))
      (_
       (let ((tail form) found)
         (while (consp tail)
           (setq found (append found (kittymacs-onboard--setters (car tail) t))
                 tail (cdr tail)))
         found)))))

(defun kittymacs-onboard--literal (form)
  "Return a list holding the value of FORM, or nil when only running it could tell."
  (pcase form
    ((or 'nil 't (pred stringp) (pred numberp) (pred keywordp)) (list form))
    (`(quote ,value) (list value))
    (`(expand-file-name ,(and path (pred stringp))) (list path))
    (`(list . ,items)
     (let ((values (mapcar #'kittymacs-onboard--literal items)))
       (and (seq-every-p #'identity values)
            (list (mapcar #'car values)))))))
(defconst kittymacs-onboard--begin
  ";; >>> kittymacs onboarding: `just onboard' or SPC C o rewrites this block, and nothing else."
  "The line that starts the block.")

(defconst kittymacs-onboard--end
  ";; <<< kittymacs onboarding: your own settings go outside these two lines."
  "The line that ends the block.")

(defconst kittymacs-onboard--begin-regexp "^[ \t]*;+[ \t]*>>>[ \t]*kittymacs onboarding"
  "What counts as a begin marker, loosely, so a damaged one is noticed.")

(defconst kittymacs-onboard--end-regexp "^[ \t]*;+[ \t]*<<<[ \t]*kittymacs onboarding"
  "What counts as an end marker, loosely, so a damaged one is noticed.")

(defconst kittymacs-onboard--new-file-header
  ";;; private.el --- This machine's settings -*- lexical-binding: t; -*-
;; lisp/private.example.el shows what else can go here.

"
  "How a `private.el' that did not exist begins.")

(defun kittymacs-onboard--marker-lines (regexp bytes)
  "Return the start and end of each line of BYTES that REGEXP matches."
  (let ((case-fold-search nil)
        (from 0)
        lines)
    (while (string-match regexp bytes from)
      (let* ((start (match-beginning 0))
             (end (or (string-search "\n" bytes start) (length bytes))))
        (push (cons start end) lines)
        (setq from end)))
    (nreverse lines)))

(defun kittymacs-onboard--top-level-p (bytes)
  "Return non-nil if the end of BYTES is outside every form and string."
  (with-temp-buffer
    (insert (kittymacs-onboard--text bytes))
    (with-syntax-table emacs-lisp-mode-syntax-table
      (let ((state (parse-partial-sexp (point-min) (point-max))))
        (and (zerop (car state)) (not (nth 3 state)))))))

(defun kittymacs-onboard--split (bytes file)
  "Return BYTES of FILE as what is before the block, the block, and what is after.
The block is nil when there is none.  Refuse when the markers make no sense."
  (let ((begins (kittymacs-onboard--marker-lines kittymacs-onboard--begin-regexp bytes))
        (ends (kittymacs-onboard--marker-lines kittymacs-onboard--end-regexp bytes)))
    (cond
     ((and (null begins) (null ends)) (list bytes nil ""))
     ((or (cdr begins) (cdr ends))
      (kittymacs-onboard--refuse
       "%s has an onboarding marker twice.  Keep one block, then run this again." file))
     ((not (and begins ends))
      (kittymacs-onboard--refuse
       "%s has one onboarding marker without its partner.  Mend the block or delete it, then run this again."
       file))
     ((> (caar begins) (caar ends))
      (kittymacs-onboard--refuse
       "%s has its onboarding markers in the wrong order.  Mend the block or delete it, then run this again."
       file))
     (t
      (let ((before (substring bytes 0 (caar begins))))
        (unless (kittymacs-onboard--top-level-p before)
          (kittymacs-onboard--refuse
           "%s has its onboarding block inside a form or a string.  Move it out, then run this again."
           file))
        (list before
              (substring bytes (caar begins) (cdar ends))
              (substring bytes (cdar ends))))))))

(defun kittymacs-onboard--print (form)
  "Return FORM as one line of Lisp."
  (let ((print-quoted t) (print-length nil) (print-level nil) (print-escape-newlines t))
    (prin1-to-string form)))

(defun kittymacs-onboard--block-text (forms)
  "Return the block holding FORMS, as bytes."
  (encode-coding-string
   (concat kittymacs-onboard--begin "\n"
           (mapconcat #'kittymacs-onboard--print forms "\n") "\n"
           kittymacs-onboard--end)
   'utf-8-unix))

(defun kittymacs-onboard--forms-only (bytes file)
  "Return just the forms in BYTES of FILE."
  (mapcar #'car (kittymacs-onboard--read-or-refuse bytes file)))

(defun kittymacs-onboard--proposed (old forms file)
  "Return the new bytes of FILE, whose bytes are OLD or nil, with FORMS in a block.
Refuse unless they read as what is outside the block and FORMS, in that place."
  (when old (kittymacs-onboard--read-or-refuse old file))
  (pcase-let* ((`(,before ,block ,after)
                (if old (kittymacs-onboard--split old file) (list "" nil "")))
               (text (kittymacs-onboard--block-text forms))
               (new (cond
                     (block (concat before text after))
                     ((string-empty-p before)
                      (concat kittymacs-onboard--new-file-header text "\n"))
                     (t (concat before
                                (if (string-suffix-p "\n" before) "\n" "\n\n")
                                text "\n")))))
    (unless (equal (kittymacs-onboard--forms-only new file)
                   (append (kittymacs-onboard--forms-only before file)
                           forms
                           (kittymacs-onboard--forms-only after file)))
      (kittymacs-onboard--refuse "The text for %s would not read back as written; nothing changed."
                                 file))
    new))
(defun kittymacs-onboard--interesting-p (option)
  "Return non-nil if onboarding has to know the value of OPTION."
  (or (memq option (kittymacs-onboard--written-options))
      (memq option kittymacs-onboard--older-options)))

(defun kittymacs-onboard--settings-of-forms (forms file place)
  "Return the interesting settings in FORMS of FILE.
PLACE is a function of a form's position, which says where the form sits."
  (let (settings)
    (pcase-dolist (`(,form ,position ,line) forms)
      (let ((setters (kittymacs-onboard--setters form)))
        (unless (or (assq 'kittymacs-backends setters)
                    (not (memq 'kittymacs-backends (flatten-tree form))))
          (push (list 'kittymacs-backends form t) setters))
        (pcase-dolist (`(,option ,value ,nested) setters)
          (when (kittymacs-onboard--interesting-p option)
            (push (list :option option :value value :nested nested :file file :line line
                        :place (funcall place position))
                  settings)))))
    (nreverse settings)))

(defun kittymacs-onboard--private-settings (file)
  "Return the settings in FILE, or refuse if FILE cannot be understood."
  (when (file-exists-p file)
    (let* ((bytes (condition-case err
                      (kittymacs-onboard--file-bytes file)
                    (file-error
                     (kittymacs-onboard--refuse "%s cannot be read (%s)."
                                                file (error-message-string err)))))
           (forms (kittymacs-onboard--read-or-refuse bytes file))
           (parts (kittymacs-onboard--split bytes file))
           (begin (1+ (length (kittymacs-onboard--text (car parts)))))
           (end (+ begin (length (kittymacs-onboard--text (or (cadr parts) ""))))))
      (kittymacs-onboard--settings-of-forms
       forms file
       (lambda (position)
         (cond ((null (cadr parts)) 'before)
               ((< position begin) 'before)
               ((< position end) 'block)
               (t 'after)))))))

(defun kittymacs-onboard--host-files ()
  "Return the host layer's files, in the order `init.el' loads them."
  (seq-mapcat (lambda (directory)
                (and (file-directory-p directory)
                     (directory-files directory t "\\`[^.#].*\\.el\\'")))
              kittymacs-onboard-host-directories))

(defun kittymacs-onboard--host-settings (notes)
  "Return the settings in the host layer, adding what it could not read to NOTES.
NOTES is a list with one element, a list that grows."
  (seq-mapcat
   (lambda (file)
     (condition-case err
         (kittymacs-onboard--settings-of-forms
          (kittymacs-onboard--read-forms
           (kittymacs-onboard--text (kittymacs-onboard--file-bytes file)))
          file (lambda (_) 'host))
       (error
        (push (format "Onboarding could not read %s, so this does not show its choices: %s"
                      file (error-message-string err))
              (car notes))
        nil)))
   (kittymacs-onboard--host-files)))

(defun kittymacs-onboard--final-values (settings notes)
  "Return the last known value of each option in SETTINGS, as an alist.
A top-level setting whose value only running it could tell goes in NOTES."
  (let (values)
    (dolist (setting settings)
      (unless (plist-get setting :nested)
        (let ((option (plist-get setting :option))
              (known (kittymacs-onboard--literal (plist-get setting :value))))
          (setq values (assq-delete-all option values))
          (if known
              (push (cons option (car known)) values)
            (push (format "%s line %d sets %s with an expression.  Onboarding does not run it, so this does not show its value."
                          (file-name-nondirectory (plist-get setting :file))
                          (plist-get setting :line) option)
                  (car notes))))))
    values))

(defun kittymacs-onboard--known-names (value option notes)
  "Return the catalogue's features among VALUE, what OPTION held.
A name the catalogue lacks goes in NOTES."
  (let ((names (if (listp value) value nil)))
    (seq-filter (lambda (name)
                  (or (assq name kittymacs-catalogue)
                      (progn
                        (push (format "%s names %s, which the catalogue lacks, so this leaves it out."
                                      option name)
                              (car notes))
                        nil)))
                names)))

(defun kittymacs-onboard--older-selection (values)
  "Return what the older options in VALUES select and exclude, as a pair."
  (cl-progv kittymacs-onboard--older-options
      (mapcar (lambda (_) nil) kittymacs-onboard--older-options)
    (dolist (option kittymacs-onboard--older-options)
      (if-let* ((found (assq option values)))
          (set option (cdr found))
        (makunbound option)))
    (cons (kittymacs-features--selected-by-older-options)
          (kittymacs-features--excluded-by-older-options))))
(cl-defstruct (kittymacs-onboard--state
               (:constructor kittymacs-onboard--make-state)
               (:copier nil)
               (:conc-name kittymacs-onboard--))
  "The answers so far."
  profile selected excluded older-selected older-excluded
  answers extra-modes modes-in-block options settings notes before
  backends distributions)

(defun kittymacs-onboard--floor ()
  "Return the features no answer can turn off."
  (kittymacs-features--in-profile 'minimal))

(defun kittymacs-onboard--on-excluding (state excluded)
  "Return the features that are on in STATE if its exclusions were EXCLUDED."
  (kittymacs-features--compute
   (kittymacs-onboard--profile state)
   (append (kittymacs-onboard--selected state) (kittymacs-onboard--older-selected state))
   (append excluded (kittymacs-onboard--older-excluded state))))

(defun kittymacs-onboard--on (state)
  "Return the features that are on in STATE."
  (kittymacs-onboard--on-excluding state (kittymacs-onboard--excluded state)))

(defun kittymacs-onboard--base (state)
  "Return the features the profile of STATE turns on by itself."
  (kittymacs-features--compute (kittymacs-onboard--profile state) nil nil))

(defun kittymacs-onboard--in-catalogue-order (names)
  "Return NAMES in the catalogue's order, each once."
  (seq-filter (lambda (name) (memq name names)) (mapcar #'car kittymacs-catalogue)))

(defun kittymacs-onboard--names (features)
  "Return FEATURES as text for a person."
  (if features (mapconcat #'symbol-name features ", ") "nothing"))

(defun kittymacs-onboard--toggle (state feature)
  "Turn FEATURE on or off in STATE, and return a sentence saying what moved."
  (let ((before (kittymacs-onboard--on state)))
    (cond
     ((memq feature (kittymacs-onboard--floor))
      (format "%s is always on: every other feature stands on it." feature))
     ((not (kittymacs-features--applies-p feature))
      (format "%s is not available on this system." feature))
     ((memq feature (kittymacs-onboard--older-excluded state))
      (format "%s is off because an older option says so: `kittymacs-terminal-ghostel'.  Change that first."
              feature))
     (t
      (if (memq feature before)
          (progn
            (setf (kittymacs-onboard--selected state)
                  (delq feature (kittymacs-onboard--selected state)))
            (when (memq feature (kittymacs-onboard--on state))
              (push feature (kittymacs-onboard--excluded state))))
        (setf (kittymacs-onboard--excluded state)
              (seq-difference (kittymacs-onboard--excluded state)
                              (kittymacs-features--with-deps (list feature))))
        (unless (memq feature (kittymacs-onboard--on state))
          (push feature (kittymacs-onboard--selected state))))
      (let ((after (kittymacs-onboard--on state)))
        (setf (kittymacs-onboard--selected state)
              (seq-filter (lambda (name)
                            (or (memq name after)
                                (not (kittymacs-features--applies-p name))))
                          (kittymacs-onboard--selected state)))
        (if (and (not (memq feature before)) (not (memq feature after)))
            (format "%s stays off: something it needs is not available here." feature)
          (format "On: %s.  Off: %s."
                  (kittymacs-onboard--names (seq-difference after before))
                  (kittymacs-onboard--names (seq-difference before after)))))))))

(defun kittymacs-onboard--written-selection (state)
  "Return what STATE writes: a pair of the selected and the excluded."
  (let* ((on (kittymacs-onboard--on state))
         (base (kittymacs-onboard--base state))
         (floor (kittymacs-onboard--floor))
         (excluded (kittymacs-onboard--excluded state)))
    (cons
     (kittymacs-onboard--in-catalogue-order
      (seq-filter (lambda (feature)
                    (or (not (kittymacs-features--applies-p feature))
                        (and (memq feature on) (not (memq feature base)))))
                  (kittymacs-onboard--selected state)))
     (kittymacs-onboard--in-catalogue-order
      (seq-filter (lambda (feature)
                    (and (not (memq feature floor))
                         (or (not (kittymacs-features--applies-p feature))
                             (memq feature
                                   (kittymacs-onboard--on-excluding
                                    state (remq feature excluded))))))
                  excluded)))))
(defun kittymacs-onboard--answers-from (modes)
  "Return the answers that the setting MODES amounts to."
  (let ((every-language (memq 'prog-mode modes)))
    (seq-keep (lambda (row)
                (unless (and every-language (plist-get (cdr row) :code))
                  (cons (car row)
                        (if (seq-every-p (lambda (mode) (memq mode modes))
                                         (plist-get (cdr row) :modes))
                            'yes
                          'no))))
              kittymacs-onboard-structural-languages)))

(defun kittymacs-onboard--covered-p (state row)
  "Return non-nil if the answer for every programming language in STATE covers ROW."
  (and (plist-get (cdr row) :code)
       (eq (alist-get "Every programming language" (kittymacs-onboard--answers state)
                      nil nil #'equal)
           'yes)))

(defun kittymacs-onboard--unanswered (state)
  "Return the rows that still want an answer in STATE."
  (seq-remove (lambda (row)
                (or (kittymacs-onboard--covered-p state row)
                    (assoc (car row) (kittymacs-onboard--answers state))))
              kittymacs-onboard-structural-languages))

(defun kittymacs-onboard--answer (state row answer)
  "Record ANSWER for ROW in STATE."
  (setf (alist-get (car row) (kittymacs-onboard--answers state) nil nil #'equal) answer))

(defun kittymacs-onboard--chosen-modes (state)
  "Return the modes the answers in STATE add up to."
  (seq-uniq
   (append
    (seq-mapcat (lambda (row)
                  (and (not (kittymacs-onboard--covered-p state row))
                       (eq (alist-get (car row) (kittymacs-onboard--answers state)
                                      nil nil #'equal)
                           'yes)
                       (plist-get (cdr row) :modes)))
                kittymacs-onboard-structural-languages)
    (kittymacs-onboard--extra-modes state))))
(defun kittymacs-onboard--setopt (option value)
  "Return the form that sets OPTION to the constant VALUE."
  (list 'setopt option
        (cond ((or (null value) (eq value t) (stringp value) (numberp value)) value)
              ((and (consp value) (eq (car value) 'expand-file-name)) value)
              (t (list 'quote value)))))

(defun kittymacs-onboard--option-form (option value)
  "Return the form that sets OPTION to the answer VALUE."
  (if (and (eq (plist-get (alist-get option kittymacs-onboard-options) :type) 'directory)
           (stringp value)
           (string-prefix-p "~" value))
      (kittymacs-onboard--setopt option (list 'expand-file-name value))
    (kittymacs-onboard--setopt option value)))

(defun kittymacs-onboard--structural-on-p (state)
  "Return non-nil if STATE has structural editing on."
  (memq 'structural-editing (kittymacs-onboard--on state)))

(defun kittymacs-onboard--block-forms (state)
  "Return the forms the block holds for the answers in STATE."
  (pcase-let ((`(,selected . ,excluded) (kittymacs-onboard--written-selection state)))
    (append
     (list (kittymacs-onboard--setopt 'kittymacs-profile (kittymacs-onboard--profile state))
           (kittymacs-onboard--setopt 'kittymacs-features selected)
           (kittymacs-onboard--setopt 'kittymacs-features-excluded excluded))
     (when (or (kittymacs-onboard--structural-on-p state)
               (kittymacs-onboard--modes-in-block state))
       (list (kittymacs-onboard--setopt 'kittymacs-structural-editing-modes
                                        (kittymacs-onboard--chosen-modes state))))
     (when-let* ((form (kittymacs-onboard--backends-form state)))
       (list form))
     (seq-keep (lambda (row)
                 (when-let* ((answer (assq (car row) (kittymacs-onboard--options state))))
                   (kittymacs-onboard--option-form (car row) (cdr answer))))
               kittymacs-onboard-options))))
(defun kittymacs-onboard--nix-host-p ()
  "Return non-nil on a machine where Nix options could hold the answer."
  (or (file-directory-p kittymacs-onboard-store-directory)
      (seq-some (lambda (file) (equal (file-name-nondirectory file) "10-nix.el"))
                (kittymacs-onboard--host-files))))

(defun kittymacs-onboard--nix-value (value)
  "Return VALUE, a form from the block, as Nix text after an option's name."
  (cond ((eq value t) " = true;")
        ((null value) " = false;")
        ((stringp value) (format " = %s;" (kittymacs-onboard--print value)))
        (t (format ".elisp = %s;"
                   (string-replace "${" "\\${"
                                   (kittymacs-onboard--print
                                    (kittymacs-onboard--print value)))))))

(defun kittymacs-onboard--nix-text (state)
  "Return the `programs.kittymacs' options that match the answers in STATE."
  (pcase-let ((`(,selected . ,excluded) (kittymacs-onboard--written-selection state)))
    (concat
     "programs.kittymacs = {\n"
     (format "  profile = \"%s\";\n" (kittymacs-onboard--profile state))
     (mapconcat (lambda (feature) (format "  features.%s.enable = true;\n" feature))
                selected "")
     (mapconcat (lambda (feature) (format "  features.%s.enable = false;\n" feature))
                excluded "")
     (mapconcat (lambda (form)
                  (format "  settings.%s%s\n" (nth 1 form)
                          (kittymacs-onboard--nix-value (nth 2 form))))
                (seq-drop (kittymacs-onboard--block-forms state) 3)
                "")
     "};\n"
     "private.el loads after the host layer, so what it sets wins over these.\n")))
(defconst kittymacs-onboard--buffer-name "*kittymacs onboarding*"
  "The buffer the screens are drawn in.")

(defun kittymacs-onboard--read-event (prompt)
  "Return the next key, showing PROMPT."
  (read-key prompt))

(defun kittymacs-onboard--read-text (prompt initial)
  "Return a line typed after PROMPT, starting from INITIAL."
  (read-string prompt initial))

(defun kittymacs-onboard--key (prompt)
  "Return the next key after PROMPT, quitting on `C-g'."
  (let ((key (kittymacs-onboard--read-event prompt)))
    (when (eql key ?\C-g)
      (signal 'quit nil))
    key))

(defun kittymacs-onboard--show (text)
  "Draw the screen TEXT, with point on the line that begins with the cursor mark."
  (let ((buffer (get-buffer-create kittymacs-onboard--buffer-name))
        position)
    (with-current-buffer buffer
      (unless (derived-mode-p 'special-mode)
        (special-mode)
        (setq-local word-wrap t
                    truncate-lines nil
                    scroll-margin 4
                    mode-line-format " kittymacs onboarding: nothing changes until the last screen"))
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text))
      (goto-char (point-min))
      (when (re-search-forward "^> " nil t)
        (goto-char (match-beginning 0)))
      (setq position (point)))
    (unless noninteractive
      (set-window-buffer (selected-window) buffer)
      (set-buffer buffer)
      (set-window-point (selected-window) position)
      (redisplay))))

(defun kittymacs-onboard--title (text)
  "Return TEXT as a heading."
  (propertize text 'face 'bold))

(defun kittymacs-onboard--plain (text)
  "Return TEXT without the Org markup around code."
  (let* ((opened (replace-regexp-in-string "\\(^\\|[ (]\\)=" "\\1" text))
         (closed (replace-regexp-in-string "=\\($\\|[] ,.;:)]\\)" "\\1" opened)))
    closed))

(defun kittymacs-onboard--needed-by (state feature)
  "Return the features that are on in STATE and need FEATURE."
  (seq-filter (lambda (other)
                (memq feature (kittymacs-features--property other :deps)))
              (kittymacs-onboard--on state)))

(defun kittymacs-onboard--status (state feature)
  "Return the mark and the reason for FEATURE in STATE, as a pair."
  (let ((on (memq feature (kittymacs-onboard--on state))))
    (cond
     ((not (kittymacs-features--applies-p feature))
      (cons "[-]" "not available on this system"))
     ((memq feature (kittymacs-onboard--floor))
      (cons "[=]" "always on"))
     ((memq feature (kittymacs-onboard--older-excluded state))
      (cons "[-]" "off, because an older option says so"))
     ((and on
           (not (memq feature (kittymacs-onboard--base state)))
           (not (memq feature (kittymacs-onboard--selected state)))
           (not (memq feature (kittymacs-onboard--older-selected state))))
      (cons "[x]" (format "pulled in: %s needs it"
                          (kittymacs-onboard--names
                           (kittymacs-onboard--needed-by state feature)))))
     (on (cons "[x]" (if (kittymacs-features--property feature :experimental) "experimental" "")))
     ((kittymacs-features--property feature :experimental)
      (cons "[ ]" "experimental: off until you choose it"))
     ((eq (kittymacs-features--property feature :profile) 'optional)
      (cons "[ ]" "optional: off until you choose it"))
     (t (cons "[ ]" "")))))

(defun kittymacs-onboard--feature-row (state feature cursor)
  "Return the lines for FEATURE in STATE, marked when CURSOR is non-nil."
  (pcase-let ((`(,mark . ,reason) (kittymacs-onboard--status state feature))
              (deps (kittymacs-features--property feature :deps))
              (untested (kittymacs-features--property feature :experimental)))
    (concat
     (if cursor "> " "  ")
     (let ((head (format "%s %s" mark feature)))
       (if cursor (propertize head 'face 'highlight) head))
     (if (string-empty-p reason) "" (format "  (%s)" reason))
     "\n      "
     (kittymacs-onboard--plain (kittymacs-features--property feature :summary))
     "\n      "
     (kittymacs-onboard--plain (kittymacs-features--property feature :example))
     (if deps (format "\n      Needs: %s." (kittymacs-onboard--names deps)) "")
     (if untested (format "\n      Experimental: %s" untested) "")
     "\n")))

(defun kittymacs-onboard--groups ()
  "Return the catalogue's groups, in the order it first names them."
  (seq-uniq (mapcar (lambda (entry) (plist-get (cdr entry) :group)) kittymacs-catalogue)))

(defun kittymacs-onboard--features-in (group)
  "Return the catalogue's features in GROUP."
  (mapcar #'car (seq-filter (lambda (entry) (eq (plist-get (cdr entry) :group) group))
                            kittymacs-catalogue)))

(defun kittymacs-onboard--screen-title (place title)
  "Return a screen's top line: PLACE is its number and the total; TITLE names it."
  (kittymacs-onboard--title
   (format "kittymacs onboarding  %d of %d  %s" (car place) (cdr place) title)))

(defun kittymacs-onboard--render-features (state group place cursor note)
  "Return the screen for GROUP in STATE: PLACE for the title, row CURSOR and NOTE."
  (concat
   (kittymacs-onboard--screen-title
    place (alist-get group kittymacs-onboard--group-titles))
   "\nSPC turns a feature on or off.  n, p move.  RET next screen.  b back.  C-g quit, writing nothing.\n"
   (if note (concat note "\n") "")
   "\n"
   (let ((index -1))
     (mapconcat (lambda (feature)
                  (setq index (1+ index))
                  (kittymacs-onboard--feature-row state feature (= index cursor)))
                (kittymacs-onboard--features-in group)
                ""))))

(defun kittymacs-onboard--features-screen (state group place)
  "Ask about the features in GROUP in STATE; return `next' or `back'."
  (let* ((features (kittymacs-onboard--features-in group))
         (cursor 0)
         note answer)
    (while (not answer)
      (kittymacs-onboard--show
       (kittymacs-onboard--render-features state group place cursor note))
      (setq note nil)
      (pcase (kittymacs-onboard--key "SPC toggle, n/p move, RET next, b back, C-g quit: ")
        ((or ?n 'down) (setq cursor (min (1+ cursor) (1- (length features)))))
        ((or ?p 'up) (setq cursor (max (1- cursor) 0)))
        (?\s (setq note (kittymacs-onboard--toggle state (nth cursor features))))
        ((or ?\r 'return 'right) (setq answer 'next))
        ((or ?b 'left) (setq answer 'back))))
    answer))

(defun kittymacs-onboard--chosen-by (state)
  "Return where the profile in STATE came from, for a person."
  (if-let* ((setting (seq-find (lambda (setting)
                                 (and (eq (plist-get setting :option) 'kittymacs-profile)
                                      (not (plist-get setting :nested))))
                               (reverse (kittymacs-onboard--settings state)))))
      (format "This starts at %s, chosen in %s."
              (kittymacs-onboard--profile state)
              (file-name-nondirectory (plist-get setting :file)))
    (if (eq (kittymacs-onboard--profile state) kittymacs-default-profile)
        (format "Nothing here has chosen yet, so this starts at %s, the default."
                kittymacs-default-profile)
      (format "Nothing here has chosen yet, and this machine ran kittymacs before %s became the default, so it stays at %s."
              kittymacs-default-profile (kittymacs-onboard--profile state)))))

(defun kittymacs-onboard--render-profile (state place)
  "Return the first screen for STATE, with PLACE as in the title."
  (concat
   (kittymacs-onboard--screen-title place "Where to start")
   "\nNothing changes until the last screen, and C-g quits at any point.\n\n"
   (format "  m  minimal: the %d features every machine gets, and where a new machine starts.\n"
           (length (kittymacs-features--compute 'minimal nil nil)))
   (format "  f  full: those and %d more.\n"
           (- (length (kittymacs-features--compute 'full nil nil))
              (length (kittymacs-features--compute 'minimal nil nil))))
   "\nThe next screens turn single features on or off, whichever you start from.\n"
   "A feature marked optional stays off under both until you choose it.\n\n"
   (kittymacs-onboard--chosen-by state) "\n"
   (mapconcat (lambda (note) (concat "\nNote: " note "\n"))
              (reverse (kittymacs-onboard--notes state)) "")))

(defun kittymacs-onboard--profile-screen (state place)
  "Ask which profile STATE starts from; return `next'."
  (let (answer)
    (while (not answer)
      (kittymacs-onboard--show (kittymacs-onboard--render-profile state place))
      (pcase (kittymacs-onboard--key "m minimal, f full, RET keep this, C-g quit: ")
        (?m (setf (kittymacs-onboard--profile state) 'minimal)
            (setq answer 'next))
        (?f (setf (kittymacs-onboard--profile state) 'full)
            (setq answer 'next))
        ((or ?\r 'return 'right) (setq answer 'next))))
    answer))

(defun kittymacs-onboard--render-structural (state place cursor note)
  "Return the structural-editing screen for STATE: PLACE, row CURSOR and NOTE."
  (concat
   (kittymacs-onboard--screen-title place "Structural editing, by language")
   "\ny or n answers a line.  Y or N answers every line still open.  RET next.  b back.  C-g quit.\n"
   (if note (concat note "\n") "")
   "\nPuni keeps brackets balanced as you edit: deleting never breaks a pair.\n"
   "Some people want that everywhere, some in Lisp and nowhere else, so nothing here starts answered.\n\n"
   "No to a line means brackets there can come unbalanced as you delete, as in plain Emacs.\n"
   "No to every line leaves Puni installed and on in no buffer; SPC t p still turns it on in one.\n"
   "To not install it at all, go back and turn off structural-editing on the Editing screen.\n\n"
   (let ((index -1))
     (mapconcat
      (lambda (row)
        (setq index (1+ index))
        (let ((answer (alist-get (car row) (kittymacs-onboard--answers state) nil nil #'equal)))
          (format "%s%s %s\n"
                  (if (= index cursor) "> " "  ")
                  (cond ((kittymacs-onboard--covered-p state row) "[~]")
                        ((eq answer 'yes) "[y]")
                        ((eq answer 'no) "[n]")
                        (t "[?]"))
                  (car row))))
      kittymacs-onboard-structural-languages ""))
   (if-let* ((extra (kittymacs-onboard--extra-modes state)))
       (format "\nAlso kept, from a setting already here: %s.\n" (kittymacs-onboard--names extra))
     "")))

(defun kittymacs-onboard--structural-screen (state place)
  "Ask by language where structural editing goes in STATE; return `next' or `back'."
  (let* ((rows kittymacs-onboard-structural-languages)
         (cursor 0)
         note answer)
    (while (not answer)
      (kittymacs-onboard--show (kittymacs-onboard--render-structural state place cursor note))
      (setq note nil)
      (pcase (kittymacs-onboard--key "y yes, n no, Y or N the rest, RET next, b back, C-g quit: ")
        ((and (or ?y ?n) key)
         (kittymacs-onboard--answer state (nth cursor rows) (if (eql key ?y) 'yes 'no))
         (setq cursor (min (1+ cursor) (1- (length rows)))))
        ((and (or ?Y ?N) key)
         (dolist (row (kittymacs-onboard--unanswered state))
           (kittymacs-onboard--answer state row (if (eql key ?Y) 'yes 'no))))
        ('down (setq cursor (min (1+ cursor) (1- (length rows)))))
        ('up (setq cursor (max (1- cursor) 0)))
        ((or ?\r 'return 'right)
         (if-let* ((open (kittymacs-onboard--unanswered state)))
             (setq note (format "Still open: %s.  Each line needs an answer."
                                (mapconcat #'car open ", ")))
           (setq answer 'next)))
        ((or ?b 'left) (setq answer 'back))))
    answer))

(defun kittymacs-onboard--options-here (state)
  "Return the rows of `kittymacs-onboard-options' that apply in STATE."
  (seq-filter (lambda (row)
                (let ((feature (plist-get (cdr row) :feature)))
                  (or (null feature) (memq feature (kittymacs-onboard--on state)))))
              kittymacs-onboard-options))

(defun kittymacs-onboard--option-source (state option)
  "Return the last setting of OPTION outside the block in STATE, or nil."
  (seq-find (lambda (setting)
              (and (eq (plist-get setting :option) option)
                   (not (eq (plist-get setting :place) 'block))
                   (not (plist-get setting :nested))))
            (reverse (kittymacs-onboard--settings state))))

(defun kittymacs-onboard--option-shown (state option)
  "Return what the screen says OPTION is, in STATE."
  (if-let* ((answer (assq option (kittymacs-onboard--options state))))
      (kittymacs-onboard--print (cdr answer))
    (if-let* ((source (kittymacs-onboard--option-source state option)))
        (format "set in %s" (file-name-nondirectory (plist-get source :file)))
      "the default")))

(defun kittymacs-onboard--render-options (state place cursor note)
  "Return the options screen for STATE: PLACE, row CURSOR and NOTE."
  (let ((index -1))
    (concat
     (kittymacs-onboard--screen-title place "A few settings")
     "\nSPC changes a line.  d puts it back to the default.  n, p move.  RET next.  b back.  C-g quit.\n"
     (if note (concat note "\n") "")
     "\nEvery line may stay as it is.\n\n"
     (mapconcat (lambda (row)
                  (setq index (1+ index))
                  (format "%s%s\n      %s: %s\n"
                          (if (= index cursor) "> " "  ")
                          (plist-get (cdr row) :label)
                          (car row)
                          (kittymacs-onboard--option-shown state (car row))))
                (kittymacs-onboard--options-here state) ""))))

(defun kittymacs-onboard--change-option (state row)
  "Ask for a new value of the option in ROW, and record it in STATE."
  (let* ((option (car row))
         (type (plist-get (cdr row) :type))
         (current (cdr (assq option (kittymacs-onboard--options state))))
         (value (if (eq type 'boolean)
                    (not current)
                  (string-trim
                   (kittymacs-onboard--read-text
                    (format "%s: " (plist-get (cdr row) :label))
                    (and (stringp current) current))))))
    (cond
     ((equal value "") nil)
     (t (setf (alist-get option (kittymacs-onboard--options state))
              (if (eq type 'directory) (file-name-as-directory value) value))))))

(defun kittymacs-onboard--options-screen (state place)
  "Ask about the options in STATE; return `next' or `back'."
  (let ((cursor 0) note answer)
    (while (not answer)
      (let ((rows (kittymacs-onboard--options-here state)))
        (kittymacs-onboard--show (kittymacs-onboard--render-options state place cursor note))
        (setq note nil)
        (pcase (kittymacs-onboard--key "SPC change, d default, n/p move, RET next, b back, C-g quit: ")
          ((or ?n 'down) (setq cursor (min (1+ cursor) (1- (length rows)))))
          ((or ?p 'up) (setq cursor (max (1- cursor) 0)))
          (?\s (kittymacs-onboard--change-option state (nth cursor rows)))
          (?d (setf (kittymacs-onboard--options state)
                    (assq-delete-all (car (nth cursor rows))
                                     (kittymacs-onboard--options state))))
          ((or ?\r 'return 'right) (setq answer 'next))
          ((or ?b 'left) (setq answer 'back)))))
    answer))
(defconst kittymacs-onboard-backend-transports '(ssh sshx docker)
  "The transports the form offers on every machine.")

(defconst kittymacs-onboard-wsl-transports '(wsl wsl-rpc)
  "The transports the form also offers on native Windows with a distribution.")

(defun kittymacs-onboard--read-distributions ()
  "Return the distributions to offer: only native Windows has any."
  (and (eq system-type 'windows-nt) (kittymacs-wsl-distributions)))

(defun kittymacs-onboard--transports (state)
  "Return the transports the form offers in STATE, the default first."
  (if (kittymacs-onboard--distributions state)
      (append kittymacs-onboard-wsl-transports kittymacs-onboard-backend-transports)
    kittymacs-onboard-backend-transports))

(defun kittymacs-onboard--transport-of (plist)
  "Return the transport of the backend PLIST, with the remote chapter's default."
  (or (plist-get plist :transport) 'ssh))

(defun kittymacs-onboard--backends-well-formed-p (value)
  "Return non-nil if VALUE has the shape `kittymacs-backends' takes."
  (and (proper-list-p value)
       (seq-every-p (lambda (entry)
                      (and (consp entry)
                           (stringp (car entry))
                           (proper-list-p (cdr entry))
                           (cl-evenp (length (cdr entry)))))
                    value)))

(defun kittymacs-onboard--backend-settings (state)
  "Return the settings of `kittymacs-backends' in STATE."
  (seq-filter (lambda (setting) (eq (plist-get setting :option) 'kittymacs-backends))
              (kittymacs-onboard--settings state)))

(defun kittymacs-onboard--backend-setting-opaque-p (setting)
  "Return non-nil if only running SETTING could tell what it makes the backends."
  (or (plist-get setting :nested)
      (let ((known (kittymacs-onboard--literal (plist-get setting :value))))
        (not (and known (kittymacs-onboard--backends-well-formed-p (car known)))))))

(defun kittymacs-onboard--backends-lock (state)
  "Return the setting that keeps this screen from changing the backends in STATE."
  (seq-find (lambda (setting)
              (or (eq (plist-get setting :place) 'after)
                  (kittymacs-onboard--backend-setting-opaque-p setting)))
            (kittymacs-onboard--backend-settings state)))

(defun kittymacs-onboard--backends-value (settings)
  "Return the backends that SETTINGS, read in order, come to."
  (alist-get 'kittymacs-backends (kittymacs-onboard--final-values settings (list nil))))

(defun kittymacs-onboard--backends-outside (state)
  "Return the backends this machine would have in STATE without the block."
  (kittymacs-onboard--backends-value
   (seq-remove (lambda (setting) (eq (plist-get setting :place) 'block))
               (kittymacs-onboard--backend-settings state))))

(defun kittymacs-onboard--backends-form (state)
  "Return the form the block holds for the backends in STATE, or nil."
  (if (kittymacs-onboard--backends-lock state)
      (when-let* ((held (seq-find (lambda (setting)
                                    (and (eq (plist-get setting :place) 'block)
                                         (not (plist-get setting :nested))))
                                  (reverse (kittymacs-onboard--backend-settings state)))))
        (list 'setopt 'kittymacs-backends (plist-get held :value)))
    (unless (equal (kittymacs-onboard--backends state)
                   (kittymacs-onboard--backends-outside state))
      (kittymacs-onboard--setopt 'kittymacs-backends (kittymacs-onboard--backends state)))))

(defun kittymacs-onboard--transport-label (transport)
  "Return TRANSPORT for a person, labelled from the catalogue."
  (format "%s%s" transport
          (if (kittymacs-features--property transport :experimental) " (experimental)" "")))

(defun kittymacs-onboard--backend-line (entry)
  "Return the line that describes the backend ENTRY."
  (format "%s: %s, %s, %s"
          (car entry)
          (kittymacs-onboard--transport-label (kittymacs-onboard--transport-of (cdr entry)))
          (or (plist-get (cdr entry) :host) "no host")
          (or (plist-get (cdr entry) :root) "no directory")))

(defun kittymacs-onboard--backends-source (state)
  "Return what the screen says about a setting of the backends outside the block."
  (let ((lock (kittymacs-onboard--backends-lock state))
        (outside (seq-find (lambda (setting) (not (eq (plist-get setting :place) 'block)))
                           (reverse (kittymacs-onboard--backend-settings state)))))
    (cond
     ((and lock (kittymacs-onboard--backend-setting-opaque-p lock))
      (format "%s line %d sets this in a way only running it could tell, so onboarding leaves it alone.  Edit it there.\n\n"
              (file-name-nondirectory (plist-get lock :file)) (plist-get lock :line)))
     (lock
      (format "%s line %d sets this after the block, so it beats anything here.  Edit it there.\n\n"
              (file-name-nondirectory (plist-get lock :file)) (plist-get lock :line)))
     (outside
      (format "%s line %d sets these, and they stay as they are unless you change them here.\nA change writes the whole list to the block, which then beats that line.\n\n"
              (file-name-nondirectory (plist-get outside :file)) (plist-get outside :line)))
     (t ""))))

(defun kittymacs-onboard--render-backends (state place cursor note)
  "Return the backends screen for STATE: PLACE, row CURSOR and NOTE."
  (let ((lock (kittymacs-onboard--backends-lock state))
        (backends (kittymacs-onboard--backends state))
        (index -1))
    (concat
     (kittymacs-onboard--screen-title place "A backend, if you work on another machine")
     (if lock
         "\nRET next.  b back.  C-g quit.\n"
       "\nSPC changes a line.  d removes it.  n, p move.  RET next.  b back.  C-g quit.\n")
     (if note (concat note "\n") "")
     "\nA backend is a machine that runs your programs while this Emacs is the screen.\n"
     "SPC o b opens its project, and SPC o B says what it has.\n"
     "This is optional: RET goes on, and leaves the backends as they are.\n\n"
     (kittymacs-onboard--backends-source state)
     (mapconcat (lambda (entry)
                  (setq index (1+ index))
                  (format "%s%s\n"
                          (if (and (not lock) (= index cursor)) "> " "  ")
                          (kittymacs-onboard--backend-line entry)))
                backends "")
     (if lock ""
       (format "%sAdd a backend\n" (if (= cursor (length backends)) "> " "  "))))))

(defconst kittymacs-onboard--backend-fields '(name transport host root)
  "The lines of the form, in order.")

(defun kittymacs-onboard--render-backend-form (state place entry cursor note)
  "Return the form for ENTRY in STATE: PLACE, row CURSOR and NOTE."
  (let* ((plist (cdr entry))
         (transport (kittymacs-onboard--transport-of plist))
         (distributions (and (memq transport kittymacs-onboard-wsl-transports)
                             (kittymacs-onboard--distributions state)))
         (untested (kittymacs-features--property transport :experimental))
         (index -1))
    (concat
     (kittymacs-onboard--screen-title place "A backend, if you work on another machine")
     "\nSPC changes a line.  n, p move.  RET keeps this backend.  b back, without it.  C-g quit.\n"
     (if note (concat note "\n") "")
     "\n"
     (mapconcat
      (pcase-lambda (`(,label ,value ,help))
        (setq index (1+ index))
        (format "%s%s: %s\n      %s\n" (if (= index cursor) "> " "  ") label (or value "") help))
      (list
       (list "Name" (car entry) "What SPC o b and SPC o B ask for.")
       (list "Transport" transport
             (format "SPC takes the next of: %s."
                     (mapconcat #'kittymacs-onboard--transport-label
                                (kittymacs-onboard--transports state) ", ")))
       (list "Host" (plist-get plist :host)
             (if distributions
                 (format "SPC takes the next of: %s." (string-join distributions ", "))
               "As Tramp takes it: build, me@build or build#2222."))
       (list "Directory" (plist-get plist :root)
             "The project's directory there, such as ~/src/project/."))
      "")
     (if untested (format "\nExperimental: %s\n" untested) ""))))

(defun kittymacs-onboard--new-backend (state)
  "Return a backend for the form in STATE, with only its defaults filled in."
  (let ((transport (car (kittymacs-onboard--transports state))))
    (list nil
          :transport transport
          :host (and (memq transport kittymacs-onboard-wsl-transports)
                     (car (kittymacs-onboard--distributions state)))
          :root nil)))

(defun kittymacs-onboard--next-in (items current)
  "Return what follows CURRENT in ITEMS, or the first of them."
  (or (cadr (member current items)) (car items)))

(defun kittymacs-onboard--typed (label current)
  "Return a line typed after LABEL, starting from CURRENT, or nil for none."
  (let ((value (string-trim (kittymacs-onboard--read-text (format "%s: " label) current))))
    (and (not (string-empty-p value)) value)))

(defun kittymacs-onboard--with-transport (state plist transport)
  "Return PLIST on TRANSPORT in STATE, without a host that only made sense before."
  (let* ((distributions (kittymacs-onboard--distributions state))
         (host (plist-get plist :host))
         (wsl (and (memq transport kittymacs-onboard-wsl-transports) distributions)))
    (plist-put (plist-put plist :transport transport)
               :host (cond ((and wsl (not (member host distributions))) (car distributions))
                           ((and (not wsl) (member host distributions)) nil)
                           (t host)))))

(defun kittymacs-onboard--change-field (state entry field)
  "Return ENTRY in STATE with FIELD changed, asking for it."
  (let* ((name (car entry))
         (plist (copy-sequence (cdr entry)))
         (transport (kittymacs-onboard--transport-of plist))
         (distributions (and (memq transport kittymacs-onboard-wsl-transports)
                             (kittymacs-onboard--distributions state))))
    (pcase field
      ('name (cons (kittymacs-onboard--typed "Name" name) plist))
      ('transport
       (cons name (kittymacs-onboard--with-transport
                   state plist
                   (kittymacs-onboard--next-in (kittymacs-onboard--transports state) transport))))
      ('host
       (cons name (plist-put plist :host
                             (if distributions
                                 (kittymacs-onboard--next-in distributions (plist-get plist :host))
                               (kittymacs-onboard--typed "Host" (plist-get plist :host))))))
      ('root
       (let ((root (kittymacs-onboard--typed "Directory" (plist-get plist :root))))
         (cons name (plist-put plist :root (and root (file-name-as-directory root)))))))))

(defun kittymacs-onboard--backend-problem (state old entry)
  "Return why ENTRY cannot take the place of OLD in STATE, or nil."
  (let ((missing (append (unless (car entry) '("a name"))
                         (unless (plist-get (cdr entry) :host) '("a host"))
                         (unless (plist-get (cdr entry) :root) '("a directory")))))
    (cond
     (missing (format "This backend still needs %s.  b goes back without it."
                      (string-join missing " and ")))
     ((assoc (car entry) (remq old (kittymacs-onboard--backends state)))
      (format "There is already a backend called %s." (car entry))))))

(defun kittymacs-onboard--keep-backend (state old entry)
  "Put ENTRY in the place of OLD in STATE; return what else that moved, or nil."
  (setf (kittymacs-onboard--backends state)
        (if old
            (cl-substitute entry old (kittymacs-onboard--backends state) :test #'eq)
          (append (kittymacs-onboard--backends state) (list entry))))
  (when (and (eq (kittymacs-onboard--transport-of (cdr entry)) 'wsl-rpc)
             (not (eq (kittymacs-onboard--transport-of (cdr old)) 'wsl-rpc))
             (not (memq 'wsl-rpc (kittymacs-onboard--on state))))
    (kittymacs-onboard--toggle state 'wsl-rpc)))

(defun kittymacs-onboard--backend-form (state place old)
  "Ask about one backend in STATE, the backend OLD or a new one.
Return what keeping it moved, or nil."
  (let ((entry (or old (kittymacs-onboard--new-backend state)))
        (last (1- (length kittymacs-onboard--backend-fields)))
        (cursor 0)
        note answer)
    (while (not answer)
      (kittymacs-onboard--show
       (kittymacs-onboard--render-backend-form state place entry cursor note))
      (setq note nil)
      (pcase (kittymacs-onboard--key "SPC change, n/p move, RET keep, b back, C-g quit: ")
        ((or ?n 'down) (setq cursor (min (1+ cursor) last)))
        ((or ?p 'up) (setq cursor (max (1- cursor) 0)))
        (?\s (setq entry (kittymacs-onboard--change-field
                          state entry (nth cursor kittymacs-onboard--backend-fields))))
        ((or ?\r 'return 'right)
         (if-let* ((problem (kittymacs-onboard--backend-problem state old entry)))
             (setq note problem)
           (setq answer 'keep)))
        ((or ?b 'left) (setq answer 'cancel))))
    (when (eq answer 'keep)
      (kittymacs-onboard--keep-backend state old entry))))

(defun kittymacs-onboard--backends-screen (state place)
  "Ask about the backends in STATE; return `next' or `back'."
  (let ((cursor 0) note answer)
    (while (not answer)
      (let* ((lock (kittymacs-onboard--backends-lock state))
             (backends (kittymacs-onboard--backends state))
             (entry (nth cursor backends)))
        (kittymacs-onboard--show (kittymacs-onboard--render-backends state place cursor note))
        (setq note nil)
        (pcase (kittymacs-onboard--key "SPC change, d remove, n/p move, RET next, b back, C-g quit: ")
          ((or ?n 'down) (setq cursor (min (1+ cursor) (length backends))))
          ((or ?p 'up) (setq cursor (max (1- cursor) 0)))
          (?\s (unless lock
                 (setq note (kittymacs-onboard--backend-form state place entry))))
          (?d (when (and entry (not lock))
                (setf (kittymacs-onboard--backends state) (remq entry backends))))
          ((or ?\r 'return 'right) (setq answer 'next))
          ((or ?b 'left) (setq answer 'back)))))
    answer))
(defun kittymacs-onboard--target-problem (file)
  "Return why FILE, or the file a link there points at, cannot be written; or nil."
  (let* ((real (file-truename file))
         (directory (file-name-directory real))
         (store (file-truename kittymacs-onboard-store-directory)))
    (cond
     ((string-prefix-p store real)
      (format "%s is in the Nix store, which cannot be changed; use the Nix options instead." real))
     ((file-directory-p real)
      (format "%s is a directory." real))
     ((and (file-exists-p real) (not (file-writable-p real)))
      (format "%s is not writable." real))
     ((not (file-directory-p directory))
      (format "%s does not exist." directory))
     ((not (file-writable-p directory))
      (format "%s is not writable, and a safe replacement needs to write there." directory)))))

(defun kittymacs-onboard--meets-block-p (state option)
  "Return non-nil if a setting of OPTION elsewhere competes with the block in STATE.
The backends compete only while the block holds them."
  (and (memq option (kittymacs-onboard--written-options))
       (or (not (eq option 'kittymacs-backends))
           (kittymacs-onboard--backends-form state))))

(defun kittymacs-onboard--later-settings (state)
  "Return the settings of what onboarding writes that follow the block in STATE."
  (seq-filter (lambda (setting)
                (and (eq (plist-get setting :place) 'after)
                     (kittymacs-onboard--meets-block-p state (plist-get setting :option))))
              (kittymacs-onboard--settings state)))

(defun kittymacs-onboard--earlier-settings (state)
  "Return the settings of what onboarding writes that the block in STATE beats."
  (seq-filter (lambda (setting)
                (and (memq (plist-get setting :place) '(before host))
                     (kittymacs-onboard--meets-block-p state (plist-get setting :option))))
              (kittymacs-onboard--settings state)))

(defun kittymacs-onboard--setting-line (setting)
  "Return where SETTING is, and what it sets, for a person."
  (format "  %s line %d: %s"
          (file-name-nondirectory (plist-get setting :file))
          (plist-get setting :line)
          (plist-get setting :option)))

(defun kittymacs-onboard--block-lines (bytes)
  "Return the lines of the block in BYTES, without its markers."
  (let ((block (cadr (kittymacs-onboard--split bytes kittymacs-onboard-private-file))))
    (and block
         (butlast (cdr (split-string (kittymacs-onboard--text block) "\n"))))))

(defun kittymacs-onboard--diff (old new)
  "Return lines showing how the lists of lines OLD and NEW differ."
  (concat
   (mapconcat (lambda (line) (format "- %s\n" line)) (seq-difference old new) "")
   (mapconcat (lambda (line) (format "%s %s\n" (if (member line old) " " "+") line)) new "")))

(defun kittymacs-onboard--backend-warning (state)
  "Return what the preview warns about the `wsl-rpc' feature and backends in STATE."
  (let ((on (memq 'wsl-rpc (kittymacs-onboard--on state)))
        (named (seq-some (lambda (entry)
                           (eq (kittymacs-onboard--transport-of (cdr entry)) 'wsl-rpc))
                         (kittymacs-onboard--backends state))))
    (cond
     ((seq-some #'kittymacs-onboard--backend-setting-opaque-p
                (kittymacs-onboard--backend-settings state))
      nil)
     ((and on (not named))
      "Warning: the wsl-rpc feature is on, and no backend uses it, so it would install and do nothing.  b goes back: name a backend over wsl-rpc, or turn it off.\n\n")
     ((and named (not on) (kittymacs-features--applies-p 'wsl-rpc))
      "Warning: a backend uses wsl-rpc, and that feature is off, so connecting to it would fail.  b goes back: turn it on, or change the backend.\n\n"))))

(defun kittymacs-onboard--render-preview (state place)
  "Return the last screen for STATE, with PLACE as in the title."
  (let* ((file kittymacs-onboard-private-file)
         (forms (kittymacs-onboard--block-forms state))
         (real (file-truename file))
         (old (and (file-exists-p real) (kittymacs-onboard--file-bytes real)))
         (problem (kittymacs-onboard--target-problem file))
         (on (kittymacs-onboard--on state))
         (before (kittymacs-onboard--before state))
         (later (kittymacs-onboard--later-settings state))
         (earlier (kittymacs-onboard--earlier-settings state)))
    (concat
     (kittymacs-onboard--screen-title place "What changes")
     "\nw writes.  n, p scroll.  b back.  C-g quit, writing nothing.\n"
     "A change takes effect at the next start, which installs what the features need.\n\n"
     (kittymacs-onboard--backend-warning state)
     (if problem
         (format "Onboarding cannot write this: %s\n\n" problem)
       (format "%s %s, in the block between its two marker lines.\nEverything else in the file stays as it is%s\n\n"
               (if old "Changes" "Creates") real
               (if old (format ", and a copy goes to %s~." (file-name-nondirectory real)) ".")))
     (kittymacs-onboard--diff
      (and old (kittymacs-onboard--block-lines old))
      (mapcar #'kittymacs-onboard--print forms))
     (format "\nFeatures that move, compared with what this machine has now.\nOn: %s.\nOff: %s.\n"
             (kittymacs-onboard--names (seq-difference on before))
             (kittymacs-onboard--names (seq-difference before on)))
     (if later
         (format "\nThese come after the block, so they beat it.  Edit them by hand if you want the block to count:\n%s\n"
                 (mapconcat #'kittymacs-onboard--setting-line later "\n"))
       "")
     (if earlier
         (format "\nThese come before the block, so the block beats them:\n%s\n"
                 (mapconcat #'kittymacs-onboard--setting-line earlier "\n"))
       "")
     (if (kittymacs-onboard--nix-host-p)
         (format "\nThe same answer as Nix options, if you would rather keep it there:\n%s"
                 (kittymacs-onboard--nix-text state))
       ""))))

(defun kittymacs-onboard--scroll (direction)
  "Scroll the screen with DIRECTION, a function, stopping quietly at either end."
  (unless noninteractive
    (ignore-errors (funcall direction 8))
    (redisplay)))

(defun kittymacs-onboard--preview-screen (state place)
  "Show what would change in STATE; return `write' or `back'."
  (kittymacs-onboard--show (kittymacs-onboard--render-preview state place))
  (let (answer)
    (while (not answer)
      (pcase (kittymacs-onboard--key "w write, n/p scroll, b back, C-g quit: ")
        (?w (setq answer 'write))
        ((or ?n 'down) (kittymacs-onboard--scroll #'scroll-up))
        ((or ?p 'up) (kittymacs-onboard--scroll #'scroll-down))
        ((or ?b 'left) (setq answer 'back))))
    answer))
(defun kittymacs-onboard--write-atomically (file bytes modes)
  "Replace FILE with BYTES and the file MODES, all at once."
  (let ((temporary (make-temp-file (expand-file-name ".private-onboarding-"
                                                     (file-name-directory file)))))
    (unwind-protect
        (let ((coding-system-for-write 'no-conversion)
              (write-region-annotate-functions nil)
              (write-region-post-annotation-function nil))
          (write-region bytes nil temporary nil 'silent)
          (set-file-modes temporary modes)
          (rename-file temporary file t))
      (when (file-exists-p temporary)
        (delete-file temporary)))))

(defun kittymacs-onboard--write (file forms)
  "Put FORMS in the block of FILE.  Return the backup's name, or t for a new file.
Return nil when the file already said this.  Refuse rather than guess."
  (let ((real (file-truename file)))
    (when-let* ((problem (kittymacs-onboard--target-problem file)))
      (kittymacs-onboard--refuse "%s" problem))
    (let* ((exists (file-exists-p real))
           (old (and exists (kittymacs-onboard--file-bytes real)))
           (new (kittymacs-onboard--proposed old forms file)))
      (unless (equal old new)
        (condition-case err
            (let ((modes (if exists (file-modes real) (logand #o666 (default-file-modes))))
                  (backup (concat real "~")))
              (when exists
                (kittymacs-onboard--write-atomically backup old modes))
              (kittymacs-onboard--write-atomically real new modes)
              (if exists backup t))
          (file-error
           (kittymacs-onboard--refuse "%s could not be written (%s)."
                                      real (error-message-string err))))))))
(defun kittymacs-onboard--can-ask-p ()
  "Return non-nil if this Emacs can draw the screens and read keys."
  (not noninteractive))

(defun kittymacs-onboard--by-hand ()
  "Return what to do where the screens cannot run."
  (format "kittymacs onboarding needs a terminal it can draw in, and this is not one.
Set the options by hand instead, in %s:

  (setopt kittymacs-profile 'minimal)             ; or 'full
  (setopt kittymacs-features '(jump lang-nix))    ; beyond the profile
  (setopt kittymacs-features-excluded '(agents))  ; out of it

literate/20-catalogue.org names every feature, and lisp/private.example.el shows the other options.
A change takes effect at the next start."
          kittymacs-onboard-private-file))

(defun kittymacs-onboard--profile-without-choice ()
  "Return the profile a start here would use with no choice, without starting.
Under `-Q' nothing has looked for packages or named these directories."
  (require 'package)
  (let ((kittymacs-lisp-dir (file-name-directory kittymacs-onboard-private-file))
        (kittymacs-var-dir kittymacs-onboard-var-directory)
        (package-user-dir (expand-file-name "elpa/" kittymacs-onboard-var-directory))
        (package-alist nil))
    (package-load-all-descriptors)
    (if (kittymacs-features--kept-on-full-p) 'full kittymacs-default-profile)))

(defun kittymacs-onboard--initial-state ()
  "Return the state for what this machine has chosen already.
Refuse if `private.el' cannot be understood."
  (let* ((notes (list nil))
         (private (kittymacs-onboard--private-settings kittymacs-onboard-private-file))
         (settings (append (kittymacs-onboard--host-settings notes) private))
         (values (kittymacs-onboard--final-values settings notes))
         (profile (alist-get 'kittymacs-profile values))
         (profile (if (memq profile '(minimal full)) profile
                    (kittymacs-onboard--profile-without-choice)))
         (older (kittymacs-onboard--older-selection values))
         (modes (let ((found (assq 'kittymacs-structural-editing-modes values)))
                  (and found (listp (cdr found)) found)))
         (known-modes (seq-mapcat (lambda (row) (plist-get (cdr row) :modes))
                                  kittymacs-onboard-structural-languages))
         (in-block (seq-filter (lambda (setting) (eq (plist-get setting :place) 'block)) private))
         (backends (cdr (assq 'kittymacs-backends values)))
         (state (kittymacs-onboard--make-state
                 :profile profile
                 :backends (and (kittymacs-onboard--backends-well-formed-p backends) backends)
                 :distributions (kittymacs-onboard--read-distributions)
                 :selected (kittymacs-onboard--known-names
                            (alist-get 'kittymacs-features values) 'kittymacs-features notes)
                 :excluded (kittymacs-onboard--known-names
                            (alist-get 'kittymacs-features-excluded values)
                            'kittymacs-features-excluded notes)
                 :older-selected (car older)
                 :older-excluded (cdr older)
                 :answers (and modes (kittymacs-onboard--answers-from (cdr modes)))
                 :extra-modes (and modes (seq-difference (cdr modes) known-modes))
                 :modes-in-block (seq-some (lambda (setting)
                                             (eq (plist-get setting :option)
                                                 'kittymacs-structural-editing-modes))
                                           in-block)
                 :options (seq-keep (lambda (row)
                                      (when-let* ((setting (seq-find
                                                            (lambda (setting)
                                                              (eq (plist-get setting :option)
                                                                  (car row)))
                                                            (reverse in-block)))
                                                  (known (kittymacs-onboard--literal
                                                          (plist-get setting :value))))
                                        (cons (car row) (car known))))
                                    kittymacs-onboard-options)
                 :settings settings)))
    (setf (kittymacs-onboard--before state) (kittymacs-onboard--on state))
    (when-let* ((problem (kittymacs-onboard--target-problem kittymacs-onboard-private-file)))
      (push (format "Onboarding cannot write this: %s  The screens still work, and end in the matching Nix options."
                    problem)
            (car notes)))
    (setf (kittymacs-onboard--notes state) (car notes))
    state))

(defun kittymacs-onboard--screens (state)
  "Return the screens for STATE, in order."
  (append
   '((profile))
   (mapcar (lambda (group) (list 'group group)) (kittymacs-onboard--groups))
   (and (kittymacs-onboard--structural-on-p state) '((structural)))
   '((backends) (options) (preview))))

(defun kittymacs-onboard--ask (state)
  "Walk the screens for STATE, until the person writes or quits."
  (let ((index 0) done)
    (while (not done)
      (let* ((screens (kittymacs-onboard--screens state))
             (place (cons (1+ index) (length screens)))
             (answer (pcase (nth index screens)
                       ('(profile) (kittymacs-onboard--profile-screen state place))
                       (`(group ,group) (kittymacs-onboard--features-screen state group place))
                       ('(structural) (kittymacs-onboard--structural-screen state place))
                       ('(backends) (kittymacs-onboard--backends-screen state place))
                       ('(options) (kittymacs-onboard--options-screen state place))
                       ('(preview) (kittymacs-onboard--preview-screen state place)))))
        (pcase answer
          ('next (setq index (1+ index)))
          ('back (setq index (max 0 (1- index))))
          ('write (setq done t)))))))

(defun kittymacs-onboard--backend-next (state)
  "Return what to do next about the backends the answers in STATE added or changed."
  (mapconcat
   (lambda (entry)
     (concat
      (format "After that start, SPC o B and then %s says what that machine has and what it is missing.\n"
              (car entry))
      (if (eq (kittymacs-onboard--transport-of (cdr entry)) 'wsl-rpc)
          (format "%s also needs a server in the distribution, which nothing installs for you: that report prints the line to run.\n"
                  (car entry))
        "")))
   (seq-difference (kittymacs-onboard--backends state)
                   (kittymacs-onboard--backends-value (kittymacs-onboard--backend-settings state)))
   ""))

(defun kittymacs-onboard--result-text (state written)
  "Return what to say after the answers in STATE; WRITTEN is what writing returned."
  (concat
   (if written
       (format "Wrote %s%s.\n"
               kittymacs-onboard-private-file
               (if (stringp written) (format ", keeping the old one as %s" written) ""))
     (format "%s already says this, so nothing changed.\n" kittymacs-onboard-private-file))
   "A change takes effect at the next start, which installs what the features need.\n"
   (kittymacs-onboard--backend-next state)
   (if-let* ((later (kittymacs-onboard--later-settings state)))
       (format "These come after the block, so they beat it:\n%s\n"
               (mapconcat #'kittymacs-onboard--setting-line later "\n"))
     "")
   (if (kittymacs-onboard--nix-host-p)
       (format "\nThe same answer as Nix options:\n%s" (kittymacs-onboard--nix-text state))
     "")))

(defun kittymacs-onboard--run ()
  "Ask, write, and return the exit status and what to say about it, as a pair."
  (condition-case err
      (if (not (kittymacs-onboard--can-ask-p))
          (cons 3 (kittymacs-onboard--by-hand))
        (let ((state (kittymacs-onboard--initial-state)))
          (kittymacs-onboard--ask state)
          (cons 0 (kittymacs-onboard--result-text
                   state
                   (kittymacs-onboard--write kittymacs-onboard-private-file
                                             (kittymacs-onboard--block-forms state))))))
    (quit (cons 2 "Quit, and wrote nothing."))
    (kittymacs-onboard-refused
     (cons 1 (format "Refused, and wrote nothing: %s" (cadr err))))
    (error
     (cons 1 (format "Failed, and wrote nothing: %s" (error-message-string err))))))

(defun kittymacs-onboard-main ()
  "Run onboarding from a command line, and exit with its status."
  (setq auto-save-list-file-prefix nil)
  (unless noninteractive
    (menu-bar-mode -1))
  (pcase-let ((`(,status . ,text) (kittymacs-onboard--run)))
    (unless (or noninteractive (display-graphic-p))
      (ignore-errors (suspend-tty)))
    (princ (concat text "\n") (if noninteractive t #'external-debugging-output))
    (kill-emacs status)))

(defun kittymacs-onboard ()
  "Choose what kittymacs installs, and write it to `private.el'.
This Emacs keeps running as it is: a change takes effect at the next start."
  (interactive)
  (let ((text (cdr (save-window-excursion (kittymacs-onboard--run)))))
    (kittymacs-onboard--show text)
    (pop-to-buffer-same-window kittymacs-onboard--buffer-name)
    (message "%s" (car (split-string text "\n")))))

(provide 'kittymacs-onboard)
;;; kittymacs-onboard.el ends here
