# Generated from literate/90-nix.org; edit the Org source, then tangle.
{
  pkgs,
  emacs ? pkgs.emacs,
}:

{
  inherit emacs;

  programs =
    with pkgs;
    [
      git # version control chapter (Magit)
      ripgrep # navigation chapter (consult-ripgrep, deadgrep)
      fd # navigation chapter (consult-fd)
      gnupg # startup chapter: GNU ELPA's signed index
      (hunspell.withDicts (d: [ d.en_US ])) # platform chapter: spelling
      python3 # Treemacs chapter: directory collapsing and the extended (colouring) git mode
      zig # terminal chapter: builds ghostel's native module
      # reading chapter: pdf-tools' server, linked out of nixpkgs' pdf-tools build
      (runCommand "epdfinfo" { } ''
        mkdir -p $out/bin
        ln -s ${emacsPackages.pdf-tools}/share/emacs/site-lisp/elpa/pdf-tools-*/epdfinfo $out/bin/epdfinfo
      '')
      mupdf-headless # reading chapter: pdf-text's extractor (mutool)
      direnv # shells chapter: envrc, each project's own environment
      (python3Packages.toPythonApplication python3Packages.jupytext) # notebooks chapter: .ipynb files
      math-preview # notebooks chapter: LaTeX drawn with MathJax
      # notebooks chapter: prints the path of emacs-zmq's native module, built by nixpkgs
      (runCommand "kittymacs-zmq-module" { } ''
        module=$(echo ${(emacsPackagesFor emacs).zmq}/share/emacs/site-lisp/elpa/zmq-*/emacs-zmq.*)
        mkdir -p $out/bin
        printf '#!%s\necho %s\n' ${runtimeShell} "$module" > $out/bin/kittymacs-zmq-module
        chmod +x $out/bin/kittymacs-zmq-module
      '')
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
      coreutils-prefixed # Dired chapter: GNU ls as `gls'
      darwin.trash # platform chapter: Trash with Finder's "Put Back"
    ];

  # Symbols Nerd Font Mono renders the icons.
  fonts = with pkgs; [
    nerd-fonts.symbols-only
  ];
}
