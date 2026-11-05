;;; removed-packages.eld --- Packages kittymacs no longer has -*- mode: lisp-data; -*-
;; tests/kittymacs-lint-tests.el fails if prose or code still names one, outside
;; the record of what was dropped in ARCHITECTURE.md.  When a package goes, add
;; it here, with what covers it now.
(
 (deadgrep . "consult-ripgrep with embark-export")
 (visual-regexp-steroids . "visual-regexp, on Emacs's own engine")
 (elisp-def . "xref and Helpful")
 (rainbow-identifiers . "nothing, it was a toggle")
 (goto-last-change . "Vundo and the mark ring")
 (package-lint . "nothing here is published to an archive")
 (dimmer . "the cursor and the pulse mark the active window")
 (iedit . "Meow's Beacon state")
 (imenu-list . "SPC b j and Treemacs")
 (eshell-up . "z for visited directories, cd ..")
 (esh-help . "nothing")
 (pcmpl-args . "Eshell's own completion")
 (pcomplete-extension . "Eshell's own completion")
)
