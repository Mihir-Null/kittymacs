;;; bench.el --- Measure what kittymacs costs -*- lexical-binding: t; -*-
;; Run from any directory:
;;   emacs -Q --batch -l /path/to/tools/bench.el -- --size
;;   emacs -Q --batch -l /path/to/tools/bench.el -- --startup
;;   emacs -Q --batch -l /path/to/tools/bench.el -- --check [BASE]
;; Add --write to record the measured counts as the budget in tests/budgets.eld.
;; (`just size', `just bench' and `just budget-check' do exactly this.)
;;
;; --size and --startup report, and exit 0 on a measurement that completes.
;; --check exits 1 when a budget rose with no stated reason.  See "Measuring" in
;; literate/80-maintenance.org.
(require 'cl-lib)
(require 'package)
(require 'seq)

(defconst kittymacs-bench-root
  (file-name-directory (directory-file-name (file-name-directory load-file-name))))
(defvar kittymacs-bench-library-only nil)

(defconst kittymacs-bench-discarded 3
  "Runs thrown away first in each configuration, while disk caches warm up.")
(defconst kittymacs-bench-settle 2
  "Seconds a measured Emacs waits after first idle, for deferred timers to run.")
(defconst kittymacs-bench-drain-timeout 1800
  "Seconds the warm-up run may take to compile what startup loads.")
(defconst kittymacs-bench-run-timeout 300
  "Seconds one measured run may take.")

(defun kittymacs-bench--path (&rest parts)
  "Return PARTS, joined, under the root of this checkout."
  (expand-file-name (string-join parts "/") kittymacs-bench-root))

;;; Statistics

(defun kittymacs-bench--median (numbers)
  "Return the median of the non-empty list NUMBERS."
  (let* ((sorted (sort (copy-sequence numbers) #'<))
         (count (length sorted))
         (middle (/ count 2)))
    (if (cl-oddp count)
        (float (nth middle sorted))
      (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2.0))))

(defun kittymacs-bench--p90 (numbers)
  "Return the nearest-rank 90th percentile of the non-empty list NUMBERS."
  (let ((sorted (sort (copy-sequence numbers) #'<)))
    (float (nth (1- (ceiling (* 0.9 (length sorted)))) sorted))))

;;; Size

(defun kittymacs-bench--forms (file)
  "Every top-level form in FILE, read but not evaluated."
  (with-temp-buffer
    (insert-file-contents file)
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun kittymacs-bench--conses (form)
  "Return the number of cons cells in FORM.
Unlike lines, this does not fall when code is joined onto fewer lines."
  (let ((count 0))
    (while (consp form)
      (setq count (+ count 1 (kittymacs-bench--conses (car form)))
            form (cdr form)))
    count))

(defun kittymacs-bench--declared (form)
  "Names of the `use-package' forms anywhere in FORM that install a package.
Those with `:ensure t' or `:vc'.  Follows `kittymacs-startup-test--ensured' in
tests/kittymacs-startup-tests.el, which leaves out `:vc' for the Nix list."
  (when (consp form)
    (append (and (eq (car form) 'use-package)
                 (symbolp (cadr form))
                 (or (eq (cadr (memq :ensure (cddr form))) t)
                     (memq :vc (cddr form)))
                 (list (cadr form)))
            (let (names)
              (while (consp form)
                (setq names (append names (kittymacs-bench--declared (car form)))
                      form (cdr form)))
              names))))

(defun kittymacs-bench--line-count (file)
  "Return the number of lines in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (count-lines (point-min) (point-max))))

(defun kittymacs-bench--elisp-files ()
  "Every Lisp file that startup may load: `private.el' is the user's, not ours."
  (append (list (kittymacs-bench--path "early-init.el")
                (kittymacs-bench--path "init.el"))
          (seq-remove (lambda (file) (string-suffix-p "/private.el" file))
                      (directory-files-recursively (kittymacs-bench--path "lisp")
                                                   "\\.el\\'"))))

(defun kittymacs-bench--org-files ()
  "Every chapter: a target stated for the literate source compares with these."
  (directory-files-recursively (kittymacs-bench--path "literate") "\\.org\\'"))

(defun kittymacs-bench--prose-files ()
  "Every page of prose: moving text between these changes no total."
  (append (list (kittymacs-bench--path "ARCHITECTURE.md")
                (kittymacs-bench--path "README.md"))
          (kittymacs-bench--org-files)))

(defun kittymacs-bench--metric (&rest parts)
  "Return the metric named by joining PARTS."
  (intern (string-join parts "/")))

(defun kittymacs-bench--declared-packages ()
  "Every package a module declares, in any gate, by name."
  (seq-uniq (seq-mapcat (lambda (file)
                          (seq-mapcat #'kittymacs-bench--declared
                                      (kittymacs-bench--forms file)))
                        (kittymacs-bench--elisp-files))))

;;; What the default profile loads

(defun kittymacs-bench--default-features ()
  "Return the features the default profile turns on, read from the catalogue."
  (let ((load-path (cons (kittymacs-bench--path "lisp") load-path)))
    (require 'kittymacs-features))
  (funcall 'kittymacs-features--in-profile (symbol-value 'kittymacs-default-profile)))

(defun kittymacs-bench--modules-in (form features)
  "Return the modules FORM loads while it runs at top level, with FEATURES on.
A form that only defines something loads nothing until it is called, so this
looks inside the forms that run as they load, and past a gate only if it is on."
  (pcase form
    ((or `(require ',module) `(kittymacs-require-module ',module))
     (and (symbolp module)
          (file-exists-p (kittymacs-bench--path "lisp" (format "%s.el" module)))
          (list module)))
    (`(when (kittymacs-feature-p ',feature) . ,body)
     (and (memq feature features)
          (seq-mapcat (lambda (inner) (kittymacs-bench--modules-in inner features)) body)))
    (`(,(or 'when 'unless 'progn 'let 'let* 'eval-and-compile 'eval-when-compile) . ,body)
     (seq-mapcat (lambda (inner) (kittymacs-bench--modules-in inner features)) body))))

(defun kittymacs-bench-default-modules ()
  "Return the modules a start on the default profile loads, by their names.
Follows `require' from init.el, the way a start does, without starting."
  (let ((features (kittymacs-bench--default-features))
        (queue (kittymacs-bench--forms (kittymacs-bench--path "init.el")))
        modules)
    (while queue
      (dolist (module (kittymacs-bench--modules-in (pop queue) features))
        (unless (memq module modules)
          (push module modules)
          (setq queue (append queue
                              (kittymacs-bench--forms
                               (kittymacs-bench--path "lisp" (format "%s.el" module))))))))
    modules))

(defun kittymacs-bench--default-files ()
  "Return every Lisp file a start on the default profile loads."
  (append (list (kittymacs-bench--path "early-init.el")
                (kittymacs-bench--path "init.el"))
          (mapcar (lambda (module) (kittymacs-bench--path "lisp" (format "%s.el" module)))
                  (kittymacs-bench-default-modules))))

(defun kittymacs-bench--default-packages ()
  "Return the packages the default profile's features install."
  (seq-uniq (seq-mapcat (lambda (feature)
                          (plist-get (alist-get feature (symbol-value 'kittymacs-catalogue))
                                     :packages))
                        (kittymacs-bench--default-features))))

(defun kittymacs-bench-size ()
  "Return an alist of metric and number for what needs no packages to count."
  (let ((total-lines 0) (total-conses 0) metrics)
    (dolist (file (kittymacs-bench--elisp-files))
      (let ((name (file-name-base file))
            (lines (kittymacs-bench--line-count file))
            (conses (kittymacs-bench--conses (kittymacs-bench--forms file))))
        (setq total-lines (+ total-lines lines)
              total-conses (+ total-conses conses))
        (push (cons (kittymacs-bench--metric "module-lines" name) lines) metrics)
        (push (cons (kittymacs-bench--metric "module-conses" name) conses) metrics)))
    (append
     `((elisp-lines . ,total-lines)
       (elisp-conses . ,total-conses)
       (default-loaded-lines . ,(apply #'+ (mapcar #'kittymacs-bench--line-count
                                                   (kittymacs-bench--default-files))))
       (default-loaded-conses . ,(apply #'+ (mapcar (lambda (file)
                                                      (kittymacs-bench--conses
                                                       (kittymacs-bench--forms file)))
                                                    (kittymacs-bench--default-files))))
       (default-packages . ,(length (kittymacs-bench--default-packages)))
       (declared-packages . ,(length (kittymacs-bench--declared-packages)))
       (org-lines . ,(apply #'+ (mapcar #'kittymacs-bench--line-count
                                        (kittymacs-bench--org-files))))
       (prose-lines . ,(apply #'+ (mapcar #'kittymacs-bench--line-count
                                          (kittymacs-bench--prose-files)))))
     (nreverse metrics))))

;;; Dependency closure

(defun kittymacs-bench--closure (roots alist)
  "Return the names reachable from ROOTS through requirements in ALIST.
ALIST has the shape of `package-alist'.  A name it does not hold is left out:
Emacs provides it, or a gate has kept it from being installed."
  (let (seen)
    (while roots
      (let* ((name (pop roots))
             (description (cadr (assq name alist))))
        (when (and description (not (memq name seen)))
          (push name seen)
          (setq roots (append (mapcar #'car (package-desc-reqs description)) roots)))))
    seen))

(defun kittymacs-bench--installed-alist ()
  "Return `package-alist' for this checkout's installed packages."
  (let ((package-user-dir (kittymacs-bench--path "var/elpa"))
        (package-directory-list nil)
        (package-alist nil))
    (package-load-all-descriptors)
    package-alist))

;;; Starting Emacs

(defvar kittymacs-bench--samples nil
  "A cons of the sample .el and .org files that measured runs open.")

(defun kittymacs-bench--make-samples (directory)
  "Copy the sample files into DIRECTORY, and return a cons of their names.
Outside the checkout, because its .dir-locals.el makes `emacs -Q' stop and ask
whether to apply them, and neither side should get a project's settings."
  (let ((el (expand-file-name "sample.el" directory))
        (org (expand-file-name "sample.org" directory)))
    (copy-file (kittymacs-bench--path "lisp/kittymacs-ui.el") el)
    (copy-file (kittymacs-bench--path "literate/25-defaults.org") org)
    (cons el org)))

(defun kittymacs-bench--output-tail (text)
  "Return the end of TEXT, the last thing a run printed, on one line."
  (let ((plain (replace-regexp-in-string "[^[:print:]]+" " " text)))
    (substring plain (max 0 (- (length plain) 300)))))

(defun kittymacs-bench--run (arguments &rest options)
  "Start Emacs with ARGUMENTS under a pty, and return the plist its probe wrote.
OPTIONS are the keywords :settle, :drain and :timeout.  Signal an error naming
the exit status and the last output when a run reports nothing."
  (let* ((out (make-temp-file "kittymacs-bench-"))
         (output "")
         (timeout (or (plist-get options :timeout) kittymacs-bench-run-timeout))
         (process-environment
          (append
           (list
            ;; TERM=linux, because an xterm-like TERM makes Emacs query the
            ;; terminal and wait up to `xterm-query-timeout' for a reply that a
            ;; bare pty never sends: two seconds no person pays.
            "TERM=linux"
            (format "KITTYMACS_BENCH_OUT=%s" out)
            (format "KITTYMACS_BENCH_SETTLE=%s" (or (plist-get options :settle) 0))
            (format "KITTYMACS_BENCH_EL=%s" (car kittymacs-bench--samples))
            (format "KITTYMACS_BENCH_ORG=%s" (cdr kittymacs-bench--samples))
            (format "KITTYMACS_BENCH_T0=%.6f" (float-time)))
           (and (plist-get options :drain) (list "KITTYMACS_BENCH_DRAIN=1"))
           ;; The window manager role is not what is measured.
           (list "KITTYMACS_EXWM")
           process-environment))
         (default-directory kittymacs-bench-root)
         (process (make-process
                   :name "kittymacs-bench"
                   :command (append (list (expand-file-name invocation-name invocation-directory))
                                    arguments
                                    (list "-l" (kittymacs-bench--path "tools/bench-probe.el")))
                   :connection-type 'pty
                   :noquery t
                   :filter (lambda (_process text)
                             (setq output (kittymacs-bench--output-tail (concat output text))))
                   :sentinel #'ignore))
         (deadline (+ (float-time) timeout)))
    (set-process-window-size process 40 120)
    (while (and (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05))
    (when (process-live-p process)
      (delete-process process)
      (delete-file out)
      (error "Emacs %S did not report within %d seconds" arguments timeout))
    (let ((report (with-temp-buffer
                    (insert-file-contents out)
                    (delete-file out)
                    (goto-char (point-min))
                    (condition-case nil (read (current-buffer)) (error nil)))))
      (or report
          (error "Emacs %S exited with status %s and no report; it last printed: %s"
                 arguments (process-exit-status process) output)))))

(defvar kittymacs-bench--failures nil
  "Why runs produced no report, newest first.")

(defun kittymacs-bench--attempt (arguments &rest options)
  "Return the report of a run with ARGUMENTS and OPTIONS, or nil if it failed.
A failed run is noted, not fatal: one Emacs dying among dozens is itself a
result, and it must not throw away what the others measured."
  (condition-case err
      (apply #'kittymacs-bench--run arguments options)
    (error (push (error-message-string err) kittymacs-bench--failures)
           nil)))

(defun kittymacs-bench--display-mismatch-p (display report)
  "Return non-nil if REPORT comes from a terminal when DISPLAY asked for a frame.
DISPLAY is the extra arguments of the run: empty asks for a frame."
  (and (null display) (not (plist-get report :graphic))))

(defun kittymacs-bench--runs ()
  "Return the number of runs to keep in each configuration."
  (let ((runs (string-to-number (or (getenv "KITTYMACS_BENCH_RUNS") "20"))))
    (if (> runs 0) runs 20)))

(defun kittymacs-bench--measure (arguments settle)
  "Return the kept reports of Emacs started with ARGUMENTS, waiting SETTLE seconds."
  (dotimes (_ kittymacs-bench-discarded)
    (kittymacs-bench--attempt arguments :settle settle))
  (or (delq nil (cl-loop repeat (kittymacs-bench--runs)
                         collect (kittymacs-bench--attempt arguments :settle settle)))
      (error "Every run of Emacs %S failed; the last: %s"
             arguments (car kittymacs-bench--failures))))

(defun kittymacs-bench--values (reports key)
  "Return the numbers REPORTS hold under KEY, skipping runs without one."
  (seq-filter #'numberp (mapcar (lambda (report) (plist-get report key)) reports)))

(defun kittymacs-bench--cell (reports key)
  "Return a table cell with the median and p90 of KEY in REPORTS."
  (let ((numbers (kittymacs-bench--values reports key)))
    (if numbers
        (format "%.3f / %.3f" (kittymacs-bench--median numbers) (kittymacs-bench--p90 numbers))
      "n/a")))

(defun kittymacs-bench--ratio (reports baseline key)
  "Return the ratio of the medians of KEY in REPORTS and in BASELINE, or nil."
  (let ((numbers (kittymacs-bench--values reports key))
        (bases (kittymacs-bench--values baseline key)))
    (when (and numbers bases)
      (/ (kittymacs-bench--median numbers) (kittymacs-bench--median bases)))))

;;; Reporting

(defun kittymacs-bench--compare (budgets measured)
  "Return (METRIC BUDGET CURRENT) for each METRIC in MEASURED that differs.
BUDGET is nil for a metric that BUDGETS does not hold yet."
  (cl-loop for (metric . current) in measured
           for budget = (alist-get metric budgets)
           unless (eql budget current)
           collect (list metric budget current)))

(defun kittymacs-bench--budgets ()
  "Return the alist in tests/budgets.eld, or nil when it does not exist."
  (let ((file (kittymacs-bench--path "tests/budgets.eld")))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (read (current-buffer))))))

(defun kittymacs-bench--write-budgets (measured)
  "Merge MEASURED into tests/budgets.eld, sorted by metric."
  (let ((merged (kittymacs-bench--budgets)))
    (pcase-dolist (`(,metric . ,value) measured)
      (setf (alist-get metric merged) value))
    (with-temp-file (kittymacs-bench--path "tests/budgets.eld")
      (insert ";;; budgets.eld --- What kittymacs may cost -*- mode: lisp-data; -*-\n"
              ";; Written by tools/bench.el --write.  `just budget-check' holds them to the\n"
              ";; merge base.  Counts from a start are of the default profile.\n"
              ";; See \"Measuring\" in literate/80-maintenance.org.\n"
              "(\n")
      (dolist (entry (sort merged (lambda (a b) (string< (car a) (car b)))))
        (insert (format " %S\n" entry)))
      (insert ")\n"))))

(defun kittymacs-bench--report-budgets (measured)
  "Print how MEASURED differs from the budgets."
  (let ((differences (kittymacs-bench--compare (kittymacs-bench--budgets) measured)))
    (princ (format "\n## Against tests/budgets.eld\n\n%s\n"
                   (if differences "| Metric | Budget | Now |\n|---|---|---|" "No differences.")))
    (pcase-dolist (`(,metric ,budget ,current) differences)
      (princ (format "| %s | %s | %s |\n" metric (or budget "none") current)))))

(defun kittymacs-bench--report-totals (measured)
  "Print the totals in MEASURED, leaving out the per-module rows."
  (princ "| Metric | Now |\n|---|---|\n")
  (pcase-dolist (`(,metric . ,value) measured)
    (unless (string-match-p "/" (symbol-name metric))
      (princ (format "| %s | %s |\n" metric value)))))

(defun kittymacs-bench--report-startup (name baseline reports)
  "Print the timing table for display NAME, of REPORTS against BASELINE."
  (let ((keys '((:first-idle . "first idle")
                (:cpu-settled . "CPU, settled")
                (:open-el . "open .el")
                (:open-org . "open .org")
                (:spc . "SPC t m"))))
    (princ (format "\n## Seconds, %s (median / p90 of %d)\n\n" name (length reports)))
    (princ "| | emacs -Q | kittymacs | ratio |\n|---|---|---|---|\n")
    (pcase-dolist (`(,key . ,label) keys)
      (let ((ratio (kittymacs-bench--ratio reports baseline key)))
        (princ (format "| %s | %s | %s | %s |\n"
                       label
                       (kittymacs-bench--cell baseline key)
                       (kittymacs-bench--cell reports key)
                       (if ratio (format "%.2f" ratio) "n/a")))))))

(defvar kittymacs-bench--off-default nil
  "The profile the measured starts ran on, when it was not the default.")

(defun kittymacs-bench--default-profile ()
  "Return the profile a machine with no choice starts on, from the catalogue's module."
  (kittymacs-bench--default-features)
  (symbol-value 'kittymacs-default-profile))

(defun kittymacs-bench--startup-counts (reports)
  "Return the counts in REPORTS, as metrics, from the last run.
They are exact and repeat from run to run, unlike the times."
  (let ((report (car (last reports))))
    (unless (eq (plist-get report :profile) (kittymacs-bench--default-profile))
      (setq kittymacs-bench--off-default (plist-get report :profile))
      (princ (format "\n**Warning:** these starts ran on the %s profile, not the default.\n"
                     (plist-get report :profile))))
    `((features . ,(plist-get report :features))
      (files-loaded . ,(plist-get report :files-loaded))
      (packages-activated . ,(plist-get report :packages-activated))
      (org-loaded-at-start . ,(if (plist-get report :org-loaded) 1 0))
      (magit-loaded-at-start . ,(if (plist-get report :magit-loaded) 1 0)))))

(defun kittymacs-bench--host-files (&optional directories)
  "Return the host files a start here would load, from DIRECTORIES.
They default to what init.el names, read rather than repeated here."
  (let ((directories
         (or directories
             (eval (nth 2 (seq-find (lambda (form)
                                      (and (eq (car-safe form) 'defvar)
                                           (eq (cadr form) 'kittymacs-host-directories)))
                                    (kittymacs-bench--forms (kittymacs-bench--path "init.el"))))
                   t))))
    (seq-mapcat (lambda (directory)
                  (and (file-directory-p directory)
                       (directory-files directory t "\\`[^.#].*\\.el\\'")))
                directories)))

(defun kittymacs-bench-startup ()
  "Start Emacs repeatedly, print the times, and return the counts as metrics."
  (unless (file-directory-p (kittymacs-bench--path "var/elpa"))
    (error "No var/elpa here; run `just install' first"))
  (when (file-exists-p (kittymacs-bench--path "lisp/private.el"))
    (princ "**Warning:** lisp/private.el exists, so these numbers include it.\n\n"))
  (when-let* ((files (kittymacs-bench--host-files)))
    (princ (format "**Warning:** host files exist, so these numbers include them: %s.\n\n"
                   (string-join files ", "))))
  (let* ((closure (kittymacs-bench--closure (kittymacs-bench--declared-packages)
                                            (kittymacs-bench--installed-alist)))
         (displays `(("terminal" "-nw")
                     ,@(and (getenv "DISPLAY") '(("graphical")))))
         (directory (make-temp-file "kittymacs-bench-samples-" t))
         (kittymacs-bench--samples (kittymacs-bench--make-samples directory))
         counts)
    (unwind-protect
        (pcase-dolist (`(,name . ,display) displays)
          (let* ((config (append (list (format "--init-directory=%s" kittymacs-bench-root)) display))
                 (warm-up (or (kittymacs-bench--attempt config :settle kittymacs-bench-settle
                                                        :drain t :timeout kittymacs-bench-drain-timeout)
                              (kittymacs-bench--run config :settle kittymacs-bench-settle
                                                    :drain t :timeout kittymacs-bench-drain-timeout))))
            ;; Built without a toolkit, Emacs ignores DISPLAY and starts in the
            ;; terminal; those numbers must not carry the word "graphical".
            (if (kittymacs-bench--display-mismatch-p display warm-up)
                (princ (format "\nThis Emacs did not open a frame, so no %s run.\n" name))
              (let ((baseline (kittymacs-bench--measure (cons "-Q" display) 0))
                    (reports (kittymacs-bench--measure config kittymacs-bench-settle)))
                (kittymacs-bench--report-startup name baseline reports)
                (unless counts
                  (setq counts (kittymacs-bench--startup-counts reports)))))))
      (delete-directory directory t))
    (unless (getenv "DISPLAY")
      (princ "\nNo DISPLAY, so no graphical run.\n"))
    (when kittymacs-bench--failures
      (princ (format "\n## Runs that failed: %d\n\n" (length kittymacs-bench--failures)))
      (dolist (failure (reverse kittymacs-bench--failures))
        (princ (format "- %s\n" failure))))
    (cons (cons 'dependency-closure (length closure)) counts)))

;;; Holding the budgets to the merge base

(defun kittymacs-bench--git (&rest arguments)
  "Run git with ARGUMENTS in this checkout; return its output, or nil if it failed."
  (let ((default-directory kittymacs-bench-root))
    (with-temp-buffer
      (when (eql 0 (apply #'call-process "git" nil '(t nil) nil arguments))
        (buffer-string)))))

(defun kittymacs-bench--merge-base (&optional base)
  "Return the commit where HEAD left BASE, or signal an error that says what is missing.
BASE defaults to what this pull request targets, or else origin/main."
  (let* ((target (or base
                     (when-let* ((ref (getenv "GITHUB_BASE_REF"))
                                 ((not (string-empty-p ref))))
                       (concat "origin/" ref))
                     "origin/main"))
         (found (kittymacs-bench--git "merge-base" "HEAD" target)))
    (if found
        (string-trim found)
      (error "No merge base between HEAD and %s: this needs that ref and enough history"
             target))))

(defun kittymacs-bench--budgets-at (commit)
  "Return the alist in tests/budgets.eld at COMMIT."
  (let ((text (kittymacs-bench--git "show" (concat commit ":tests/budgets.eld"))))
    (unless text
      (error "No tests/budgets.eld at %s" commit))
    (car (read-from-string text))))

(defun kittymacs-bench--parse-reason (line)
  "Return (NAMES . REASON) from the trailer value LINE, or nil if it names no reason."
  (when (string-match "\\`\\([^:]+\\):[ \t]*\\(.*[^ \t].*\\)\\'" line)
    (let ((reason (match-string 2 line)))
      (cons (mapcar #'intern (split-string (match-string 1 line) "[, \t]+" t)) reason))))

(defun kittymacs-bench--stated-reasons (base)
  "Return an alist of budget and reason, from the commits after BASE up to HEAD.
Each reason comes from a trailer: Budget-rise: NAME, NAME: why."
  (let (reasons)
    (dolist (line (split-string
                   (or (kittymacs-bench--git
                        "log" "--format=%(trailers:key=Budget-rise,valueonly,unfold)"
                        (concat base "..HEAD"))
                       "")
                   "\n" t))
      (when-let* ((parsed (kittymacs-bench--parse-reason (string-trim line))))
        (dolist (name (car parsed))
          (push (cons name (cdr parsed)) reasons))))
    reasons))

(defun kittymacs-bench--current (recorded measured)
  "Return RECORDED with what MEASURED holds in its place, so a count cannot go stale."
  (append measured (seq-remove (lambda (entry) (assq (car entry) measured)) recorded)))

(defun kittymacs-bench--stale (recorded measured)
  "Return the metrics in MEASURED whose count differs from RECORDED, as a list."
  (mapcar #'car (kittymacs-bench--compare recorded measured)))

(defun kittymacs-bench--rises (base current)
  "Return (METRIC BEFORE NOW) for each budget in BASE that CURRENT holds higher.
A metric BASE lacks has nothing to rise from: a new module also moves the totals."
  (cl-loop for (metric . before) in base
           for now = (alist-get metric current)
           when (and now (> now before))
           collect (list metric before now)))

(defun kittymacs-bench--missing (base current)
  "Return the budgets in BASE that CURRENT has dropped.
A module's rows may go with the module.  Dropping any other would end its ratchet."
  (cl-loop for (metric . _) in base
           unless (or (assq metric current)
                      (string-prefix-p "module-" (symbol-name metric)))
           collect metric))

(defun kittymacs-bench--report-check (base-commit base current reasons)
  "Print how CURRENT moved from BASE at BASE-COMMIT, and the REASONS stated."
  (princ (format "\n## Budgets against %s\n\n" (substring base-commit 0 (min 10 (length base-commit)))))
  (let ((moved (cl-loop for (metric . before) in base
                        for now = (alist-get metric current)
                        unless (or (null now) (= now before))
                        collect (list metric before now))))
    (if (null moved)
        (princ "Nothing moved.\n")
      (princ "| Budget | Base | Now | Reason |\n|---|---|---|---|\n")
      (pcase-dolist (`(,metric ,before ,now) moved)
        (princ (format "| %s | %s | %s | %s |\n" metric before now
                       (if (> now before)
                           (or (alist-get metric reasons) "**none**")
                         "")))))))

(defun kittymacs-bench-check (&optional base)
  "Fail unless each budget held against the merge base with BASE.
Return nil on success, and otherwise the list of failures it printed."
  (let* ((commit (kittymacs-bench--merge-base base))
         (before (kittymacs-bench--budgets-at commit))
         (recorded (kittymacs-bench--budgets))
         (measured (kittymacs-bench-size))
         (current (kittymacs-bench--current recorded measured))
         (reasons (kittymacs-bench--stated-reasons commit))
         (stale (kittymacs-bench--stale recorded measured))
         (missing (kittymacs-bench--missing before current))
         (unstated (seq-remove (lambda (rise) (assq (car rise) reasons))
                               (kittymacs-bench--rises before current)))
         failures)
    (kittymacs-bench--report-check commit before current reasons)
    (when stale
      (push (format "tests/budgets.eld is out of date for %s: run `just size --write'."
                    (mapconcat #'symbol-name stale ", "))
            failures))
    (when missing
      (push (format "tests/budgets.eld no longer holds %s."
                    (mapconcat #'symbol-name missing ", "))
            failures))
    (when unstated
      (push (format "These rose with no stated reason.  End a commit message with the trailer:\n\n  Budget-rise: %s: WHY\n"
                    (mapconcat (lambda (rise) (symbol-name (car rise))) unstated ", "))
            failures))
    (dolist (failure failures)
      (princ (format "\n**Fail:** %s\n" failure)))
    (unless failures
      (princ "\nEvery budget held.\n"))
    failures))

(when (and noninteractive (not kittymacs-bench-library-only))
  (let* ((args (delete "--" command-line-args-left))
         (write (member "--write" args))
         (mode (car (delete "--write" args)))
         measured)
    (setq command-line-args-left nil)
    (pcase mode
      ("--size" nil)
      ("--startup" (setq measured (kittymacs-bench-startup)))
      ("--check" (kill-emacs (if (kittymacs-bench-check (cadr args)) 1 0)))
      (_ (error "Usage: emacs -Q --batch -l tools/bench.el -- --size|--startup [--write], or --check [BASE]")))
    (setq measured (append measured (kittymacs-bench-size)))
    (princ "\n## Counts\n\n")
    (kittymacs-bench--report-totals measured)
    (kittymacs-bench--report-budgets measured)
    (when write
      (when kittymacs-bench--off-default
        (error "These starts ran on the %s profile, and tests/budgets.eld holds the default's"
               kittymacs-bench--off-default))
      (kittymacs-bench--write-budgets measured)
      (princ "\nWrote tests/budgets.eld.\n"))))

;;; bench.el ends here
