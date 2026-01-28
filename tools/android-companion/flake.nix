{
  description = "Continuum Studio - Android Companion App Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, android-nixpkgs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        # Android SDK configuration
        androidSdk = android-nixpkgs.sdk.${system} (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          emulator
          # For x86_64 emulator images (optional)
          # system-images-android-34-google-apis-x86-64
        ]);

      in {
        devShells.default = pkgs.mkShell {
          name = "continuum-studio-android";

          buildInputs = with pkgs; [
            # ═══════════════════════════════════════════════════════════════
            # ANDROID SDK & BUILD TOOLS
            # ═══════════════════════════════════════════════════════════════
            androidSdk
            gradle
            kotlin
            
            # ═══════════════════════════════════════════════════════════════
            # JAVA (Required for Android/Gradle)
            # ═══════════════════════════════════════════════════════════════
            jdk17                      # Android requires JDK 17

            # ═══════════════════════════════════════════════════════════════
            # ANDROID DEVELOPMENT TOOLS
            # ═══════════════════════════════════════════════════════════════
            android-tools              # adb, fastboot
            scrcpy                     # Screen mirroring/control
            
            # ═══════════════════════════════════════════════════════════════
            # BUILD & DEVELOPMENT UTILITIES
            # ═══════════════════════════════════════════════════════════════
            jq                         # JSON processing
            ripgrep                    # Fast search
            fd                         # Fast file finder
            bat                        # Better cat
            
            # ═══════════════════════════════════════════════════════════════
            # FOR HARNESS SCRIPTS
            # ═══════════════════════════════════════════════════════════════
            bash
            coreutils
          ];

          ANDROID_HOME = "${androidSdk}/share/android-sdk";
          ANDROID_SDK_ROOT = "${androidSdk}/share/android-sdk";
          JAVA_HOME = "${pkgs.jdk17}";
          GRADLE_OPTS = "-Dorg.gradle.daemon=false";

          shellHook = ''
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║     🚀 CONTINUUM STUDIO - Android Development               ║"
            echo "║     Companion App for AI Workflow Integration               ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo ""
            echo "📱 Android SDK: $ANDROID_HOME"
            echo "☕ Java: $JAVA_HOME"
            echo ""
            echo "🛠️  Available Tools:"
            echo "  adb              - Android Debug Bridge"
            echo "  gradle           - Build system"
            echo "  kotlin           - Kotlin compiler"
            echo "  scrcpy           - Screen mirror & control"
            echo ""
            echo "📋 Quick Commands:"
            echo "  # List connected devices"
            echo "  adb devices"
            echo ""
            echo "  # Build debug APK"
            echo "  ./android-harness build"
            echo ""
            echo "  # Install to device"
            echo "  ./android-harness install"
            echo ""
            echo "  # View device screen"
            echo "  scrcpy"
            echo ""
            
            # Ensure gradle wrapper is executable if it exists
            if [ -f "./gradlew" ]; then
              chmod +x ./gradlew
            fi
          '';
        };

        # Package the harness script
        packages = {
          android-harness = pkgs.writeShellScriptBin "android-harness" ''
            ${builtins.readFile ./android-harness}
          '';
        };
      }
    );
}

