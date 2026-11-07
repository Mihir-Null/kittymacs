# Generated from literate/90-nix.org; edit the Org source, then tangle.
{ lib }:

let
  catalogue = builtins.fromJSON (builtins.readFile ./features.json);
  names = builtins.attrNames catalogue;
  depsOf = name: catalogue.${name}.deps or [ ];
  withDeps =
    features:
    let
      grown = lib.unique (features ++ lib.concatMap depsOf features);
    in
    if lib.length grown == lib.length features then features else withDeps grown;
  answered = cfg: value: lib.filter (name: cfg.features.${name}.enable == value) names;

  settingType =
    let
      value =
        lib.types.nullOr (
          lib.types.oneOf [
            lib.types.bool
            lib.types.int
            lib.types.float
            lib.types.str
            (lib.types.listOf value)
            (lib.types.submodule {
              options.elisp = lib.mkOption {
                type = lib.types.str;
                description = "Elisp to write as it stands, such as `'modus-vivendi`.";
              };
            })
          ]
        )
        // {
          description = "Elisp value";
        };
    in
    value;

  renderValue =
    value:
    if value == null || value == false then
      "nil"
    else if value == true then
      "t"
    else if builtins.isString value then
      builtins.toJSON value
    else if builtins.isList value then
      if value == [ ] then "nil" else "(list ${lib.concatMapStringsSep " " renderValue value})"
    else if builtins.isAttrs value then
      value.elisp
    else
      toString value;

