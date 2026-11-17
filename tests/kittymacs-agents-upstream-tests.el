;;; kittymacs-agents-upstream-tests.el --- Pinned ACP registry contract -*- lexical-binding: t; -*-
(require 'package)
(when-let* ((directory (getenv "KITTYMACS_TEST_PACKAGES")))
  (setq package-user-dir directory))
(package-initialize)
(require 'agent-shell)
(load (expand-file-name "kittymacs-agents-tests.el" (file-name-directory load-file-name)) nil t)

(ert-deftest kittymacs-agents-metadata-matches-the-real-upstream-registry ()
  (let ((configs (mapcar #'funcall (agent-shell-default-agent-config-makers))))
    (should (equal (sort (mapcar (lambda (config) (map-elt config :identifier)) configs) #'string<)
                   (sort (mapcar #'car kittymacs-agent-harnesses) #'string<)))
    (dolist (row kittymacs-agent-harnesses)
      ;; Existing installations can retain older defaults, and hosts may
      ;; override these options.  Check the contract, not the live command text.
      (let ((option (plist-get (cdr row) :command-option)))
        (should (get option 'custom-type))
        (should (consp (symbol-value option)))
        (should (seq-every-p #'stringp (symbol-value option))))
      (should (boundp (plist-get (cdr row) :environment-option))))))

(ert-deftest kittymacs-agents-real-environments-and-command-options-are-used ()
  (let* ((symbols (seq-mapcat (lambda (row)
                                (list (plist-get (cdr row) :command-option)
                                      (plist-get (cdr row) :environment-option)))
                              kittymacs-agent-harnesses))
         (values (mapcar #'symbol-value symbols))
         (kittymacs-agent-commands '((codex . ("test-wrapper" "codex-acp"))))
         (process-environment '("PATH=/acp-test" "HTTPS_PROXY=https://proxy.invalid")))
    (cl-progv symbols values
      (kittymacs-agent-configure-harnesses)
      (should (equal agent-shell-openai-codex-acp-command '("test-wrapper" "codex-acp")))
      (dolist (row kittymacs-agent-harnesses)
        (should (member "PATH=/acp-test"
                        (symbol-value (plist-get (cdr row) :environment-option))))))))
