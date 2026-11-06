# Generated from literate/90-nix.org (the kittymacs repository).
# A NixOS machine with kittymacs.  Change `me', and replace the boot and file
# system lines with the machine's own, then:
#
#   sudo nixos-rebuild switch --flake .#machine
#   git clone https://github.com/Mihir-Null/kittymacs.git ~/.config/emacs
{
  description = "A NixOS machine with kittymacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    # On a stable nixpkgs with no Emacs 31, delete this line.
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, kittymacs, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
        modules = [
          kittymacs.nixosModules.default
          {
            programs.kittymacs = {
              enable = true;
              package = kittymacs.packages.${system}.default;
            };
            users.users.me.isNormalUser = true;

            # Placeholders: use the machine's hardware-configuration.nix.
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };

            nixpkgs.hostPlatform = system;
            system.stateVersion = "26.05";
          }
        ];
      };
    };
}
