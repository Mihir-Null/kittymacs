# A complete nix-on-droid device that uses the kittymacs module.  Copy it as
# a starting point.  On the phone:
#
#   nix-on-droid switch --flake .#default --impure
#
# The --impure is nix-on-droid's, not this flake's.  proot-static cannot be
# built on the device, so nix-on-droid hardcodes the store path of a
# pre-built one and reaches it with `builtins.storePath', which pure
# evaluation forbids.  Anything that evaluates the activation script needs
# the flag.
#
# To check this file against the checkout you are in, rather than the
# published repository, evaluate the package list it produces.  That is what
# this repository contributes, it stays inside pure evaluation, and it is
# the same check the nix-darwin example gets (CI runs it; nothing is built):
#
#   nix eval --no-write-lock-file --override-input kittymacs path:$PWD \
#     --json ./nix/example-nix-on-droid#nixOnDroidConfigurations.default.config.home-manager.config.home.packages \
#     --apply 'ps: map (p: p.name) ps'
#
# This is the *other* Android path, and it is a different machine from the
# Android port of Emacs.  Here Emacs is an ordinary GNU/Linux Emacs running
# inside nix-on-droid's PRoot, so `system-type' is `gnu/linux' and none of
# the configuration's Android branches apply: every package works, ghostel
# included, and nothing degrades.  What it is not is an Android application,
# so being graphical needs a display server -- Termux:X11 -- and everything
# pays for the PRoot.
#
# The two paths cannot be combined, which is worth stating plainly because it
# is the obvious thing to want.  A Nix store path exists only inside the
# PRoot: a binary's ELF interpreter is /nix/store/...-glibc/ld-linux-*.so,
# which does not resolve on the real Android filesystem, so the Android port
# of Emacs could not execute anything installed here even if the two
# applications shared a user ID -- which they also do not.  Pair the Android
# port with Termux instead; see nix/README.org.
{
  description = "Example nix-on-droid device with kittymacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Pin this to a release branch (nix-on-droid/release-24.05, say) if you
    # would rather not track a development branch on a telephone.
    nix-on-droid.url = "github:nix-community/nix-on-droid/master";
    nix-on-droid.inputs.nixpkgs.follows = "nixpkgs";
    nix-on-droid.inputs.home-manager.follows = "home-manager";
    kittymacs.url = "github:Mihir-Null/kittymacs";
    kittymacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-on-droid, kittymacs, ... }: {
    # nix-on-droid runs on the device, so the package set is the device's.
    nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = import nixpkgs { system = "aarch64-linux"; };
      modules = [
        ({ pkgs, ... }: {
          # nix-on-droid's own home-manager sets the user name and home
          # directory, so nothing here has to name /data/data/com.termux.nix.
          home-manager.config = { config, ... }: {
            imports = [ kittymacs.homeManagerModules.default ];

            programs.kittymacs = {
              enable = true;

              # Installs Emacs and everything the configuration discovers at
              # startup: git, ripgrep, fd, gnupg, hunspell with its
              # dictionary, python3, and the Nerd Font for the icons.
              installPackages = true;

              # pgtk speaks Wayland and X11 both, so one build serves
              # Termux:X11 either way.  For a console-only device use
              # pkgs.emacs-nox with `installFonts = false' below: the
              # configuration notices it has no graphical display and turns
              # its icons off by itself.
              package = pkgs.emacs-pgtk;
              # installFonts = false;

              # The checkout stays writable outside the store, because the
              # configuration installs its own Emacs packages under var/ and
              # keeps private.el beside its modules.
              source = "${config.home.homeDirectory}/src/kittymacs";
            };

            home.stateVersion = "24.05";
          };

          system.stateVersion = "24.05";
        })
      ];
    };
  };
}
