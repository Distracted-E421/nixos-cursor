# Cursor IDE - macOS (Darwin) Package
# MIT License - Copyright (c) 2025 e421 (distracted.e421@gmail.com)
#
# Darwin-native Cursor package using DMG extraction.
# Provides feature parity with Linux package where possible.
#
# Supports:
#   - x86_64-darwin (Intel Macs)
#   - aarch64-darwin (Apple Silicon)
#   - Universal binaries (fat binaries for both architectures)
#
# Usage:
#   pkgs.callPackage ./cursor/darwin.nix { }
#   pkgs.callPackage ./cursor/darwin.nix { version = "2.0.77"; ... }

{
  lib,
  stdenv,
  fetchurl,
  undmg,
  makeWrapper,
  # Version info
  version ? "2.0.77",
  hash ? "sha256-PLACEHOLDER_NEEDS_HASH", # x64 hash
  hashArm64 ? "sha256-PLACEHOLDER_NEEDS_HASH", # arm64 hash
  hashUniversal ? "sha256-PLACEHOLDER_NEEDS_HASH", # Universal binary hash
  srcUrl ? null, # Override URL
  srcUrlArm64 ? null, # ARM64-specific URL
  srcUrlUniversal ? null, # Universal binary URL
  # Package customization
  binaryName ? "cursor",
  commandLineArgs ? [ ],
  shareDirName ? "cursor",
  postInstall ? "",
  # Build options
  preferUniversal ? true, # Use universal binary when available (recommended)
}:

let
  inherit (stdenv) hostPlatform;

  # Determine which binary to use
  useUniversal = preferUniversal && srcUrlUniversal != null;

  # Select appropriate source based on architecture
  selectedSrc =
    if useUniversal then
      fetchurl {
        url = srcUrlUniversal;
        hash = hashUniversal;
      }
    else if hostPlatform.isAarch64 then
      fetchurl {
        url = if srcUrlArm64 != null then srcUrlArm64 else srcUrl;
        hash = hashArm64;
      }
    else
      fetchurl {
        url = srcUrl;
        hash = hash;
      };

  # Handle commandLineArgs as list or string
  argsList =
    if lib.isList commandLineArgs then commandLineArgs else lib.splitString " " commandLineArgs;
  argsString = lib.concatMapStrings (arg: " \"${arg}\"") argsList;

in
stdenv.mkDerivation rec {
  pname = "cursor";
  inherit version;

  src = selectedSrc;

  nativeBuildInputs = [
    undmg
    makeWrapper
  ];

  # Don't unpack automatically - we handle it manually
  dontUnpack = true;

  installPhase = ''
        runHook preInstall

        # Extract DMG
        undmg "$src"

        # Create output directories
        mkdir -p $out/Applications
        mkdir -p $out/bin
        
        # Copy app bundle to Applications
        cp -r "Cursor.app" $out/Applications/
        
        # Create versioned symlink if this is a versioned package
        ${lib.optionalString (shareDirName != "cursor") ''
          ln -s $out/Applications/Cursor.app $out/Applications/Cursor-${version}.app
        ''}

        # Create wrapper script that launches the app
        # macOS apps are launched differently than Linux binaries
        makeWrapper "$out/Applications/Cursor.app/Contents/MacOS/Cursor" "$out/bin/.${binaryName}-wrapped" \
          --add-flags "--disable-gpu-sandbox"

        # Create the user-facing binary with args
        cat > $out/bin/${binaryName} << 'EOF'
    #!/bin/bash
    exec "$out/bin/.${binaryName}-wrapped"${argsString} "$@"
    EOF
        chmod +x $out/bin/${binaryName}
        substituteInPlace $out/bin/${binaryName} --replace '$out' "$out"

        # Create .desktop equivalent for macOS (for tools that use it)
        mkdir -p $out/share/applications
        cat > $out/share/applications/${shareDirName}.desktop << EOF
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Cursor ${version}
    GenericName=AI Code Editor
    Comment=AI-first code editor based on VS Code
    Exec=$out/bin/${binaryName} %F
    Icon=${shareDirName}
    Terminal=false
    Categories=Development;IDE;TextEditor;
    MimeType=text/plain;inode/directory;
    StartupNotify=true
    EOF

        # Copy icon if available
        if [ -f "$out/Applications/Cursor.app/Contents/Resources/Cursor.icns" ]; then
          mkdir -p $out/share/icons
          cp "$out/Applications/Cursor.app/Contents/Resources/Cursor.icns" $out/share/icons/${shareDirName}.icns
        fi

        # Custom postInstall hook
        ${postInstall}

        runHook postInstall
  '';

  passthru = {
    inherit version;
    platform =
      if useUniversal then
        "darwin-universal"
      else if hostPlatform.isAarch64 then
        "darwin-arm64"
      else
        "darwin-x64";
  };

  meta = with lib; {
    description = "AI-first code editor (macOS build)";
    longDescription = ''
      Cursor is an AI-first code editor based on VS Code with enhanced AI features.

      This is the macOS (Darwin) package, extracted from the official DMG.

      Features:
      - Native macOS app bundle
      - Universal binary support (Intel + Apple Silicon)
      - Multi-version installation support
      - Isolated user data per version (optional)

      Note: Cursor itself is proprietary software. This package wraps the official
      DMG with Nix-specific integration.
    '';
    homepage = "https://www.cursor.com/";
    license = licenses.unfree;
    maintainers = with maintainers; [ distracted-e421 ];
    platforms = [
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
