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
#
# Automatically updated by update.sh script
# To update: cd cursor && ./update.sh

{ lib
, stdenv
, fetchurl
, appimageTools
, makeWrapper
, wrapGAppsHook3
, autoPatchelfHook
, glib
, nss
, nspr
, atk
, at-spi2-atk
, cups
, dbus
, libdrm
, gtk3
, pango
, cairo
, xorg
, mesa
, libglvnd
, expat
, libxkbcommon
, alsa-lib
, udev
, commandLineArgs ? ""  # Command-line arguments (--update=false is added automatically)
}:

let
  inherit (stdenv) hostPlatform;
  
  # Disable Cursor's built-in updater (NixOS incompatible - /nix/store is read-only)
  finalCommandLineArgs = "--update=false " + commandLineArgs;
  
  # Official Cursor releases - Updated automatically by update.sh
  # To manually update: run ./update.sh
  sources = {
    x86_64-linux = fetchurl {
      url = "https://downloads.cursor.com/production/a8d8905b06c8da1739af6f789efd59c28ac2a680/linux/x64/Cursor-2.1.20-x86_64.AppImage";
      hash = "sha256-V/5KDAJlXPLMQelnUgnfv2v3skxkb1V/n3Qn0qtwHaA=";
    };
    aarch64-linux = fetchurl {
      url = "https://downloads.cursor.com/production/a8d8905b06c8da1739af6f789efd59c28ac2a680/linux/arm64/Cursor-2.1.20-aarch64.AppImage";
      hash = "sha256-0ZRFG69/n7nulZLPerX6aAbPuObFv93pUQqnnMILhoo=";
    };
  };

  # Select source for current platform
  appImageSrc = sources.${hostPlatform.system} or (
    throw "Cursor is not available for ${hostPlatform.system}. Supported: ${lib.concatStringsSep ", " (lib.attrNames sources)}"
  );

  # Extract AppImage contents
  cursor-extracted = appimageTools.extractType2 {
    pname = "cursor";
    version = "2.1.20";  # Updated automatically by update.sh
    src = appImageSrc;
  };

in
stdenv.mkDerivation rec {
  pname = "cursor";
  version = "2.1.20";  # Updated automatically by update.sh

  src = cursor-extracted;

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsHook3
    autoPatchelfHook  # Critical: patches ELF binaries for NixOS
  ];

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
    xorg.libxkbfile      # For native-keymap module (fixes keyboard mapping errors)
    mesa
    libglvnd             # Provides libGL.so.1 for GPU acceleration
    expat
    libxkbcommon
    alsa-lib
    udev
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share
    
    # Copy extracted AppImage contents
    cp -r usr/share/cursor $out/share/
    
    # Copy icons and desktop files
    if [ -d usr/share/icons ]; then
      cp -r usr/share/icons $out/share/
    fi
    if [ -d usr/share/pixmaps ]; then
      cp -r usr/share/pixmaps $out/share/
    fi
    
    # Install helper scripts
    mkdir -p $out/libexec/cursor
    substitute ${./check-update.sh} $out/libexec/cursor/check-update \
      --subst-var-by version "${version}"
    chmod +x $out/libexec/cursor/check-update
    
    substitute ${./nix-update.sh} $out/libexec/cursor/nix-update \
      --subst-var-by version "${version}"
    chmod +x $out/libexec/cursor/nix-update
    
    # Create wrapper with proper environment and NixOS-specific fixes
    makeWrapper $out/share/cursor/cursor $out/bin/cursor \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        stdenv.cc.cc.lib
        libglvnd  # GPU acceleration
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
      ]}" \
      --set ELECTRON_OVERRIDE_DIST_PATH "$out/share/cursor" \
      --set VSCODE_BUILTIN_EXTENSIONS_DIR "$out/share/cursor/resources/app/extensions" \
      --set ELECTRON_NO_SANDBOX "1" \
      --set ELECTRON_DISABLE_SECURITY_WARNINGS "1" \
      --set CURSOR_CHECK_UPDATE "$out/libexec/cursor/check-update" \
      --set CURSOR_NIX_UPDATE "$out/libexec/cursor/nix-update" \
      --add-flags "${finalCommandLineArgs}" \
      --add-flags "--ozone-platform-hint=auto" \
      --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations,VaapiVideoDecoder,WebRTCPipeWireCapturer" \
      --add-flags "--disable-gpu-sandbox" \
      --add-flags "--enable-gpu-rasterization" \
      --add-flags "--enable-zero-copy" \
      --add-flags "--ignore-gpu-blocklist" \
      --add-flags "--enable-accelerated-2d-canvas" \
      --add-flags "--num-raster-threads=4" \
      --add-flags "--enable-oop-rasterization"
    
    # Create convenience update command
    cat > $out/bin/cursor-update << 'EOF'
#!/usr/bin/env bash
exec "$CURSOR_NIX_UPDATE" "$@"
EOF
    chmod +x $out/bin/cursor-update
    
    # Create update check command
    cat > $out/bin/cursor-check-update << 'EOF'
#!/usr/bin/env bash
exec "$CURSOR_CHECK_UPDATE" "$@"
EOF
    chmod +x $out/bin/cursor-check-update
    
    # Create desktop entry
    mkdir -p $out/share/applications
    cat > $out/share/applications/cursor.desktop <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cursor
GenericName=AI Code Editor
Comment=AI-first code editor based on VS Code
Exec=$out/bin/cursor %F
Icon=cursor
Terminal=false
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;
StartupNotify=true
StartupWMClass=Cursor
EOF

    runHook postInstall
  '';

  passthru = {
    unwrapped = cursor-extracted;
    updateScript = ./update.sh;
    inherit sources;
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
    license = licenses.unfree;  # Cursor is proprietary
    maintainers = with maintainers; [ ];  # Add your GitHub username when upstreaming
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
