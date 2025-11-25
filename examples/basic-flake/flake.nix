{
  description = "Cursor on NixOS - Basic Example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixos-cursor - Multi-version Cursor IDE for NixOS
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-cursor,
    }:
    {
      homeConfigurations."myuser" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true; # Cursor is unfree
          overlays = [ nixos-cursor.overlays.default ];
        };

        modules = [
          nixos-cursor.homeManagerModules.default
          {
            home = {
              username = "myuser";
              homeDirectory = "/home/myuser";
              stateVersion = "24.05";
            };

            # Enable Cursor (minimal - no MCP servers)
            programs.cursor = {
              enable = true;
            };
          }
        ];
      };
    };
}
