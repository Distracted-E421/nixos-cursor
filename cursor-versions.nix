# Multi-Version Cursor System
# Allows running different Cursor versions simultaneously with different binary names
#
# Usage:
#   cursor         # Main version (2.0.77 - Latest targeted stable)
#   cursor-2.0.77  # Explicit 2.0.77
#   cursor-1.7.54  # Classic 1.7.54 (Pre-2.0)
#   cursor-2.0.64  # Last with old custom modes (fallback)
#
# User Data Strategy:
#   - Each version can have isolated data: ~/.cursor-VERSION/
#   - Or share base data with sync: ~/.config/Cursor/ + version-specific overrides
#   - Controlled via CURSOR_DATA_STRATEGY environment variable:
#     * "shared" - All versions share ~/.config/Cursor (default, careful!)
#     * "isolated" - Each version gets ~/.cursor-VERSION/ (safest)
#     * "sync" - Base shared + version-specific overrides (balanced)

{
  lib,
  callPackage,
}:

let
  # Local AppImages (for when DNS is broken or specific local file needed)
  localAppImages = {
    # "2.0.77" = /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage;
  };

  # User data directory strategies
  makeUserDataArgs =
    {
      version,
      dataStrategy ? "isolated",
    }:
    if dataStrategy == "shared" then
      # Share everything - DANGEROUS if versions have incompatible DBs!
      ""
    else if dataStrategy == "isolated" then
      # Complete isolation - safest
      # We pass path components separately to avoid quoting issues
      # Use \$HOME literal to ensure it's expanded by the shell script wrapper at runtime
      [ "--user-data-dir" "\$HOME/.cursor-${version}" "--extensions-dir" "\$HOME/.cursor-${version}/extensions" ]
    else if dataStrategy == "sync" then
      # Hybrid: base config shared, version-specific overrides
      # TODO: Implement sync mechanism
      [ "--user-data-dir" "\$HOME/.cursor-${version}" "--extensions-dir" "\$HOME/.config/Cursor/extensions" ]
    else
      throw "Invalid dataStrategy: ${dataStrategy}. Use: shared, isolated, or sync";

  # Base cursor package builder
  mkCursorVersion =
    {
      version,
      hash,
      hashAarch64 ? "sha256-PLACEHOLDER",
      srcUrl ? null,
      binaryName ? "cursor",
      useLocalAppImage ? false,
      dataStrategy ? "isolated", # isolated|shared|sync
    }:
    let
      localAppImage =
        if useLocalAppImage && (builtins.hasAttr version localAppImages) then
          localAppImages.${version}
        else
          null;

      userDataArgs = makeUserDataArgs { inherit version dataStrategy; };

      basePackage = callPackage ./cursor {
        inherit
          version
          hash
          hashAarch64
          srcUrl
          localAppImage
          ;
        commandLineArgs = userDataArgs;
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
    in
    basePackage;

in
{
  # Main cursor package (Defaults to 2.0.77 as requested)
  cursor = mkCursorVersion {
    version = "2.0.77";
    hash = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=";
    srcUrl = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage";
    binaryName = "cursor"; 
    dataStrategy = "shared"; # Main version uses standard location
  };

  # Version 2.0.77 - Targeted Version
  cursor-2_0_77 = mkCursorVersion {
    version = "2.0.77";
    hash = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=";
    srcUrl = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage";
    binaryName = "cursor-2.0.77";
    dataStrategy = "isolated";
  };

  # Version 1.7.54 - Classic Pre-2.0
  cursor-1_7_54 = mkCursorVersion {
    version = "1.7.54";
    hash = "sha256-BKxFrfKFMWmJhed+lB5MjYHbCR9qZM3yRcs7zWClYJE=";
    srcUrl = "https://downloads.cursor.com/production/5c17eb2968a37f66bc6662f48d6356a100b67be8/linux/x64/Cursor-1.7.54-x86_64.AppImage";
    binaryName = "cursor-1.7.54";
    dataStrategy = "isolated";
  };
  
  # Version 2.0.64 - Fallback/Reference
  cursor-2_0_64 = mkCursorVersion {
    version = "2.0.64";
    hash = "sha256-FP3tl/BDl9FFR/DujbaTKT80tyCNHTzEqCTQ/6bXaaU=";
    binaryName = "cursor-2.0.64";
    dataStrategy = "isolated";
  };
}
