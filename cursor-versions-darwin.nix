# Multi-Version Cursor System - Darwin (macOS)
# MIT License - Copyright (c) 2025 e421 (distracted.e421@gmail.com)
#
# Darwin equivalent of cursor-versions.nix
# Provides the same 48 versions for macOS users.
#
# NOTE: Hashes are PLACEHOLDER - must be computed on macOS using:
#   nix hash file Cursor-darwin-universal.dmg
#
# Total Versions: 48 (1.6.45 through 2.1.34)
#   - 2.1.x Latest Era: 11 versions
#   - 2.0.x Custom Modes Era: 17 versions
#   - 1.7.x Classic Era: 19 versions
#   - 1.6.x Legacy: 1 version

{
  lib,
  callPackage,
}:

let
  # User data directory strategies (same as Linux)
  makeUserDataArgs =
    {
      version,
      dataStrategy ? "isolated",
    }:
    if dataStrategy == "shared" then
      []
    else if dataStrategy == "isolated" then
      [
        "--user-data-dir"
        "\\$HOME/.cursor-${version}"
        "--extensions-dir"
        "\\$HOME/.cursor-${version}/extensions"
      ]
    else if dataStrategy == "sync" then
      [
        "--user-data-dir"
        "\\$HOME/.cursor-${version}"
        "--extensions-dir"
        "\\$HOME/Library/Application Support/Cursor/extensions"
      ]
    else
      throw "Invalid dataStrategy: ${dataStrategy}. Use: shared, isolated, or sync";

  # Extract commit hash from URL pattern
  # URL format: https://downloads.cursor.com/production/COMMIT_HASH/darwin/...
  getCommitHash = url:
    let
      parts = lib.splitString "/" url;
      # Commit hash is at index 4 (0-indexed)
    in
    builtins.elemAt parts 4;

  # Base Darwin cursor package builder
  mkCursorDarwinVersion =
    {
      version,
      commitHash,  # The unique commit identifier in the URL
      hashX64 ? "sha256-PLACEHOLDER_NEEDS_VERIFICATION",
      hashArm64 ? "sha256-PLACEHOLDER_NEEDS_VERIFICATION",
      hashUniversal ? "sha256-PLACEHOLDER_NEEDS_VERIFICATION",
      binaryName ? "cursor",
      dataStrategy ? "isolated",
    }:
    let
      userDataArgs = makeUserDataArgs { inherit version dataStrategy; };
      shareDirName = if binaryName == "cursor" then "cursor" else "cursor-${version}";
      
      # Build URLs from commit hash
      baseUrl = "https://downloads.cursor.com/production/${commitHash}/darwin";
      srcUrl = "${baseUrl}/x64/Cursor-darwin-x64.dmg";
      srcUrlArm64 = "${baseUrl}/arm64/Cursor-darwin-arm64.dmg";
      srcUrlUniversal = "${baseUrl}/universal/Cursor-darwin-universal.dmg";

      basePackage = callPackage ./cursor/darwin.nix {
        inherit
          version
          srcUrl
          srcUrlArm64
          srcUrlUniversal
          shareDirName
          ;
        hash = hashX64;
        hashArm64 = hashArm64;
        inherit hashUniversal;
        commandLineArgs = userDataArgs;
        preferUniversal = true;  # Prefer universal for compatibility
        postInstall = lib.optionalString (binaryName != "cursor") ''
          # Rename binary to version-specific name
          mv $out/bin/cursor $out/bin/${binaryName}
          if [ -f "$out/bin/.cursor-wrapped" ]; then
            mv $out/bin/.cursor-wrapped $out/bin/.${binaryName}-wrapped
          fi
          substituteInPlace $out/bin/${binaryName} \
            --replace ".cursor-wrapped" ".${binaryName}-wrapped"
          substituteInPlace $out/share/applications/${shareDirName}.desktop \
            --replace "Exec=$out/bin/cursor" "Exec=$out/bin/${binaryName}"
        '';
      };
    in
    basePackage;

  # ===== VERSION DATA =====
  # Commit hashes extracted from URL files
  
  commits = {
    # 2.1.x Latest Era
    "2.1.34" = "609c37304ae83141fd217c4ae638bf532185650f";
    "2.1.32" = "ef979b1b43d85eee2a274c25fd62d5502006e425";
    "2.1.26" = "f628a4761be40b8869ca61a6189cafd14756dff4";
    "2.1.25" = "7584ea888f7eb7bf76c9873a8f71b28f034a982e";
    "2.1.24" = "ac32b095dae9b8e0cfede6c5ebc55e589ee50e1b";
    "2.1.20" = "a8d8905b06c8da1739af6f789efd59c28ac2a680";
    "2.1.19" = "39a966b4048ef6b8024b27d4812a50d88de29cc3";
    "2.1.17" = "6757269838ae9ac4caaa2be13f396fdfbcf1f9a6";
    "2.1.15" = "a022145cbf8aea0babc3b039a98551c1518de024";
    "2.1.7" = "3d2e45538bcc4fd7ed28cc113c2110b26a824a00";
    "2.1.6" = "92340560ea81cb6168e2027596519d68af6c90a1";
    
    # 2.0.x Custom Modes Era
    "2.0.77" = "ba90f2f88e4911312761abab9492c42442117cfe";
    "2.0.75" = "9e7a27b76730ca7fe4aecaeafc58bac1e2c82121";
    "2.0.74" = "a965544b869cfb53b46806974091f97565545e48";
    "2.0.73" = "55b873ebecb5923d3b947d7e67e841d3ac781886";
    "2.0.69" = "63fcac100bd5d5749f2a98aa47d65f6eca61db39";
    "2.0.64" = "25412918da7e74b2686b25d62da1f01cfcd27683";
    "2.0.63" = "505046dcfad2acda3d066e32b7cd8b6e2dc1fdcd";
    "2.0.60" = "c6d93c13f57509f77eb65783b28e75a857b74c03";
    "2.0.57" = "eb037ef2bfba33ac568b0da614cb1c7b738455d6";
    "2.0.54" = "7a31bffd467aa2d9adfda69076eb924e9062cb27";
    "2.0.52" = "2125c48207a2a9aa55bce3d0af552912c84175d9";
    "2.0.43" = "8e4da76ad196925accaa169efcae28c45454cce3";
    "2.0.40" = "a9b73428ca6aeb2d24623da2841a271543735562";
    "2.0.38" = "3fa438a81d579067162dd8767025b788454e6f93";
    "2.0.34" = "45fd70f3fe72037444ba35c9e51ce86a1977ac11";
    "2.0.32" = "9a5dd36e54f13fb9c0e74490ec44d080dbc5df53";
    "2.0.11" = "4aa02949dc5065af49f2f6f72e3278386a3f7116";
    
    # 1.7.x Classic Era
    "1.7.54" = "5c17eb2968a37f66bc6662f48d6356a100b67be8";
    "1.7.53" = "2360b5184996146896b23297d625844656d67433";  # Different from Linux!
    "1.7.52" = "9675251a06b1314d50ff34b0cbe5109b78f848cd";
    "1.7.46" = "b9e5948c1ad20443a5cecba6b84a3c9b99d62582";
    "1.7.44" = "9d178a4a5589981b62546448bb32920a8219a5de";
    "1.7.43" = "df279210b53cf4686036054b15400aa2fe06d6dd";
    "1.7.40" = "df79b2380cd32922cad03529b0dc0c946c311856";
    "1.7.39" = "a9c77ceae65b77ff772d6adfe05f24d8ebcb2794";
    "1.7.38" = "fe5d1728063e86edeeda5bebd2c8e14bf4d0f96a";
    "1.7.36" = "493c403e4a45c5f971d1c76cc74febd0968d57d8";
    "1.7.33" = "7e354b5347e1541c01374049086622a27a745985";  # Different from Linux!
    "1.7.28" = "adb0f9e3e4f184bba7f3fa6dbfd72ad0ebb8cfd8";
    "1.7.25" = "429604585b94ab2b96a4dabff4660f41d5b7fb8f";
    "1.7.23" = "5069385c5a69db511722405ab5aeadc01579afd8";
    "1.7.22" = "31b1fbfcec1bf758f7140645f005fc78b5df355b";
    "1.7.17" = "34881053400013f38e2354f1479c88c9067039a2";
    "1.7.16" = "39476a6453a2a2903ed6446529255038f81c929f";
    "1.7.12" = "b3f1951240d5016648330fab51192dc03e8d705a";
    "1.7.11" = "867f14c797c14c23a187097ea179bc97d215a7c4";
    
    # 1.6.x Legacy
    "1.6.45" = "3ccce8f55d8cca49f6d28b491a844c699b8719a3";
  };

