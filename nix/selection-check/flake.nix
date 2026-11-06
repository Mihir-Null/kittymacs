# Generated from literate/90-nix.org (the kittymacs repository).
# Hosts for `just nix-selection`, each with a report of what it produced.
{
  description = "Home Manager hosts that exercise kittymacs's selection options";

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
      selection = import "${kittymacs}/nix/selection.nix" { inherit lib; };

      nixosHost =
        settings:
        nixpkgs.lib.nixosSystem {
          modules = [
            kittymacs.nixosModules.default
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
              programs.kittymacs = {
                enable = true;
              }
              // settings;
            }
          ];
        };
      darwinHost =
        settings:
        nix-darwin.lib.darwinSystem {
          modules = [
            kittymacs.darwinModules.default
            {
              nixpkgs.hostPlatform = "aarch64-darwin";
              system.stateVersion = 6;
              programs.kittymacs = {
                enable = true;
              }
              // settings;
            }
          ];
        };
      host =
        settings:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          modules = [
            kittymacs.homeManagerModules.default
            {
              home = {
                username = "me";
                homeDirectory = "/home/me";
                stateVersion = "24.11";
              };
              programs.kittymacs = {
                enable = true;
                source = "/home/me/src/kittymacs";
              }
              // settings;
            }
          ];
        };
      describe =
        {
          system,
          config,
          files,
        }:
        let
          cfg = config.programs.kittymacs;
        in
        {
          inherit system;
          files = lib.mapAttrs' (name: file: lib.nameValuePair (baseNameOf name) file.text) (
            lib.filterAttrs (name: _: lib.hasPrefix "kittymacs/" name) files
          );
          said = {
            inherit (cfg) profile;
            features = lib.filterAttrs (_: enable: enable != null) (
              lib.mapAttrs (_: feature: feature.enable) cfg.features
            );
          };
          enabled = selection.enabled system cfg;
          built =
            if cfg.daemon then
              map (package: package.pname) config.services.emacs.package.deps.explicitRequires
            else
              null;
        };
      report =
        settings:
        let
          inherit (host settings) config;
        in
        describe {
          system = "gnu/linux";
          inherit config;
          files = config.xdg.configFile;
        };
      systemReport =
        system: build: settings:
        let
          inherit (build settings) config;
        in
        describe {
          inherit system config;
          files = config.environment.etc;
        };
      nixosReport = systemReport "gnu/linux" nixosHost;
      darwinReport = systemReport "darwin" darwinHost;

      fullOptions = {
        profile = "full";
        features = {
          lang-nix.enable = true;
          jump.enable = false;
          icons.enable = false;
        };
        settings = {
          kittymacs-nix-check-true = true;
          kittymacs-nix-check-false = false;
          kittymacs-nix-check-null = null;
          kittymacs-nix-check-number = 3;
          kittymacs-nix-check-string = "a \"quoted\" line\n";
          kittymacs-nix-check-list = [
            "one"
            2
            { elisp = "'three"; }
          ];
          kittymacs-nix-check-symbol.elisp = "'chosen";
        };
        hostFiles."50-check" = "(setq kittymacs-nix-check-host-file t)";
      };
      minimalOptions = {
        profile = "minimal";
        features = {
          file-tree.enable = true;
          jupyter.enable = true;
        };
        packagesFromNix = true;
        extraPackages = epkgs: [ epkgs.avy ];
        daemon = true;
      };
    in
    {
      hosts =
        lib.mapAttrs (_: report) {
          plain = { };
          full = fullOptions;
          minimal = minimalOptions;
          noProfile.features.jump.enable = false;
          extraOnly = {
            extraPackages = epkgs: [ epkgs.vundo ];
            daemon = true;
          };
        }
        // {
          nixosPlain = nixosReport { };
          nixosFull = nixosReport fullOptions;
          nixosMinimal = nixosReport minimalOptions;
          darwinPlain = darwinReport { };
          # Not a feature for a Mac: both sides must drop it.
          darwinFull = darwinReport (
            lib.recursiveUpdate fullOptions { features.window-manager.enable = true; }
          );
          darwinMinimal = darwinReport minimalOptions;
        };

      # These three must fail evaluation.
      typo = report { features.no-such-feature.enable = true; };
      reserved = report { hostFiles."10-nix" = ""; };
      darwinReserved = (darwinHost { hostFiles."10-nix" = ""; }).system.drvPath;
    };
}
