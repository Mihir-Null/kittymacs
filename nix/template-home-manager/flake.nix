# Generated from literate/90-nix.org (the kittymacs repository).
# A Home Manager home with kittymacs.  Change `me', /home/me and `system', then:
#
#   nix run github:nix-community/home-manager -- switch --flake .#me
{
  description = "A Home Manager home with kittymacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    # On a stable nixpkgs with no Emacs 31, delete this line.
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      kittymacs,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      homeConfigurations.me = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [
          kittymacs.homeManagerModules.default
          {
            home = {
              username = "me";
              homeDirectory = "/home/me";
              stateVersion = "26.05";
            };
            programs.home-manager.enable = true;
            programs.kittymacs = {
              enable = true;
              package = kittymacs.packages.${system}.default;
              # The first switch clones the writable checkout here.
              source = "/home/me/src/kittymacs";
            };
          }
        ];
      };
    };
}
