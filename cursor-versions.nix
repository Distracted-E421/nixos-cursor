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
      # Use \\$HOME literal to ensure it's expanded by the shell script wrapper at runtime
      # Note: In Nix string, "\\" becomes "\", so "\\$HOME" becomes "\$HOME" in the generated script
      [ "--user-data-dir" "\\$HOME/.cursor-${version}" "--extensions-dir" "\\$HOME/.cursor-${version}/extensions" ]
    else if dataStrategy == "sync" then
      # Hybrid: base config shared, version-specific overrides
      # TODO: Implement sync mechanism
      [ "--user-data-dir" "\\$HOME/.cursor-${version}" "--extensions-dir" "\\$HOME/.config/Cursor/extensions" ]
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
    hash = "sha256-zT9GhdwGDWZJQl+WpV2txbmp3/tJRtL6ds1UZQoKNzA=";
    srcUrl = "https://downloads.cursor.com/production/25412918da7e74b2686b25d62da1f01cfcd27683/linux/x64/Cursor-2.0.64-x86_64.AppImage";
    binaryName = "cursor-2.0.64";
    dataStrategy = "isolated";
  };

  # ===== Additional 2.0.x Versions (Custom Modes Era) =====
  
  cursor-2_0_75 = mkCursorVersion {
    version = "2.0.75";
    hash = "sha256-e/FNGAN+AErgEv4GaMQLPhV0LmSuHF9RNQ+SJEiP2z4=";
    srcUrl = "https://downloads.cursor.com/production/9e7a27b76730ca7fe4aecaeafc58bac1e2c82121/linux/x64/Cursor-2.0.75-x86_64.AppImage";
    binaryName = "cursor-2.0.75";
    dataStrategy = "isolated";
  };

  cursor-2_0_74 = mkCursorVersion {
    version = "2.0.74";
    hash = "sha256-fXcdWBXyD6V6oXm9w/wqhLkK+mlqJouE/VmuKcfaaPQ=";
    srcUrl = "https://downloads.cursor.com/production/a965544b869cfb53b46806974091f97565545e48/linux/x64/Cursor-2.0.74-x86_64.AppImage";
    binaryName = "cursor-2.0.74";
    dataStrategy = "isolated";
  };

  cursor-2_0_73 = mkCursorVersion {
    version = "2.0.73";
    hash = "sha256-361RG5msRvohsgLs4fUWxExSylcPBkq2zfEB3IiQ3Ho=";
    srcUrl = "https://downloads.cursor.com/production/55b873ebecb5923d3b947d7e67e841d3ac781886/linux/x64/Cursor-2.0.73-x86_64.AppImage";
    binaryName = "cursor-2.0.73";
    dataStrategy = "isolated";
  };

  cursor-2_0_69 = mkCursorVersion {
    version = "2.0.69";
    hash = "sha256-dwhYqX3/VtutxDSDPoHicM8D/sUvkWRnOjrSOBPiV+s=";
    srcUrl = "https://downloads.cursor.com/production/63fcac100bd5d5749f2a98aa47d65f6eca61db39/linux/x64/Cursor-2.0.69-x86_64.AppImage";
    binaryName = "cursor-2.0.69";
    dataStrategy = "isolated";
  };

  cursor-2_0_63 = mkCursorVersion {
    version = "2.0.63";
    hash = "sha256-7wA1R0GeUSXSViviXAK+mc14CSE2aTgFrbcBKj5dTbI=";
    srcUrl = "https://downloads.cursor.com/production/505046dcfad2acda3d066e32b7cd8b6e2dc1fdcd/linux/x64/Cursor-2.0.63-x86_64.AppImage";
    binaryName = "cursor-2.0.63";
    dataStrategy = "isolated";
  };

  cursor-2_0_60 = mkCursorVersion {
    version = "2.0.60";
    hash = "sha256-g/FMqKk/FapbRTQ5+IG1R2LHVlDXDNDc3uN9lJMMcaI=";
    srcUrl = "https://downloads.cursor.com/production/c6d93c13f57509f77eb65783b28e75a857b74c03/linux/x64/Cursor-2.0.60-x86_64.AppImage";
    binaryName = "cursor-2.0.60";
    dataStrategy = "isolated";
  };

  # ===== Pre-2.0 Versions (Classic Era) =====

  cursor-1_7_53 = mkCursorVersion {
    version = "1.7.53";
    hash = "sha256-zg5hpGRw0YL5XMpSn9ts4i4toT/fumj8rDJixGh1Hvc=";
    srcUrl = "https://downloads.cursor.com/production/ab6b80c19b51fe71d58e69d8ed3802be587b3418/linux/x64/Cursor-1.7.53-x86_64.AppImage";
    binaryName = "cursor-1.7.53";
    dataStrategy = "isolated";
  };

  cursor-1_7_52 = mkCursorVersion {
    version = "1.7.52";
    hash = "sha256-nhDDdXE5/m9uASiQUJ4GHfApkzkf9ju5b8s0h6BhpjQ=";
    srcUrl = "https://downloads.cursor.com/production/9675251a06b1314d50ff34b0cbe5109b78f848cd/linux/x64/Cursor-1.7.52-x86_64.AppImage";
    binaryName = "cursor-1.7.52";
    dataStrategy = "isolated";
  };

  cursor-1_7_46 = mkCursorVersion {
    version = "1.7.46";
    hash = "sha256-XDKDZYCagr7bEL4HzQFkhdUhPiL5MaRzZTPNrLDPZDM=";
    srcUrl = "https://downloads.cursor.com/production/b9e5948c1ad20443a5cecba6b84a3c9b99d62582/linux/x64/Cursor-1.7.46-x86_64.AppImage";
    binaryName = "cursor-1.7.46";
    dataStrategy = "isolated";
  };
}
