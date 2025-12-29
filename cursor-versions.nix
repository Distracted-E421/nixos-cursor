# Multi-Version Cursor System (RC5.0)
# Allows running different Cursor versions simultaneously with UNIQUE binary names
#
# CRITICAL FIX (RC3.4): Each version now installs to unique paths:
#   - /share/cursor-VERSION/  (instead of /share/cursor/)
#   - /bin/cursor-VERSION     (instead of /bin/cursor)
# This allows multiple versions to coexist in home.packages without conflicts.
#
# Total Versions: 64+ (1.7.11 through 2.3.10)
#   - 2.3.x Latest Era: 1 version (2.3.10) - NO CUSTOM MODES, LATEST
#   - 2.2.x Latest Era: 11 versions (2.2.3 - 2.2.27) - NO CUSTOM MODES
#   - 2.1.x Post-Removal: 21 versions (2.1.6 - 2.1.50) - NO CUSTOM MODES  
#   - 2.0.x Custom Modes Era: 17 versions (2.0.11 - 2.0.77) - HAS CUSTOM MODES
#   - 1.7.x Classic Era: 19 versions (1.7.11 - 1.7.54) - Legacy
#   - 1.6.x: DROPPED (no longer supported by Cursor)
#
# Usage Examples:
#   cursor         # Main version (2.0.77 - Last with custom modes)
#   cursor-2.2.27  # Latest version (use with Cursor Studio external modes)
#   cursor-2.0.77  # Explicit custom modes version (isolated data)
#   cursor-1.7.54  # Latest pre-2.0 (isolated data)
#
# Multi-Version Installation (NOW WORKS!):
#   home.packages = [
#     cursor           # /bin/cursor, /share/cursor/
#     cursor-2_0_64    # /bin/cursor-2.0.64, /share/cursor-2.0.64/
#     cursor-1_7_54    # /bin/cursor-1.7.54, /share/cursor-1.7.54/
#   ];
#
# User Data Strategy:
#   - Each version can have isolated data: ~/.cursor-VERSION/
#   - Or share base data with sync: ~/.config/Cursor/ + version-specific overrides
#   - Controlled via dataStrategy parameter:
#     * "shared" - All versions share ~/.config/Cursor (use with caution!)
#     * "isolated" - Each version gets ~/.cursor-VERSION/ (safest, default)
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
      [
        "--user-data-dir"
        "\\$HOME/.cursor-${version}"
        "--extensions-dir"
        "\\$HOME/.cursor-${version}/extensions"
      ]
    else if dataStrategy == "sync" then
      # Hybrid: base config shared, version-specific overrides
      # TODO: Implement sync mechanism
      [
        "--user-data-dir"
        "\\$HOME/.cursor-${version}"
        "--extensions-dir"
        "\\$HOME/.config/Cursor/extensions"
      ]
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

      # Compute the share directory name (cursor for main, cursor-VERSION for others)
      shareDirName = if binaryName == "cursor" then "cursor" else "cursor-${version}";

      basePackage = callPackage ./cursor {
        inherit
          version
          hash
          hashAarch64
          srcUrl
          localAppImage
          ;
        commandLineArgs = userDataArgs;
        # Pass shareDirName to base package for version-specific installation
        shareDirName = shareDirName;
        postInstall = lib.optionalString (binaryName != "cursor") ''
          # Rename binary to version-specific name
          mv $out/bin/cursor $out/bin/${binaryName}

          # CRITICAL: Also rename the wrapped binaries created by makeWrapper
          # These would otherwise conflict when installing multiple versions:
          #   .cursor-wrapped -> .cursor-VERSION-wrapped
          if [ -f "$out/bin/.cursor-wrapped" ]; then
            mv $out/bin/.cursor-wrapped $out/bin/.${binaryName}-wrapped
          fi

          # CRITICAL: Update the script to reference the renamed wrapper
          # The shell script still has ".cursor-wrapped" hardcoded, we need to fix it
          substituteInPlace $out/bin/${binaryName} \
            --replace ".cursor-wrapped" ".${binaryName}-wrapped"

          # Update desktop entry to use version-specific binary
          # Note: Desktop file is already named ${shareDirName}.desktop (cursor-VERSION.desktop)
          substituteInPlace $out/share/applications/${shareDirName}.desktop \
            --replace "Exec=$out/bin/cursor" "Exec=$out/bin/${binaryName}"

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

  # ===== 2.1.x Latest Era (11 versions) =====

  cursor-2_1_34 = mkCursorVersion {
    version = "2.1.34";
    hash = "sha256-NPs0P+cnPo3KMdezhAkPR4TwpcvIrSuoX+40NsKyfzA=";
    srcUrl = "https://downloads.cursor.com/production/609c37304ae83141fd217c4ae638bf532185650f/linux/x64/Cursor-2.1.34-x86_64.AppImage";
    binaryName = "cursor-2.1.34";
    dataStrategy = "isolated";
  };

  cursor-2_1_32 = mkCursorVersion {
    version = "2.1.32";
    hash = "sha256-jNO4EiJXJEMJ1+gGElgZ2alsQHsceg4YPRdQocY9c6k=";
    srcUrl = "https://downloads.cursor.com/production/ef979b1b43d85eee2a274c25fd62d5502006e425/linux/x64/Cursor-2.1.32-x86_64.AppImage";
    binaryName = "cursor-2.1.32";
    dataStrategy = "isolated";
  };

  cursor-2_1_26 = mkCursorVersion {
    version = "2.1.26";
    hash = "sha256-qw3e/Di5iI5wHbMAJOZiDUsmo46CJhdTWvoWeVDtV/M=";
    srcUrl = "https://downloads.cursor.com/production/f628a4761be40b8869ca61a6189cafd14756dff4/linux/x64/Cursor-2.1.26-x86_64.AppImage";
    binaryName = "cursor-2.1.26";
    dataStrategy = "isolated";
  };

  cursor-2_1_25 = mkCursorVersion {
    version = "2.1.25";
    hash = "sha256-qY+qg0CCRwfZH7PE2YINmANL43l4m5ysXg3L+Q2WGzk=";
    srcUrl = "https://downloads.cursor.com/production/7584ea888f7eb7bf76c9873a8f71b28f034a982e/linux/x64/Cursor-2.1.25-x86_64.AppImage";
    binaryName = "cursor-2.1.25";
    dataStrategy = "isolated";
  };

  cursor-2_1_24 = mkCursorVersion {
    version = "2.1.24";
    hash = "sha256-GFnW4v1/R6AjW2cZyMp65KQZdOwipb5h90ruxN19xxU=";
    srcUrl = "https://downloads.cursor.com/production/ac32b095dae9b8e0cfede6c5ebc55e589ee50e1b/linux/x64/Cursor-2.1.24-x86_64.AppImage";
    binaryName = "cursor-2.1.24";
    dataStrategy = "isolated";
  };

  cursor-2_1_20 = mkCursorVersion {
    version = "2.1.20";
    hash = "sha256-dP61tSPD8DAU2gOruM40Eomwqz8VeTh6iS4V3muCk14=";
    srcUrl = "https://downloads.cursor.com/production/a8d8905b06c8da1739af6f789efd59c28ac2a680/linux/x64/Cursor-2.1.20-x86_64.AppImage";
    binaryName = "cursor-2.1.20";
    dataStrategy = "isolated";
  };

  cursor-2_1_19 = mkCursorVersion {
    version = "2.1.19";
    hash = "sha256-5ReInUdqLRQzDsS+Rr7dwPrmZHH2Q/k9T+xR0EhQJNE=";
    srcUrl = "https://downloads.cursor.com/production/39a966b4048ef6b8024b27d4812a50d88de29cc3/linux/x64/Cursor-2.1.19-x86_64.AppImage";
    binaryName = "cursor-2.1.19";
    dataStrategy = "isolated";
  };

  cursor-2_1_17 = mkCursorVersion {
    version = "2.1.17";
    hash = "sha256-w+nc8sJyzogP0YwHgsJclNI+MpfEPrliW6IlCkLeKoc=";
    srcUrl = "https://downloads.cursor.com/production/6757269838ae9ac4caaa2be13f396fdfbcf1f9a6/linux/x64/Cursor-2.1.17-x86_64.AppImage";
    binaryName = "cursor-2.1.17";
    dataStrategy = "isolated";
  };

  cursor-2_1_15 = mkCursorVersion {
    version = "2.1.15";
    hash = "sha256-KQiFlwaG60yB/PEyUm3HmcrIt2l+s92qhVl02mrrcV0=";
    srcUrl = "https://downloads.cursor.com/production/a022145cbf8aea0babc3b039a98551c1518de024/linux/x64/Cursor-2.1.15-x86_64.AppImage";
    binaryName = "cursor-2.1.15";
    dataStrategy = "isolated";
  };

  cursor-2_1_7 = mkCursorVersion {
    version = "2.1.7";
    hash = "sha256-Bj8TcpYI7bPd3JgRut+AS0NXBnUFeEeHfGCiwCP+4o0=";
    srcUrl = "https://downloads.cursor.com/production/3d2e45538bcc4fd7ed28cc113c2110b26a824a00/linux/x64/Cursor-2.1.7-x86_64.AppImage";
    binaryName = "cursor-2.1.7";
    dataStrategy = "isolated";
  };

  cursor-2_1_6 = mkCursorVersion {
    version = "2.1.6";
    hash = "sha256-o3SKiDXkXRKm73EPcSsT7TldCBJWi/fs/7W/B/m5ge4=";
    srcUrl = "https://downloads.cursor.com/production/92340560ea81cb6168e2027596519d68af6c90a1/linux/x64/Cursor-2.1.6-x86_64.AppImage";
    binaryName = "cursor-2.1.6";
    dataStrategy = "isolated";
  };

  # ===== 2.0.x Custom Modes Era (17 versions) =====

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

  # ===== Additional 2.0.x Versions (9 new - Early Custom Modes) =====

  cursor-2_0_57 = mkCursorVersion {
    version = "2.0.57";
    hash = "sha256-RZ7BzmtbmdiAuXoCyllR+HgBbvQcGwhN/kIvJVxg6vo=";
    srcUrl = "https://downloads.cursor.com/production/eb037ef2bfba33ac568b0da614cb1c7b738455d6/linux/x64/Cursor-2.0.57-x86_64.AppImage";
    binaryName = "cursor-2.0.57";
    dataStrategy = "isolated";
  };

  cursor-2_0_54 = mkCursorVersion {
    version = "2.0.54";
    hash = "sha256-ndss1uOAHk04Y6KnPWGqm+dTyGCrVOR1uJW/8nD/T/s=";
    srcUrl = "https://downloads.cursor.com/production/7a31bffd467aa2d9adfda69076eb924e9062cb27/linux/x64/Cursor-2.0.54-x86_64.AppImage";
    binaryName = "cursor-2.0.54";
    dataStrategy = "isolated";
  };

  cursor-2_0_52 = mkCursorVersion {
    version = "2.0.52";
    hash = "sha256-+rH+ubUx7FDyK+EoqNgnMpjR1yvp6J2Hymgl/xQWvxw=";
    srcUrl = "https://downloads.cursor.com/production/2125c48207a2a9aa55bce3d0af552912c84175d9/linux/x64/Cursor-2.0.52-x86_64.AppImage";
    binaryName = "cursor-2.0.52";
    dataStrategy = "isolated";
  };

  cursor-2_0_43 = mkCursorVersion {
    version = "2.0.43";
    hash = "sha256-ok+7uBlI9d3a5R5FvMaWlbPM6tX2eCse7jZ7bmlPExY=";
    srcUrl = "https://downloads.cursor.com/production/8e4da76ad196925accaa169efcae28c45454cce3/linux/x64/Cursor-2.0.43-x86_64.AppImage";
    binaryName = "cursor-2.0.43";
    dataStrategy = "isolated";
  };

  cursor-2_0_40 = mkCursorVersion {
    version = "2.0.40";
    hash = "sha256-BwKprsZ4V5IPp0W7eef7ZPrr3K4DlQoKKwIJeJQxnC4=";
    srcUrl = "https://downloads.cursor.com/production/a9b73428ca6aeb2d24623da2841a271543735562/linux/x64/Cursor-2.0.40-x86_64.AppImage";
    binaryName = "cursor-2.0.40";
    dataStrategy = "isolated";
  };

  cursor-2_0_38 = mkCursorVersion {
    version = "2.0.38";
    hash = "sha256-HD+8OytWJrWgMy8PVo2+X7b5UdL6fBQpw7XRH+lvzDA=";
    srcUrl = "https://downloads.cursor.com/production/3fa438a81d579067162dd8767025b788454e6f93/linux/x64/Cursor-2.0.38-x86_64.AppImage";
    binaryName = "cursor-2.0.38";
    dataStrategy = "isolated";
  };

  cursor-2_0_34 = mkCursorVersion {
    version = "2.0.34";
    hash = "sha256-x51N2BttMkfKwH4/Uxn/ZNFVPZbaNdsZm8BFFIMmxBM=";
    srcUrl = "https://downloads.cursor.com/production/45fd70f3fe72037444ba35c9e51ce86a1977ac11/linux/x64/Cursor-2.0.34-x86_64.AppImage";
    binaryName = "cursor-2.0.34";
    dataStrategy = "isolated";
  };

  cursor-2_0_32 = mkCursorVersion {
    version = "2.0.32";
    hash = "sha256-Qe7C4wW5TjnpiwanOgmK56Gk6i0ORp2p89ld1NZrBb0=";
    srcUrl = "https://downloads.cursor.com/production/9a5dd36e54f13fb9c0e74490ec44d080dbc5df53/linux/x64/Cursor-2.0.32-x86_64.AppImage";
    binaryName = "cursor-2.0.32";
    dataStrategy = "isolated";
  };

  cursor-2_0_11 = mkCursorVersion {
    version = "2.0.11";
    hash = "sha256-p5rEvlEt02iV+/sz9FahA3lim1V5lw8IPO5B0hUBj2g=";
    srcUrl = "https://downloads.cursor.com/production/4aa02949dc5065af49f2f6f72e3278386a3f7116/linux/x64/Cursor-2.0.11-x86_64.AppImage";
    binaryName = "cursor-2.0.11";
    dataStrategy = "isolated";
  };

  # ===== Additional 1.7.x Versions (15 new - Extended Classic Era) =====

  cursor-1_7_44 = mkCursorVersion {
    version = "1.7.44";
    hash = "sha256-/eLb6+ECxFmpzgtRIgfO2PPn28kFbA3Xmq8ZjPrDQ5g=";
    srcUrl = "https://downloads.cursor.com/production/9d178a4a5589981b62546448bb32920a8219a5de/linux/x64/Cursor-1.7.44-x86_64.AppImage";
    binaryName = "cursor-1.7.44";
    dataStrategy = "isolated";
  };

  cursor-1_7_43 = mkCursorVersion {
    version = "1.7.43";
    hash = "sha256-StY0yYqIuDCf6hbXJHERnRXqwVBnzKX2pxfretaUHo8=";
    srcUrl = "https://downloads.cursor.com/production/df279210b53cf4686036054b15400aa2fe06d6dd/linux/x64/Cursor-1.7.43-x86_64.AppImage";
    binaryName = "cursor-1.7.43";
    dataStrategy = "isolated";
  };

  cursor-1_7_40 = mkCursorVersion {
    version = "1.7.40";
    hash = "sha256-+NNq6fSEQ9zYnDL13vz4uLOpqk61QLjLIbTcfQhTFe0=";
    srcUrl = "https://downloads.cursor.com/production/df79b2380cd32922cad03529b0dc0c946c311856/linux/x64/Cursor-1.7.40-x86_64.AppImage";
    binaryName = "cursor-1.7.40";
    dataStrategy = "isolated";
  };

  cursor-1_7_39 = mkCursorVersion {
    version = "1.7.39";
    hash = "sha256-QDn1SH1RB6Dod4EJHXynynEpNPhq81dQZnHbVcw3nBs=";
    srcUrl = "https://downloads.cursor.com/production/a9c77ceae65b77ff772d6adfe05f24d8ebcb2794/linux/x64/Cursor-1.7.39-x86_64.AppImage";
    binaryName = "cursor-1.7.39";
    dataStrategy = "isolated";
  };

  cursor-1_7_38 = mkCursorVersion {
    version = "1.7.38";
    hash = "sha256-52QJVbXO3CYeL4vVZ249xabS7AoYFDOxKCQ6m3vB+vE=";
    srcUrl = "https://downloads.cursor.com/production/fe5d1728063e86edeeda5bebd2c8e14bf4d0f96a/linux/x64/Cursor-1.7.38-x86_64.AppImage";
    binaryName = "cursor-1.7.38";
    dataStrategy = "isolated";
  };

  cursor-1_7_36 = mkCursorVersion {
    version = "1.7.36";
    hash = "sha256-zY9kM9td0yKAMxVmad7saN4c6z2p5OFEa7ScCA3Qo3I=";
    srcUrl = "https://downloads.cursor.com/production/493c403e4a45c5f971d1c76cc74febd0968d57d8/linux/x64/Cursor-1.7.36-x86_64.AppImage";
    binaryName = "cursor-1.7.36";
    dataStrategy = "isolated";
  };

  cursor-1_7_33 = mkCursorVersion {
    version = "1.7.33";
    hash = "sha256-bXT/NVqcyR+RrqZdd0TbtcsyLjGb8Wv5S5On9JLElG4=";
    srcUrl = "https://downloads.cursor.com/production/a84f941711ad680a635c8a3456002833186c484f/linux/x64/Cursor-1.7.33-x86_64.AppImage";
    binaryName = "cursor-1.7.33";
    dataStrategy = "isolated";
  };

  cursor-1_7_28 = mkCursorVersion {
    version = "1.7.28";
    hash = "sha256-ZB/xGGKyVnfmNASWtfkmoxvzzkXa2pUlmgY2Bb9f5lU=";
    srcUrl = "https://downloads.cursor.com/production/adb0f9e3e4f184bba7f3fa6dbfd72ad0ebb8cfd8/linux/x64/Cursor-1.7.28-x86_64.AppImage";
    binaryName = "cursor-1.7.28";
    dataStrategy = "isolated";
  };

  cursor-1_7_25 = mkCursorVersion {
    version = "1.7.25";
    hash = "sha256-gUjzdixozoexd67ugeaabtUspnkaie9HXhIvFWY0lyM=";
    srcUrl = "https://downloads.cursor.com/production/429604585b94ab2b96a4dabff4660f41d5b7fb8f/linux/x64/Cursor-1.7.25-x86_64.AppImage";
    binaryName = "cursor-1.7.25";
    dataStrategy = "isolated";
  };

  cursor-1_7_23 = mkCursorVersion {
    version = "1.7.23";
    hash = "sha256-cN6kYGMLNGOjinUIDWdn7mVyDd7TKwLwdqanN6ZRGE0=";
    srcUrl = "https://downloads.cursor.com/production/5069385c5a69db511722405ab5aeadc01579afd8/linux/x64/Cursor-1.7.23-x86_64.AppImage";
    binaryName = "cursor-1.7.23";
    dataStrategy = "isolated";
  };

  cursor-1_7_22 = mkCursorVersion {
    version = "1.7.22";
    hash = "sha256-bidAyiP0we39/87ySCK63tii1BtGVpFsuRC1ayXqsh0=";
    srcUrl = "https://downloads.cursor.com/production/31b1fbfcec1bf758f7140645f005fc78b5df355b/linux/x64/Cursor-1.7.22-x86_64.AppImage";
    binaryName = "cursor-1.7.22";
    dataStrategy = "isolated";
  };

  cursor-1_7_17 = mkCursorVersion {
    version = "1.7.17";
    hash = "sha256-OsZiUXWKNLO8sUqielk0kap0DAkMY8OvWYO0KV3iads=";
    srcUrl = "https://downloads.cursor.com/production/34881053400013f38e2354f1479c88c9067039a2/linux/x64/Cursor-1.7.17-x86_64.AppImage";
    binaryName = "cursor-1.7.17";
    dataStrategy = "isolated";
  };

  cursor-1_7_16 = mkCursorVersion {
    version = "1.7.16";
    hash = "sha256-uWqVzOT9miTPnNZgWLzJ2nddOhZldHKOYaaFO7KK9n8=";
    srcUrl = "https://downloads.cursor.com/production/39476a6453a2a2903ed6446529255038f81c929f/linux/x64/Cursor-1.7.16-x86_64.AppImage";
    binaryName = "cursor-1.7.16";
    dataStrategy = "isolated";
  };

  cursor-1_7_12 = mkCursorVersion {
    version = "1.7.12";
    hash = "sha256-vSvRGVIJCZjodNQ+cFFUd/fkzy1PzAXj5TQ2C7xV9Vc=";
    srcUrl = "https://downloads.cursor.com/production/b3f1951240d5016648330fab51192dc03e8d705a/linux/x64/Cursor-1.7.12-x86_64.AppImage";
    binaryName = "cursor-1.7.12";
    dataStrategy = "isolated";
  };

  cursor-1_7_11 = mkCursorVersion {
    version = "1.7.11";
    hash = "sha256-CrR/KcKkBHBTIc1K/npJSR85I031MSF3mx0nTduKyWE=";
    srcUrl = "https://downloads.cursor.com/production/867f14c797c14c23a187097ea179bc97d215a7c4/linux/x64/Cursor-1.7.11-x86_64.AppImage";
    binaryName = "cursor-1.7.11";
    dataStrategy = "isolated";
  };

  # ===== 1.6.x Legacy Version (1 new) =====

  # ===== 1.6.x DROPPED - No longer supported by Cursor =====
  # cursor-1_6_45 removed in RC5.0 - version no longer supported

  # ===== 2.2.x Latest Era (11 versions) - NO CUSTOM MODES =====
  # These versions require Cursor Studio external modes for custom mode functionality
  
  # ═══════════════════════════════════════════════════════════════════
  # 2.3.x Era - LATEST (auto-synced from GitHub)
  # ═══════════════════════════════════════════════════════════════════

  cursor-2_3_10 = mkCursorVersion {
    version = "2.3.10";
    hash = "sha256-qFaT0jQUcy1q3USdaeKBrrd3n9GtlPz94iQd8iW5/l0=";
    srcUrl = "https://downloads.cursor.com/production/af6d64e4848e6185e482a2de5bac040191c8d79f/linux/x64/Cursor-2.3.10-x86_64.AppImage";
    binaryName = "cursor-2.3.10";
    dataStrategy = "isolated";
  };

  # ═══════════════════════════════════════════════════════════════════
  # 2.2.x Era (11 versions: 2.2.3 - 2.2.27)
  # ═══════════════════════════════════════════════════════════════════

  cursor-2_2_27 = mkCursorVersion {
    version = "2.2.27";
    hash = "sha256-zK0uSKNJ2N6C5nBz0QqLgWbUXXQ/A9oavVK62DKsGpc=";
    srcUrl = "https://downloads.cursor.com/production/92d81a68151ca9bec11fda0a58d29fef7cbccf65/linux/x64/Cursor-2.2.27-x86_64.AppImage";
    binaryName = "cursor-2.2.27";
    dataStrategy = "isolated";
  };

  cursor-2_2_23 = mkCursorVersion {
    version = "2.2.23";
    hash = "sha256-brApIRhvllH1lZU9wD87uSt7Q2ogDbEBrkF4EGB54Rk=";
    srcUrl = "https://downloads.cursor.com/production/b3c95a7981bb3057526f1f865e8c307a9911ce00/linux/x64/Cursor-2.2.23-x86_64.AppImage";
    binaryName = "cursor-2.2.23";
    dataStrategy = "isolated";
  };

  cursor-2_2_20 = mkCursorVersion {
    version = "2.2.20";
    hash = "sha256-dY42LaaP7CRbqY2tuulJOENa+QUGSL09m07PvxsZCr0=";
    srcUrl = "https://downloads.cursor.com/production/b3573281c4775bfc6bba466bf6563d3d498d1074/linux/x64/Cursor-2.2.20-x86_64.AppImage";
    binaryName = "cursor-2.2.20";
    dataStrategy = "isolated";
  };

  cursor-2_2_17 = mkCursorVersion {
    version = "2.2.17";
    hash = "sha256-8TTNIGlatkHE8O87h8VGevjaiyWDR8qq8PA7l64Bijs=";
    srcUrl = "https://downloads.cursor.com/production/cf858ca030e9c9a99ea444ec6efcbcfc40bfda75/linux/x64/Cursor-2.2.17-x86_64.AppImage";
    binaryName = "cursor-2.2.17";
    dataStrategy = "isolated";
  };

  cursor-2_2_14 = mkCursorVersion {
    version = "2.2.14";
    hash = "sha256-L4kzRm08rWbb05VNX5RHyPaL3Ij6UCzQDoLaahIGYbI=";
    srcUrl = "https://downloads.cursor.com/production/1685afce45886aa5579025ac7e077fc3d4369c52/linux/x64/Cursor-2.2.14-x86_64.AppImage";
    binaryName = "cursor-2.2.14";
    dataStrategy = "isolated";
  };

  cursor-2_2_12 = mkCursorVersion {
    version = "2.2.12";
    hash = "sha256-wc68sRJXWstwwCHq2NO4xhKjRlIg19rI3mIYHGcR4PE=";
    srcUrl = "https://downloads.cursor.com/production/4395cbb45916e730692e72c853b893578fbb0112/linux/x64/Cursor-2.2.12-x86_64.AppImage";
    binaryName = "cursor-2.2.12";
    dataStrategy = "isolated";
  };

  cursor-2_2_9 = mkCursorVersion {
    version = "2.2.9";
    hash = "sha256-++9Mnok7wVlFd3PGucBKms8t9PuAPpYuZ2ynZd+peCU=";
    srcUrl = "https://downloads.cursor.com/production/a86689c93e9fb11addfbefd29a6ec7c0a59175e7/linux/x64/Cursor-2.2.9-x86_64.AppImage";
    binaryName = "cursor-2.2.9";
    dataStrategy = "isolated";
  };

  cursor-2_2_8 = mkCursorVersion {
    version = "2.2.8";
    hash = "sha256-4zMSGjv4Sedp1KNpLnaKX0EeLsz8RVNsa531HUmoRxQ=";
    srcUrl = "https://downloads.cursor.com/production/acdb5a1ab634f13d3d9381161dcb9603f184e677/linux/x64/Cursor-2.2.8-x86_64.AppImage";
    binaryName = "cursor-2.2.8";
    dataStrategy = "isolated";
  };

  cursor-2_2_7 = mkCursorVersion {
    version = "2.2.7";
    hash = "sha256-Sv26X8Wk5agTVXbWCWiaJKpcNZrlqDwczbi4Fdq0suU=";
    srcUrl = "https://downloads.cursor.com/production/c7365150b3b3d35fd5f6504a5686fb9ea5eea3b3/linux/x64/Cursor-2.2.7-x86_64.AppImage";
    binaryName = "cursor-2.2.7";
    dataStrategy = "isolated";
  };

  cursor-2_2_6 = mkCursorVersion {
    version = "2.2.6";
    hash = "sha256-A8fNzxm/itf7yqhlO/GLKzcO5rgGslKnM0aSuJ+mXeQ=";
    srcUrl = "https://downloads.cursor.com/production/bb70f115f7056b569146f670bfeb812a30eaf061/linux/x64/Cursor-2.2.6-x86_64.AppImage";
    binaryName = "cursor-2.2.6";
    dataStrategy = "isolated";
  };

  cursor-2_2_3 = mkCursorVersion {
    version = "2.2.3";
    hash = "sha256-n64UK0cQBDMtSyrk+rS7N1/CJCUBS05x25pytFTwdr4=";
    srcUrl = "https://downloads.cursor.com/production/c25eb90df95d64f6d280779237c1ca39f9f3eef6/linux/x64/Cursor-2.2.3-x86_64.AppImage";
    binaryName = "cursor-2.2.3";
    dataStrategy = "isolated";
  };

  # ===== Additional 2.1.x Versions (10 new) =====
  
  cursor-2_1_50 = mkCursorVersion {
    version = "2.1.50";
    hash = "sha256-gitfWzovz0OxwoLXIMQ4PqMk+S8KzZlqcp0hmwVR2nE=";
    srcUrl = "https://downloads.cursor.com/production/56f0a83df8e9eb48585fcc4858a9440db4cc7771/linux/x64/Cursor-2.1.50-x86_64.AppImage";
    binaryName = "cursor-2.1.50";
    dataStrategy = "isolated";
  };

  cursor-2_1_49 = mkCursorVersion {
    version = "2.1.49";
    hash = "sha256-o64V7fjbsqSR/S/7uviIKumCljjetwsYo3R3jzXz3cY=";
    srcUrl = "https://downloads.cursor.com/production/21a2ed198584d56a91c0b996d1a09c93f8538440/linux/x64/Cursor-2.1.49-x86_64.AppImage";
    binaryName = "cursor-2.1.49";
    dataStrategy = "isolated";
  };

  cursor-2_1_48 = mkCursorVersion {
    version = "2.1.48";
    hash = "sha256-Uq61ZZZzlRyDqPaNnJbteFQ4KC9usD5DdUSTGgvo2wI=";
    srcUrl = "https://downloads.cursor.com/production/ce371ffbf5e240ca47f4b5f3f20efed084991120/linux/x64/Cursor-2.1.48-x86_64.AppImage";
    binaryName = "cursor-2.1.48";
    dataStrategy = "isolated";
  };

  cursor-2_1_47 = mkCursorVersion {
    version = "2.1.47";
    hash = "sha256-/juvatx3xrTdL+EMEECHereGhIa4vmFj0gPQQBA00to=";
    srcUrl = "https://downloads.cursor.com/production/2d3ce3499c15efd55b6b8538ea255eb7ba4266b2/linux/x64/Cursor-2.1.47-x86_64.AppImage";
    binaryName = "cursor-2.1.47";
    dataStrategy = "isolated";
  };

  cursor-2_1_46 = mkCursorVersion {
    version = "2.1.46";
    hash = "sha256-4YCBHefGYDQmh7qbLipCmHkyzHBq95b4NtiOS2Sc22o=";
    srcUrl = "https://downloads.cursor.com/production/ab326d0767c02fb9847b342c43ea58275c4b1685/linux/x64/Cursor-2.1.46-x86_64.AppImage";
    binaryName = "cursor-2.1.46";
    dataStrategy = "isolated";
  };

  cursor-2_1_44 = mkCursorVersion {
    version = "2.1.44";
    hash = "sha256-JUNkdQX/z5TryDK8aeC1QFADdGLpWbeemqArmnMeXQo=";
    srcUrl = "https://downloads.cursor.com/production/f6a8593b2b7c61c2063c79d5a8fcd248c9db458a/linux/x64/Cursor-2.1.44-x86_64.AppImage";
    binaryName = "cursor-2.1.44";
    dataStrategy = "isolated";
  };

  cursor-2_1_42 = mkCursorVersion {
    version = "2.1.42";
    hash = "sha256-UqHi9QlQSaOJZWW6bmElDrK5GaEGT3kU5LsXg2LUeHg=";
    srcUrl = "https://downloads.cursor.com/production/2e353c5f5b30150ff7b874dee5a87660693d9de6/linux/x64/Cursor-2.1.42-x86_64.AppImage";
    binaryName = "cursor-2.1.42";
    dataStrategy = "isolated";
  };

  cursor-2_1_41 = mkCursorVersion {
    version = "2.1.41";
    hash = "sha256-bVixbzTzMhfK/EP8mRBx2ZAEBKreEx6nMwTp1UFkJ1M=";
    srcUrl = "https://downloads.cursor.com/production/1321aa9140784391e83a406174345e818fe156f9/linux/x64/Cursor-2.1.41-x86_64.AppImage";
    binaryName = "cursor-2.1.41";
    dataStrategy = "isolated";
  };

  cursor-2_1_39 = mkCursorVersion {
    version = "2.1.39";
    hash = "sha256-SsKhW8q/AzOn1HqykhwaVHyTVm+OqTUiFtda7XDiAho=";
    srcUrl = "https://downloads.cursor.com/production/60d42bed27e5775c43ec0428d8c653c49e58e26a/linux/x64/Cursor-2.1.39-x86_64.AppImage";
    binaryName = "cursor-2.1.39";
    dataStrategy = "isolated";
  };

  cursor-2_1_36 = mkCursorVersion {
    version = "2.1.36";
    hash = "sha256-aaprRB2BAaUCHj7m5aGacCBHisjN2pVZ+Ca3u1ifxBA=";
    srcUrl = "https://downloads.cursor.com/production/9cd7c8b6cebcbccc1242df211dee45a4b6fe15e4/linux/x64/Cursor-2.1.36-x86_64.AppImage";
    binaryName = "cursor-2.1.36";
    dataStrategy = "isolated";
  };
}
