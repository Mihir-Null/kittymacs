# Generated from literate/90-nix.org; edit the Org source, then tangle.
{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "tramp-rpc-server";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "ArthurHeymans";
    repo = "emacs-tramp-rpc";
    rev = "543b3bf30b8a80b8cd0200c98d00f22a4e0220ac";
    hash = "sha256-kmb0tolO3E/cXqvdzTUQFKPGgDXSO0uN+98RXvmMvBk=";
  };

  cargoHash = lib.fakeHash;
  cargoBuildFlags = [
    "--package"
    "tramp-rpc-server"
  ];
  doCheck = false;

  meta = {
    description = "The server behind kittymacs's wsl-rpc transport";
    homepage = "https://github.com/ArthurHeymans/emacs-tramp-rpc";
    license = lib.licenses.gpl3Plus;
    mainProgram = "tramp-rpc-server";
  };
}
