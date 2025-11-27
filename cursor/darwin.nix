# Cursor IDE - macOS (Darwin) Package
# MIT License - Copyright (c) 2025 e421 (distracted.e421@gmail.com)
#
# EXPERIMENTAL: Darwin support for Cursor IDE
#
# This package extracts Cursor from the official DMG and wraps it for Nix.
# Works on both Intel (x86_64-darwin) and Apple Silicon (aarch64-darwin).
#
# Usage:
#   pkgs.callPackage ./cursor/darwin.nix { }
#   pkgs.callPackage ./cursor/darwin.nix { version = "2.1.34"; }

{
  lib,
  stdenv,
  fetchurl,
  undmg,
  makeWrapper,
  version ? "2.1.34",
  hash ? "sha256-PLACEHOLDER",
  hashArm64 ? "sha256-PLACEHOLDER",
  hashUniversal ? "sha256-PLACEHOLDER",
  srcUrl ? null,
  useUniversal ? true, # Use universal binary by default for simplicity
}:

let
  inherit (stdenv) hostPlatform;

  # Determine which architecture to use
  arch =
    if useUniversal then "universal"
    else if hostPlatform.isAarch64 then "arm64"
    else "x64";

  # Select appropriate hash
  selectedHash =
    if useUniversal then hashUniversal
    else if hostPlatform.isAarch64 then hashArm64
    else hash;

  # Build version-specific URL if not provided
  # Note: The commit hash in the URL varies by version
  # For now, we require srcUrl to be provided for each version
  dmgSrc = fetchurl {
    url = srcUrl;
    hash = selectedHash;
  };

in
stdenv.mkDerivation rec {
  pname = "cursor";
  inherit version;

  src = dmgSrc;

  # Unpack the DMG
  nativeBuildInputs = [
    undmg
    makeWrapper
  ];

  unpackPhase = ''
    undmg "$src"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -r "Cursor.app" $out/Applications/

    # Create bin symlinks
    mkdir -p $out/bin
    
    # The main Cursor binary is inside the app bundle
    makeWrapper "$out/Applications/Cursor.app/Contents/MacOS/Cursor" $out/bin/cursor \
      --add-flags "--disable-gpu-sandbox"

    runHook postInstall
  '';

  meta = with lib; {
    description = "AI-first code editor (macOS build)";
    longDescription = ''
      Cursor is an AI-first code editor based on VS Code with enhanced AI features.

      This is the macOS (Darwin) package, extracted from the official DMG.

      EXPERIMENTAL: This package is under development and may have issues.
      Please report problems at: https://github.com/Distracted-E421/nixos-cursor/issues
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
