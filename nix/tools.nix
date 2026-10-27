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

  # The editing font, the prose font and the icon font.
  fonts = with pkgs; [
    # Older nixpkgs (nixos-26.05) has no Nerd Font build of it.
    (nerd-fonts.googlesanscode or googlesans-code)
    (stdenvNoCC.mkDerivation {
      pname = "google-sans-flex";
      version = "0-unstable-2026-10-27";
      # Not yet in nixpkgs' google-fonts; replace with
      # `google-fonts.override { fonts = [ "GoogleSansFlex" ]; }` once it is.
      src = fetchurl {
        name = "GoogleSansFlex.ttf";
        url = "https://raw.githubusercontent.com/google/fonts/ddf386ba1b9fbc6b2c818f1ddcd9148f54ced94b/ofl/googlesansflex/GoogleSansFlex%5BROND%2Copsz%2Cslnt%2Cwdth%2Cwght%5D.ttf";
        hash = "sha256-qax3B5iFfV6KxZPO1Csi5Ap8CM7Jgxn5Kw7Mwng6d7o=";
      };
      dontUnpack = true;
      installPhase = ''
        install -Dm444 $src $out/share/fonts/truetype/GoogleSansFlex.ttf
      '';
      meta.license = lib.licenses.ofl;
    })
    nerd-fonts.symbols-only
  ];
}
