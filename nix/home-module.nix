# home-manager module: link a writable checkout into place as ~/.config/emacs,
# clone it there on first activation, and, without nix-darwin, install Emacs
# and the tools for this user.
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
#
# flake.nix applies the first function to the flake itself, so the clone can
# default to the revision of the kittymacs flake that the host locked.
{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.kittymacs;
  tools = import ./tools.nix { inherit pkgs; emacs = cfg.package; };
  git = "${pkgs.git}/bin/git";
  coreutils = "${pkgs.coreutils}/bin";
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
        ~/.config/emacs becomes a symbolic link to it, and activation clones
        `repository` there if nothing is there yet.  Leave null to manage
        the clone by hand.
      '';
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/Mihir-Null/kittymacs.git";
      description = ''
        Git URL that activation clones `source` from when it does not exist.
        Point it at a fork to start from your own copy.
      '';
    };

    revision = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = self.rev or null;
      defaultText = lib.literalMD ''
        the commit of the kittymacs flake this module comes from, as the
        host's `flake.lock` records it; null when that flake is a working
        tree with uncommitted changes
      '';
      example = "0123456789abcdef0123456789abcdef01234567";
      description = ''
        Full commit hash to check out when `source` is cloned.  The clone is
        shallow and detached at that commit.  The pin applies to the first
        clone only.  After that the checkout is yours: you pull, commit and
        switch branches in it, so an activation that finds it at another
        commit prints a one-line notice and changes nothing.  With null,
        nothing is cloned.
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
      description = ''
        The Emacs to install, and to run when `daemon` is on.  kittymacs
        needs 30.1 or later.
      '';
    };

    daemon = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the Emacs server at login, so `emacsclient` opens files in
        frames of one running Emacs.  This turns on Home Manager's
        `services.emacs` with `package`: a systemd user service on Linux and
        a launchd agent on macOS, plus an "Emacs Client" desktop entry on
        Linux.  Where no systemd user session runs (nix-on-droid, WSL
        without systemd) the service is written but nothing starts it.  On a
        Mac, turn on this option or the nix-darwin module's, not both.
      '';
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

    # The checkout is ordinary user data, so activation clones it into the
    # home directory rather than building it into the generation.  Three
    # cases:
    #
    # - A symbolic link to nothing is probably a disk that is not mounted,
    #   so it stops activation instead of being cloned over.
    # - Nothing there: fetch only the pinned commit, with `origin` set to
    #   `repository` so the checkout can pull later.  The work happens in a
    #   temporary directory beside `source`, which is moved into place only
    #   once HEAD is that commit, so a failed fetch leaves nothing half-made.
    #   A failure only warns: the network may not be up yet (home-manager
    #   runs at boot on NixOS), and the rest of the home configuration should
    #   not wait for it.  The next activation tries again.  The subshell is
    #   run with errexit on and not as an `if` condition, where bash would
    #   ignore `set -e` and go on past a failed fetch.
    # - A Git checkout at another commit: say so, and touch nothing.
    #
    # git and coreutils are named by store path, because activation does not
    # promise that either is on PATH.
    home.activation.cloneKittymacs =
      lib.mkIf (cfg.source != null && cfg.revision != null)
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          source=${lib.escapeShellArg cfg.source}
          repository=${lib.escapeShellArg cfg.repository}
          revision=${lib.escapeShellArg cfg.revision}
          if [[ -L $source && ! -e $source ]]; then
            errorEcho "kittymacs: $source is a symbolic link to nothing"
            exit 1
          elif [[ ! -e $source ]]; then
            if [[ -v DRY_RUN ]]; then
              echo "kittymacs: would clone $repository at $revision into $source"
            else
              parent=$(${coreutils}/dirname -- "$source")
              ${coreutils}/mkdir -p -- "$parent"
              set +e
              (
                set -e
                temp=$(${coreutils}/mktemp -d "$parent/.kittymacs.XXXXXXXX")
                trap '${coreutils}/rm -rf -- "$temp"' EXIT
                ${git} -C "$temp" init --quiet
                ${git} -C "$temp" remote add origin "$repository"
                ${git} -C "$temp" fetch --quiet --depth 1 origin "$revision"
                ${git} -C "$temp" checkout --quiet --detach FETCH_HEAD
                head=$(${git} -C "$temp" rev-parse HEAD)
                if [[ $head != "$revision" ]]; then
                  errorEcho "kittymacs: $revision fetched as $head; give a full commit hash"
                  exit 1
                fi
                ${coreutils}/mv -- "$temp" "$source"
              )
              cloneStatus=$?
              set -e
              if (( cloneStatus != 0 )); then
                warnEcho "kittymacs: could not clone $repository at $revision into $source; activation goes on without it, and the next one tries again"
              fi
            fi
          elif [[ -e $source/.git ]] \
            && head=$(${git} -C "$source" rev-parse HEAD 2>/dev/null) \
            && [[ $head != "$revision" ]]; then
            noteEcho "kittymacs: $source is at $head, not the pinned $revision; left as it is"
          fi
        '');

    services.emacs = lib.mkIf cfg.daemon {
      enable = true;
      inherit (cfg) package;
      client.enable = true;
    };
  };
}
