{
  description = "Cursor with nix develop integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in {
      # Development shell with Cursor integration
      devShells.${system}.default = pkgs.mkShell {
        # IMPORTANT: Use buildInputs, NOT nativeBuildInputs
        # This ensures environment is passed to Cursor
        buildInputs = with pkgs; [
          # Development tools
          nodejs_22
          python312
          rustc
          cargo
          
          # Your project dependencies
          pkg-config
          openssl
          
          # Cursor (if installed via this flake)
          # cursor
        ];

        # Environment variables for development
        shellHook = ''
          echo "🚀 Development environment loaded"
          echo "Node: $(node --version)"
          echo "Python: $(python --version)"
          echo "Rust: $(rustc --version)"
          echo ""
          echo "Launch Cursor: cursor ."
          
          # Set up project-specific paths
          export PROJECT_ROOT="$PWD"
          export PATH="$PROJECT_ROOT/node_modules/.bin:$PATH"
        '';
      };
    };
}
