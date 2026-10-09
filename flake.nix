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
      darwinModules.default = import ./nix/darwin-module.nix;
      darwinModules.kittymacs = self.darwinModules.default;

      # The module is given the flake itself, so the clone can default to
      # this flake's revision.
      homeManagerModules.default = import ./nix/home-module.nix { inherit self; };
      homeManagerModules.kittymacs = self.homeManagerModules.default;

      packages = forEachSystem (
        pkgs: tools: {
          tools = pkgs.buildEnv {
            name = "kittymacs-tools";
            paths = tools.programs ++ tools.fonts;
          };
          default = tools.emacs;
        }
      );

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
