{
  description = "Cursor on NixOS - Complete with MCP Servers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Local path for testing (update to github URL when published)
    # TODO: Change to "github:yourusername/cursor-nixos" after release
    # NOTE: For development, keep as relative path to test local changes immediately
    cursor-nixos.url = "path:../../";
  };

  outputs = { self, nixpkgs, home-manager, cursor-nixos }: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ cursor-nixos.overlays.default ];
      };
    in {
    homeConfigurations."myuser" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      
      modules = [
        cursor-nixos.homeManagerModules.default
        {
          home = {
            username = "myuser";
            homeDirectory = "/home/myuser";
            stateVersion = "24.05";
          };

          # Cursor with ALL MCP servers enabled
          programs.cursor = {
            enable = true;
            
            mcp = {
              enable = true;  # Enables filesystem, memory, nixos by default
              
              # Filesystem paths AI can access
              filesystemPaths = [
                "/home/myuser"
                "/home/myuser/projects"
                # Add more paths as needed
              ];
              
              # GitHub operations (optional)
              github = {
                enable = true;
                # token = null;  # For public repos only
                # For private repos, set token (use agenix/sops-nix in production)
              };
              
              # Browser automation
              playwright = {
                enable = true;
                browser = "chromium";  # or "chrome" or "firefox"
                browserPackage = pkgs.chromium;
                headless = false;  # Set true for headless mode
                
                # Optional: Persistent profile
                # userDataDir = "/home/myuser/.local/share/playwright/profile";
                # saveSession = true;
                
                # Optional: Debugging
                # saveTrace = true;
                # saveVideo = true;
              };
            };
          };

          # Install browser for Playwright
          home.packages = with pkgs; [
            chromium  # or google-chrome
          ];
        }
      ];
    };
  };
}
