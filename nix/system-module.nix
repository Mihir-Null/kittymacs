# Generated from literate/90-nix.org; edit the Org source, then tangle.
{ moduleName, packageNote }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.kittymacs;
  selection = import ./selection.nix { inherit lib; };
  tools = import ./tools.nix {
    inherit pkgs;
    emacs = cfg.package;
  };
  emacs = selection.emacsFor (selection.systemType pkgs) cfg;
in
{
  options.programs.kittymacs = selection.options // {
    enable = lib.mkEnableOption "kittymacs: Emacs with the tools its configuration looks for";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emacs;
      defaultText = lib.literalExpression "pkgs.emacs";
      description = ''
        The Emacs to install, and to run when `daemon` is on.  kittymacs
        needs 31.1 or later.  ${packageNote}
      '';
    };

    packagesFromNix = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build the Emacs packages the configuration declares into `package`
        with Nix, pinned by the flake's lock, so startup installs nothing
        from the network.  The few nixpkgs lacks still install into the
        checkout's `var/elpa`.  No binary cache carries them, so each
        flake update compiles them all on the machine.  Off, every package
        comes from the archives.
      '';
    };

    daemon = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the Emacs server at login, so `emacsclient` opens files in
        frames of one running Emacs.  This turns on ${moduleName}'s
        `services.emacs` with `package`.  Turn on this option or the
        home-manager module's, not both.
      '';
    };

    suggestions = {
      enable = lib.mkEnableOption ''
        Copilot's language server, for the suggestions chapter's ghost text
        and next edits.  nixpkgs marks it unfree: allow it, for example with
        `nixpkgs.config.allowUnfreePredicate`.  Installing the server turns
        nothing on in Emacs; `SPC t a` or `kittymacs-suggestions` does
      '';
      package = lib.mkPackageOption pkgs "copilot-language-server" { };
    };
  };

  config = lib.mkIf (cfg.enable || cfg.backend.enable) {
    assertions = selection.assertions {
      inherit cfg;
      usesPackage = !cfg.backend.enable || cfg.daemon;
    };

    environment.systemPackages =
      if cfg.backend.enable then
        tools.backendPrograms ++ lib.optional cfg.backend.rpcServer tools.rpcServer
      else
        [ emacs ] ++ tools.programs ++ lib.optional cfg.suggestions.enable cfg.suggestions.package;
    fonts.packages = lib.optionals (!cfg.backend.enable) tools.fonts;

    environment.etc = lib.mapAttrs' (
      file: text: lib.nameValuePair "kittymacs/conf.d/${file}" { inherit text; }
    ) (selection.hostLayer moduleName cfg);

    services.emacs = lib.mkIf cfg.daemon {
      enable = true;
      package = emacs;
    };
  };
}
