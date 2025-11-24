# Multi-Version Cursor System
# Allows running different Cursor versions simultaneously with different binary names
#
# Usage:
#   cursor-2.0.64  # Last version with custom modes
#   cursor-2.0.77  # Latest 2.0.x
#   cursor-1.7.54  # Popular pre-2.0 version

{ lib, callPackage }:

let
  # Base cursor package builder
  mkCursorVersion = { version, hash, hashAarch64 ? "sha256-PLACEHOLDER", binaryName ? "cursor" }:
    let
      basePackage = callPackage ./cursor {
        inherit version hash hashAarch64;
        commandLineArgs = "--user-data-dir=$HOME/.cursor-${version} --extensions-dir=$HOME/.cursor-${version}/extensions";
        postInstall = lib.optionalString (binaryName != "cursor") ''
          # Rename binary to version-specific name
          mv $out/bin/cursor $out/bin/${binaryName}
          
          # Update desktop entry
          substituteInPlace $out/share/applications/cursor.desktop \
            --replace "Exec=$out/bin/cursor" "Exec=$out/bin/${binaryName}" \
            --replace "Name=Cursor" "Name=Cursor ${version}" \
            --replace "Icon=cursor" "Icon=cursor-${version}"
          
          # Rename update commands if they exist
          if [ -f "$out/bin/cursor-update" ]; then
            mv $out/bin/cursor-update $out/bin/${binaryName}-update
          fi
          if [ -f "$out/bin/cursor-check-update" ]; then
            mv $out/bin/cursor-check-update $out/bin/${binaryName}-check-update
          fi
        '';
      };
    in basePackage;

in {
  # Version 2.0.64 - Last with custom modes (DEFAULT)
  cursor = mkCursorVersion {
    version = "2.0.64";
    hash = "sha256-FP3tl/BDl9FFR/DujbaTKT80tyCNHTzEqCTQ/6bXaaU=";
    binaryName = "cursor";  # Main binary keeps standard name
  };

  # Version 2.0.64 - Named variant
  cursor-2_0_64 = mkCursorVersion {
    version = "2.0.64";
    hash = "sha256-FP3tl/BDl9FFR/DujbaTKT80tyCNHTzEqCTQ/6bXaaU=";
    binaryName = "cursor-2.0.64";
  };

  # Version 2.0.77 - Latest 2.0.x (TODO: get hash)
  cursor-2_0_77 = mkCursorVersion {
    version = "2.0.77";
    hash = "sha256-PLACEHOLDER";  # TODO: Get correct hash
    binaryName = "cursor-2.0.77";
  };

  # Version 1.7.54 - Popular pre-2.0 (TODO: get hash)
  cursor-1_7_54 = mkCursorVersion {
    version = "1.7.54";
    hash = "sha256-PLACEHOLDER";  # TODO: Get correct hash
    binaryName = "cursor-1.7.54";
  };
}
