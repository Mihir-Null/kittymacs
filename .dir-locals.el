;;; Directory Local Variables -*- no-byte-compile: t -*-
;; The chapters join the notes graph: with kittymacs, opening any page adds
;; this checkout to the graph that SPC n searches, and the graph remembers
;; it.  Plain Emacs asks whether to apply these variables; they do nothing
;; without kittymacs.  See literate/conventions.org.
((nil . ((kittymacs-org-node-project . t)
         (kittymacs-org-node-excluded-directories . ("var" "tests" "tools" "lisp")))))
