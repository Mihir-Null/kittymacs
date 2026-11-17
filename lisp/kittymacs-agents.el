;;; kittymacs-agents.el --- A coding agent in a buffer -*- lexical-binding: t; -*-
;; Generated from literate/77-agents.org; edit the Org source, then tangle.

;;; Code:

(require 'map)
(require 'seq)
(require 'kittymacs-catalogue)
(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(declare-function notifications-notify "notifications" (&rest params))
(declare-function claude-code-ide "claude-code-ide" ())
(declare-function claude-code-ide-switch-to-buffer "claude-code-ide" ())
(declare-function agent-shell-make-environment-variables "agent-shell" (&rest vars))
(declare-function agent-shell-subscribe-to "agent-shell" (&rest args))
(declare-function agent-shell-attention-acknowledge "agent-shell-attention" (buffer))
(declare-function agent-shell-attention--mark-buffer "agent-shell-attention" (buffer label &rest args))
(defvar agent-shell-elicitation--experimental-feature-enabled)
(defvar agent-shell-preferred-agent-config)
(declare-function agent-shell-new-shell "agent-shell" ())
(declare-function gptel-agent "gptel-agent" (&optional project-dir agent-preset))
(defun kittymacs-agent-choose-harness ()
  "Start a new shell with the ACP picker, regardless of the saved default."
  (interactive)
  (require 'agent-shell)
  (let ((agent-shell-preferred-agent-config nil))
    (agent-shell-new-shell)))

(defcustom kittymacs-agent-harness nil
  "Default ACP harness identifier, or nil to ask when starting a shell.
See `kittymacs-agent-harnesses' for built-ins.  A custom identifier must
also have a configuration in `agent-shell-agent-configs'."
  :type 'symbol
  :group 'kittymacs)

(defcustom kittymacs-agent-commands nil
  "Command overrides by ACP harness identifier.
Each entry is (IDENTIFIER . (PROGRAM ARG...)).  Unlisted harnesses use
agent-shell's command options.  Set this before the agents module loads."
  :type '(alist :key-type symbol :value-type (repeat string))
  :group 'kittymacs)

(defun kittymacs-agent-configure-harnesses ()
  "Apply host command overrides and default environments to ACP harnesses."
  (dolist (row kittymacs-agent-harnesses)
    (let* ((identifier (car row))
           (command-option (plist-get (cdr row) :command-option))
           (environment-option (plist-get (cdr row) :environment-option))
           (override (alist-get identifier kittymacs-agent-commands)))
      (when override
        (unless (and (consp override) (seq-every-p #'stringp override))
          (error "Invalid ACP command for %s: %S" identifier override))
        (set command-option override))
      (when (and (boundp environment-option) (not (symbol-value environment-option)))
        (set environment-option
             (agent-shell-make-environment-variables :inherit-env t))))))

(defcustom kittymacs-agent-claude-command '("claude-agent-acp")
  "The command agent-shell runs for Claude: a program, then its arguments.
The program is looked up on `exec-path'.  Set this before this module
loads, in `private.el' or a host file."
  :type '(repeat string)
  :group 'kittymacs)

(when (kittymacs-feature-p 'agents)
  (condition-case err
      (progn
        (use-package acp
          :vc (:url "https://github.com/xenodium/acp.el"
               :rev "2959da5fa8657da17a78ac6ceef303a50e3e69de")
          :defer t)
        (use-package agent-shell
          :vc (:url "https://github.com/xenodium/agent-shell"
               :rev "14e8e2a2f2b495f83c9d7b18be7838e45d75bf56")
          :commands (agent-shell agent-shell-interrupt agent-shell-toggle agent-shell-new-shell agent-shell-switch-buffer
                     agent-shell-resume-session agent-shell-send-dwim agent-shell-send-file
                     agent-shell-help-menu)
          :init
          ;; Private and experimental: without it agent-shell offers no form,
          ;; so Claude's AskUserQuestion never reaches you.
          (setq agent-shell-elicitation--experimental-feature-enabled t)
          :custom
          (agent-shell-preferred-agent-config kittymacs-agent-harness)
          (agent-shell-anthropic-claude-acp-command kittymacs-agent-claude-command)
          (agent-shell-activity-group-expand-by-default nil)
          (agent-shell-highlight-blocks nil)
          (agent-shell-header-style 'text)
          :config
          (kittymacs-agent-configure-harnesses)))
    (error
     (kittymacs-features-vc-warning "agent-shell" "https://github.com/xenodium/agent-shell" err))))
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

(defun kittymacs-agent--question-event (buffer event)
  "Count a question form in BUFFER as waiting, from EVENT, until it is answered."
  (pcase (map-elt event :event)
    ('elicitation-request
     (let ((label (concat "Question: " (or (map-elt (map-elt event :data) :message) ""))))
       (when (fboundp 'agent-shell-attention--mark-buffer)
         (agent-shell-attention--mark-buffer buffer label :force t))
       (unless (eq (window-buffer (selected-window)) buffer)
         (kittymacs-agent-notify buffer (format "%s agent" (buffer-name buffer)) label))))
    ('elicitation-response
     (when (fboundp 'agent-shell-attention-acknowledge)
       (agent-shell-attention-acknowledge buffer)))))

(defun kittymacs-agent-watch-questions ()
  "Let this agent-shell buffer's question forms count as waiting."
  (let ((buffer (current-buffer)))
    (agent-shell-subscribe-to
     :shell-buffer buffer
     :on-event (lambda (event)
                 (when (buffer-live-p buffer)
                   (kittymacs-agent--question-event buffer event))))))

(when (kittymacs-feature-p 'agents)
  (condition-case err
      (use-package agent-shell-attention
        :vc (:url "https://github.com/ultronozm/agent-shell-attention.el"
             :rev "8d5116f174fc35177aedc0f967a8fa3d6784aa1b")
        :after agent-shell
        :demand t
        :custom
        (agent-shell-attention-notify-function #'kittymacs-agent-notify)
        :config
        (agent-shell-attention-mode 1))
    (error
     (kittymacs-features-vc-warning "agent-shell-attention"
                                    "https://github.com/ultronozm/agent-shell-attention.el" err)))

  (when (locate-library "agent-shell-attention")
    (keymap-set kittymacs-agent-map "j" (cons "jump to waiting shell" #'agent-shell-attention-jump))
    (keymap-set kittymacs-agent-map "d" (cons "all shells" #'agent-shell-attention-dashboard))
    (add-hook 'agent-shell-mode-hook #'kittymacs-agent-watch-questions)))
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

(defvar-keymap kittymacs-claude-code-ide-map
  :doc "claude-code-ide's sessions, on SPC a w.
w, d and j are left free for an integration's own commands.")

(when (kittymacs-feature-p 'claude-code-ide)
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
     (kittymacs-features-vc-warning "claude-code-ide"
                                    "https://github.com/manzaltu/claude-code-ide.el" err)))

  (keymap-set kittymacs-agent-map "w" (cons "claude-code-ide sessions" kittymacs-claude-code-ide-map))
  ;; w, d and j stay unbound here: an integration adds its own there.
  (when (locate-library "claude-code-ide")
    (keymap-set kittymacs-claude-code-ide-map "n" (cons "new instance" #'claude-code-ide))
    (keymap-set kittymacs-claude-code-ide-map "b" (cons "pick a session" #'claude-code-ide-list-sessions))
    (keymap-set kittymacs-claude-code-ide-map "p" (cons "send a prompt" #'claude-code-ide-send-prompt))
    (keymap-set kittymacs-claude-code-ide-map "i" (cons "interrupt" #'claude-code-ide-send-escape))
    (keymap-set kittymacs-claude-code-ide-map "r" (cons "resume a session" #'claude-code-ide-resume))))
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
    :commands (gptel-agent)))
(defconst kittymacs-agent-interface-commands
  '((agent-shell
     ("a" "start or switch" agent-shell)
     ("n" "new shell" agent-shell-new-shell)
     ("t" "toggle" agent-shell-toggle)
     ("b" "switch shell" agent-shell-switch-buffer)
     ("r" "resume session" agent-shell-resume-session)
     ("s" "send region or file" agent-shell-send-dwim)
     ("f" "send file" agent-shell-send-file)
     ("i" "interrupt" agent-shell-interrupt)
     ("?" "menu" agent-shell-help-menu))
    (gptel-agent
     ("a" "start or switch" kittymacs-agent-gptel-start-or-switch)
     ("n" "new agent" gptel-agent)
     ("s" "add region or buffer" gptel-add)
     ("f" "add file" gptel-add-file)
     ("p" "send" gptel-send)
     ("i" "interrupt" gptel-abort)
     ("?" "menu" gptel-menu))
    (claude-code-ide
     ("a" "start or switch" kittymacs-agent-claude-code-ide-start-or-switch)
     ("n" "new instance" claude-code-ide)
     ("t" "toggle" claude-code-ide-toggle)
     ("b" "switch instance" claude-code-ide-list-sessions)
     ("r" "resume session" claude-code-ide-resume)
     ("s" "send region" claude-code-ide-insert-at-mentioned)
     ("p" "send prompt" claude-code-ide-send-prompt)
     ("i" "interrupt" claude-code-ide-send-escape)
     ("?" "menu" claude-code-ide-menu)))
  "Commands by interface: key, label and interactive command.")

(defvar-keymap kittymacs-agent-shell-map :doc "ACP sessions on SPC a e.")
(defvar-keymap kittymacs-gptel-agent-map :doc "gptel-agent on SPC a g.")

(defun kittymacs-agent--available-interfaces ()
  "Return enabled interfaces whose packages can load."
  (seq-filter (lambda (row)
                (and (kittymacs-feature-p (plist-get (cdr row) :feature))
                     (locate-library (plist-get (cdr row) :library))))
              kittymacs-agent-interfaces))

(defun kittymacs-agent--primary ()
  "Return the available primary interface, including legacy preferences."
  (let* ((available (mapcar #'car (kittymacs-agent--available-interfaces)))
         (legacy (cond ((kittymacs-feature-p 'agent-claude-code-ide) 'claude-code-ide)
                       ((and (memq 'agent-gptel kittymacs-features)
                             (not (memq 'agents kittymacs-features))) 'gptel-agent)))
         (preferred (or kittymacs-agent-primary-interface legacy)))
    (if (memq preferred available) preferred (car available))))

(defun kittymacs-agent--dispatch (key)
  "Run the primary interface's command for KEY."
  (let* ((interface (kittymacs-agent--primary))
         (command (nth 2 (assoc key (alist-get interface kittymacs-agent-interface-commands)))))
    (unless command (user-error "Primary interface %s has no command for %s" interface key))
    (call-interactively command)))

(defun kittymacs-agent-start ()
  "Run the primary interface's start command."
  (interactive)
  (kittymacs-agent--dispatch "a"))

(defun kittymacs-agent-new ()
  "Run the primary interface's new command."
  (interactive)
  (kittymacs-agent--dispatch "n"))

(defun kittymacs-agent-toggle ()
  "Run the primary interface's toggle command."
  (interactive)
  (kittymacs-agent--dispatch "t"))

(defun kittymacs-agent-switch ()
  "Run the primary interface's switch command."
  (interactive)
  (kittymacs-agent--dispatch "b"))

(defun kittymacs-agent-resume ()
  "Run the primary interface's resume command."
  (interactive)
  (kittymacs-agent--dispatch "r"))

(defun kittymacs-agent-send ()
  "Run the primary interface's send command."
  (interactive)
  (kittymacs-agent--dispatch "s"))

(defun kittymacs-agent-file ()
  "Run the primary interface's file command."
  (interactive)
  (kittymacs-agent--dispatch "f"))

(defun kittymacs-agent-prompt ()
  "Run the primary interface's prompt command."
  (interactive)
  (kittymacs-agent--dispatch "p"))

(defun kittymacs-agent-interrupt ()
  "Run the primary interface's interrupt command."
  (interactive)
  (kittymacs-agent--dispatch "i"))

(defun kittymacs-agent-menu ()
  "Run the primary interface's menu command."
  (interactive)
  (kittymacs-agent--dispatch "?"))

(defconst kittymacs-agent--dispatchers
  '(("a" . kittymacs-agent-start) ("n" . kittymacs-agent-new)
    ("t" . kittymacs-agent-toggle) ("b" . kittymacs-agent-switch)
    ("r" . kittymacs-agent-resume) ("s" . kittymacs-agent-send)
    ("f" . kittymacs-agent-file) ("p" . kittymacs-agent-prompt)
    ("i" . kittymacs-agent-interrupt) ("?" . kittymacs-agent-menu))
  "Shared key dispatchers, independent of package command names.")

(defun kittymacs-agent--bind-primary ()
  "Bind shared keys for the primary interface, preserving extension keys."
  (dolist (entry kittymacs-agent--dispatchers)
    (keymap-unset kittymacs-agent-map (car entry) t))
  (let ((commands (alist-get (kittymacs-agent--primary) kittymacs-agent-interface-commands)))
    (when (assoc "a" commands)
      (keymap-set kittymacs-agent-map "a" (cons "start or switch" #'kittymacs-agent-start)))
    (when (assoc "n" commands)
      (keymap-set kittymacs-agent-map "n" (cons "new session" #'kittymacs-agent-new)))
    (when (assoc "t" commands)
      (keymap-set kittymacs-agent-map "t" (cons "toggle" #'kittymacs-agent-toggle)))
    (when (assoc "b" commands)
      (keymap-set kittymacs-agent-map "b" (cons "switch session" #'kittymacs-agent-switch)))
    (when (assoc "r" commands)
      (keymap-set kittymacs-agent-map "r" (cons "resume" #'kittymacs-agent-resume)))
    (when (assoc "s" commands)
      (keymap-set kittymacs-agent-map "s" (cons "send context" #'kittymacs-agent-send)))
    (when (assoc "f" commands)
      (keymap-set kittymacs-agent-map "f" (cons "send file" #'kittymacs-agent-file)))
    (when (assoc "p" commands)
      (keymap-set kittymacs-agent-map "p" (cons "send prompt" #'kittymacs-agent-prompt)))
    (when (assoc "i" commands)
      (keymap-set kittymacs-agent-map "i" (cons "interrupt" #'kittymacs-agent-interrupt)))
    (when (assoc "?" commands)
      (keymap-set kittymacs-agent-map "?" (cons "menu" #'kittymacs-agent-menu)))))

(defun kittymacs-agent-set-primary (interface)
  "Choose INTERFACE for the shared agent keys for this Emacs session."
  (interactive
   (list (intern (completing-read
                  "Primary interface: "
                  (mapcar (lambda (row) (symbol-name (car row)))
                          (kittymacs-agent--available-interfaces)) nil t))))
  (unless (assq interface (kittymacs-agent--available-interfaces))
    (user-error "Interface %s is disabled or its package is missing" interface))
  (setq kittymacs-agent-primary-interface interface)
  (kittymacs-agent--bind-primary))

(dolist (row (kittymacs-agent--available-interfaces))
  (let* ((interface (car row))
         (map (pcase interface
                ('agent-shell kittymacs-agent-shell-map)
                ('gptel-agent kittymacs-gptel-agent-map)
                ('claude-code-ide kittymacs-claude-code-ide-map))))
    (dolist (entry (alist-get interface kittymacs-agent-interface-commands))
      (keymap-set map (car entry) (cons (nth 1 entry) (nth 2 entry))))))

(when (assq 'agent-shell (kittymacs-agent--available-interfaces))
  (keymap-set kittymacs-agent-map "e" (cons "ACP sessions" kittymacs-agent-shell-map)))
(when (assq 'gptel-agent (kittymacs-agent--available-interfaces))
  (keymap-set kittymacs-agent-map "g" (cons "gptel-agent" kittymacs-gptel-agent-map)))

(when (and (kittymacs-feature-p 'agents) (locate-library "agent-shell"))
  (keymap-set kittymacs-agent-map "h" (cons "choose ACP harness" #'kittymacs-agent-choose-harness))
  (keymap-set kittymacs-agent-shell-map "h" (cons "choose ACP harness" #'kittymacs-agent-choose-harness))
  (when (locate-library "agent-shell-attention")
    (keymap-set kittymacs-agent-shell-map "j" (cons "waiting shell" #'agent-shell-attention-jump))
    (keymap-set kittymacs-agent-shell-map "d" (cons "all shells" #'agent-shell-attention-dashboard))))
(when (kittymacs-agent--available-interfaces)
  (keymap-set kittymacs-agent-map "P" (cons "choose primary interface" #'kittymacs-agent-set-primary)))
(kittymacs-agent--bind-primary)

(provide 'kittymacs-agents)
;;; kittymacs-agents.el ends here
