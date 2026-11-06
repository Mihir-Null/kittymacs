# Generated from literate/90-nix.org; edit the Org source, then tangle.
# EMACS with the packages of FEATURES, or of every feature when FEATURES is
# null, then EXTRAPACKAGES.  copilot (unfree), consult-ghostel (not in nixpkgs)
# and the catalogue's Git packages stay out.
{
  emacs,
  features ? null,
  extraPackages ? null,
}:

let
  catalogue = builtins.fromJSON (builtins.readFile ./features.json);
  archiveOnly = [
    "copilot"
    "consult-ghostel"
  ];
  fromNix =
    feature:
    let
      entry = catalogue.${feature};
      left = archiveOnly ++ entry.vc or [ ];
    in
    builtins.filter (package: !(builtins.elem package left)) entry.packages;
  chosen = if features == null then builtins.attrNames catalogue else features;
in
emacs.pkgs.withPackages (
  epkgs:
  let
    # MELPA builds ws-butler from a clone of Savannah's whole NonGNU ELPA
    # repository; NonGNU ELPA's own release is one small tarball.
    packageSet = epkgs // {
      inherit (epkgs.nongnuPackages) ws-butler;
    };
    rank = package: builtins.replaceStrings [ "-" ] [ "" ] package.pname;
  in
  builtins.sort (a: b: rank a < rank b) (
    map (name: packageSet.${name}) (builtins.concatMap fromNix chosen)
  )
  ++ (if extraPackages == null then [ ] else extraPackages epkgs)
)
