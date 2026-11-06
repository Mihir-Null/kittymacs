# Generated from literate/90-nix.org; edit the Org source, then tangle.
{
  pkgs,
  emacs ? pkgs.emacs,
}:

let
  inherit (pkgs) lib;
  tool = feature: command: package: { inherit feature command package; };
  font = feature: package: { inherit feature package; };
  isOn = features: entry: entry.feature == null || lib.elem entry.feature features;
  packagesOf = map (entry: entry.package);

  programTable =
    with pkgs;
    [
      (tool "version-control" "git" git) # version control chapter (Magit)
      (tool "completion" "rg" ripgrep) # navigation chapter (consult-ripgrep)
      (tool "completion" "fd" fd) # navigation chapter (consult-fd)
      (tool null "gpg" gnupg) # startup chapter: GNU ELPA's signed index
      (tool "spelling" "hunspell" (hunspell.withDicts (d: [ d.en_US ]))) # platform chapter: spelling
      (tool "file-tree" "python3" python3) # Treemacs chapter: directory collapsing and the extended (colouring) git mode
      (tool "terminal" "zig" zig) # terminal chapter: builds ghostel's native module
      # reading chapter: pdf-tools' server, linked out of nixpkgs' pdf-tools build
      (tool "pdf-reading" "epdfinfo" (
        runCommand "epdfinfo" { } ''
          mkdir -p $out/bin
          ln -s ${emacsPackages.pdf-tools}/share/emacs/site-lisp/elpa/pdf-tools-*/epdfinfo $out/bin/epdfinfo
        ''
      ))
      (tool "pdf-reading" "mutool" mupdf-headless) # reading chapter: pdf-text's extractor
      (tool "project-environment" "direnv" direnv) # shells chapter: envrc, each project's own environment
      (tool "notebooks" "jupytext" (python3Packages.toPythonApplication python3Packages.jupytext)) # notebooks chapter: .ipynb files
      (tool "notebooks" "math-preview" math-preview) # notebooks chapter: LaTeX drawn with MathJax
      # notebooks chapter: prints the path of emacs-zmq's native module, built by nixpkgs
      (tool "jupyter" "kittymacs-zmq-module" (
        runCommand "kittymacs-zmq-module" { } ''
          module=$(echo ${(emacsPackagesFor emacs).zmq}/share/emacs/site-lisp/elpa/zmq-*/emacs-zmq.*)
          mkdir -p $out/bin
          printf '#!%s\necho %s\n' ${runtimeShell} "$module" > $out/bin/kittymacs-zmq-module
          chmod +x $out/bin/kittymacs-zmq-module
        ''
      ))
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      (tool null "gls" coreutils-prefixed) # Dired chapter: GNU ls as `gls'
      (tool null "trash" darwin.trash) # platform chapter: Trash with Finder's "Put Back"
    ];

  # The editing font, the prose font and the icon font.
  fontTable = with pkgs; [
    # Older nixpkgs (nixos-26.05) has no Nerd Font build of it.
    (font null (nerd-fonts.googlesanscode or googlesans-code))
    (font null (
      stdenvNoCC.mkDerivation {
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
      }
    ))
    (font "icons" nerd-fonts.symbols-only)
  ];
in
{
  inherit emacs;

  programs = packagesOf programTable;
  fonts = packagesOf fontTable;
  programsFor = features: packagesOf (lib.filter (isOn features) programTable);
  fontsFor = features: packagesOf (lib.filter (isOn features) fontTable);

  # What the doctor looks for, and the feature that asks for each.
  commands = map (entry: { inherit (entry) feature command; }) programTable;

  # A machine that Emacs reaches from elsewhere: no Emacs, no fonts, no GUI.
  backendPrograms =
    packagesOf (
      lib.filter (
        entry:
        lib.elem entry.command [
          "git"
          "rg"
          "fd"
          "direnv"
        ]
      ) programTable
    )
    ++ lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.inotify-tools
    ++ [
      pkgs.nil
      pkgs.pyright
      pkgs.bash-language-server
    ];
}
