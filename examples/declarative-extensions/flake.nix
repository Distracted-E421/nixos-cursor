{
  description = "Cursor with semi-declarative extension management";

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

          programs.cursor = {
            enable = true;
            mcp.enable = true;
          };

          # Semi-declarative extension management
          # This installs extensions on activation, but Cursor can still modify them
          home.activation.cursorExtensions = 
            let
              # List of extensions to install
              extensions = [
                "github.copilot"
                "github.copilot-chat"
                "esbenp.prettier-vscode"
                "dbaeumer.vscode-eslint"
                "rust-lang.rust-analyzer"
                "ms-python.python"
                # Add more extensions here
              ];
              
              installExtension = ext: ''
                if ! $DRY_RUN; then
                  echo "Installing extension: ${ext}"
                  ${pkgs.lib.getExe pkgs.cursor} --install-extension ${ext} 2>/dev/null || true
                fi
              '';
            in
              pkgs.lib.hm.dag.entryAfter ["writeBoundary"] ''
                # Install extensions if Cursor is available
                if command -v cursor >/dev/null 2>&1; then
                  ${pkgs.lib.concatMapStringsSep "\n" installExtension extensions}
                fi
              '';
        }
      ];
    };
  };
}
