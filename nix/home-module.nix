# home-manager module: link a writable checkout into place as ~/.config/emacs
# and, without nix-darwin, install Emacs and the tools for this user.
#
#   imports = [ inputs.kittymacs.homeManagerModules.default ];
#   programs.kittymacs = {
#     enable = true;
#     source = "${config.home.homeDirectory}/src/kittymacs";
#   };
#
# The link points outside the Nix store on purpose: the configuration
# installs its packages under var/ and keeps private.el beside the modules,
# and both must stay writable.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kittymacs;
  tools = import ./tools.nix { inherit pkgs; emacs = cfg.package; };
in
{
  options.programs.kittymacs = {
    enable = lib.mkEnableOption "kittymacs, linked into ~/.config/emacs";

    source = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/Users/me/src/kittymacs";
      description = ''
        Absolute path of a writable clone of the repository.  When set,
        ~/.config/emacs becomes a symbolic link to it.  Leave null to manage
        the clone by hand.
      '';
    };

    installPackages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install Emacs and the tools into the user profile.  Turn off when
        the nix-darwin module already installs them system-wide.
      '';
    };

    installFonts = lib.mkOption {
      type = lib.types.bool;
      default = cfg.installPackages;
      defaultText = lib.literalExpression "config.programs.kittymacs.installPackages";
      description = ''
        Install the Nerd Font that renders the icons, and turn on
        fontconfig.  Turn off for a terminal-only Emacs, which has no use
        for either; the configuration detects the missing font and renders
        without icons.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emacs;
      defaultText = lib.literalExpression "pkgs.emacs";
      description = "The Emacs to install when `installPackages` is on.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      (lib.optionals cfg.installPackages ([ cfg.package ] ++ tools.programs))
      ++ (lib.optionals cfg.installFonts tools.fonts);
    fonts.fontconfig.enable = lib.mkIf cfg.installFonts (lib.mkDefault true);

    xdg.configFile."emacs" = lib.mkIf (cfg.source != null) {
      source = config.lib.file.mkOutOfStoreSymlink cfg.source;
    };
  };
}
