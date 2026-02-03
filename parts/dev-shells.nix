# Cursor IDE Development Shells
# Development environments for working on nixos-cursor
{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, lib, ... }: {
    devShells = {
      default = pkgs.mkShell {
        name = "nixos-cursor-dev";

        packages = with pkgs; [
          # Modern shell scripting
          nushell

          # Python with batteries
          (python3.withPackages (ps: with ps; [
            httpx  # Async HTTP client
            rich   # Beautiful terminal output
            typer  # CLI framework
          ]))

          # Development tools
          jq            # JSON processing
          statix        # Nix linter
          nixpkgs-fmt   # Nix formatter

          # Testing
          shellcheck    # Bash linter (for legacy scripts)
        ];

        shellHook = ''
          echo "nixos-cursor development shell"
          echo ""
          echo "Available tools:"
          echo "  nu        - Nushell (modern shell scripts)"
          echo "  python    - Python 3 with httpx, rich, typer"
          echo "  statix    - Nix linter"
          echo ""
          echo "Scripts:"
          echo "  nu scripts/nu/disk-usage.nu --help"
          echo "  python scripts/python/compute_hashes.py --help"
        '';
      };

      # Full development shell with all compiled languages
      full = pkgs.mkShell {
        name = "nixos-cursor-full";

        packages = with pkgs; [
          # Shells
          nushell

          # Python
          (python3.withPackages (ps: with ps; [
            httpx
            rich
            typer
          ]))

          # Elixir/BEAM
          elixir
          erlang

          # Compiled languages
          nim
          zig
          cargo
          rustc

          # Development
          jq
          statix
          nixpkgs-fmt
          shellcheck
        ];
      };
    };
  };
}
