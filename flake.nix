{
  description = "Cursor IDE with MCP Servers for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # MCP servers (memory, playwright, etc.)
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, mcp-servers-nix }: 
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      # Package outputs
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;  # Cursor is proprietary
          };
        in 
        let
          # Multi-version cursor system
          cursorVersions = pkgs.callPackage ./cursor-versions.nix {};
        in
        {
          default = self.packages.${system}.cursor;
          
          # Main cursor package (2.0.77 - targeted stable)
          inherit (cursorVersions) cursor;
          
          # Version-specific packages for running multiple instances (37 total)
          # Custom Modes Era - 2.0.x (17 versions)
          inherit (cursorVersions) 
            cursor-2_0_77 cursor-2_0_75 cursor-2_0_74 cursor-2_0_73 
            cursor-2_0_69 cursor-2_0_64 cursor-2_0_63 cursor-2_0_60
            cursor-2_0_57 cursor-2_0_54 cursor-2_0_52 cursor-2_0_43
            cursor-2_0_40 cursor-2_0_38 cursor-2_0_34 cursor-2_0_32 cursor-2_0_11;
          
          # Classic Era - 1.7.x (19 versions)
          inherit (cursorVersions) 
            cursor-1_7_54 cursor-1_7_53 cursor-1_7_52 cursor-1_7_46
            cursor-1_7_44 cursor-1_7_43 cursor-1_7_40 cursor-1_7_39 cursor-1_7_38
            cursor-1_7_36 cursor-1_7_33 cursor-1_7_28 cursor-1_7_25 cursor-1_7_23
            cursor-1_7_22 cursor-1_7_17 cursor-1_7_16 cursor-1_7_12 cursor-1_7_11;
          
          # Legacy Era - 1.6.x (1 version)
          inherit (cursorVersions) cursor-1_6_45;
          
          # Isolated test instance (separate profile for testing)
          cursor-test = (pkgs.callPackage ./cursor {
            commandLineArgs = [ "--user-data-dir=/tmp/cursor-test-profile --extensions-dir=/tmp/cursor-test-extensions" ];
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
          
          # Cursor Version Manager (GUI Launcher)
          cursor-manager = pkgs.callPackage ./cursor/manager.nix {};
        }
      );

      # Home Manager module
      homeManagerModules = {
        default = import ./home-manager-module;
        cursor-with-mcp = import ./home-manager-module;
      };

      # Overlays
      overlays.default = final: prev: {
        cursor = final.callPackage ./cursor {};
        
        # MCP server packages from mcp-servers-nix
        mcp-server-memory = mcp-servers-nix.packages.${final.system}.mcp-server-memory or null;
        playwright-mcp = mcp-servers-nix.packages.${final.system}.playwright-mcp or null;
      };
    };
}
