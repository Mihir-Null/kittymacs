# Generated from literate/90-nix.org (the kittymacs repository).
# Hosts for `just nix-matrix`, each evaluated to what a switch would build.
{
  description = "Hosts that exercise every way of using kittymacs's modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nix-darwin,
      kittymacs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      emacsOf = system: kittymacs.packages.${system}.default;
      oldEmacs = {
        type = "derivation";
        name = "emacs-30.2";
        version = "30.2";
        outPath = "/nonexistent";
        drvPath = "/nonexistent";
      };

      homeWith =
        system: settings:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            kittymacs.homeManagerModules.default
            {
              home = {
                username = "me";
                homeDirectory = if lib.hasSuffix "darwin" system then "/Users/me" else "/home/me";
                stateVersion = "24.11";
              };
              programs.kittymacs = {
                enable = true;
                source = "/home/me/src/kittymacs";
                # So the clone step is part of what is compared.
                revision = "0123456789abcdef0123456789abcdef01234567";
              }
              // settings;
            }
          ];
        };
      linuxHome = homeWith "x86_64-linux";
      home =
        settings: (linuxHome ({ package = emacsOf "x86_64-linux"; } // settings)).activationPackage.drvPath;

      nixosWith =
        settings:
        nixpkgs.lib.nixosSystem {
          modules = [
            kittymacs.nixosModules.default
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
              boot.loader.grub.enable = false;
              fileSystems."/" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };
              programs.kittymacs = {
                enable = true;
              }
              // settings;
            }
          ];
        };
      nixos =
        settings:
        (nixosWith ({ package = emacsOf "x86_64-linux"; } // settings))
        .config.system.build.toplevel.drvPath;

      darwinWith =
        settings:
        nix-darwin.lib.darwinSystem {
          modules = [
            kittymacs.darwinModules.default
            {
              nixpkgs.hostPlatform = "aarch64-darwin";
              system.stateVersion = 6;
              # nix-darwin's launchd agent asks for one, and `daemon` is one.
              system.primaryUser = "me";
              programs.kittymacs = {
                enable = true;
              }
              // settings;
            }
          ];
        };
      darwin =
        settings: (darwinWith ({ package = emacsOf "aarch64-darwin"; } // settings)).system.drvPath;

      # A home whose packages hold no Emacs and no fonts.
      headless =
        host:
        let
          names = map lib.getName host.config.home.packages;
        in
        assert !(lib.any (name: builtins.match ".*(emacs|font).*" name != null) names);
        host.activationPackage.drvPath;
    in
    {
      cases = {
        home-plain = home { };
        home-daemon = home { daemon = true; };
        home-packages = home { packagesFromNix = true; };
        home-darwin =
          (homeWith "aarch64-darwin" {
            package = emacsOf "aarch64-darwin";
            daemon = true;
            source = "/Users/me/src/kittymacs";
          }).activationPackage.drvPath;
        home-xdg =
          let
            host = home-manager.lib.homeManagerConfiguration {
              pkgs = nixpkgs.legacyPackages.x86_64-linux;
              modules = [
                kittymacs.homeManagerModules.default
                {
                  home = {
                    username = "me";
                    homeDirectory = "/home/me";
                    stateVersion = "24.11";
                  };
                  xdg.configHome = "/home/me/.xdg";
                  programs.kittymacs = {
                    enable = true;
                    package = emacsOf "x86_64-linux";
                    profile = "minimal";
                  };
                }
              ];
            };
          in
          assert host.config.home.file ? ".config/kittymacs/conf.d/10-nix.el";
          assert host.config.xdg.configFile ? "kittymacs/conf.d/10-nix.el";
          host.activationPackage.drvPath;
        home-backend = headless (linuxHome {
          backend.enable = true;
        });
        home-backend-rpc-server = headless (linuxHome {
          backend = {
            enable = true;
            rpcServer = true;
          };
        });
        home-rpc-server =
          let
            host = linuxHome {
              package = emacsOf "x86_64-linux";
              backend.rpcServer = true;
            };
            names = map lib.getName host.config.home.packages;
          in
          assert lib.elem "tramp-rpc-server" names;
          assert lib.elem "emacs" names;
          host.activationPackage.drvPath;
        home-old-unused =
          (linuxHome {
            package = oldEmacs;
            installPackages = false;
          }).activationPackage.drvPath;
        nixos = nixos { };
        nixos-full = nixos {
          daemon = true;
          packagesFromNix = true;
          profile = "minimal";
          features.jump.enable = true;
        };
        nixos-backend =
          let
            host = nixosWith {
              package = oldEmacs;
              backend.enable = true;
            };
          in
          assert !(lib.any (package: lib.getName package == "emacs") host.config.environment.systemPackages);
          host.config.system.build.toplevel.drvPath;
        darwin = darwin { };
        darwin-full = darwin {
          daemon = true;
          packagesFromNix = true;
        };
      };

      mustFail = {
        home = (linuxHome { package = oldEmacs; }).activationPackage.drvPath;
        nixos = (nixosWith { package = oldEmacs; }).config.system.build.toplevel.drvPath;
        darwin = (darwinWith { package = oldEmacs; }).system.drvPath;
        floor = home { features.meow.enable = false; };
        dependency = home {
          features = {
            jupyter.enable = true;
            notebooks.enable = false;
          };
        };
      };

      mustFailSays = rec {
        home = "and programs.kittymacs.package is Emacs";
        nixos = home;
        darwin = home;
        floor = "programs.kittymacs.features.meow.enable is false, but the minimal profile always keeps meow.";
        dependency = "programs.kittymacs.features.jupyter.enable is true, but jupyter needs notebooks and programs.kittymacs.features.notebooks.enable is false.";
      };

      defaultEmacs = (linuxHome { }).activationPackage.drvPath;
      defaultEmacsVersion = nixpkgs.legacyPackages.x86_64-linux.emacs.version;
    };
}
