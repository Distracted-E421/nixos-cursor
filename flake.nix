{
  description = "Cursor IDE with MCP Servers for NixOS and macOS";

  nixConfig = {
    extra-substituters = [
      "https://nixos-cursor.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-cursor.cachix.org-1:8YAZIsMXbzdSJh6YF71XIVR2OgnRXXZ+7e82dL5yCqI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # MCP servers (memory, playwright, etc.)
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      mcp-servers-nix,
    }:
    let
      # All supported systems
      # Linux: Full support with AppImage
      # Darwin: Full support with DMG (hashes need verification on macOS)
      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      darwinSystems = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      systems = linuxSystems ++ darwinSystems;
      forAllSystems = nixpkgs.lib.genAttrs systems;
      forLinuxSystems = nixpkgs.lib.genAttrs linuxSystems;
      forDarwinSystems = nixpkgs.lib.genAttrs darwinSystems;

      # Helper to create app entries from packages
      mkApp = pkg: mainProgram: {
        type = "app";
        program = "${pkg}/bin/${mainProgram}";
      };

      # All version names (shared across platforms)
      allVersions = [
        # 2.1.x Latest Era (11 versions)
        "cursor-2_1_34"
        "cursor-2_1_32"
        "cursor-2_1_26"
        "cursor-2_1_25"
        "cursor-2_1_24"
        "cursor-2_1_20"
        "cursor-2_1_19"
        "cursor-2_1_17"
        "cursor-2_1_15"
        "cursor-2_1_7"
        "cursor-2_1_6"
        # 2.0.x Custom Modes Era (17 versions)
        "cursor-2_0_77"
        "cursor-2_0_75"
        "cursor-2_0_74"
        "cursor-2_0_73"
        "cursor-2_0_69"
        "cursor-2_0_64"
        "cursor-2_0_63"
        "cursor-2_0_60"
        "cursor-2_0_57"
        "cursor-2_0_54"
        "cursor-2_0_52"
        "cursor-2_0_43"
        "cursor-2_0_40"
        "cursor-2_0_38"
        "cursor-2_0_34"
        "cursor-2_0_32"
        "cursor-2_0_11"
        # 1.7.x Classic Era (19 versions)
        "cursor-1_7_54"
        "cursor-1_7_53"
        "cursor-1_7_52"
        "cursor-1_7_46"
        "cursor-1_7_44"
        "cursor-1_7_43"
        "cursor-1_7_40"
        "cursor-1_7_39"
        "cursor-1_7_38"
        "cursor-1_7_36"
        "cursor-1_7_33"
        "cursor-1_7_28"
        "cursor-1_7_25"
        "cursor-1_7_23"
        "cursor-1_7_22"
        "cursor-1_7_17"
        "cursor-1_7_16"
        "cursor-1_7_12"
        "cursor-1_7_11"
        # 1.6.x Legacy (1 version)
        "cursor-1_6_45"
      ];

      # Convert package name to binary name (cursor-2_1_34 -> cursor-2.1.34)
      pkgToBinary =
        name: if name == "cursor" then "cursor" else builtins.replaceStrings [ "_" ] [ "." ] name;
    in
    {
      # Package outputs
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true; # Cursor is proprietary
          };

          lib = pkgs.lib;
          isLinux = lib.hasInfix "linux" system;
          isDarwin = lib.hasInfix "darwin" system;

          # Load platform-specific version module
          cursorVersions =
            if isLinux then
              pkgs.callPackage ./cursor-versions.nix { }
            else if isDarwin then
              pkgs.callPackage ./cursor-versions-darwin.nix { }
            else
              throw "Unsupported system: ${system}";
        in
        {
          default = self.packages.${system}.cursor;

          # Main cursor package (2.0.77 - targeted stable)
          inherit (cursorVersions) cursor;

          # Version-specific packages for running multiple instances (48 total)
          # Latest Era - 2.1.x (11 versions)
          inherit (cursorVersions)
            cursor-2_1_34
            cursor-2_1_32
            cursor-2_1_26
            cursor-2_1_25
            cursor-2_1_24
            cursor-2_1_20
            cursor-2_1_19
            cursor-2_1_17
            cursor-2_1_15
            cursor-2_1_7
            cursor-2_1_6
            ;

          # Custom Modes Era - 2.0.x (17 versions)
          inherit (cursorVersions)
            cursor-2_0_77
            cursor-2_0_75
            cursor-2_0_74
            cursor-2_0_73
            cursor-2_0_69
            cursor-2_0_64
            cursor-2_0_63
            cursor-2_0_60
            cursor-2_0_57
            cursor-2_0_54
            cursor-2_0_52
            cursor-2_0_43
            cursor-2_0_40
            cursor-2_0_38
            cursor-2_0_34
            cursor-2_0_32
            cursor-2_0_11
            ;

          # Classic Era - 1.7.x (19 versions)
          inherit (cursorVersions)
            cursor-1_7_54
            cursor-1_7_53
            cursor-1_7_52
            cursor-1_7_46
            cursor-1_7_44
            cursor-1_7_43
            cursor-1_7_40
            cursor-1_7_39
            cursor-1_7_38
            cursor-1_7_36
            cursor-1_7_33
            cursor-1_7_28
            cursor-1_7_25
            cursor-1_7_23
            cursor-1_7_22
            cursor-1_7_17
            cursor-1_7_16
            cursor-1_7_12
            cursor-1_7_11
            ;

          # Legacy Era - 1.6.x (1 version)
          inherit (cursorVersions) cursor-1_6_45;
        }
        # Linux-specific extras
        // lib.optionalAttrs isLinux {
          # Isolated test instance (separate profile for testing)
          cursor-test =
            (pkgs.callPackage ./cursor {
              commandLineArgs = [
                "--user-data-dir=/tmp/cursor-test-profile --extensions-dir=/tmp/cursor-test-extensions"
              ];
            }).overrideAttrs
              (old: {
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

          # Cursor Version Manager (Rust CLI - Linux only for now)
          cursor-manager = pkgs.callPackage ./cursor/manager.nix { };
          
          # Cursor Chat Library - chat history management with markdown preview
          cursor-chat-library = pkgs.callPackage ./cursor/chat-library.nix { };
        }
        # Darwin-specific extras
        // lib.optionalAttrs isDarwin {
          # Darwin test instance
          cursor-test = (
            pkgs.callPackage ./cursor/darwin.nix {
              version = "2.0.77";
              srcUrl = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/x64/Cursor-darwin-x64.dmg";
              srcUrlArm64 = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/arm64/Cursor-darwin-arm64.dmg";
              srcUrlUniversal = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/universal/Cursor-darwin-universal.dmg";
              binaryName = "cursor-test";
              shareDirName = "cursor-test";
              commandLineArgs = [
                "--user-data-dir"
                "\\$HOME/.cursor-test"
                "--extensions-dir"
                "\\$HOME/.cursor-test/extensions"
              ];
            }
          );
        }
      );

      # App outputs - enables clean `nix run github:...#cursor-1_7_54` syntax
      apps = forAllSystems (
        system:
        let
          pkgs = self.packages.${system};
          lib = nixpkgs.lib;
          isLinux = lib.hasInfix "linux" system;
        in
        {
          default = mkApp pkgs.cursor "cursor";

          # Main cursor
          cursor = mkApp pkgs.cursor "cursor";
          cursor-test = mkApp pkgs.cursor-test "cursor-test";

          # 2.1.x Latest Era (11 versions)
          cursor-2_1_34 = mkApp pkgs.cursor-2_1_34 "cursor-2.1.34";
          cursor-2_1_32 = mkApp pkgs.cursor-2_1_32 "cursor-2.1.32";
          cursor-2_1_26 = mkApp pkgs.cursor-2_1_26 "cursor-2.1.26";
          cursor-2_1_25 = mkApp pkgs.cursor-2_1_25 "cursor-2.1.25";
          cursor-2_1_24 = mkApp pkgs.cursor-2_1_24 "cursor-2.1.24";
          cursor-2_1_20 = mkApp pkgs.cursor-2_1_20 "cursor-2.1.20";
          cursor-2_1_19 = mkApp pkgs.cursor-2_1_19 "cursor-2.1.19";
          cursor-2_1_17 = mkApp pkgs.cursor-2_1_17 "cursor-2.1.17";
          cursor-2_1_15 = mkApp pkgs.cursor-2_1_15 "cursor-2.1.15";
          cursor-2_1_7 = mkApp pkgs.cursor-2_1_7 "cursor-2.1.7";
          cursor-2_1_6 = mkApp pkgs.cursor-2_1_6 "cursor-2.1.6";

          # 2.0.x Custom Modes Era (17 versions)
          cursor-2_0_77 = mkApp pkgs.cursor-2_0_77 "cursor-2.0.77";
          cursor-2_0_75 = mkApp pkgs.cursor-2_0_75 "cursor-2.0.75";
          cursor-2_0_74 = mkApp pkgs.cursor-2_0_74 "cursor-2.0.74";
          cursor-2_0_73 = mkApp pkgs.cursor-2_0_73 "cursor-2.0.73";
          cursor-2_0_69 = mkApp pkgs.cursor-2_0_69 "cursor-2.0.69";
          cursor-2_0_64 = mkApp pkgs.cursor-2_0_64 "cursor-2.0.64";
          cursor-2_0_63 = mkApp pkgs.cursor-2_0_63 "cursor-2.0.63";
          cursor-2_0_60 = mkApp pkgs.cursor-2_0_60 "cursor-2.0.60";
          cursor-2_0_57 = mkApp pkgs.cursor-2_0_57 "cursor-2.0.57";
          cursor-2_0_54 = mkApp pkgs.cursor-2_0_54 "cursor-2.0.54";
          cursor-2_0_52 = mkApp pkgs.cursor-2_0_52 "cursor-2.0.52";
          cursor-2_0_43 = mkApp pkgs.cursor-2_0_43 "cursor-2.0.43";
          cursor-2_0_40 = mkApp pkgs.cursor-2_0_40 "cursor-2.0.40";
          cursor-2_0_38 = mkApp pkgs.cursor-2_0_38 "cursor-2.0.38";
          cursor-2_0_34 = mkApp pkgs.cursor-2_0_34 "cursor-2.0.34";
          cursor-2_0_32 = mkApp pkgs.cursor-2_0_32 "cursor-2.0.32";
          cursor-2_0_11 = mkApp pkgs.cursor-2_0_11 "cursor-2.0.11";

          # 1.7.x Classic Era (19 versions)
          cursor-1_7_54 = mkApp pkgs.cursor-1_7_54 "cursor-1.7.54";
          cursor-1_7_53 = mkApp pkgs.cursor-1_7_53 "cursor-1.7.53";
          cursor-1_7_52 = mkApp pkgs.cursor-1_7_52 "cursor-1.7.52";
          cursor-1_7_46 = mkApp pkgs.cursor-1_7_46 "cursor-1.7.46";
          cursor-1_7_44 = mkApp pkgs.cursor-1_7_44 "cursor-1.7.44";
          cursor-1_7_43 = mkApp pkgs.cursor-1_7_43 "cursor-1.7.43";
          cursor-1_7_40 = mkApp pkgs.cursor-1_7_40 "cursor-1.7.40";
          cursor-1_7_39 = mkApp pkgs.cursor-1_7_39 "cursor-1.7.39";
          cursor-1_7_38 = mkApp pkgs.cursor-1_7_38 "cursor-1.7.38";
          cursor-1_7_36 = mkApp pkgs.cursor-1_7_36 "cursor-1.7.36";
          cursor-1_7_33 = mkApp pkgs.cursor-1_7_33 "cursor-1.7.33";
          cursor-1_7_28 = mkApp pkgs.cursor-1_7_28 "cursor-1.7.28";
          cursor-1_7_25 = mkApp pkgs.cursor-1_7_25 "cursor-1.7.25";
          cursor-1_7_23 = mkApp pkgs.cursor-1_7_23 "cursor-1.7.23";
          cursor-1_7_22 = mkApp pkgs.cursor-1_7_22 "cursor-1.7.22";
          cursor-1_7_17 = mkApp pkgs.cursor-1_7_17 "cursor-1.7.17";
          cursor-1_7_16 = mkApp pkgs.cursor-1_7_16 "cursor-1.7.16";
          cursor-1_7_12 = mkApp pkgs.cursor-1_7_12 "cursor-1.7.12";
          cursor-1_7_11 = mkApp pkgs.cursor-1_7_11 "cursor-1.7.11";

          # 1.6.x Legacy Era (1 version)
          cursor-1_6_45 = mkApp pkgs.cursor-1_6_45 "cursor-1.6.45";
        }
      );

      # Home Manager module
      homeManagerModules = {
        default = import ./home-manager-module;
        cursor-with-mcp = import ./home-manager-module;
      };

      # Development shells
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "nixos-cursor-dev";

            packages = with pkgs; [
              # Modern shell scripting
              nushell

              # Python with batteries
              (python3.withPackages (
                ps: with ps; [
                  httpx # Async HTTP client
                  rich # Beautiful terminal output
                  typer # CLI framework
                ]
              ))

              # Compiled languages (optional, for future use)
              # nim           # Python-like syntax, compiles to C
              # zig           # Systems programming
              # cargo rustc   # Rust toolchain

              # Development tools
              jq # JSON processing (fallback)
              statix # Nix linter
              nixpkgs-fmt # Nix formatter

              # Testing
              shellcheck # Bash linter (for legacy scripts)
            ];

            shellHook = ''
              echo "nixos-cursor development shell"
              echo ""
              echo "Available tools:"
              echo "  nu        - Nushell (modern shell scripts)"
              echo "  python    - Python 3 with httpx, rich, typer"
              echo "  statix    - Nix linter"
              echo ""
              echo "Scripts:"
              echo "  nu scripts/nu/disk-usage.nu --help"
              echo "  python scripts/python/compute_hashes.py --help"
            '';
          };

          # Full development shell with all compiled languages
          full = pkgs.mkShell {
            name = "nixos-cursor-full";

            packages = with pkgs; [
              # Shells
              nushell

              # Python
              (python3.withPackages (
                ps: with ps; [
                  httpx
                  rich
                  typer
                ]
              ))

              # Elixir/BEAM
              elixir
              erlang

              # Compiled languages
              nim
              zig
              cargo
              rustc

              # Development
              jq
              statix
              nixpkgs-fmt
              shellcheck
            ];
          };
        }
      );

      # Overlays
      overlays.default = final: prev: {
        cursor = final.callPackage ./cursor { };

        # MCP server packages from mcp-servers-nix
        mcp-server-memory = mcp-servers-nix.packages.${final.system}.mcp-server-memory or null;
        playwright-mcp = mcp-servers-nix.packages.${final.system}.playwright-mcp or null;

        # NPM security module for MCP servers
        npm-security = final.callPackage ./security { };
      };

      # Security module (standalone import)
      lib.npmSecurity = import ./security;
    };
}
