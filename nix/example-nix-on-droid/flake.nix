# Generated from literate/90-nix.org (the kittymacs repository).
# A complete nix-on-droid device with kittymacs: copy it as a starting point.
# On the phone:
#
#   nix-on-droid switch --flake .#default --impure
#
# The --impure is nix-on-droid's own requirement, not this flake's.
{
  description = "Example nix-on-droid device with kittymacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Pin this to a release branch (nix-on-droid/release-24.05, say) if you
    # would rather not track a development branch on a telephone.
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid/master";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    kittymacs.url = "github:Mihir-Null/kittymacs";
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      nix-on-droid,
      kittymacs,
      ...
    }:
    {
      # nix-on-droid runs on the device, so the package set is the device's.
      nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = import nixpkgs { system = "aarch64-linux"; };
        modules = [
          ({ pkgs, ... }: {
            # nix-on-droid's own home-manager sets the user name and home
            # directory, so nothing here has to name /data/data/com.termux.nix.
            home-manager.config = { config, ... }: {
              imports = [ kittymacs.homeManagerModules.default ];

              programs.kittymacs = {
                enable = true;

                # Installs Emacs and everything the configuration discovers at
                # startup: git, ripgrep, fd, gnupg, hunspell with its
                # dictionary, python3, and the Nerd Font for the icons.
                installPackages = true;

                # pgtk speaks Wayland and X11 both, so one build serves
                # Termux:X11 either way.  For a console-only device use
                # pkgs.emacs-nox with `installFonts = false' below: the
                # configuration notices it has no graphical display and turns
                # its icons off by itself.
                package = pkgs.emacs-pgtk;
                # installFonts = false;

                # The checkout stays writable outside the store, because the
                # configuration installs its own Emacs packages under var/ and
                # keeps private.el beside its modules.  The first switch
                # clones it here, at the kittymacs revision flake.lock pins.
                source = "${config.home.homeDirectory}/src/kittymacs";
              };

              home.stateVersion = "24.05";
            };

            system.stateVersion = "24.05";
          })
        ];
      };
    };
}
