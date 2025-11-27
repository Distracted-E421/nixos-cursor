# Cursor IDE - Enhanced NixOS Package
# MIT License - Copyright (c) 2025 e421 (distracted.e421@gmail.com)
#
# Production-ready Cursor package with NixOS-specific fixes:
# - libxkbfile for native-keymap module
# - libGL for GPU acceleration
# - Wayland support
# - Proper FHS environment wrapping
#
# Usage:
#   pkgs.callPackage ./cursor/default.nix { }
#   pkgs.callPackage ./cursor/default.nix { version = "2.0.77"; hash = "sha256-..."; }
#
# Automatically updated by update.sh script
# To update: cd cursor && ./update.sh

{
  lib,
  stdenv,
  fetchurl,
  appimageTools,
  makeWrapper,
  wrapGAppsHook3,
  autoPatchelfHook,
  glib,
  nss,
  nspr,
  atk,
  at-spi2-atk,
  cups,
  dbus,
  libdrm,
  gtk3,
  pango,
  cairo,
  xorg,
  mesa,
  libglvnd,
  expat,
  libxkbcommon,
  alsa-lib,
  udev,
  version ? "2.0.77", # Cursor version to build
  hash ? "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=", # AppImage hash for x86_64
  hashAarch64 ? "sha256-PLACEHOLDER_NEEDS_VERIFICATION", # AppImage hash for aarch64
  srcUrl ? null, # x86_64 download URL (null = use downloader.cursor.sh)
  srcUrlAarch64 ? null, # aarch64 download URL (null = derive from srcUrl or use downloader.cursor.sh)
  localAppImage ? null, # Path to local AppImage file (for offline builds or DNS issues)
  commandLineArgs ? "", # Command-line arguments (string or list)
  shareDirName ? "cursor", # Directory name under /share/ (cursor or cursor-VERSION for multi-version)
  postInstall ? "", # Additional postInstall steps (for version-specific customization)
}:

let
  inherit (stdenv) hostPlatform;

  # Handle commandLineArgs as list or string
  argsList =
    if lib.isList commandLineArgs then commandLineArgs else lib.splitString " " commandLineArgs;

  # Helper to quote arguments for the shell script (double quotes allow variable expansion)
  # This ensures that if we pass "$HOME/..." it gets expanded at runtime
  argsString = lib.concatMapStrings (arg: " \"${arg}\"") argsList;

  # Derive aarch64 URL from x86_64 URL if not explicitly provided
  # Pattern: .../linux/x64/Cursor-VERSION-x86_64.AppImage -> .../linux/arm64/Cursor-VERSION-aarch64.AppImage
  deriveAarch64Url =
    x64Url:
    if x64Url == null then
      null
    else
      builtins.replaceStrings [ "/linux/x64/" "-x86_64.AppImage" ] [ "/linux/arm64/" "-aarch64.AppImage" ]
        x64Url;

  # Effective aarch64 URL (explicit or derived)
  effectiveSrcUrlAarch64 = if srcUrlAarch64 != null then srcUrlAarch64 else deriveAarch64Url srcUrl;

  # Select source: local file > specific URL > standard URL
  appImageSrc =
    if localAppImage != null then
      # Use local AppImage (for DNS issues or offline builds)
      localAppImage
    else if hostPlatform.system == "x86_64-linux" && srcUrl != null then
      # Use provided x86_64 URL
      fetchurl {
        url = srcUrl;
        inherit hash;
      }
    else if hostPlatform.system == "aarch64-linux" && effectiveSrcUrlAarch64 != null then
      # Use provided or derived aarch64 URL
      fetchurl {
        url = effectiveSrcUrlAarch64;
        hash = hashAarch64;
      }
    else
      # Fall back to standard downloader.cursor.sh URLs
      let
        sources = {
          x86_64-linux = fetchurl {
            url = "https://downloader.cursor.sh/linux/appImage/x64/${version}";
            inherit hash;
          };
          aarch64-linux = fetchurl {
            url = "https://downloader.cursor.sh/linux/appImage/arm64/${version}";
            hash = hashAarch64;
          };
        };
      in
      sources.${hostPlatform.system}
        or (throw "Cursor is not available for ${hostPlatform.system}. Supported: ${lib.concatStringsSep ", " (lib.attrNames sources)}");

  # Extract AppImage contents
  cursor-extracted = appimageTools.extractType2 {
    pname = "cursor";
    inherit version;
    src = appImageSrc;
  };

