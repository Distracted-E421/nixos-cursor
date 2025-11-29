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
          noto-fonts-emoji
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

        # Default package: Full release build (slow but optimal)
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "cursor-studio";
          version = "0.2.0";
          src = ./.;

          cargoLock.lockFile = ./Cargo.lock;

          inherit buildInputs;
          nativeBuildInputs = nativeBuildInputs ++ [pkgs.mold];

          # Use release-fast profile for nix builds (good balance)
          buildPhase = ''
            export CARGO_PROFILE_RELEASE_LTO=thin
            export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16
            cargo build --release --frozen
          '';

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/cursor-studio $out/bin/
          '';

          postFixup = ''
            patchelf --add-rpath "${libPath}" $out/bin/cursor-studio
          '';

          meta = with pkgs.lib; {
            description = "Cursor version manager and chat library (egui)";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "cursor-studio";
          };
        };

        # Alias for easy access
        packages.cursor-studio = self.packages.${system}.default;

        # Make it runnable with `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/cursor-studio";
        };

        apps.cursor-studio = self.apps.${system}.default;
      }
    );
}
