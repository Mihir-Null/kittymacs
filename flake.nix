{
  description = "kittymacs: a Meow-first Emacs configuration, with the tools it looks for";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      # nixpkgs-unstable dropped x86_64-darwin in 26.11; an Intel Mac can
      # point this flake's nixpkgs input at the nixpkgs-26.05-darwin branch.
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      # Each per-system output gets the package set and the tool list.
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in f pkgs (import ./nix/tools.nix { inherit pkgs; }));
    in
    {
      # nix-darwin: `imports = [ kittymacs.darwinModules.default ];` then
      # `programs.kittymacs.enable = true;`.  Installs Emacs, every program the
      # configuration discovers, and the icon font.  See nix/README.org.
      darwinModules.default = import ./nix/darwin-module.nix;
      darwinModules.kittymacs = self.darwinModules.default;

      # home-manager: links the checkout into place as ~/.config/emacs and can
      # install the same tools for a user without nix-darwin.
      homeManagerModules.default = import ./nix/home-module.nix;
      homeManagerModules.kittymacs = self.homeManagerModules.default;

      # The programs the configuration discovers at startup, as one list, so a
      # plain `nix profile install` or a NixOS configuration can use them too.
      packages = forEachSystem (pkgs: tools: {
        tools = pkgs.buildEnv {
          name = "kittymacs-tools";
          paths = tools.programs ++ tools.fonts;
        };
        default = tools.emacs;
      });

      # `nix develop` gives a shell with Emacs and the tools for the batch
      # checks in AGENTS.md; no configuration is loaded.
      devShells = forEachSystem (pkgs: tools: {
        default = pkgs.mkShell {
          packages = [ tools.emacs ] ++ tools.programs;
          shellHook = ''
            echo "kittymacs: emacs -Q --batch -l tools/tangle.el -- --check"
          '';
        };
      });
    };
}
