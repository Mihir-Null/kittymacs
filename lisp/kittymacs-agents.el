;;; kittymacs-agents.el --- A coding agent in a buffer -*- lexical-binding: t; -*-
;; Generated from literate/77-agents.org; edit the Org source, then tangle.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(declare-function notifications-notify "notifications" (&rest params))
(declare-function claude-code-ide "claude-code-ide" ())
(declare-function claude-code-ide-switch-to-buffer "claude-code-ide" ())
(declare-function claude-code-ide-send-prompt "claude-code-ide" (&optional prompt session))
(declare-function claude-code-ide--get-working-directory "claude-code-ide" ())
(declare-function claude-code-ide-mcp--sessions-for-project "claude-code-ide-mcp" (project-dir))
(declare-function claude-code-ide-mcp-session-buffer "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-client "claude-code-ide-mcp" (session))
(declare-function claude-code-ide-mcp-session-project-dir "claude-code-ide-mcp" (session))
(declare-function diff-review-branch "diff-review" (branch))
(defvar claude-code-ide-cli-extra-flags)
(declare-function gptel-agent "gptel-agent" (&optional project-dir agent-preset))
(when (kittymacs-feature-p 'agents)
  (use-package agent-shell
    :ensure t
    :commands (agent-shell agent-shell-toggle agent-shell-new-shell agent-shell-switch-buffer
               agent-shell-resume-session agent-shell-send-dwim agent-shell-send-file
               agent-shell-help-menu)
    :custom
    (agent-shell-preferred-agent-config 'claude-code)
    (agent-shell-activity-group-expand-by-default nil)
    (agent-shell-highlight-blocks nil)
    (agent-shell-header-style 'text)
    :config
    (setopt agent-shell-anthropic-claude-environment
            (agent-shell-make-environment-variables :inherit-env t)))

  (keymap-set kittymacs-agent-map "a" (cons "start or switch" #'agent-shell))
  (keymap-set kittymacs-agent-map "n" (cons "new shell" #'agent-shell-new-shell))
  (keymap-set kittymacs-agent-map "t" (cons "toggle" #'agent-shell-toggle))
  (keymap-set kittymacs-agent-map "b" (cons "switch shell" #'agent-shell-switch-buffer))
  (keymap-set kittymacs-agent-map "r" (cons "resume session" #'agent-shell-resume-session))
  (keymap-set kittymacs-agent-map "s" (cons "send region or file" #'agent-shell-send-dwim))
  (keymap-set kittymacs-agent-map "f" (cons "send a file" #'agent-shell-send-file))
  (keymap-set kittymacs-agent-map "?" (cons "menu" #'agent-shell-help-menu)))
(defcustom kittymacs-agent-mcp-servers nil
  "MCP servers every agent-shell session starts with.
Each element has the shape `agent-shell-mcp-servers' documents.  Set this
before this module loads, in `private.el' or a host file."
  :type '(repeat sexp)
  :group 'kittymacs)

(when (and (kittymacs-feature-p 'agents) kittymacs-agent-mcp-servers)
  (setopt agent-shell-mcp-servers kittymacs-agent-mcp-servers))
(defun kittymacs-agent-notify (_buffer title body)
  "Show a desktop notification with TITLE and BODY.
The value of `agent-shell-attention-notify-function'."
  (pcase system-type
    ('darwin
     (call-process "osascript" nil 0 nil "-e"
                   (format "display notification %S with title %S" body title)))
    (_
     (when (require 'notifications nil t)
       (ignore-errors
         (notifications-notify :app-name "agent-shell" :title title :body body))))))

(defun kittymacs-agent-vc-warning (package url err)
  "Warn that PACKAGE, from the Git repository URL, did not install: ERR."
  (display-warning 'kittymacs
                   (format "%s was not installed: %s
Check that `git clone %s' works from a terminal, and which git Emacs runs: %s"
                           package (error-message-string err) url (executable-find "git"))
                   :warning))

(when (kittymacs-feature-p 'agents)
  (condition-case err
      (use-package agent-shell-attention
        :vc (:url "https://github.com/ultronozm/agent-shell-attention.el"
             :rev "aaf599121445ead597a14da62bad580c8897ee6c")
        :after agent-shell
        :demand t
        :custom
        (agent-shell-attention-notify-function #'kittymacs-agent-notify)
        :config
        (agent-shell-attention-mode 1))
    (error
     (kittymacs-agent-vc-warning "agent-shell-attention"
                                 "https://github.com/ultronozm/agent-shell-attention.el" err)))

  (when (locate-library "agent-shell-attention")
    (keymap-set kittymacs-agent-map "j" (cons "jump to waiting shell" #'agent-shell-attention-jump))
    (keymap-set kittymacs-agent-map "d" (cons "all shells" #'agent-shell-attention-dashboard))))
(when (kittymacs-feature-p 'agents)
  (with-eval-after-load 'meow
    (dolist (entry '((agent-shell-mode . insert)
                     (agent-shell-diff-mode . motion)
                     (agent-shell-viewport-view-mode . motion)
                     (agent-shell-viewport-edit-mode . insert)))
      (add-to-list 'meow-mode-state-list entry)))

  (kittymacs-define-localleader 'agent-shell-mode
    "i" (cons "interrupt" #'agent-shell-interrupt)
    "m" (cons "next permission mode" #'agent-shell-cycle-session-mode)
    "M" (cons "choose model" #'agent-shell-set-session-model)
    "c" (cons "compose prompt" #'agent-shell-prompt-compose)
    "f" (cons "send file" #'agent-shell-send-file)
    "y" (cons "copy last reply" #'agent-shell-copy-last-output)
    "t" (cons "open transcript" #'agent-shell-open-transcript)
    "r" (cons "restart" #'agent-shell-restart)
    "?" (cons "menu" #'agent-shell-help-menu)))
(defun kittymacs-agent-claude-code-ide-start-or-switch ()
  "Switch to this project's Claude Code, or start one where there is none."
  (interactive)
  (condition-case nil
      (claude-code-ide-switch-to-buffer)
    (user-error (claude-code-ide))))

(when (kittymacs-feature-p 'agent-claude-code-ide)
  (condition-case err
      (use-package claude-code-ide
        :vc (:url "https://github.com/manzaltu/claude-code-ide.el"
             :rev "50a3d55262805d7207889ed429ff30da96fbf68b")
        :commands (claude-code-ide claude-code-ide-toggle claude-code-ide-resume
                   claude-code-ide-list-sessions claude-code-ide-switch-to-buffer
                   claude-code-ide-insert-at-mentioned claude-code-ide-send-prompt
                   claude-code-ide-send-escape claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'ghostel)
        :config
        (claude-code-ide-emacs-tools-setup))
    (error
     (kittymacs-agent-vc-warning "claude-code-ide"
                                 "https://github.com/manzaltu/claude-code-ide.el" err)))

  (when (locate-library "claude-code-ide")
    (keymap-set kittymacs-agent-map "a"
                (cons "start or switch" #'kittymacs-agent-claude-code-ide-start-or-switch))
    (keymap-set kittymacs-agent-map "n" (cons "new instance" #'claude-code-ide))
    (keymap-set kittymacs-agent-map "t" (cons "toggle" #'claude-code-ide-toggle))
    (keymap-set kittymacs-agent-map "b" (cons "switch instance" #'claude-code-ide-list-sessions))
    (keymap-set kittymacs-agent-map "r" (cons "resume session" #'claude-code-ide-resume))
    (keymap-set kittymacs-agent-map "s" (cons "send region" #'claude-code-ide-insert-at-mentioned))
    (keymap-set kittymacs-agent-map "p" (cons "send a prompt" #'claude-code-ide-send-prompt))
    (keymap-set kittymacs-agent-map "i" (cons "interrupt" #'claude-code-ide-send-escape))
    (keymap-set kittymacs-agent-map "?" (cons "menu" #'claude-code-ide-menu))))
(defface kittymacs-pair-line '((t :inherit secondary-selection))
  "A line Claude commented on."
  :group 'kittymacs)

(defface kittymacs-pair-text '((t :inherit font-lock-warning-face :slant italic))
  "Claude's words beside or below a line."
  :group 'kittymacs)

(defun kittymacs-pair--buffer (buffer)
  "BUFFER as a live buffer: a buffer, a buffer name, or a file name to visit."
  (or (get-buffer buffer)
      (and (stringp buffer) (file-exists-p buffer) (find-file-noselect buffer))
      (error "No buffer or file: %s" buffer)))

(defun kittymacs-pair--goto-line (line)
  "Move to the start of LINE, counted from 1."
  (goto-char (point-min))
  (forward-line (1- line)))

(defun kittymacs-pair-comment (buffer line text)
  "Mark LINE of BUFFER and show TEXT after it, as an overlay.
The buffer's text is untouched."
  (with-current-buffer (kittymacs-pair--buffer buffer)
    (save-excursion
      (kittymacs-pair--goto-line line)
      (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
        (overlay-put ov 'kittymacs-pair t)
        (overlay-put ov 'face 'kittymacs-pair-line)
        (overlay-put ov 'after-string
                     (propertize (concat "   <- Claude: " text) 'face 'kittymacs-pair-text))
        ov))))

(defun kittymacs-pair-note (buffer line text)
  "Show TEXT, an explanation or a question, as a block below LINE of BUFFER.
An overlay: the buffer's text is untouched."
  (with-current-buffer (kittymacs-pair--buffer buffer)
    (save-excursion
      (kittymacs-pair--goto-line line)
      (let ((ov (make-overlay (line-end-position) (line-end-position))))
        (overlay-put ov 'kittymacs-pair t)
        (overlay-put ov 'after-string
                     (concat "\n" (propertize (concat " Claude: " text " ")
                                              'face '(kittymacs-pair-text kittymacs-pair-line))))
        ov))))

(defun kittymacs-pair-clear (&optional buffer)
  "Remove Claude's comments and notes from BUFFER, or from every buffer."
  (interactive)
  (dolist (b (if buffer (list (kittymacs-pair--buffer buffer)) (buffer-list)))
    (with-current-buffer b
      (remove-overlays (point-min) (point-max) 'kittymacs-pair t))))

(defun kittymacs-pair-snippet (buffer line text &optional replace)
  "Put TEXT into BUFFER at LINE, replacing REPLACE lines there (none by default).
Save the buffer when it had no unsaved changes before, so the gutter marks
the edit; otherwise leave it unsaved, since saving would write the owner's
unsaved edits too.  Return a sentence saying which."
  (with-current-buffer (kittymacs-pair--buffer buffer)
    (barf-if-buffer-read-only)
    (let ((modified (buffer-modified-p))
          (text (if (string-suffix-p "\n" text) text (concat text "\n"))))
      (undo-boundary)
      (save-excursion
        (kittymacs-pair--goto-line line)
        (unless (bolp) (insert "\n"))   ; past a last line with no newline
        (let ((start (point)))
          (when (and replace (> replace 0))
            (delete-region start (progn (forward-line replace) (point))))
          (goto-char start)
          (insert text)
          (pulse-momentary-highlight-region start (point))))
      (undo-boundary)
      (cond ((not buffer-file-name)
             (format "Wrote into %s, which visits no file" (buffer-name)))
            (modified
             (format "Left %s unsaved: it had unsaved changes of the owner's" (buffer-name)))
            (t (save-buffer)
               (format "Saved %s" buffer-file-name))))))

(defcustom kittymacs-pair-secret-script "tools/secret.sh"
  "The script, relative to a repository, that `kittymacs-pair-secret' feeds.
It reads the secret on standard input and takes the caller's arguments."
  :type 'string
  :group 'kittymacs)

(defun kittymacs-pair-secret (repo &rest args)
  "Ask for a secret and pipe it to REPO's `kittymacs-pair-secret-script' with ARGS.
The plaintext goes from `read-passwd' to the script's standard input and
nowhere else: the caller sees only this function's value."
  (let* ((what (string-join (cons kittymacs-pair-secret-script args) " "))
         (script (expand-file-name kittymacs-pair-secret-script repo))
         (plain (read-passwd (format "Secret for %s (not shown): " what))))
    (unwind-protect
        (with-temp-buffer
          (insert plain)
          (let ((status (apply #'call-process-region (point-min) (point-max) script
                               t t nil args)))
            (if (eq status 0)
                (format "%s: written" what)
              (error "%s exited %s: %s" what status (buffer-string)))))
      (clear-string plain))))
(defvar kittymacs-pair-status-functions nil
  "Functions called with the path of a Change session's status file.
Whatever writes that file calls this hook through emacsclient after each
write, so Emacs learns of a change without watching for it.")

(defconst kittymacs-pair--board-name "*Change sessions*"
  "The board's buffer.")

(defvar kittymacs-pair--sessions (make-hash-table :test #'equal)
  "Each status file's name, to its contents as an alist when last read.")

(defun kittymacs-pair--read-json (file)
  "FILE's JSON object as an alist, or nil when it is missing or unreadable."
  (when (file-readable-p file)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents file)
        (json-parse-buffer :object-type 'alist :null-object nil :false-object nil)))))

(defun kittymacs-pair--waiting-p (status)
  "Whether STATUS is a session waiting for the owner."
  (member (alist-get 'state status) '("waiting" "idle")))

(defun kittymacs-pair--load (file)
  "Read status FILE into the table, or drop it when it is gone.
Return its contents before and after, as a cons."
  (let* ((file (expand-file-name file))
         (old (gethash file kittymacs-pair--sessions))
         (new (kittymacs-pair--read-json file)))
    (if new
        (puthash file new kittymacs-pair--sessions)
      (remhash file kittymacs-pair--sessions))
    (cons old new)))

(defun kittymacs-pair-status-update (file)
  "Read the status FILE, ring when it starts to need the owner, redraw.
The function `kittymacs-pair-status-functions' runs."
  (pcase-let* ((`(,old . ,new) (kittymacs-pair--load file))
               (state (alist-get 'state new)))
    (when (and (member state '("waiting" "review"))
               (not (equal state (alist-get 'state old))))
      (let ((message (alist-get 'message new)))
        (kittymacs-agent-notify nil (format "Claude: %s" (alist-get 'branch new))
                                (cond ((equal state "review") "ready for review")
                                      ((and message (not (string-empty-p message))) message)
                                      (t "waiting for you")))))
    (force-mode-line-update t)
    (when-let* ((board (get-buffer kittymacs-pair--board-name)))
      (with-current-buffer board
        (kittymacs-pair--board-print)))))

(defun kittymacs-pair-mode-line ()
  "The live Change sessions by state, for the mode line; empty when none is."
  (let ((working 0) (waiting 0) (review 0))
    (maphash (lambda (_file status)
               (pcase (alist-get 'state status)
                 ((or "starting" "working") (cl-incf working))
                 ((or "waiting" "idle") (cl-incf waiting))
                 ("review" (cl-incf review))))
             kittymacs-pair--sessions)
    (if (zerop (+ working waiting review))
        ""
      (propertize (concat " CC"
                          (if (> working 0) (format " ⚙%d" working) "")
                          (if (> waiting 0) (format " ⏳%d" waiting) "")
                          (if (> review 0) (format " ✓%d" review) "")
                          " ")
                  'help-echo "Change sessions: mouse-1 or SPC a d opens the board"
                  'mouse-face 'mode-line-highlight
                  'local-map (make-mode-line-mouse-map 'mouse-1 #'kittymacs-pair-board)))))

(defun kittymacs-pair--common-dir (root)
  "The Git directory every worktree of ROOT shares, or nil.
Read from the files, so it starts no process; nil for a remote ROOT."
  (unless (file-remote-p root)
    (let ((dotgit (expand-file-name ".git" root)))
      (cond
       ((file-directory-p dotgit) (file-name-as-directory dotgit))
       ((file-regular-p dotgit)
        (when-let* ((gitdir (with-temp-buffer
                              (insert-file-contents dotgit)
                              (and (looking-at "gitdir: \\(.*\\)$")
                                   (file-name-as-directory
                                    (expand-file-name (match-string 1) root))))))
          (let ((commondir (expand-file-name "commondir" gitdir)))
            (file-name-as-directory
             (if (file-readable-p commondir)
                 (expand-file-name (string-trim (with-temp-buffer
                                                  (insert-file-contents commondir)
                                                  (buffer-string)))
                                   gitdir)
               gitdir)))))))))

(defun kittymacs-pair-scan ()
  "Read the status files of every project Emacs knows into the table, afresh."
  (require 'project)
  (let ((dirs (delete-dups
               (append
                (mapcar #'file-name-directory (hash-table-keys kittymacs-pair--sessions))
                (delq nil (mapcar (lambda (root)
                                    (when-let* ((common (kittymacs-pair--common-dir root)))
                                      (expand-file-name "agents/" common)))
                                  (project-known-project-roots)))))))
    (clrhash kittymacs-pair--sessions)
    (dolist (dir dirs)
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.json\\'"))
          (kittymacs-pair--load file))))
    (force-mode-line-update t)))

(defun kittymacs-pair--session (status)
  "The live claude-code-ide session in STATUS's worktree, or nil."
  (when-let* ((worktree (alist-get 'worktree status))
              ((fboundp 'claude-code-ide-mcp--sessions-for-project)))
    (cl-some (lambda (dir)
               (cl-find-if (lambda (session)
                             (buffer-live-p (claude-code-ide-mcp-session-buffer session)))
                           (claude-code-ide-mcp--sessions-for-project dir)))
             (list (file-name-as-directory worktree) (directory-file-name worktree)))))

(defun kittymacs-pair--session-buffer (status)
  "The terminal buffer of STATUS's claude-code-ide session, or nil."
  (when-let* ((session (kittymacs-pair--session status)))
    (claude-code-ide-mcp-session-buffer session)))

(defun kittymacs-pair--outside (status)
  "Say that STATUS's session runs where Emacs cannot show it."
  (message "%s runs outside Emacs (%s), as %s"
           (alist-get 'branch status) (or (alist-get 'how status) "unknown")
           (alist-get 'session status)))

(defun kittymacs-pair-jump ()
  "Switch to the Change session that has waited longest for you.
Pressed again from that session, go on to the next one."
  (interactive)
  (dolist (file (hash-table-keys kittymacs-pair--sessions))
    (kittymacs-pair--load file))
  (let* ((waiting (sort (cl-loop for status being the hash-values of kittymacs-pair--sessions
                                 when (kittymacs-pair--waiting-p status) collect status)
                        (lambda (a b) (string< (or (alist-get 'at a) "") (or (alist-get 'at b) "")))))
         (buffers (delq nil (mapcar #'kittymacs-pair--session-buffer waiting)))
         (next (or (cl-find-if (lambda (b) (not (eq b (current-buffer)))) buffers)
                   (car buffers))))
    (cond (next (pop-to-buffer next))
          (waiting (kittymacs-pair--outside (car waiting)))
          (t (message "No Change session is waiting for you")))))
(defun kittymacs-pair--review (file status)
  "The review of STATUS, whose status file is FILE: (VIEWED OPEN VERDICT).
Each is a string, empty when there is no review yet."
  (let* ((common (file-name-directory (directory-file-name (file-name-directory file))))
         (branch (alist-get 'branch status))
         (review (and branch (kittymacs-pair--read-json
                              (expand-file-name (concat "review/" branch ".json") common)))))
    (if (not review)
        (list "" "" "")
      (let* ((verdict (alist-get 'verdict review))
             (tip (ignore-errors
                    (let ((default-directory (file-name-as-directory
                                              (or (alist-get 'worktree status) common))))
                      (car (process-lines "git" "rev-parse" branch))))))
        (list (number-to-string (length (alist-get 'viewed review)))
              (number-to-string (cl-count-if-not (lambda (c) (alist-get 'resolved c))
                                                 (alist-get 'comments review)))
              (cond ((not verdict) "")
                    ((equal (alist-get 'head verdict) tip) (alist-get 'state verdict))
                    (t "stale")))))))

(defun kittymacs-pair--board-print ()
  "Fill the board from the table, keeping point on its row."
  (setq tabulated-list-entries
        (cl-loop for file being the hash-keys of kittymacs-pair--sessions
                 using (hash-values status)
                 collect (list file
                               (apply #'vector
                                      (or (alist-get 'branch status) "?")
                                      (or (alist-get 'state status) "?")
                                      (append (kittymacs-pair--review file status)
                                              (list (or (alist-get 'message status) "")))))))
  (tabulated-list-print t))

(defun kittymacs-pair--board-revert ()
  "Read the status files again, for `revert-buffer'."
  (kittymacs-pair-scan)
  (kittymacs-pair--board-print))

(defun kittymacs-pair--board-status ()
  "The status of the session on this row."
  (or (gethash (tabulated-list-get-id) kittymacs-pair--sessions)
      (user-error "No session on this line")))

(defun kittymacs-pair-board-visit ()
  "Open the terminal of the session on this row."
  (interactive)
  (let ((status (kittymacs-pair--board-status)))
    (if-let* ((buffer (kittymacs-pair--session-buffer status)))
        (pop-to-buffer buffer)
      (kittymacs-pair--outside status))))

(defun kittymacs-pair-board-review ()
  "Review the branch of the session on this row, in diff-review."
  (interactive)
  (let ((status (kittymacs-pair--board-status)))
    (unless (fboundp 'diff-review-branch)
      (user-error "diff-review is not installed: turn on the branch-review feature"))
    (let ((default-directory (file-name-as-directory (alist-get 'worktree status))))
      (diff-review-branch (alist-get 'branch status)))))

(defvar-keymap kittymacs-pair-board-mode-map
  :doc "The board of Change sessions."
  :parent tabulated-list-mode-map
  "RET" #'kittymacs-pair-board-visit
  "r" #'kittymacs-pair-board-review)

(define-derived-mode kittymacs-pair-board-mode tabulated-list-mode "Change sessions"
  "The Change sessions, their state and their reviews.
\\{kittymacs-pair-board-mode-map}"
  (setq tabulated-list-format [("Branch" 28 t) ("State" 8 t)
                               ("Viewed" 6 nil :right-align t) ("Open" 4 nil :right-align t)
                               ("Verdict" 9 t) ("Message" 0 nil)])
  (setq tabulated-list-padding 1)
  (add-hook 'tabulated-list-revert-hook #'kittymacs-pair--board-revert nil t)
  (tabulated-list-init-header))

(defun kittymacs-pair-board ()
  "Show the board of Change sessions."
  (interactive)
  (kittymacs-pair-scan)
  (with-current-buffer (get-buffer-create kittymacs-pair--board-name)
    (unless (derived-mode-p 'kittymacs-pair-board-mode)
      (kittymacs-pair-board-mode))
    (kittymacs-pair--board-print)
    (pop-to-buffer (current-buffer))))
(defcustom kittymacs-pair-dispatch-command nil
  "The program that starts a Change session, or nil to find pair-dispatch.
Nil looks on `exec-path', then at ~/.claude/skills/pair/pair-dispatch.
It is called as PROGRAM REPO BRANCH BRIEF-FILE."
  :type '(choice (const :tag "Find pair-dispatch" nil) file)
  :group 'kittymacs)

(defcustom kittymacs-pair-ready-delay 1.5
  "Seconds between a new session's editor connection and its first message."
  :type 'number
  :group 'kittymacs)

(defun kittymacs-pair--dispatch-program ()
  "The command that starts a Change session, as a list, or nil."
  (when-let* ((file (or kittymacs-pair-dispatch-command
                        (executable-find "pair-dispatch")
                        (expand-file-name "~/.claude/skills/pair/pair-dispatch")))
              ((file-exists-p file)))
    (if (file-executable-p file) (list file) (list "bash" file))))

(defun kittymacs-pair--repo ()
  "The root of this buffer's project, or its directory."
  (let ((dir (if-let* ((project (project-current)))
                 (project-root project)
               default-directory)))
    (when (file-remote-p dir)
      (user-error "A Change session starts in a repository on this machine"))
    (expand-file-name dir)))

(defun kittymacs-pair--dispatch (repo branch brief)
  "Start a Change session on BRANCH of REPO, with the text BRIEF."
  (let* ((program (or (kittymacs-pair--dispatch-program)
                      (user-error "No pair-dispatch: set `kittymacs-pair-dispatch-command'")))
         (file (make-temp-file "change-brief-" nil ".md" brief))
         (output (get-buffer-create "*Change dispatch*"))
         (default-directory (expand-file-name "~/")))
    (with-current-buffer output
      (goto-char (point-max))
      (insert (format "\n%s %s\n" (string-join program " ") branch)))
    (make-process
     :name "pair-dispatch" :buffer output :noquery t
     :command (append program (list repo branch file))
     :sentinel (lambda (process _event)
                 (unless (process-live-p process)
                   (ignore-errors (delete-file file))
                   (if (zerop (process-exit-status process))
                       (message "Change session started on %s" branch)
                     (display-buffer output)
                     (message "Could not start a Change session on %s" branch)))))))

(defvar-local kittymacs-pair--brief-target nil
  "In a brief buffer, the repository and the branch, as a cons.")

(defvar-keymap kittymacs-pair-brief-mode-map
  :doc "Keys of a Change session's brief."
  "C-c C-c" #'kittymacs-pair-brief-send
  "C-c C-k" #'kittymacs-pair-brief-cancel)

(define-minor-mode kittymacs-pair-brief-mode
  "A brief for a Change session: \\[kittymacs-pair-brief-send] starts it."
  :lighter " Brief")

(defun kittymacs-pair-brief-send ()
  "Start the Change session this buffer is the brief of."
  (interactive)
  (pcase-let ((`(,repo . ,branch) kittymacs-pair--brief-target)
              (brief (buffer-string)))
    (kittymacs-pair--dispatch repo branch brief)
    (quit-window t)))

(defun kittymacs-pair-brief-cancel ()
  "Drop this brief."
  (interactive)
  (quit-window t))

(defun kittymacs-pair-dispatch (branch &optional brief)
  "Start a Change session on a new BRANCH of this project, from BRIEF.
Interactively, BRIEF is the region; without one, a buffer opens to write it."
  (interactive (list (read-string "Branch for the Change session: ")
                     (when (use-region-p)
                       (buffer-substring-no-properties (region-beginning) (region-end)))))
  (let ((repo (kittymacs-pair--repo)))
    (if brief
        (kittymacs-pair--dispatch repo branch brief)
      (pop-to-buffer (generate-new-buffer (format "*Change brief: %s*" branch)))
      (text-mode)
      (insert "Goal:\n\nContext:\n\nChecks:\n")
      (goto-char (point-min))
      (end-of-line)
      (insert " ")
      (setq kittymacs-pair--brief-target (cons repo branch))
      (kittymacs-pair-brief-mode 1)
      (setq header-line-format
            (substitute-command-keys
             "Brief for a Change session: \\[kittymacs-pair-brief-send] starts it, \\[kittymacs-pair-brief-cancel] drops it"))
      (when (fboundp 'meow--switch-state)
        (meow--switch-state 'insert)))))

(defun kittymacs-pair--asking-p (buffer)
  "Whether Claude's screen in BUFFER shows a question waiting for a choice.
Only the last lines count: the screen, not what scrolled away."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (let ((end (point)))
        (forward-line -12)
        (search-forward "Enter to confirm" end t)))))

(defun kittymacs-pair--mark-waiting (status-file message)
  "Mark the session of STATUS-FILE as waiting, with MESSAGE, and tell the hook."
  (when-let* ((status (and status-file (kittymacs-pair--read-json status-file)))
              ((not (equal (alist-get 'state status) "waiting"))))
    (setf (alist-get 'state status) "waiting"
          (alist-get 'message status) message
          (alist-get 'at status) (format-time-string "%FT%T%:z"))
    (let ((new (concat status-file ".new")))
      (with-temp-file new (insert (json-encode status) "\n"))
      (rename-file new status-file t))
    (run-hook-with-args 'kittymacs-pair-status-functions status-file)))

(defun kittymacs-pair--send-when-ready (session prompt status-file tries &optional settled)
  "Send PROMPT to SESSION once it is connected and asks nothing.
Claude Code can open on questions of its own, such as whether to trust the
folder, and a message typed into one would answer it.  While one waits,
STATUS-FILE, when given, says so.  TRIES counts the seconds waited; after
an hour this gives up.  SETTLED is set on the check after
`kittymacs-pair-ready-delay', which sends."
  (let ((buffer (claude-code-ide-mcp-session-buffer session)))
    (cond
     ((not (buffer-live-p buffer)))
     ((and (claude-code-ide-mcp-session-client session)
           (not (kittymacs-pair--asking-p buffer)))
      (if settled
          (claude-code-ide-send-prompt prompt session)
        (run-with-timer kittymacs-pair-ready-delay nil #'kittymacs-pair--send-when-ready
                        session prompt status-file tries t)))
     ((< tries 3600)
      (when (kittymacs-pair--asking-p buffer)
        (kittymacs-pair--mark-waiting status-file "Claude Code asks a question before it starts"))
      (run-with-timer 1 nil #'kittymacs-pair--send-when-ready
                      session prompt status-file (1+ tries)))
     (t (message "Claude in %s did not get ready within an hour; its first message was not sent"
                 (claude-code-ide-mcp-session-project-dir session))))))

(defun kittymacs-pair-start (worktree name prompt &rest environment)
  "Start claude-code-ide in WORKTREE as NAME, then send it PROMPT.
ENVIRONMENT is \"VARIABLE=value\" strings for the session's process; a
CC_PAIR_STATUS among them names its status file.  Return the session's
buffer name."
  (require 'claude-code-ide)
  (let* ((default-directory (file-name-as-directory (expand-file-name worktree)))
         (process-environment (append environment process-environment))
         (claude-code-ide-cli-extra-flags
          (string-trim (concat claude-code-ide-cli-extra-flags " -n "
                               (shell-quote-argument name))))
         (current-prefix-arg nil)
         (dir (claude-code-ide--get-working-directory)))
    (when (claude-code-ide-mcp--sessions-for-project dir)
      (user-error "%s has a Claude session already" dir))
    (claude-code-ide)
    (let ((session (car (claude-code-ide-mcp--sessions-for-project dir))))
      (kittymacs-pair--send-when-ready
       session prompt
       (cl-some (lambda (pair) (and (string-prefix-p "CC_PAIR_STATUS=" pair)
                                    (substring pair (length "CC_PAIR_STATUS="))))
                environment)
       0)
      (buffer-name (claude-code-ide-mcp-session-buffer session)))))
(defvar diff-review--head-name)
(defvar diff-review--tip)
(defvar diff-review--root)
(defvar diff-review--comments)

(defcustom kittymacs-pair-verdict-prompt
  "The owner's verdict on %s is %s, with %d open threads. Read the review's threads and answer them."
  "The message a Change session gets on a verdict.
Its arguments are the commit, the verdict and the number of open threads."
  :type 'string
  :group 'kittymacs)

(defun kittymacs-pair--status-for-branch (root branch)
  "The status file and contents of BRANCH's session in ROOT's repository, a cons."
  (when-let* ((common (kittymacs-pair--common-dir root))
              (dir (expand-file-name "agents/" common))
              ((file-directory-p dir)))
    (cl-loop for file in (directory-files dir t "\\.json\\'")
             for status = (kittymacs-pair--read-json file)
             when (equal (alist-get 'branch status) branch)
             return (cons file status))))

(defun kittymacs-pair--nudge (state)
  "Tell the Change session of this review's branch about the verdict STATE.
Runs after `diff-review--set-verdict', in the review's buffer."
  (when-let* ((branch diff-review--head-name)
              (tip diff-review--tip)
              (found (kittymacs-pair--status-for-branch diff-review--root branch))
              (session (kittymacs-pair--session (cdr found))))
    (claude-code-ide-send-prompt
     (format kittymacs-pair-verdict-prompt (substring tip 0 (min 7 (length tip))) state
             (cl-count-if-not (lambda (c) (eq (gethash "resolved" c) t))
                              diff-review--comments))
     session)))
(when (kittymacs-feature-p 'agent-claude-code-ide)
  (add-hook 'kittymacs-pair-status-functions #'kittymacs-pair-status-update)
  (add-to-list 'mode-line-misc-info '(:eval (kittymacs-pair-mode-line)))
  (keymap-set kittymacs-agent-map "d" (cons "Change sessions" #'kittymacs-pair-board))
  (keymap-set kittymacs-agent-map "j" (cons "jump to one waiting" #'kittymacs-pair-jump))
  (when (kittymacs-pair--dispatch-program)
    (keymap-set kittymacs-agent-map "C" (cons "start a Change session" #'kittymacs-pair-dispatch)))
  (with-eval-after-load 'meow
    (add-to-list 'meow-mode-state-list '(kittymacs-pair-board-mode . motion)))
  (with-eval-after-load 'diff-review
    (advice-add 'diff-review--set-verdict :after #'kittymacs-pair--nudge)))
(when (kittymacs-feature-p 'agent-eca)
  (use-package eca
    :ensure t
    :commands (eca eca-chat-new eca-chat-toggle-window eca-chat-select eca-chat-resume
               eca-chat-add-context-to-user-prompt eca-chat-add-filepath-to-user-prompt
               eca-chat-go-to-next-attention eca-transient-menu)
    :custom
    (eca-server-install-path
     (expand-file-name (if (eq system-type 'windows-nt) "eca/eca.exe" "eca/eca")
                       kittymacs-cache-dir)))

  (keymap-set kittymacs-agent-map "a" (cons "start or switch" #'eca))
  (keymap-set kittymacs-agent-map "n" (cons "new chat" #'eca-chat-new))
  (keymap-set kittymacs-agent-map "t" (cons "toggle" #'eca-chat-toggle-window))
  (keymap-set kittymacs-agent-map "b" (cons "switch chat" #'eca-chat-select))
  (keymap-set kittymacs-agent-map "r" (cons "resume chat" #'eca-chat-resume))
  (keymap-set kittymacs-agent-map "s" (cons "send region or file" #'eca-chat-add-context-to-user-prompt))
  (keymap-set kittymacs-agent-map "f" (cons "send a file path" #'eca-chat-add-filepath-to-user-prompt))
  (keymap-set kittymacs-agent-map "j" (cons "jump to waiting chat" #'eca-chat-go-to-next-attention))
  (keymap-set kittymacs-agent-map "?" (cons "menu" #'eca-transient-menu))

  (with-eval-after-load 'meow
    (dolist (entry '((eca-chat-mode . insert)
                     (eca-chat-compose-mode . insert)))
      (add-to-list 'meow-mode-state-list entry)))

  (kittymacs-define-localleader 'eca-chat-mode
    "i" (cons "stop" #'eca-chat-stop-prompt)
    "m" (cons "next agent" #'eca-chat-cycle-agent)
    "M" (cons "choose model" #'eca-chat-select-model)
    "y" (cons "accept tool call" #'eca-chat-tool-call-accept-next)
    "x" (cons "reject tool call" #'eca-chat-tool-call-reject-next)
    "Y" (cons "accept every call" #'eca-chat-tool-call-accept-all)
    "?" (cons "menu" #'eca-transient-menu)))
(defun kittymacs-agent-gptel-start-or-switch ()
  "Switch to this project's gptel-agent buffer, or start one where there is none."
  (interactive)
  (let ((root (expand-file-name (if-let* ((project (project-current)))
                                    (project-root project)
                                  default-directory))))
    (if-let* ((buffer (seq-find (lambda (buffer)
                                  (and (string-prefix-p "*gptel-agent:" (buffer-name buffer))
                                       (equal (expand-file-name
                                               (buffer-local-value 'default-directory buffer))
                                              root)))
                                (buffer-list))))
        (pop-to-buffer buffer)
      (gptel-agent root))))

(when (kittymacs-feature-p 'agent-gptel)
  (use-package gptel
    :ensure t
    :commands (gptel gptel-send gptel-menu gptel-add gptel-add-file gptel-abort))

  (use-package gptel-agent
    :ensure t
    :commands (gptel-agent))

  (keymap-set kittymacs-agent-map "a" (cons "start or switch" #'kittymacs-agent-gptel-start-or-switch))
  (keymap-set kittymacs-agent-map "n" (cons "new agent" #'gptel-agent))
  (keymap-set kittymacs-agent-map "s" (cons "add region or buffer" #'gptel-add))
  (keymap-set kittymacs-agent-map "f" (cons "add a file" #'gptel-add-file))
  (keymap-set kittymacs-agent-map "p" (cons "send" #'gptel-send))
  (keymap-set kittymacs-agent-map "i" (cons "interrupt" #'gptel-abort))
  (keymap-set kittymacs-agent-map "?" (cons "menu" #'gptel-menu)))

(provide 'kittymacs-agents)
;;; kittymacs-agents.el ends here
