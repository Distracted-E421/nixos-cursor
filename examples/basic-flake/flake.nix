{
  description = "Cursor on NixOS - Basic Example (v0.2.0)";

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
          ({ pkgs, nixos-cursor, ... }: {
            home = {
              username = "myuser";
              homeDirectory = "/home/myuser";
              stateVersion = "24.05";
              
              sessionVariables = {
                CURSOR_FLAKE_URI = "github:Distracted-E421/nixos-cursor";
              };

              # Direct package installation (recommended)
              packages = [
                nixos-cursor.packages.${system}.cursor        # Latest stable
                nixos-cursor.packages.${system}.cursor-studio # Dashboard + CLI
              ];
            };

            # Optional: Enable Cursor HM module for MCP config
            # programs.cursor.enable = true;
          })
        ];
      };
    };
}
