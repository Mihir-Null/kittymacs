# Generated from literate/90-nix.org; edit the Org source, then tangle.
{
  nixpkgs,
  nixosModule,
  overlay,
  pkgs,
  tools,
}:

let
  inherit (pkgs) lib;
  selection = import ./selection.nix { inherit lib; };
  catalogue = builtins.fromJSON (builtins.readFile ./features.json);
  system = selection.systemType pkgs;
  namesOf = map lib.getName;

  check =
    name: holds:
    if holds then
      pkgs.runCommand "kittymacs-check-${name}" { } "touch $out"
    else
      throw "kittymacs: the flake check ${name} failed; see \"The flake's checks\" in literate/90-nix.org";

  minimalTools = namesOf (tools.programsFor (selection.profileFeatures system "minimal"));
  fullTools = namesOf (tools.programsFor (selection.profileFeatures system "full"));
  backendTools = namesOf tools.backendPrograms;

  standIn = version: {
    type = "derivation";
    name = "emacs-${version}";
    inherit version;
    outPath = "/nonexistent";
    drvPath = "/nonexistent";
  };

  nixos =
    settings:
    (nixpkgs.lib.nixosSystem {
      modules = [
        nixosModule
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = "26.05";
          programs.kittymacs = {
            enable = true;
            package = standIn "31.1";
          }
          // settings;
        }
      ];
    }).config;
  # NixOS's own assertions want a bootable machine, which these are not.
  failedAssertions =
    config:
    lib.filter (lib.hasInfix "kittymacs") (
      map (a: a.message) (lib.filter (a: !a.assertion) config.assertions)
    );
  hostLayerNames =
    config: lib.filter (lib.hasPrefix "kittymacs/") (builtins.attrNames config.environment.etc);

  plain = nixos { };
  chosen = nixos { profile = "minimal"; };
  old = nixos { package = standIn "30.2"; };
  oldBackend = nixos {
    package = standIn "30.2";
    backend.enable = true;
  };
in
{
  tool-features = check "tool-features" (
    lib.all (entry: entry.feature == null || catalogue ? ${entry.feature}) tools.commands
  );

  profiles-narrow = check "profiles-narrow" (
    lib.length minimalTools < lib.length fullTools
    && lib.all (name: lib.elem name fullTools) minimalTools
    && !(lib.elem "kittymacs-zmq-module" fullTools)
  );

  backend-headless = check "backend-headless" (
    lib.elem "direnv" backendTools
    && (pkgs.stdenv.hostPlatform.isLinux -> lib.elem "inotify-tools" backendTools)
    && !(lib.any (name: builtins.match ".*(emacs|font|gtk|qt|X11).*" name != null) backendTools)
  );
}
// lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  overlay = check "overlay" (
    (pkgs.extend overlay).kittymacs.backend.drvPath == (import ./profiles.nix { inherit pkgs; })
    .backend.drvPath
  );

  rpc-server-opt-in = check "rpc-server-opt-in" (
    let
      packagesOfHost = config: namesOf config.environment.systemPackages;
      off = nixos { backend.enable = true; };
      on = nixos {
        backend = {
          enable = true;
          rpcServer = true;
        };
      };
      unasked = nixos { backend.rpcServer = true; };
    in
    !(lib.elem "tramp-rpc-server" (packagesOfHost off))
    && !(lib.elem "tramp-rpc-server" backendTools)
    && lib.elem "tramp-rpc-server" (packagesOfHost on)
    && !(lib.elem "tramp-rpc-server" (packagesOfHost unasked))
  );

  system-module = check "system-module" (
    failedAssertions plain == [ ]
    && hostLayerNames plain == [ ]
    && hostLayerNames chosen == [ "kittymacs/conf.d/10-nix.el" ]
    && lib.hasInfix "programs.kittymacs.package" (lib.concatStrings (failedAssertions old))
    && failedAssertions oldBackend == [ ]
  );
}
