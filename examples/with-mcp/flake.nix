{
  description = "Cursor on NixOS - Complete with MCP Servers (v0.2.0)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixos-cursor v0.2.0 - Multi-version Cursor IDE + Cursor Studio
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  };

  outputs = { self, nixpkgs, home-manager, nixos-cursor }: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ nixos-cursor.overlays.default ];
      };
    in {
    homeConfigurations."myuser" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit nixos-cursor; };
      
      modules = [
        nixos-cursor.homeManagerModules.default
        ({ config, pkgs, nixos-cursor, ... }: {
          home = {
            username = "myuser";
            homeDirectory = "/home/myuser";
            stateVersion = "24.05";
            
            sessionVariables = {
              CURSOR_FLAKE_URI = "github:Distracted-E421/nixos-cursor";
            };

            # Direct package installation (recommended approach)
            packages = [
              nixos-cursor.packages.${system}.cursor         # Latest stable
              nixos-cursor.packages.${system}.cursor-studio  # Dashboard + CLI
              nixos-cursor.packages.${system}.cursor-2_0_64  # Fallback
              pkgs.chromium                                   # For Playwright
            ];
          };

          # MCP Server Configuration via Home Manager Module
          programs.cursor = {
            enable = true;
            
            mcp = {
              enable = true;
              
              filesystemPaths = [
                "/home/myuser"
                "/home/myuser/projects"
              ];
              
              github = {
                enable = true;
                # tokenFile = "/run/agenix/github-token"; # See agenix example
              };
              
              playwright = {
                enable = true;
                browser = "chromium";
                browserPackage = pkgs.chromium;
                headless = false;
              };
            };
          };
        })
      ];
    };
  };
}
