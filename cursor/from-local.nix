# Build Cursor from a local AppImage file
# Useful when network is unavailable or for testing specific versions
#
# Usage:
#   nix build --impure --expr '(import ./cursor/from-local.nix { 
#     pkgs = import <nixpkgs> {}; 
#     appImagePath = /home/e421/Downloads/cursor.AppImage;
#     version = "2.0.64";
#   })'

{ pkgs
, appImagePath  # Path to local AppImage
, version ? "unknown"
, commandLineArgs ? ""
, postInstall ? ""
}:

pkgs.callPackage ./default.nix {
  inherit version commandLineArgs postInstall;
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Dummy hash
  # Override fetchurl to use local file
}