in
{
  # ===== Main Package (2.0.77 - Targeted Stable with Custom Modes) =====
  cursor = mkCursorDarwinVersion {
    version = "2.0.77";
    commitHash = commits."2.0.77";
    binaryName = "cursor";
    dataStrategy = "shared";
  };

  # ===== 2.1.x Latest Era (11 versions) =====

  cursor-2_1_34 = mkCursorDarwinVersion {
    version = "2.1.34";
    commitHash = commits."2.1.34";
    binaryName = "cursor-2.1.34";
  };

  cursor-2_1_32 = mkCursorDarwinVersion {
    version = "2.1.32";
    commitHash = commits."2.1.32";
    binaryName = "cursor-2.1.32";
  };

  cursor-2_1_26 = mkCursorDarwinVersion {
    version = "2.1.26";
    commitHash = commits."2.1.26";
    binaryName = "cursor-2.1.26";
  };

  cursor-2_1_25 = mkCursorDarwinVersion {
    version = "2.1.25";
    commitHash = commits."2.1.25";
    binaryName = "cursor-2.1.25";
  };

  cursor-2_1_24 = mkCursorDarwinVersion {
    version = "2.1.24";
    commitHash = commits."2.1.24";
    binaryName = "cursor-2.1.24";
  };

  cursor-2_1_20 = mkCursorDarwinVersion {
    version = "2.1.20";
    commitHash = commits."2.1.20";
    binaryName = "cursor-2.1.20";
  };

  cursor-2_1_19 = mkCursorDarwinVersion {
    version = "2.1.19";
    commitHash = commits."2.1.19";
    binaryName = "cursor-2.1.19";
  };

  cursor-2_1_17 = mkCursorDarwinVersion {
    version = "2.1.17";
    commitHash = commits."2.1.17";
    binaryName = "cursor-2.1.17";
  };

  cursor-2_1_15 = mkCursorDarwinVersion {
    version = "2.1.15";
    commitHash = commits."2.1.15";
    binaryName = "cursor-2.1.15";
  };

  cursor-2_1_7 = mkCursorDarwinVersion {
    version = "2.1.7";
    commitHash = commits."2.1.7";
    binaryName = "cursor-2.1.7";
  };

  cursor-2_1_6 = mkCursorDarwinVersion {
    version = "2.1.6";
    commitHash = commits."2.1.6";
    binaryName = "cursor-2.1.6";
  };

  # ===== 2.0.x Custom Modes Era (17 versions) =====

  cursor-2_0_77 = mkCursorDarwinVersion {
    version = "2.0.77";
    commitHash = commits."2.0.77";
    binaryName = "cursor-2.0.77";
  };

  cursor-2_0_75 = mkCursorDarwinVersion {
    version = "2.0.75";
    commitHash = commits."2.0.75";
    binaryName = "cursor-2.0.75";
  };

  cursor-2_0_74 = mkCursorDarwinVersion {
    version = "2.0.74";
    commitHash = commits."2.0.74";
    binaryName = "cursor-2.0.74";
  };

  cursor-2_0_73 = mkCursorDarwinVersion {
    version = "2.0.73";
    commitHash = commits."2.0.73";
    binaryName = "cursor-2.0.73";
  };

  cursor-2_0_69 = mkCursorDarwinVersion {
    version = "2.0.69";
    commitHash = commits."2.0.69";
    binaryName = "cursor-2.0.69";
  };

  cursor-2_0_64 = mkCursorDarwinVersion {
    version = "2.0.64";
    commitHash = commits."2.0.64";
    binaryName = "cursor-2.0.64";
  };

  cursor-2_0_63 = mkCursorDarwinVersion {
    version = "2.0.63";
    commitHash = commits."2.0.63";
    binaryName = "cursor-2.0.63";
  };

  cursor-2_0_60 = mkCursorDarwinVersion {
    version = "2.0.60";
    commitHash = commits."2.0.60";
    binaryName = "cursor-2.0.60";
  };

  cursor-2_0_57 = mkCursorDarwinVersion {
    version = "2.0.57";
    commitHash = commits."2.0.57";
    binaryName = "cursor-2.0.57";
  };

  cursor-2_0_54 = mkCursorDarwinVersion {
    version = "2.0.54";
    commitHash = commits."2.0.54";
    binaryName = "cursor-2.0.54";
  };

  cursor-2_0_52 = mkCursorDarwinVersion {
    version = "2.0.52";
    commitHash = commits."2.0.52";
    binaryName = "cursor-2.0.52";
  };

  cursor-2_0_43 = mkCursorDarwinVersion {
    version = "2.0.43";
    commitHash = commits."2.0.43";
    binaryName = "cursor-2.0.43";
  };

  cursor-2_0_40 = mkCursorDarwinVersion {
    version = "2.0.40";
    commitHash = commits."2.0.40";
    binaryName = "cursor-2.0.40";
  };

  cursor-2_0_38 = mkCursorDarwinVersion {
    version = "2.0.38";
    commitHash = commits."2.0.38";
    binaryName = "cursor-2.0.38";
  };

  cursor-2_0_34 = mkCursorDarwinVersion {
    version = "2.0.34";
    commitHash = commits."2.0.34";
    binaryName = "cursor-2.0.34";
  };

  cursor-2_0_32 = mkCursorDarwinVersion {
    version = "2.0.32";
    commitHash = commits."2.0.32";
    binaryName = "cursor-2.0.32";
  };

  cursor-2_0_11 = mkCursorDarwinVersion {
    version = "2.0.11";
    commitHash = commits."2.0.11";
    binaryName = "cursor-2.0.11";
  };

  # ===== 1.7.x Classic Era (19 versions) =====

  cursor-1_7_54 = mkCursorDarwinVersion {
    version = "1.7.54";
    commitHash = commits."1.7.54";
    binaryName = "cursor-1.7.54";
  };

  cursor-1_7_53 = mkCursorDarwinVersion {
    version = "1.7.53";
    commitHash = commits."1.7.53";
    binaryName = "cursor-1.7.53";
  };

  cursor-1_7_52 = mkCursorDarwinVersion {
    version = "1.7.52";
    commitHash = commits."1.7.52";
    binaryName = "cursor-1.7.52";
  };

  cursor-1_7_46 = mkCursorDarwinVersion {
    version = "1.7.46";
    commitHash = commits."1.7.46";
    binaryName = "cursor-1.7.46";
  };

  cursor-1_7_44 = mkCursorDarwinVersion {
    version = "1.7.44";
    commitHash = commits."1.7.44";
    binaryName = "cursor-1.7.44";
  };

  cursor-1_7_43 = mkCursorDarwinVersion {
    version = "1.7.43";
    commitHash = commits."1.7.43";
    binaryName = "cursor-1.7.43";
  };

  cursor-1_7_40 = mkCursorDarwinVersion {
    version = "1.7.40";
    commitHash = commits."1.7.40";
    binaryName = "cursor-1.7.40";
  };

  cursor-1_7_39 = mkCursorDarwinVersion {
    version = "1.7.39";
    commitHash = commits."1.7.39";
    binaryName = "cursor-1.7.39";
  };

  cursor-1_7_38 = mkCursorDarwinVersion {
    version = "1.7.38";
    commitHash = commits."1.7.38";
    binaryName = "cursor-1.7.38";
  };

  cursor-1_7_36 = mkCursorDarwinVersion {
    version = "1.7.36";
    commitHash = commits."1.7.36";
    binaryName = "cursor-1.7.36";
  };

  cursor-1_7_33 = mkCursorDarwinVersion {
    version = "1.7.33";
    commitHash = commits."1.7.33";
    binaryName = "cursor-1.7.33";
  };

  cursor-1_7_28 = mkCursorDarwinVersion {
    version = "1.7.28";
    commitHash = commits."1.7.28";
    binaryName = "cursor-1.7.28";
  };

  cursor-1_7_25 = mkCursorDarwinVersion {
    version = "1.7.25";
    commitHash = commits."1.7.25";
    binaryName = "cursor-1.7.25";
  };

  cursor-1_7_23 = mkCursorDarwinVersion {
    version = "1.7.23";
    commitHash = commits."1.7.23";
    binaryName = "cursor-1.7.23";
  };

  cursor-1_7_22 = mkCursorDarwinVersion {
    version = "1.7.22";
    commitHash = commits."1.7.22";
    binaryName = "cursor-1.7.22";
  };

  cursor-1_7_17 = mkCursorDarwinVersion {
    version = "1.7.17";
    commitHash = commits."1.7.17";
    binaryName = "cursor-1.7.17";
  };

  cursor-1_7_16 = mkCursorDarwinVersion {
    version = "1.7.16";
    commitHash = commits."1.7.16";
    binaryName = "cursor-1.7.16";
  };

  cursor-1_7_12 = mkCursorDarwinVersion {
    version = "1.7.12";
    commitHash = commits."1.7.12";
    binaryName = "cursor-1.7.12";
  };

  cursor-1_7_11 = mkCursorDarwinVersion {
    version = "1.7.11";
    commitHash = commits."1.7.11";
    binaryName = "cursor-1.7.11";
  };

  # ===== 1.6.x Legacy (1 version) =====

  cursor-1_6_45 = mkCursorDarwinVersion {
    version = "1.6.45";
    commitHash = commits."1.6.45";
    binaryName = "cursor-1.6.45";
  };
}