in
stdenv.mkDerivation rec {
  pname = "cursor";
  inherit version;

  src = cursor-extracted;

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsHook3
    autoPatchelfHook # Critical: patches ELF binaries for NixOS
  ];

  # Prevent wrapGAppsHook3 from wrapping our binaries - we handle wrapping manually
  # This is critical for multi-version support: wrapGAppsHook3 creates .X-wrapped files
  # with hardcoded names that conflict when installing multiple versions
  dontWrapGApps = true;

  # Runtime dependencies for autoPatchelfHook and execution
  buildInputs = [
    stdenv.cc.cc.lib
    glib
    nss
    nspr
    atk
    at-spi2-atk
    cups
    dbus
    libdrm
    gtk3
    pango
    cairo
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxkbfile # For native-keymap module (fixes keyboard mapping errors)
    mesa
    libglvnd # Provides libGL.so.1 for GPU acceleration
    expat
    libxkbcommon
    alsa-lib
    udev
  ];

  installPhase = ''
        runHook preInstall

        mkdir -p $out/bin $out/share
        
        # Copy extracted AppImage contents to version-specific directory
        # This allows multiple versions to coexist without path conflicts
        cp -r usr/share/cursor $out/share/${shareDirName}
        
        # Copy icons with version-specific names to avoid conflicts
        # When installing multiple versions, each needs unique icon filenames
        if [ -d usr/share/icons ]; then
          mkdir -p $out/share/icons
          cp -r usr/share/icons/hicolor $out/share/icons/
          
          # Only rename if shareDirName != "cursor" (versioned packages)
          if [ "${shareDirName}" != "cursor" ]; then
            # Rename cursor.png to ${shareDirName}.png in ALL icon sizes
            # Use find to catch all sizes (16x16, 22x22, 24x24, 32x32, 48x48, 64x64, 128x128, 256x256, 512x512, etc.)
            find "$out/share/icons/hicolor" -name "cursor.png" -type f | while read iconfile; do
              dir=$(dirname "$iconfile")
              mv "$iconfile" "$dir/${shareDirName}.png"
            done
            
            # Also rename any cursor.svg files if they exist
            find "$out/share/icons/hicolor" -name "cursor.svg" -type f | while read iconfile; do
              dir=$(dirname "$iconfile")
              mv "$iconfile" "$dir/${shareDirName}.svg"
            done
          fi
        fi
        
        # Copy pixmaps with version-specific names
        if [ -d usr/share/pixmaps ]; then
          mkdir -p $out/share/pixmaps
          if [ "${shareDirName}" = "cursor" ]; then
            # Main package: just copy as-is
            cp -r usr/share/pixmaps/* $out/share/pixmaps/
          else
            # Versioned package: rename files
            for f in usr/share/pixmaps/*; do
              if [ -f "$f" ]; then
                base=$(basename "$f")
                newname=$(echo "$base" | sed "s/cursor/${shareDirName}/g")
                cp "$f" "$out/share/pixmaps/$newname"
              fi
            done
          fi
        fi
        
        # Install helper scripts
        mkdir -p $out/libexec/${shareDirName}
        substitute ${./check-update.sh} $out/libexec/${shareDirName}/check-update \
          --subst-var-by version "${version}"
        chmod +x $out/libexec/${shareDirName}/check-update
        
        substitute ${./nix-update.sh} $out/libexec/${shareDirName}/nix-update \
          --subst-var-by version "${version}"
        chmod +x $out/libexec/${shareDirName}/nix-update
        
        # Create wrapper with proper environment and NixOS-specific fixes
        # We use dontWrapGApps=true and add GApps args manually to avoid wrapper name conflicts
        # This creates .cursor-wrapped which will be renamed by postInstall for versioned packages
        makeWrapper $out/share/${shareDirName}/cursor $out/bin/.cursor-wrapped \
          "''${gappsWrapperArgs[@]}" \
          --prefix LD_LIBRARY_PATH : "${
            lib.makeLibraryPath [
              stdenv.cc.cc.lib
              libglvnd
              glib
              nss
              nspr
              atk
              at-spi2-atk
              cups
              dbus
              libdrm
              gtk3
              pango
              cairo
              xorg.libX11
              xorg.libXcomposite
              xorg.libXdamage
              xorg.libXext
              xorg.libXfixes
              xorg.libXrandr
              mesa
              expat
              libxkbcommon
              alsa-lib
              udev
            ]
          }" \
          --set ELECTRON_OVERRIDE_DIST_PATH "$out/share/${shareDirName}" \
          --set VSCODE_BUILTIN_EXTENSIONS_DIR "$out/share/${shareDirName}/resources/app/extensions" \
          --set ELECTRON_NO_SANDBOX "1" \
          --set ELECTRON_DISABLE_SECURITY_WARNINGS "1" \
          --set CURSOR_CHECK_UPDATE "$out/libexec/${shareDirName}/check-update" \
          --set CURSOR_NIX_UPDATE "$out/libexec/${shareDirName}/nix-update" \
          --add-flags "--ozone-platform-hint=auto" \
          --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecoder,WebRTCPipeWireCapturer" \
          --add-flags "--disable-gpu-sandbox" \
          --add-flags "--enable-gpu-rasterization" \
          --add-flags "--enable-zero-copy" \
          --add-flags "--ignore-gpu-blocklist" \
          --add-flags "--enable-accelerated-2d-canvas" \
          --add-flags "--num-raster-threads=4" \
          --add-flags "--enable-oop-rasterization"
        
        # Create the final binary that handles dynamic arguments (like $HOME)
        # For versioned packages, postInstall will rename everything to version-specific names
        cat > $out/bin/cursor << 'CURSOR_SCRIPT_EOF'
    #!/bin/bash
    exec "$out/bin/.cursor-wrapped" --update=false ${argsString} "$@"
    CURSOR_SCRIPT_EOF
        chmod +x $out/bin/cursor
        
        # Fix the script to have actual paths (not Nix variables)
        substituteInPlace $out/bin/cursor \
          --replace '$out' "$out" \
          --replace '${argsString}' "${argsString}"
        
        # Create convenience update command
        cat > $out/bin/cursor-update << 'UPDATE_SCRIPT_EOF'
    #!/usr/bin/env bash
    exec "$CURSOR_NIX_UPDATE" "$@"
    UPDATE_SCRIPT_EOF
        chmod +x $out/bin/cursor-update
        
        # Create update check command  
        cat > $out/bin/cursor-check-update << 'CHECK_SCRIPT_EOF'
    #!/usr/bin/env bash
    exec "$CURSOR_CHECK_UPDATE" "$@"
    CHECK_SCRIPT_EOF
        chmod +x $out/bin/cursor-check-update
        
        # Create desktop entry with version-specific filename to avoid conflicts
        # shareDirName is "cursor" for main package, "cursor-VERSION" for versioned packages
        mkdir -p $out/share/applications
        cat > $out/share/applications/${shareDirName}.desktop << DESKTOP_ENTRY_EOF
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=Cursor ${version}
    GenericName=AI Code Editor
    Comment=AI-first code editor based on VS Code
    Exec=$out/bin/cursor %F
    Icon=${shareDirName}
    Terminal=false
    Categories=Development;IDE;TextEditor;
    MimeType=text/plain;inode/directory;
    StartupNotify=true
    StartupWMClass=Cursor
    DESKTOP_ENTRY_EOF

        # Custom postInstall hook (for version-specific modifications)
        ${postInstall}

        runHook postInstall
  '';

  passthru = {
    unwrapped = cursor-extracted;
    updateScript = ./update.sh;
    inherit version;
    usingLocalAppImage = localAppImage != null;
  };

  meta = with lib; {
    description = "AI-first code editor (NixOS-optimized build)";
    longDescription = ''
      Cursor is an AI-first code editor based on VS Code with enhanced AI features.

      This NixOS package includes:
      - libxkbfile fix for keyboard mapping
      - libGL support for GPU acceleration
      - Wayland window decorations
      - Proper library path configuration

      Note: Cursor itself is proprietary software. This package wraps the official
      AppImage with NixOS-specific fixes.
    '';
    homepage = "https://www.cursor.com/";
    license = licenses.unfree; # Cursor is proprietary...duh
    maintainers = with maintainers; [ distracted-e421 ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
