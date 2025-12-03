{
  description = "Cursor Studio (egui) - Version Manager + Chat Library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
    flake-utils,
  }:
  # System-agnostic outputs
    {
      # Home Manager module for declarative configuration
      homeManagerModules.default = import ./home-manager-module.nix;
      homeManagerModules.cursor-studio = import ./home-manager-module.nix;
    }
    //
    # Per-system outputs
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];
        pkgs = import nixpkgs {inherit system overlays;};

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = ["rust-src" "rust-analyzer"];
        };

        buildInputs = with pkgs; [
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

          # Fonts for Unicode support
          dejavu_fonts
          noto-fonts
          noto-fonts-color-emoji
          jetbrains-mono
        ];

        nativeBuildInputs = with pkgs; [
          pkg-config
          rustToolchain
          cmake
          # Fast linker - dramatically reduces link time
          mold
          clang
        ];

        libPath = pkgs.lib.makeLibraryPath buildInputs;
      in {
        # ============================================
        # Development Shell - Use this for fast iteration
        # ============================================
        devShells.default = pkgs.mkShell {
          inherit buildInputs nativeBuildInputs;

          LD_LIBRARY_PATH = libPath;

          # Note: sccache conflicts with incremental compilation
          # For dev builds, incremental is faster, so we don't use sccache here
          # sccache is better for CI/clean builds

          shellHook = ''
            echo "🎨 Cursor Studio (egui) Development Environment"
            echo "   Rust: $(rustc --version)"
            echo "   Linker: mold (fast)"
            echo ""
            echo "   🚀 FAST DEVELOPMENT:"
            echo "      cargo run              # Debug build (fastest compile)"
            echo "      cargo run --release    # Release build"
            echo ""
            echo "   📦 DISTRIBUTION:"
            echo "      nix build              # Full optimized build"
            echo ""
            echo "   ⚠️  Stay in this shell! Don't exit until cargo finishes."
          '';
        };

        # ============================================
        # Packages
        # ============================================

        # Lite package: Core GUI only (fast build ~2 min)
        packages.lite = pkgs.rustPlatform.buildRustPackage {
          pname = "cursor-studio";
          version = "0.2.0";
          src = ./.;

          cargoLock.lockFile = ./Cargo.lock;

          inherit buildInputs;
          nativeBuildInputs = nativeBuildInputs ++ [pkgs.mold];

          # Fast build: no sync features
          buildPhase = ''
            export CARGO_PROFILE_RELEASE_LTO=thin
            export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
            cargo build --release --frozen --no-default-features \
              --bin cursor-studio --bin cursor-studio-cli
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/cursor-studio $out/bin/
            cp target/release/cursor-studio-cli $out/bin/
          '';

          postFixup = ''
            patchelf --add-rpath "${libPath}" $out/bin/cursor-studio
            patchelf --add-rpath "${libPath}" $out/bin/cursor-studio-cli
          '';

          meta = with pkgs.lib; {
            description = "Cursor Studio - Lite (core GUI, fast build)";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "cursor-studio";
          };
        };

        # Full package: All sync features (slow build ~7 min)
        packages.full = pkgs.rustPlatform.buildRustPackage {
          pname = "cursor-studio-full";
          version = "0.2.0";
          src = ./.;

          cargoLock.lockFile = ./Cargo.lock;

          inherit buildInputs;
          nativeBuildInputs = nativeBuildInputs ++ [pkgs.mold];

          # Full build: all features including P2P and server sync
          buildPhase = ''
            export CARGO_PROFILE_RELEASE_LTO=thin
            export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
            cargo build --release --frozen --features full
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/cursor-studio $out/bin/
            cp target/release/cursor-studio-cli $out/bin/
            # Install sync binaries
            for bin in p2p-sync sync-server sync-cli; do
              if [ -f "target/release/$bin" ]; then
                cp "target/release/$bin" $out/bin/
              fi
            done
          '';

          postFixup = ''
            for bin in $out/bin/*; do
              patchelf --add-rpath "${libPath}" "$bin"
            done
          '';

          meta = with pkgs.lib; {
            description = "Cursor Studio - Full (with P2P + server sync)";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "cursor-studio";
          };
        };

        # Default: Lite for fast builds (use 'full' when testing sync)
        packages.default = self.packages.${system}.lite;

        # Aliases
        packages.cursor-studio = self.packages.${system}.lite;
        packages.cursor-studio-full = self.packages.${system}.full;

        # Make it runnable with `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/cursor-studio";
        };

        apps.cursor-studio = self.apps.${system}.default;

        # Full version with sync features
        apps.full = {
          type = "app";
          program = "${self.packages.${system}.full}/bin/cursor-studio";
        };

        apps.p2p-sync = {
          type = "app";
          program = "${self.packages.${system}.full}/bin/p2p-sync";
        };

        apps.sync-server = {
          type = "app";
          program = "${self.packages.${system}.full}/bin/sync-server";
        };
      }
    );
}
