# cursor-studio - Modern Cursor IDE Manager
#
# A Rust/egui application for managing Cursor IDE versions and viewing chat history.
# Replaces the deprecated Python/tkinter cursor-manager and cursor-chat-library.
#
# Usage:
#   pkgs.callPackage ./cursor-studio-egui/package.nix { }
#
{
  lib,
  stdenv,
  rustPlatform,
  pkg-config,
  mold,
  clang,
  cmake,
  wayland,
  wayland-protocols,
  libxkbcommon,
  xorg,
  libGL,
  mesa,
  openssl,
  sqlite,
  fontconfig,
  freetype,
  dejavu_fonts,
  noto-fonts,
  jetbrains-mono,
  makeWrapper,
}: let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
  rustPlatform.buildRustPackage {
    pname = "cursor-studio";
    version = cargoToml.package.version;

    src = lib.cleanSource ./.;

    cargoLock.lockFile = ./Cargo.lock;

    nativeBuildInputs = [
      pkg-config
      mold
      clang
      cmake
      makeWrapper
    ];

    buildInputs = [
      # Wayland
      wayland
      wayland-protocols
      libxkbcommon

      # X11 fallback
      xorg.libX11
      xorg.libXcursor
      xorg.libXrandr
      xorg.libXi

      # Graphics
      libGL
      mesa

      # System
      openssl
      sqlite
      fontconfig
      freetype
    ];

    # Build with release-fast profile (good balance of speed/optimization)
    # Default: Core GUI only (~2 min build)
    # To enable sync features: cargo build --release --features full (~7 min)
    buildPhase = ''
      runHook preBuild
      export CARGO_PROFILE_RELEASE_LTO=thin
      export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
      cargo build --release --frozen
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin

      # Install GUI
      cp target/release/cursor-studio $out/bin/

      # Install CLI
      cp target/release/cursor-studio-cli $out/bin/

      # Install sync binaries (if built with features)
      for bin in p2p-sync sync-server sync-cli; do
        if [ -f "target/release/$bin" ]; then
          cp "target/release/$bin" $out/bin/
        fi
      done

      runHook postInstall
    '';

    postFixup = let
      libPath = lib.makeLibraryPath [
        wayland
        wayland-protocols
        libxkbcommon
        xorg.libX11
        xorg.libXcursor
        xorg.libXrandr
        xorg.libXi
        libGL
        mesa
        fontconfig
        freetype
      ];
    in ''
      patchelf --add-rpath "${libPath}" $out/bin/cursor-studio
      patchelf --add-rpath "${libPath}" $out/bin/cursor-studio-cli

      # Patch sync binaries if they exist
      for bin in p2p-sync sync-server sync-cli; do
        if [ -f "$out/bin/$bin" ]; then
          patchelf --add-rpath "${libPath}" "$out/bin/$bin"
        fi
      done

      # Wrap to ensure fonts are available
      wrapProgram $out/bin/cursor-studio \
        --prefix XDG_DATA_DIRS : "${dejavu_fonts}/share:${noto-fonts}/share:${jetbrains-mono}/share"
    '';

    # Skip tests that require network or display
    doCheck = false;

    meta = with lib; {
      description = "Modern Cursor IDE manager with chat library (Rust/egui)";
      longDescription = ''
        Cursor Studio is a fast, native application for managing Cursor IDE:

        - Version Management: Switch between 48+ Cursor versions
        - Chat Library: View and search conversation history
        - Security Scanning: Detect API keys and secrets
        - Theme Support: Use VS Code themes
        - Export: Save conversations as Markdown

        Includes both GUI (cursor-studio) and CLI (cursor-studio-cli) interfaces.
      '';
      homepage = "https://github.com/Distracted-E421/nixos-cursor";
      license = licenses.mit;
      maintainers = with maintainers; [distracted-e421];
      platforms = platforms.linux;
      mainProgram = "cursor-studio";
    };

    passthru = {
      cli = stdenv.mkDerivation {
        pname = "cursor-studio-cli";
        inherit (cargoToml.package) version;
        src = ./.;

        # This is a dummy derivation - the CLI is built with the main package
        # and exposed separately for convenience
        installPhase = ''
          echo "Use cursor-studio package - CLI is included"
          exit 1
        '';

        meta = {
          description = "CLI interface for Cursor Studio";
          mainProgram = "cursor-studio-cli";
        };
      };
    };
  }
