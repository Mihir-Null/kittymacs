;;; kittymacs-agents-tests.el --- ACP host settings -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path (expand-file-name "../lisp" (file-name-directory load-file-name)))
(require 'kittymacs-features)
(defvar agent-shell-preferred-agent-config nil)
(let ((kittymacs-profile 'minimal) (kittymacs-features nil))
  (require 'kittymacs-agents))

(ert-deftest kittymacs-agents-offers-the-picker-by-default ()
  (should-not (default-value 'kittymacs-agent-harness)))

(ert-deftest kittymacs-agents-harnesses-are-complete-and-sorted ()
  ;; Snapshot of every configuration identifier in the pinned upstream registry.
  (should (equal (sort (mapcar #'car kittymacs-agent-harnesses) #'string<)
                 '(antigravity auggie claude-code cline codebuddy codex copilot cursor
                   deepseek droid gemini-cli goose grok-build hermes junie kimi kiro
                   mistral-vibe omp openclaw opencode pi qoder qwen-code)))
  (let ((labels (mapcar (lambda (row) (plist-get (cdr row) :label))
                        kittymacs-agent-harnesses)))
    (should (equal labels (sort (copy-sequence labels)
                               (lambda (a b) (string< (downcase a) (downcase b))))))))

(ert-deftest kittymacs-agents-preserves-explicit-environments-and-unlisted-commands ()
  (let* ((kittymacs-agent-harnesses
          '((codex :command-option kittymacs-agents-test-command
                   :environment-option kittymacs-agents-test-environment)))
         (kittymacs-agent-commands nil))
    (cl-progv '(kittymacs-agents-test-command kittymacs-agents-test-environment)
        '(("original") ("TOKEN=explicit"))
      (cl-letf (((symbol-function 'agent-shell-make-environment-variables)
                 (lambda (&rest _) (ert-fail "Replaced an explicit environment"))))
        (kittymacs-agent-configure-harnesses)
        (should (equal (symbol-value 'kittymacs-agents-test-command) '("original")))
        (should (equal (symbol-value 'kittymacs-agents-test-environment)
                       '("TOKEN=explicit")))))))

(ert-deftest kittymacs-agents-applies-wrappers-and-inherits-unset-environments ()
  (let* ((kittymacs-agent-harnesses
          '((claude-code :command-option kittymacs-agents-test-command
                         :environment-option kittymacs-agents-test-environment)))
         (kittymacs-agent-commands '((claude-code . ("wrapper" "--acp")))))
    (cl-progv '(kittymacs-agents-test-command kittymacs-agents-test-environment)
        '(("legacy-claude-command") nil)
      (cl-letf (((symbol-function 'agent-shell-make-environment-variables)
                 (lambda (&rest args)
                   (should (equal args '(:inherit-env t)))
                   '("PATH=/test"))))
        (kittymacs-agent-configure-harnesses)
        (should (equal (symbol-value 'kittymacs-agents-test-command)
                       '("wrapper" "--acp")))
        (should (equal (symbol-value 'kittymacs-agents-test-environment)
                       '("PATH=/test")))))))

(ert-deftest kittymacs-agents-rejects-malformed-command-overrides ()
  (let ((kittymacs-agent-harnesses '((codex :command-option unused)))
        (kittymacs-agent-commands '((codex . "a shell string"))))
    (should-error (kittymacs-agent-configure-harnesses))))

(ert-deftest kittymacs-agents-can-pick-another-harness-without-changing-the-default ()
  (let ((agent-shell-preferred-agent-config 'codex) called)
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest _)
                 (should (eq feature 'agent-shell)) t))
              ((symbol-function 'agent-shell-new-shell)
               (lambda ()
                 (should-not agent-shell-preferred-agent-config)
                 (setq called t))))
      (kittymacs-agent-choose-harness))
    (should called)
    (should (eq agent-shell-preferred-agent-config 'codex))))
