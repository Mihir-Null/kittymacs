;;; kittymacs-agents.el --- A coding agent in a buffer -*- lexical-binding: t; -*-
;; Generated from literate/77-agents.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-defaults)
(require 'kittymacs-leader)

(declare-function notifications-notify "notifications" (&rest params))
(declare-function claude-code-ide "claude-code-ide" ())
(declare-function claude-code-ide-switch-to-buffer "claude-code-ide" ())
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
     (kittymacs-agent-vc-warning "claude-code-ide"
                                 "https://github.com/manzaltu/claude-code-ide.el" err)))

  (keymap-set kittymacs-agent-map "w" (cons "claude-code-ide sessions" kittymacs-claude-code-ide-map))
  ;; w, d and j stay unbound here: an integration adds its own there.
  (when (locate-library "claude-code-ide")
    (keymap-set kittymacs-claude-code-ide-map "n" (cons "new instance" #'claude-code-ide))
    (keymap-set kittymacs-claude-code-ide-map "b" (cons "pick a session" #'claude-code-ide-list-sessions))
    (keymap-set kittymacs-claude-code-ide-map "p" (cons "send a prompt" #'claude-code-ide-send-prompt))
    (keymap-set kittymacs-claude-code-ide-map "i" (cons "interrupt" #'claude-code-ide-send-escape))
    (keymap-set kittymacs-claude-code-ide-map "r" (cons "resume a session" #'claude-code-ide-resume))))

(when (kittymacs-feature-p 'agent-claude-code-ide)
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
