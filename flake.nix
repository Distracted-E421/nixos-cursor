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
        in {
          default = self.packages.${system}.cursor;
          cursor = pkgs.callPackage ./cursor {};
          
          # Isolated test instance
          cursor-test = (pkgs.callPackage ./cursor {
            commandLineArgs = "--user-data-dir=/tmp/cursor-test-profile --extensions-dir=/tmp/cursor-test-extensions";
          }).overrideAttrs (old: {
            pname = "cursor-test";
            postInstall = old.postInstall + ''
              mv $out/bin/cursor $out/bin/cursor-test
              substituteInPlace $out/share/applications/cursor.desktop \
                --replace "Exec=$out/bin/cursor" "Exec=$out/bin/cursor-test" \
                --replace "Name=Cursor" "Name=Cursor (Test)"
            '';
          });
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
