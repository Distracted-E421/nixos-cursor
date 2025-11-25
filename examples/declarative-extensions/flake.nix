{
  description = "Cursor with semi-declarative extension management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixos-cursor - Multi-version Cursor IDE for NixOS
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
