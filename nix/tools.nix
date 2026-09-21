# The programs kittymacs looks for at startup, as Nix packages.  Every module
# and the dev shell draw from this one list, so the set of dependencies is
# stated once.  Each entry names the chapter that discovers it.
{ pkgs, emacs ? pkgs.emacs }:

{
  inherit emacs;

  programs = with pkgs; [
    git                       # version control chapter (Magit)
    ripgrep                   # navigation chapter (consult-ripgrep, deadgrep)
    fd                        # navigation chapter (consult-fd)
    gnupg                     # startup chapter: GNU ELPA's signed index
    (hunspell.withDicts (d: [ d.en_US ]))  # platform chapter: spelling
    python3                   # treemacs chapter: directory collapsing and the
                              # extended (directory-colouring) git mode
  ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    coreutils-prefixed        # Dired chapter: GNU ls as `gls'
    darwin.trash              # platform chapter: Trash with Finder's "Put Back"
  ];

  # Symbols Nerd Font Mono renders the icons; Google Sans Code, the preferred
  # editing font, is not packaged in nixpkgs and the platform font is used
  # until it is installed by hand.
  fonts = with pkgs; [
    nerd-fonts.symbols-only
  ];
}