in
rec {
  options = {
    profile = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "minimal"
          "full"
        ]
      );
      default = null;
      example = "minimal";
      description = ''
        Where this machine's features start: `kittymacs-profile`.  `full`
        leaves out the features the catalogue marks optional.  Null writes
        nothing, so the configuration decides.
      '';
    };

    features = lib.mapAttrs (_: entry: {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          ${entry.summary}${
            lib.optionalString (entry ? experimental) "  Experimental: ${entry.experimental}"
          }  True adds it to `kittymacs-features`, false to
          `kittymacs-features-excluded`, and null leaves it to `profile`.
        '';
      };
    }) catalogue;

    settings = lib.mkOption {
      type = lib.types.attrsOf settingType;
      default = { };
      example = lib.literalExpression ''
        {
          kittymacs-frames-only = false;
          kittymacs-theme.elisp = "'modus-vivendi";
        }
      '';
      description = ''
        More options to set with `setopt`, in the generated host file.  Use
        them for what the chapters read as they load, the `kittymacs-` options:
        a chapter that sets a package's option runs later and replaces it.
        True is `t`, false and null are `nil`, a list is a list, and
        `{ elisp = "..."; }` is written as it stands, which is how to give a
        symbol.
      '';
    };

    hostFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      example = lib.literalExpression ''
        { "50-mail" = "(add-hook 'after-init-hook #'my-mail-setup 90)"; }
      '';
      description = ''
        Host-layer files, by name without `.el`, as their text.  They load in
        name order, before `private.el`.  `10-nix` is the generated file's.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.nullOr (lib.types.functionTo (lib.types.listOf lib.types.package));
      default = null;
      example = lib.literalExpression "epkgs: [ epkgs.vterm ]";
      description = ''
        More Emacs packages for Nix to build into the Emacs, chosen from its
        package set.  This works with `packagesFromNix` off too.
      '';
    };

    backend.enable = lib.mkEnableOption ''
      a machine that Emacs reaches from elsewhere: only the headless tools, with
      no Emacs, no fonts and nothing with a GUI.  It works without `enable`.
      `daemon` still runs `package`, and `source` still links a checkout, if set
    '';
  };

  # The features that are on for SYSTEMTYPE, Emacs's name for the system, or
  # null when the options chose nothing.
  enabled =
    systemType: cfg:
    let
      selected = answered cfg true;
      excluded = answered cfg false;
      inProfile = profile: lib.filter (name: catalogue.${name}.profile == profile) names;
      floor = inProfile "minimal";
      dropUnmet =
        features:
        let
          kept = lib.filter (name: lib.all (dep: lib.elem dep features) (depsOf name)) features;
        in
        if lib.length kept == lib.length features then features else dropUnmet kept;
      removed = lib.subtractLists floor excluded;
      wanted = lib.unique (
        floor ++ lib.optionals (cfg.profile != "minimal") (inProfile "full") ++ withDeps selected
      );
      applies = name: !(lib.elem systemType (catalogue.${name}.not-on or [ ]));
    in
    if cfg.profile == null && selected == [ ] && excluded == [ ] then
      null
    else
      dropUnmet (lib.filter (name: !(lib.elem name removed) && applies name) wanted);

  # Emacs's name for the system PKGS is for.
  systemType = pkgs: if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "gnu/linux";

  # The features of the profile PROFILE, for the flake's packages.
  profileFeatures =
    system: profile:
    enabled system {
      inherit profile;
      features = lib.mapAttrs (_: _: { enable = null; }) catalogue;
    };

  # The Emacs a module installs and runs.
  emacsFor =
    system: cfg:
    if cfg.packagesFromNix then
      import ./packages.nix {
        emacs = cfg.package;
        features = enabled system cfg;
        inherit (cfg) extraPackages;
      }
    else if cfg.extraPackages != null then
      cfg.package.pkgs.withPackages cfg.extraPackages
    else
      cfg.package;

  # The features a module installs tools for.
  toolFeatures =
    system: cfg:
    let
      features = enabled system cfg;
    in
    if features == null then profileFeatures system "full" else features;

  assertions =
    { cfg, usesPackage }:
    let
      version = lib.getVersion cfg.package;
      excluded = answered cfg false;
      option = name: "programs.kittymacs.features.${name}.enable";
      alwaysKept = name: catalogue.${name}.profile == "minimal";
      refuseExcluded =
        name: "${option name} is false, but the minimal profile always keeps ${name}. Remove the setting.";
      refuseSelected =
        name:
        map (
          dep: "${option name} is true, but ${name} needs ${dep} and ${option dep} is false. Change one."
        ) (lib.intersectLists (withDeps (depsOf name)) excluded);
      conflicts =
        map refuseExcluded (lib.filter alwaysKept excluded)
        ++ lib.concatMap refuseSelected (answered cfg true);
    in
    [
      {
        assertion = !(cfg.hostFiles ? "10-nix");
        message = ''programs.kittymacs.hostFiles."10-nix" is the file the selection options write; choose another name.'';
      }
      {
        assertion = !usesPackage || version == "" || lib.versionAtLeast version "31";
        message = "kittymacs needs Emacs 31 or later, and programs.kittymacs.package is Emacs ${version}. Set programs.kittymacs.package to a newer one, such as kittymacs.packages.<system>.default from a kittymacs input that does not follow this nixpkgs.";
      }
    ]
    ++ map (message: {
      assertion = false;
      inherit message;
    }) conflicts;

  # The text of 10-nix.el, or null when the options ask for nothing.
  hostFile =
    moduleName: cfg:
    let
      setFeatures =
        option: features:
        lib.optional (features != [ ]) "(setopt ${option} '(${lib.concatStringsSep " " features}))";
      lines =
        lib.optional (cfg.profile != null) "(setopt kittymacs-profile '${cfg.profile})"
        ++ setFeatures "kittymacs-features" (answered cfg true)
        ++ setFeatures "kittymacs-features-excluded" (answered cfg false)
        ++ lib.mapAttrsToList (name: value: "(setopt ${name} ${renderValue value})") cfg.settings;
    in
    if lines == [ ] then
      null
    else
      lib.concatLines (
        [
          ";;; 10-nix.el --- What programs.kittymacs chose -*- lexical-binding: t; -*-"
          ";; Generated by the kittymacs ${moduleName} module; change its options instead."
        ]
        ++ lines
      );

  # Each host-layer file MODULENAME writes, by file name, as its text.
  hostLayer =
    moduleName: cfg:
    let
      generated = hostFile moduleName cfg;
    in
    lib.optionalAttrs (generated != null) { "10-nix.el" = generated; }
    // lib.mapAttrs' (
      name: text:
      lib.nameValuePair "${name}.el" ''
        ;;; -*- lexical-binding: t; -*-
        ${text}
      ''
    ) cfg.hostFiles;
}
