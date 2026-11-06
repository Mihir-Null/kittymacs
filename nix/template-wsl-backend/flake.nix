# Generated from literate/90-nix.org (the kittymacs repository).
# The Linux side of a Windows setup: the headless tools, with no Emacs and no
# fonts.  How Emacs on Windows reaches this side is not chosen yet, and a later
# step brings it, so nothing here assumes a transport.
# Change `me', /home/me and `system', then, inside the distribution:
#
#   nix run github:nix-community/home-manager -- switch --flake .#me
{
  description = "The Linux side of a Windows setup, with kittymacs's headless tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      kittymacs,
      ...
    }:
    {
      homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [
          kittymacs.homeManagerModules.default
          {
            home = {
              username = "me";
              homeDirectory = "/home/me";
              stateVersion = "26.05";
            };
            programs.home-manager.enable = true;
            programs.kittymacs.backend.enable = true;
          }
        ];
      };
    };
}
