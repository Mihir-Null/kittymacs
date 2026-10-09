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
