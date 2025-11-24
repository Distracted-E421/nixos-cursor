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
          
          # Main cursor package (2.0.64 - last with custom modes)
          inherit (cursorVersions) cursor;
          
          # Version-specific packages for running multiple instances
          inherit (cursorVersions) cursor-2_0_64 cursor-2_0_77 cursor-1_7_54;
          
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
