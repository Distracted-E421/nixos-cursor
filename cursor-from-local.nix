# Quick script to build Cursor from local AppImage files
# Usage: nix-build cursor-from-local.nix --arg appImagePath /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage --arg version '"2.0.77"'

{ pkgs ? import <nixpkgs> {}
, appImagePath
, version 
}:

let
  # Get hash of the local AppImage
  appImageSrc = builtins.path {
    path = appImagePath;
    name = "cursor-${version}.AppImage";
  };

in pkgs.callPackage ./cursor {
  inherit version;
  # Override the fetchurl sources to use local file
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Dummy - overridden below
}.overrideAttrs (old: {
  # Replace the src with local AppImage extraction
  src = pkgs.appimageTools.extractType2 {
    pname = "cursor";
    inherit version;
    src = appImageSrc;
  };
})
