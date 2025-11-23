{
  description = "Cursor on NixOS - Basic Example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Local path for testing (update to github URL when published)
    # TODO: Change to "github:yourusername/cursor-nixos" after release
    cursor-nixos.url = "path:../../";
  };

  outputs = { self, nixpkgs, home-manager, cursor-nixos }: {
    homeConfigurations."myuser" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;  # Cursor is unfree
        overlays = [ cursor-nixos.overlays.default ];
      };
      
      modules = [
        cursor-nixos.homeManagerModules.default
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
