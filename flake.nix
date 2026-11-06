# Generated from literate/90-nix.org; edit the Org source, then tangle.
{
  description = "kittymacs: a Meow-first Emacs configuration, with the tools it looks for";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # nixpkgs-unstable dropped x86_64-darwin in 26.11; an Intel Mac can
      # point this flake's nixpkgs input at the nixpkgs-26.05-darwin branch.
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      # Each per-system output gets the package set and the tool list.
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          f pkgs (import ./nix/tools.nix { inherit pkgs; })
        );
    in
    {
      darwinModules.default = import ./nix/system-module.nix {
        moduleName = "nix-darwin";
        packageNote = "`pkgs.emacs` is the Cocoa build; `pkgs.emacs-macport` is the Mitsuharu port.";
      };
      darwinModules.kittymacs = self.darwinModules.default;

      nixosModules.default = import ./nix/system-module.nix {
        moduleName = "NixOS";
        packageNote = "`pkgs.emacs-pgtk` speaks Wayland; `pkgs.emacs-nox` has no GUI.";
      };
      nixosModules.kittymacs = self.nixosModules.default;

      # The module is given the flake itself, so the clone can default to
      # this flake's revision.
      homeManagerModules.default = import ./nix/home-module.nix { inherit self; };
      homeManagerModules.kittymacs = self.homeManagerModules.default;

      overlays.default = final: _: { kittymacs = import ./nix/profiles.nix { pkgs = final; }; };

      packages = forEachSystem (pkgs: _: import ./nix/profiles.nix { inherit pkgs; });

      apps = forEachSystem (pkgs: tools: import ./nix/apps.nix { inherit pkgs tools; });

      checks = forEachSystem (
        pkgs: tools:
        import ./nix/checks.nix {
          inherit nixpkgs pkgs tools;
          nixosModule = self.nixosModules.default;
          overlay = self.overlays.default;
        }
      );

      formatter = forEachSystem (pkgs: _: pkgs.nixfmt-tree);

      templates = {
        home-manager = {
          path = ./nix/template-home-manager;
          description = "A Home Manager home with kittymacs, on any Linux";
          welcomeText = "Edit flake.nix: its first lines name what to change.";
        };
        nix-darwin = {
          path = ./nix/template-nix-darwin;
          description = "A nix-darwin Mac with kittymacs";
          welcomeText = "Edit flake.nix: its first lines name what to change.";
        };
        nixos = {
          path = ./nix/template-nixos;
          description = "A NixOS machine with kittymacs";
          welcomeText = "Edit flake.nix: its first lines name what to change.";
        };
        wsl-backend = {
          path = ./nix/template-wsl-backend;
          description = "The Linux side of a Windows setup: the tools, with no Emacs or fonts";
          welcomeText = "Edit flake.nix: its first lines name what to change.";
        };
      };

      # Emacs and the tools, plus just and the Nix linters for the recipes.
      devShells = forEachSystem (
        pkgs: tools: {
          default = pkgs.mkShell {
            packages = [
              tools.emacs
            ]
            ++ tools.programs
            ++ [
              pkgs.just
              pkgs.nixfmt
              pkgs.deadnix
              pkgs.statix
            ];
            shellHook = ''
              echo "kittymacs: just --list"
            '';
          };
        }
      );
    };
}
