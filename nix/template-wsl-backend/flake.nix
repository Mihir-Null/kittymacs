# Generated from literate/90-nix.org (the kittymacs repository).
# The Linux side of a Windows setup: the headless tools, with no Emacs and no
# fonts.  Emacs on Windows reaches this side through wsl.exe, so it needs no sshd
# and no key.
# Change `me', /home/me and `system', then, inside the distribution:
#
#   nix run github:nix-community/home-manager -- switch --flake .#me
#
# To connect, name the distribution as `wsl --list' prints it, in private.el on
# Windows, and press SPC o b:
#
#   (setopt kittymacs-backends
#           '(("wsl" :transport wsl :host "Ubuntu-24.04" :root "~/src/project/")))
#
# For `:transport wsl-rpc', turn on `backend.rpcServer' below, and see "tramp-rpc
# through wsl.exe" in literate/36-remote.org.  A distribution without Nix builds
# the same revision with one line, which needs Rust 1.88:
#
#   cargo install --locked --root ~/.local --git https://github.com/ArthurHeymans/emacs-tramp-rpc --rev 543b3bf30b8a80b8cd0200c98d00f22a4e0220ac tramp-rpc-server
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
            # programs.kittymacs.backend.rpcServer = true;
          }
        ];
      };
    };
}
