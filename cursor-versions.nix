# Multi-Version Cursor System
# Allows running different Cursor versions simultaneously with different binary names
#
# Usage:
#   cursor         # Main version (2.0.64 - last with custom modes)
#   cursor-2.0.64  # Explicit 2.0.64
#   cursor-2.0.77  # Latest 2.0.x
#   cursor-1.7.54  # Popular pre-2.0
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
  # Local AppImages (for when DNS is broken)
  localAppImages = {
    "2.0.77" = /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage;
    # Add more as you download them:
    # "2.0.64" = /home/e421/Downloads/Cursor-2.0.64-x86_64.AppImage;
    # "1.7.54" = /home/e421/Downloads/Cursor-1.7.54-x86_64.AppImage;
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
      # NOTE: Use ''$ to escape $ for runtime expansion (Nix indented string syntax)
      "--user-data-dir=''$HOME/.cursor-${version} --extensions-dir=''$HOME/.cursor-${version}/extensions"
    else if dataStrategy == "sync" then
      # Hybrid: base config shared, version-specific overrides
      # TODO: Implement sync mechanism
      "--user-data-dir=''$HOME/.cursor-${version} --extensions-dir=''$HOME/.config/Cursor/extensions"
    else
      throw "Invalid dataStrategy: ${dataStrategy}. Use: shared, isolated, or sync";

  # Base cursor package builder
  mkCursorVersion =
    {
      version,
      hash,
      hashAarch64 ? "sha256-PLACEHOLDER",
      binaryName ? "cursor",
      useLocalAppImage ? true, # Prefer local AppImage (for DNS issues)
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
  # Main cursor package (2.0.64 - last with custom modes, DEFAULT)
  cursor = mkCursorVersion {
    version = "2.0.64";
    hash = "sha256-FP3tl/BDl9FFR/DujbaTKT80tyCNHTzEqCTQ/6bXaaU=";
    binaryName = "cursor"; # Main binary keeps standard name
    useLocalAppImage = false; # Try network first for main version
    dataStrategy = "shared"; # Main version uses standard location
  };

  # Version 2.0.64 - Named variant (isolated data)
  cursor-2_0_64 = mkCursorVersion {
    version = "2.0.64";
    hash = "sha256-FP3tl/BDl9FFR/DujbaTKT80tyCNHTzEqCTQ/6bXaaU=";
    binaryName = "cursor-2.0.64";
    dataStrategy = "isolated";
  };

  # Version 2.0.77 - Latest 2.0.x (FROM LOCAL APPIMAGE!)
  cursor-2_0_77 = mkCursorVersion {
    version = "2.0.77";
    hash = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=";
    binaryName = "cursor-2.0.77";
    useLocalAppImage = true; # Use local file!
    dataStrategy = "isolated";
  };

  # Version 1.7.54 - Popular pre-2.0 (TODO: get hash and local AppImage)
  cursor-1_7_54 = mkCursorVersion {
    version = "1.7.54";
    hash = "sha256-PLACEHOLDER"; # TODO: Get correct hash
    binaryName = "cursor-1.7.54";
    useLocalAppImage = false; # No local file yet
    dataStrategy = "isolated";
  };
}
