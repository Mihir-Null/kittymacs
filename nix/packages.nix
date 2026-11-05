# Generated from literate/90-nix.org; edit the Org source, then tangle.
# EMACS with the packages of FEATURES, or of every feature when FEATURES is
# null, then EXTRAPACKAGES.  copilot (unfree), consult-ghostel (not in nixpkgs)
# and the catalogue's Git packages stay out.
{
  emacs,
  features ? null,
  extraPackages ? null,
}:

emacs.pkgs.withPackages (
  epkgs:
  let
    # MELPA builds ws-butler from a clone of Savannah's whole NonGNU ELPA
    # repository; NonGNU ELPA's own release is one small tarball.
    inherit (epkgs.nongnuPackages) ws-butler;
    keyed = with epkgs; {
      meow = [ meow ];
      undo-tree = [ vundo ];
      structural-editing = [
        puni
        aggressive-indent
      ];
      surround = [ embrace ];
      syntax-things = [ meow-tree-sitter ];
      visual-replace = [ visual-regexp ];
      whitespace-cleanup = [ ws-butler ];
      snippets = [ yasnippet ];
      spelling = [
        flyspell-correct
        consult-flyspell
      ];
      completion = [
        vertico
        orderless
        marginalia
        consult
        embark
        embark-consult
        corfu
        cape
      ];
      directory-switch = [ consult-dir ];
      jump = [ avy ];
      window-picker = [ ace-window ];
      workspaces = [ tabspaces ];
      file-tree = [
        treemacs
        treemacs-nerd-icons
        treemacs-tab-bar
        treemacs-magit
      ];
      dired-extras = [
        diredfl
        dired-narrow
        dired-ranger
        async
      ];
      doom-look = [
        doom-themes
        doom-modeline
      ];
      icons = [
        nerd-icons
        nerd-icons-completion
        nerd-icons-corfu
        nerd-icons-dired
      ];
      code-display = [
        rainbow-delimiters
        highlight-indent-guides
      ];
      ui-polish = [
        spacious-padding
        hl-todo
        highlight-numbers
        goggles
        outline-minor-faces
      ];
      focus-mode = [
        writeroom-mode
        hide-mode-line
      ];
      frames = [ frames-only-mode ];
      home-page = [ dashboard ];
      popups = [ popper ];
      color-names = [ rainbow-mode ];
      help-extras = [
        helpful
        elisp-demos
        info-colors
      ];
      command-menus = [ casual ];
      key-display = [ keycast ];
      version-control = [ magit ];
      diff-hl = [ diff-hl ];
      project-environment = [ envrc ];
      shell-path = [ exec-path-from-shell ];
      terminal = [ ghostel ];
      eshell-highlight = [ eshell-syntax-highlighting ];
      org-extras = [
        org-ql
        org-super-agenda
        org-contrib
        org-modern
        org-appear
      ];
      linked-notes = [ org-roam ];
      pdf-reading = [
        pdf-tools
        org-noter
        org-pdftools
        org-noter-pdftools
      ];
      more-checkers = [ flymake-collection ];
      notebooks = [
        code-cells
        math-preview
      ];
      jupyter = [ jupyter ];
      lang-nix = [
        nix-mode
        nix-ts-mode
      ];
      lang-racket = [ racket-mode ];
      lang-guile = [
        geiser
        geiser-guile
      ];
      agents = [ agent-shell ];
      suggestions = [ ];
      window-manager = [ exwm ];
    };
    chosen = if features == null then builtins.attrNames keyed else features;
    rank = package: builtins.replaceStrings [ "-" ] [ "" ] package.pname;
  in
  builtins.sort (a: b: rank a < rank b) (builtins.concatMap (feature: keyed.${feature}) chosen)
  ++ (if extraPackages == null then [ ] else extraPackages epkgs)
)
