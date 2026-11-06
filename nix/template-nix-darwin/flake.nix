# Generated from literate/90-nix.org (the kittymacs repository).
# A Mac with kittymacs.  Change `me' and the host name, then:
#
#   nix run github:nix-darwin/nix-darwin -- switch --flake .#mac
#   git clone https://github.com/Mihir-Null/kittymacs.git ~/.config/emacs
{
  description = "A nix-darwin Mac with kittymacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    # On a stable nixpkgs with no Emacs 31, delete this line.
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nix-darwin, kittymacs, ... }:
    let
      system = "aarch64-darwin";
    in
    {
      darwinConfigurations.mac = nix-darwin.lib.darwinSystem {
        modules = [
          kittymacs.darwinModules.default
          {
            programs.kittymacs = {
              enable = true;
              package = kittymacs.packages.${system}.default;
            };
            users.users.me.home = "/Users/me";
            system.primaryUser = "me";
            system.stateVersion = 6;
            nixpkgs.hostPlatform = system;
          }
        ];
      };
    };
}
