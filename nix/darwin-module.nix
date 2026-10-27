# Generated from literate/90-nix.org; edit the Org source, then tangle.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.kittymacs;
  tools = import ./tools.nix {
    inherit pkgs;
    emacs = cfg.package;
  };
  emacs = if cfg.packagesFromNix then import ./packages.nix { emacs = cfg.package; } else cfg.package;
in
{
  options.programs.kittymacs = {
    enable = lib.mkEnableOption "kittymacs: Emacs with the tools its configuration looks for";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emacs;
      defaultText = lib.literalExpression "pkgs.emacs";
      description = ''
        The Emacs to install, and to run when `daemon` is on.  kittymacs
        needs 31.1 or later.  `pkgs.emacs` is nixpkgs' current release as
        the Cocoa build; `pkgs.emacs-macport` is the Mitsuharu port.
      '';
    };

    packagesFromNix = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Build the Emacs packages the configuration declares into `package`
        with Nix, pinned by the flake's lock, so startup installs nothing
        from the network.  The few nixpkgs lacks still install into the
        checkout's `var/elpa`.  Off, every package comes from the archives.
      '';
    };

    daemon = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the Emacs server at login, so `emacsclient` opens files in
        frames of one running Emacs.  This turns on nix-darwin's
        `services.emacs` with `package`, a launchd agent.  Turn on this
        option or the home-manager module's, not both.
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

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      emacs
    ]
    ++ tools.programs
    ++ lib.optional cfg.suggestions.enable cfg.suggestions.package;
    fonts.packages = tools.fonts;

    services.emacs = lib.mkIf cfg.daemon {
      enable = true;
      package = emacs;
    };
  };
}
