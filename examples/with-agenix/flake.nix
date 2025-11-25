# Example: Cursor with agenix secrets
# 
# This example shows how to use agenix for secure GitHub MCP token management.
# The token is encrypted at rest and only decrypted at runtime.

{
  description = "Cursor with agenix secrets management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
    
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-cursor, agenix }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ nixos-cursor.overlays.default ];
    };
  in {
    # NixOS configuration (for system-level secret decryption)
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        agenix.nixosModules.default
        
        # Declare the secret - it will be decrypted to /run/agenix/github-mcp-token
        {
          age.secrets.github-mcp-token = {
            file = ./secrets/github-token.age;
            owner = "myuser";
            group = "users";
            mode = "0400";
          };
        }
      ];
    };

    # Home Manager configuration
    homeConfigurations."myuser" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      
      modules = [
        nixos-cursor.homeManagerModules.default
        
        {
          home = {
            username = "myuser";
            homeDirectory = "/home/myuser";
            stateVersion = "24.05";
          };

          programs.cursor = {
            enable = true;
            
            mcp = {
              enable = true;
              
              # GitHub with agenix-managed token
              github = {
                enable = true;
                tokenFile = "/run/agenix/github-mcp-token";
              };
              
              # Other MCP servers (no secrets needed)
              memory.enable = true;
              nixos.enable = true;
            };
          };
        }
      ];
    };
  };
}
