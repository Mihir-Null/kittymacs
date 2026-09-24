# A complete nix-darwin system that uses the kittymacs module.  Copy it as a
# starting point.  To evaluate it against the checkout you are in, rather
# than the published repository, override the input (CI does this on Linux;
# building the system needs a Mac):
#
#   nix eval --no-write-lock-file --override-input kittymacs path:$PWD #     --json ./nix/example#darwinConfigurations.example.config.programs.kittymacs.enable
{
  description = "Example nix-darwin host with kittymacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-darwin, home-manager, kittymacs, ... }: {
    darwinConfigurations.example = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        kittymacs.darwinModules.default
        home-manager.darwinModules.home-manager
        ({ pkgs, ... }: {
          # Emacs, ripgrep, fd, git, gnupg, hunspell, gls, trash, the icon font.
          programs.kittymacs.enable = true;
          programs.kittymacs.daemon = false;

          # The checkout stays writable outside the store; home-manager clones
          # it on the first switch, at the kittymacs revision flake.lock pins,
          # and links it into place.  Packages are already installed
          # system-wide.
          users.users.me.home = "/Users/me";
          home-manager.users.me = {
            imports = [ kittymacs.homeManagerModules.default ];
            programs.kittymacs = {
              enable = true;
              installPackages = false;
              source = "/Users/me/src/kittymacs";
            };
            home.stateVersion = "24.11";
          };

          system.primaryUser = "me";
          system.stateVersion = 6;
          nixpkgs.hostPlatform = "aarch64-darwin";
        })
      ];
    };
  };
}
