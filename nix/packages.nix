# Generated from literate/90-nix.org; edit the Org source, then tangle.
# EMACS with every package the chapters declare with `:ensure t`, except
# copilot (unfree) and consult-ghostel (not in nixpkgs).
{ emacs }:

emacs.pkgs.withPackages (
  epkgs:
  let
    # MELPA builds ws-butler from a clone of Savannah's whole NonGNU ELPA
    # repository; NonGNU ELPA's own release is one small tarball.
    inherit (epkgs.nongnuPackages) ws-butler;
  in
  with epkgs;
  [
    ace-window
    agent-shell
    aggressive-indent
    async
    avy
    cape
    casual
    code-cells
    consult
    consult-dir
    consult-flyspell
    corfu
    dashboard
    diff-hl
    diredfl
    dired-narrow
    dired-ranger
    doom-modeline
    doom-themes
    elisp-demos
    embark
    embark-consult
    embrace
    envrc
    eshell-syntax-highlighting
    exec-path-from-shell
    exwm
    flymake-collection
    flyspell-correct
    frames-only-mode
    geiser
    geiser-guile
    ghostel
    goggles
    helpful
    hide-mode-line
    highlight-indent-guides
    highlight-numbers
    hl-todo
    info-colors
    jupyter
    keycast
    magit
    marginalia
    math-preview
    meow
    meow-tree-sitter
    nerd-icons
    nerd-icons-completion
    nerd-icons-corfu
    nerd-icons-dired
    nix-mode
    nix-ts-mode
    orderless
    org-appear
    org-contrib
    org-modern
    org-noter
    org-noter-pdftools
    org-pdftools
    org-ql
    org-roam
    org-super-agenda
    outline-minor-faces
    pdf-tools
    popper
    puni
    racket-mode
    rainbow-delimiters
    rainbow-mode
    spacious-padding
    tabspaces
    treemacs
    treemacs-magit
    treemacs-nerd-icons
    treemacs-tab-bar
    vertico
    visual-regexp
    vundo
    writeroom-mode
    ws-butler
    yasnippet
  ]
)
