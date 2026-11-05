# Generated from literate/90-nix.org; edit the Org source, then tangle.
{ lib }:

let
  catalogue = builtins.fromJSON (builtins.readFile ./features.json);
  names = builtins.attrNames catalogue;
  depsOf = name: catalogue.${name}.deps or [ ];
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
{
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
          ${entry.summary}  True adds it to `kittymacs-features`, false to
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
      withDeps =
        features:
        let
          grown = lib.unique (features ++ lib.concatMap depsOf features);
        in
        if lib.length grown == lib.length features then features else withDeps grown;
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

  # The text of 10-nix.el, or null when the options ask for nothing.
  hostFile =
    cfg:
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
          ";; Generated by the kittymacs Home Manager module; change its options instead."
        ]
        ++ lines
      );
}
