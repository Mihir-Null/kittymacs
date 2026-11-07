# Generated from literate/90-nix.org; edit the Org source, then tangle.
{ pkgs, tools }:

let
  inherit (pkgs) lib;

  # Sets `checkout`, or returns 1.  Each app says for itself what that means.
  findCheckout = ''
    is_checkout() {
      [ -f "$1/init.el" ] && [ -f "$1/lisp/kittymacs-catalogue.el" ]
    }
    config_emacs="''${XDG_CONFIG_HOME:-$HOME/.config}/emacs"
    find_checkout() {
      if [ -n "''${KITTYMACS_CHECKOUT:-}" ]; then
        if is_checkout "$KITTYMACS_CHECKOUT"; then
          checkout=$KITTYMACS_CHECKOUT
          return 0
        fi
        echo "kittymacs: KITTYMACS_CHECKOUT is $KITTYMACS_CHECKOUT, which is not a kittymacs checkout." >&2
        exit 2
      fi
      for candidate in "$PWD" "$config_emacs" "$HOME/.emacs.d"; do
        if is_checkout "$candidate"; then
          checkout=$candidate
          return 0
        fi
      done
      return 1
    }
  '';

  # What an app that cannot go on without one says.
  noCheckout = ''
    no_checkout() {
      cat >&2 <<EOF
    kittymacs: $1
    It needs a writable checkout, because the configuration is never in the Nix store.
    Looked in: this directory, $config_emacs and $HOME/.emacs.d.

    To make one:  git clone https://github.com/Mihir-Null/kittymacs.git $config_emacs
    To name one:  KITTYMACS_CHECKOUT=/path/to/kittymacs nix run github:Mihir-Null/kittymacs#$2
    EOF
      exit 2
    }
  '';

  app =
    {
      name,
      description,
      runtimeInputs,
      needsCheckout ? true,
      text,
    }:
    {
      type = "app";
      program = lib.getExe (
        pkgs.writeShellApplication {
          name = "kittymacs-${name}";
          inherit runtimeInputs;
          text = findCheckout + lib.optionalString needsCheckout noCheckout + text;
        }
      );
      meta = { inherit description; };
    };
in
{
  default = app {
    name = "start";
    description = "Start Emacs on a kittymacs checkout, with the tools on its PATH";
    runtimeInputs = [ tools.emacs ] ++ tools.programs;
    text = ''
      find_checkout || no_checkout "there is no checkout to start." default
      exec emacs --init-directory="$checkout" "$@"
    '';
  };

  onboard = app {
    name = "onboard";
    description = "Choose what a kittymacs checkout installs, on screens that write its private.el";
    runtimeInputs = [ tools.emacs ];
    text = ''
      find_checkout || no_checkout "there is no checkout to write private.el in." onboard
      module=$checkout/lisp/kittymacs-onboard.el
      if [ ! -f "$module" ]; then
        echo "kittymacs: $checkout is older than onboarding; pull it, then run this again." >&2
        exit 2
      fi
      echo "kittymacs: onboarding $checkout"
      if [ -t 0 ] && [ -t 1 ] && [ "''${TERM:-dumb}" != dumb ]; then
        exec emacs -nw -Q -l "$module" -f kittymacs-onboard-main
      else
        exec emacs -Q --batch -l "$module" -f kittymacs-onboard-main
      fi
    '';
  };

  doctor = app {
    name = "doctor";
    description = "Report this machine's Emacs, checkout, host-layer files and tools";
    # Empty, so the tools it looks for are the person's and not this app's.
    runtimeInputs = [ ];
    needsCheckout = false;
    text = ''
      problems=0
      line() { printf '%-11s %s\n' "$1" "$2"; }

      if version=$(emacs --version 2>/dev/null); then
        read -r _ _ version <<<"''${version%%$'\n'*}"
        if [ "''${version%%.*}" -ge 31 ]; then
          line Emacs "$version, $(command -v emacs)"
        else
          line Emacs "$version, $(command -v emacs): too old, kittymacs needs 31.1 or later"
          problems=1
        fi
      else
        line Emacs "none on PATH; nix run github:Mihir-Null/kittymacs starts one"
        problems=1
      fi

      features=
      selection_known=
      if find_checkout; then
        line Checkout "$checkout"
        if [ -f "$checkout/lisp/kittymacs-onboard.el" ] \
          && features=$(${tools.emacs}/bin/emacs -Q --batch -l "$checkout/lisp/kittymacs-onboard.el" \
            --eval '(princ (mapconcat (function symbol-name) (kittymacs-onboard--on (kittymacs-onboard--initial-state)) " "))' 2>/dev/null); then
          selection_known=yes
          line Selection "$features"
        else
          line Selection "could not be read; every tool is listed"
        fi
      else
        line Checkout "none; nix run github:Mihir-Null/kittymacs#onboard says how to make one"
        problems=1
      fi

      for directory in /etc/kittymacs/conf.d "''${XDG_CONFIG_HOME:-$HOME/.config}/kittymacs/conf.d"; do
        files=
        for file in "$directory"/*.el; do
          if [ -e "$file" ]; then
            files="$files ''${file##*/}"
          fi
        done
        line "Host layer" "$directory:''${files:- nothing}"
      done

      tool_missing=
      needs() {
        [ -z "$selection_known" ] || [ "$1" = - ] || [[ " $features " == *" $1 "* ]]
      }
      while read -r feature command; do
        if needs "$feature"; then
          if command -v "$command" >/dev/null; then
            line Tool "$command"
          else
            line Tool "$command is missing, and ''${feature/#-/every start} would use it"
            tool_missing=yes
          fi
        fi
      done <<'EOF'
      ${lib.concatMapStringsSep "\n" (
        entry: "${if entry.feature == null then "-" else entry.feature} ${entry.command}"
      ) tools.commands}
      EOF

      if [ -n "$tool_missing" ]; then
        line Hint "on Nix, select its feature in programs.kittymacs, or add the tool to home.packages"
      fi

      exit "$problems"
    '';
  };
}
