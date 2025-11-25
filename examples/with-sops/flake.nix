# Example: Cursor with sops-nix secrets
# 
# This example shows how to use sops-nix for secure GitHub MCP token management.
# sops-nix has native Home Manager support, making it ideal for user-level secrets.

{
  description = "Cursor with sops-nix secrets management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
    
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-cursor, sops-nix }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ nixos-cursor.overlays.default ];
    };
  in {
    # Home Manager configuration with sops-nix
    homeConfigurations."myuser" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      
      modules = [
        sops-nix.homeManagerModules.sops
        nixos-cursor.homeManagerModules.default
        
        ({ config, ... }: {
          home = {
            username = "myuser";
            homeDirectory = "/home/myuser";
            stateVersion = "24.05";
          };

          # sops-nix configuration
          sops = {
            # Path to your encrypted secrets file
            defaultSopsFile = ./secrets/mcp-tokens.yaml;
            
            # Your age key for decryption
            age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
            
            # Declare the secret
            secrets.github-mcp-token = {
              # Key in the YAML file
              key = "github_token";
              # Decrypted to: ~/.config/sops-nix/secrets/github-mcp-token
            };
          };

          programs.cursor = {
            enable = true;
            
            mcp = {
              enable = true;
              
              # GitHub with sops-nix managed token
              github = {
                enable = true;
                # Reference the sops secret path directly!
                tokenFile = config.sops.secrets.github-mcp-token.path;
              };
              
              # Other MCP servers
              memory.enable = true;
              nixos.enable = true;
            };
          };
        })
      ];
    };
  };
}
