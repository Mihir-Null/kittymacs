# Generated from literate/90-nix.org; edit the Org source, then tangle.
{ pkgs }:

let
  tools = import ./tools.nix { inherit pkgs; };
  selection = import ./selection.nix { inherit (pkgs) lib; };

  profile =
    name:
    let
      features = selection.profileFeatures (selection.systemType pkgs) name;
    in
    pkgs.buildEnv {
      name = "kittymacs-${name}";
      paths = [
        (import ./packages.nix {
          inherit (tools) emacs;
          inherit features;
        })
      ]
      ++ tools.programsFor features
      ++ tools.fontsFor features;
    };
in
{
  default = tools.emacs;
  tools = pkgs.buildEnv {
    name = "kittymacs-tools";
    paths = tools.programs ++ tools.fonts;
  };
  with-packages = import ./packages.nix { inherit (tools) emacs; };
  minimal = profile "minimal";
  full = profile "full";
  backend = pkgs.buildEnv {
    name = "kittymacs-backend";
    paths = tools.backendPrograms;
  };
  rpc-server = tools.rpcServer;
}
