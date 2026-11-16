;;; kittymacs-onboard-hint.el --- Reach onboarding from a started Emacs -*- lexical-binding: t; -*-
;; Generated from literate/22-onboarding.org; edit the Org source, then tangle.

;;; Code:

(require 'kittymacs-features)

(autoload 'kittymacs-onboard "kittymacs-onboard"
  "Choose what kittymacs installs, and write it to `private.el'." t)

(defun kittymacs-onboard-hint ()
  "Say where this machine started and where to choose, if it has chosen nothing."
  (unless (or noninteractive (daemonp)
              kittymacs-profile kittymacs-features kittymacs-features-excluded)
    (message "kittymacs: nothing chosen yet, so this is the %s profile.  SPC C o chooses, or `just onboard' in a terminal."
             (kittymacs-features-profile))))

(add-hook 'emacs-startup-hook #'kittymacs-onboard-hint 90)

(provide 'kittymacs-onboard-hint)
;;; kittymacs-onboard-hint.el ends here
