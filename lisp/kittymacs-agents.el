;;; kittymacs-agents.el --- Claude Code in a buffer -*- lexical-binding: t; -*-
;; Generated from literate/77-agents.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-leader)

(declare-function auth-source-pick-first-password "auth-source" (&rest spec))
(declare-function notifications-notify "notifications" (&rest params))
(use-package agent-shell
  :ensure t
  :commands (agent-shell agent-shell-toggle agent-shell-new-shell agent-shell-switch-buffer
             agent-shell-resume-session agent-shell-send-dwim agent-shell-send-file
             agent-shell-help-menu)
  :custom
  (agent-shell-preferred-agent-config 'claude-code)
  :config
  (setopt agent-shell-anthropic-claude-environment
          (agent-shell-make-environment-variables :inherit-env t)))
(defun kittymacs-agent-alphaxiv-headers ()
  "Return an Authorization header for alphaXiv's MCP server, or nil.
The key is the password `auth-source' holds for host api.alphaxiv.org."
  (require 'auth-source)
  (when-let* ((key (auth-source-pick-first-password :host "api.alphaxiv.org")))
    `(((name . "Authorization") (value . ,(concat "Bearer " key))))))

(setopt agent-shell-mcp-servers
        `(((name . "context7")
           (command . "context7-mcp")
           (args . ())
           (env . ()))
          ((name . "nixos")
           (command . "mcp-nixos")
           (args . ())
           (env . ()))
          ((name . "alphaxiv")
           (type . "http")
           (url . "https://api.alphaxiv.org/mcp/v1")
           (headers . ,(lambda () (kittymacs-agent-alphaxiv-headers))))))
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
   (display-warning 'kittymacs
                    (format "agent-shell-attention was not installed: %s
Check that `git clone https://github.com/ultronozm/agent-shell-attention.el' works from a terminal, and which git Emacs runs: %s"
                            (error-message-string err) (executable-find "git"))
                    :warning)))
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
  "?" (cons "menu" #'agent-shell-help-menu))

(provide 'kittymacs-agents)
;;; kittymacs-agents.el ends here
