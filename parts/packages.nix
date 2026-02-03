# Cursor IDE Packages
# All versioned Cursor packages for Linux and Darwin
{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, lib, ... }:
    let
      isLinux = lib.hasInfix "linux" system;
      isDarwin = lib.hasInfix "darwin" system;

      # Load platform-specific version module
      cursorVersions =
        if isLinux then
          pkgs.callPackage ../cursor-versions.nix { }
        else if isDarwin then
          pkgs.callPackage ../cursor-versions-darwin.nix { }
        else
          throw "Unsupported system: ${system}";

      # All version names (shared across platforms)
      allVersions = [
        # 2.4.x Latest Era
        "cursor-2_4_21" "cursor-2_4_20" "cursor-2_4_18" "cursor-2_4_14" "cursor-2_4_7"
        # 2.3.x Era
        "cursor-2_3_41" "cursor-2_3_40" "cursor-2_3_39" "cursor-2_3_35" "cursor-2_3_34"
        "cursor-2_3_33" "cursor-2_3_29" "cursor-2_3_26" "cursor-2_3_23" "cursor-2_3_21"
        "cursor-2_3_20" "cursor-2_3_15" "cursor-2_3_14" "cursor-2_3_10"
        # 2.2.x Era
        "cursor-2_2_27" "cursor-2_2_23" "cursor-2_2_20" "cursor-2_2_17" "cursor-2_2_14"
        "cursor-2_2_12" "cursor-2_2_9" "cursor-2_2_8" "cursor-2_2_7" "cursor-2_2_6" "cursor-2_2_3"
        # 2.1.x Post-Custom-Modes Era
        "cursor-2_1_50" "cursor-2_1_49" "cursor-2_1_48" "cursor-2_1_47" "cursor-2_1_46"
        "cursor-2_1_44" "cursor-2_1_42" "cursor-2_1_41" "cursor-2_1_39" "cursor-2_1_36"
        "cursor-2_1_34" "cursor-2_1_32" "cursor-2_1_26" "cursor-2_1_25" "cursor-2_1_24"
        "cursor-2_1_20" "cursor-2_1_19" "cursor-2_1_17" "cursor-2_1_15" "cursor-2_1_7" "cursor-2_1_6"
        # 2.0.x Custom Modes Era - LAST WITH CUSTOM MODES
        "cursor-2_0_77" "cursor-2_0_75" "cursor-2_0_74" "cursor-2_0_73" "cursor-2_0_69"
        "cursor-2_0_64" "cursor-2_0_63" "cursor-2_0_60" "cursor-2_0_57" "cursor-2_0_54"
        "cursor-2_0_52" "cursor-2_0_43" "cursor-2_0_40" "cursor-2_0_38" "cursor-2_0_34"
        "cursor-2_0_32" "cursor-2_0_11"
        # 1.7.x Classic Era
        "cursor-1_7_54" "cursor-1_7_53" "cursor-1_7_52" "cursor-1_7_46" "cursor-1_7_44"
        "cursor-1_7_43" "cursor-1_7_40" "cursor-1_7_39" "cursor-1_7_38" "cursor-1_7_36"
        "cursor-1_7_33" "cursor-1_7_28" "cursor-1_7_25" "cursor-1_7_23" "cursor-1_7_22"
        "cursor-1_7_17" "cursor-1_7_16" "cursor-1_7_12" "cursor-1_7_11"
      ];

      # Generate version packages dynamically
      versionPackages = lib.listToAttrs (
        map (name: lib.nameValuePair name (cursorVersions.${name} or null))
          (builtins.filter (name: cursorVersions ? ${name}) allVersions)
      );
    in
    {
      packages = {
        # Default package
        default = config.packages.cursor;

        # Main cursor package (2.0.77 - targeted stable)
        inherit (cursorVersions) cursor;
      }
      # Add all version packages
      // versionPackages
      # Linux-specific extras
      // lib.optionalAttrs isLinux {
        # Isolated test instance
        cursor-test =
          (pkgs.callPackage ../cursor {
            version = "2.0.77";
            hash = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=";
            srcUrl = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage";
            commandLineArgs = [
              "--user-data-dir" "/tmp/cursor-test-profile"
              "--extensions-dir" "/tmp/cursor-test-extensions"
            ];
          }).overrideAttrs (old: {
            pname = "cursor-test";
            postInstall = (old.postInstall or "") + ''
              mv $out/bin/cursor $out/bin/cursor-test
              if [ -f "$out/bin/cursor-update" ]; then
                mv $out/bin/cursor-update $out/bin/cursor-test-update
              fi
              if [ -f "$out/bin/cursor-check-update" ]; then
                mv $out/bin/cursor-check-update $out/bin/cursor-test-check-update
              fi
              substituteInPlace $out/share/applications/cursor.desktop \
                --replace-fail "Exec=$out/bin/cursor" "Exec=$out/bin/cursor-test" \
                --replace-fail "Name=Cursor" "Name=Cursor (Test)"
            '';
          });

        # Cursor Studio - Modern Rust/egui IDE Manager
        cursor-studio = pkgs.callPackage ../cursor-studio-egui/package.nix { };

        # CLI wrappers
        cursor-studio-cli = pkgs.writeShellScriptBin "cursor-studio-cli" ''
          exec ${config.packages.cursor-studio}/bin/cursor-studio-cli "$@"
        '';

        cs = pkgs.writeShellScriptBin "cs" ''
          exec ${config.packages.cursor-studio}/bin/cursor-studio-cli "$@"
        '';

        # Backward compatibility
        cursor-versions = pkgs.writeShellScriptBin "cursor-versions" ''
          echo "⚠️  cursor-versions is deprecated. Use 'cs' instead."
          exec ${config.packages.cursor-studio}/bin/cursor-studio-cli "$@"
        '';

        # Isolation tools
        cursor-isolation-tools = pkgs.stdenv.mkDerivation {
          pname = "cursor-isolation-tools";
          version = "0.1.0";
          src = ../archive/cursor-isolation;

          installPhase = ''
            mkdir -p $out/bin $out/share/doc/cursor-isolation-tools
            for script in cursor-backup cursor-sandbox cursor-share-data cursor-test sync-versions; do
              if [ -f "$src/$script" ]; then
                cp "$src/$script" "$out/bin/"
                chmod +x "$out/bin/$script"
              fi
            done
            cp "$src/README.md" "$out/share/doc/cursor-isolation-tools/" 2>/dev/null || true
          '';

          meta = with lib; {
            description = "Lightweight bash tools for Cursor IDE isolation and testing";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };

        # Proxy launcher
        cursor-proxy-launcher = pkgs.stdenv.mkDerivation {
          pname = "cursor-proxy-launcher";
          version = "0.1.0";
          src = ../tools/proxy-test;

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ pkgs.openssl pkgs.dig pkgs.iptables ];

          installPhase = ''
            mkdir -p $out/bin
            cp cursor-proxy-launcher $out/bin/
            chmod +x $out/bin/cursor-proxy-launcher
            wrapProgram $out/bin/cursor-proxy-launcher \
              --prefix PATH : ${lib.makeBinPath [ pkgs.openssl pkgs.dig pkgs.coreutils pkgs.gnugrep pkgs.gnused ]}
          '';

          meta = with lib; {
            description = "Painless launcher for Cursor AI traffic interception";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };

        # Legacy managers (deprecated)
        cursor-manager = pkgs.callPackage ../cursor/manager.nix { };
        cursor-chat-library = pkgs.callPackage ../cursor/chat-library.nix { };
        cursor-proxy = pkgs.callPackage ../tools/proxy-test/cursor-proxy { };

        # Dialog daemon
        cursor-dialog-daemon = pkgs.callPackage ../tools/cursor-dialog-daemon { };
        cursor-dialog-cli = pkgs.writeShellScriptBin "cursor-dialog-cli" ''
          exec ${config.packages.cursor-dialog-daemon}/bin/cursor-dialog-cli "$@"
        '';
      }
      # Darwin-specific extras
      // lib.optionalAttrs isDarwin {
        cursor-test = pkgs.callPackage ../cursor/darwin.nix {
          version = "2.0.77";
          srcUrl = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/x64/Cursor-darwin-x64.dmg";
          srcUrlArm64 = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/arm64/Cursor-darwin-arm64.dmg";
          srcUrlUniversal = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/universal/Cursor-darwin-universal.dmg";
          binaryName = "cursor-test";
          shareDirName = "cursor-test";
          commandLineArgs = [
            "--user-data-dir" "\\$HOME/.cursor-test"
            "--extensions-dir" "\\$HOME/.cursor-test/extensions"
          ];
        };
      };
    };
}
