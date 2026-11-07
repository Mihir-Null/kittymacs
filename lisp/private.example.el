;;; private.example.el --- Example local overrides -*- lexical-binding: t; -*-
;; Generated from literate/80-maintenance.org; edit the Org source, then tangle.

;; Copy to private.el for account and machine settings that should not be
;; committed.  init.el loads private.el early, before most chapters, because
;; they read the kittymacs options below while they load.  Set those at top
;; level with `setopt'.  A package option that a chapter also sets must go in
;; the `after-init-hook' function at the end of this file instead: the chapter
;; runs after this file and would replace a top-level value.

;; Features
;; Where this machine starts, and what it adds or leaves out; the names are in
;; literate/20-catalogue.org.  Set these here or in a host file: Customize's
;; file loads too late.  A feature's packages install on the next start.
;; `just onboard' or SPC C o asks instead, and writes a block of these here.
;; (setopt kittymacs-profile 'minimal)
;; (setopt kittymacs-features '(jump lang-nix))
;; (setopt kittymacs-features-excluded '(suggestions agents))

;; Identity
;; (setq user-full-name "Your Name"
;;       user-mail-address "you@example.com")

;; Paths
;; (setopt kittymacs-project-directory (expand-file-name "~/src/"))
;; (setopt kittymacs-org-directory (expand-file-name "~/Documents/my-org/"))

;; Linked notes, read when the Org-roam chapter loads.  The exclusions are
;; folder names left out of the personal graph at any depth.
;; (setopt kittymacs-org-roam-directory (expand-file-name "~/notes/"))
;; (setopt kittymacs-org-roam-excluded-directories
;;         '(".git" ".cache" "cache" "caches" "archive"))
;; A project becomes a graph of its own with a .dir-locals.el at its root,
;; not with settings here; see literate/71-org-roam.org:
;;   ((nil . ((kittymacs-org-roam-project . t)
;;            (kittymacs-org-roam-excluded-directories . ("secrets")))))

;; Agents
;; The MCP servers each agent-shell session starts with; see
;; literate/77-agents.org.
;; (setopt kittymacs-agent-mcp-servers
;;         '(((name . "docs") (command . "docs-mcp") (args . ()) (env . ()))))

;; Backends
;; The machines this Emacs works on, by name; SPC o b opens one's project and
;; SPC o B says what it has.  See literate/36-remote.org.
;; (setopt kittymacs-backends
;;         '(("build" :transport ssh :host "build.example.org" :root "~/src/project/")
;;           ("wsl" :transport wsl :host "Ubuntu-24.04" :root "~/src/project/")))
;; The same distribution through tramp-rpc's server, which is opt-in: a quicker,
;; sturdier way in.  It needs the wsl-rpc feature and the server.  See literate/36-remote.org.
;; (setopt kittymacs-features '(wsl-rpc)
;;         kittymacs-backends
;;         '(("wsl" :transport wsl-rpc :host "Ubuntu-24.04" :root "~/src/project/")))
;; What the doctor looks for, and where Tramp searches after the login shell's PATH.
;; (setopt kittymacs-backend-tools '("git" "rg" "pyright-langserver"))
;; (setopt kittymacs-remote-nix-path '("~/.nix-profile/bin"))
;; Which completion sources may run on their own in a remote buffer.
;; (setopt kittymacs-remote-auto-capfs '(eglot-completion-at-point))

;; A fallback for Windows-side files, where file I/O across WSL would ruin
;; performance.  Each start warns.  See msys2-fallback in literate/37-msys2.org.
;; (setopt kittymacs-features '(msys2-fallback)
;;         kittymacs-msys2-root "D:/Tools/msys64/")

;; Terminal
;; Where the escape key goes while a full-screen program is drawing in the
;; terminal (`auto', `terminal' or `meow').
;; (setopt kittymacs-terminal-escape 'terminal)

;; macOS
;; Swap Command and Option, or give the right Option key to Emacs too:
;; (setopt kittymacs-macos-modifiers '((ns-command-modifier . meta)
;;                                     (ns-option-modifier . super)
;;                                     (ns-right-option-modifier . meta)))

;; Structural editing
;; Which modes keep brackets balanced with Puni.  Some people want it in Lisp and
;; nowhere else, and a mode here covers the modes derived from it.
;; (setopt kittymacs-structural-editing-modes '(emacs-lisp-mode lisp-mode))

;; Language tooling
;; Eglot is available manually through SPC l e.  Automatic startup and
;; external language packages are opt-in because their servers and runtimes
;; belong to the platform.
;; (setopt kittymacs-eglot-auto-start-modes '(python-mode python-ts-mode)
;;         kittymacs-language-packages '(nix racket guile))

;; Suggestions
;; Copilot's ghost text and next edits in every programming file, which
;; sends those files to GitHub.  Off by default; SPC t a turns them on in one
;; buffer.  Files matching kittymacs-suggestions-excluded-files never get them.
;; (setopt kittymacs-suggestions t)

;; Notebooks
;; Jupyter kernels through emacs-jupyter (SPC m n j).  Off by default: it
;; needs emacs-zmq's native module, which the Nix tools provide and which
;; emacs-zmq otherwise downloads or builds, asking first.
;; (setopt kittymacs-notebooks-jupyter t)

;; UI
;; (setopt kittymacs-theme 'doom-dark+
;;         kittymacs-light-theme 'doom-one-light
;;         kittymacs-font-family "GoogleSansCode Nerd Font"
;;         kittymacs-icons 'auto
;;         kittymacs-nerd-font "Symbols Nerd Font Mono")

;; Package options that a chapter also sets.  Depth 90 runs this after the
;; chapters' own after-init functions.
;; (add-hook 'after-init-hook
;;           (lambda ()
;;             ;; Let programs in the terminal write the system clipboard
;;             ;; (OSC 52).  Handy over SSH; it also lets anything you `cat'
;;             ;; set your clipboard.
;;             (setopt ghostel-enable-osc52 t)
;;             ;; Route `compile', `recompile' and `project-compile' through
;;             ;; a real terminal instead of Emacs's compilation buffer.
;;             (ghostel-compile-global-mode 1)
;;             ;; Set when ghostel loads, so wait for it.
;;             (with-eval-after-load 'ghostel
;;               (setopt ghostel-shell '("/bin/zsh" "--login"))))
;;           90)
