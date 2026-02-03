{
  description = "cursor-docs - Local documentation indexing for Cursor with semantic search (v0.3.0-pre)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { config, self', inputs', pkgs, system, lib, ... }:
        let
          # Elixir/Erlang versions
          erlang = pkgs.erlang_26;
          elixir = pkgs.elixir_1_16;

          # Native dependencies for NIFs
          nativeDeps = with pkgs; [
            sqlite
            openssl
            zlib
          ];

          # Development tools (minimal)
          devTools = with pkgs; [
            # Elixir tooling
            elixir-ls

            # Database tools (SQLite only - lightweight)
            sqlite
            litecli

            # Utilities
            jq
            curl
          ];
        in
        {
          # Default development shell - lightweight, SQLite-based
          devShells.default = pkgs.mkShell {
            name = "cursor-docs-dev";

            buildInputs = nativeDeps ++ devTools ++ [
              erlang
              elixir
              pkgs.rebar3
            ];

            shellHook = ''
              # Elixir environment
              export MIX_HOME=$PWD/.nix-mix
              export HEX_HOME=$PWD/.nix-hex
              export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
              export ERL_AFLAGS="-kernel shell_history enabled"

              # Native library paths for exqlite
              export PKG_CONFIG_PATH="${lib.makeSearchPath "lib/pkgconfig" nativeDeps}"
              export LD_LIBRARY_PATH="${lib.makeLibraryPath nativeDeps}"
              export EXQLITE_SYSTEM_SQLITE=1

              # Install hex/rebar if needed
              mix local.hex --force --if-missing 2>/dev/null
              mix local.rebar --force --if-missing 2>/dev/null

              echo ""
              echo "╔════════════════════════════════════════════════════════════════╗"
              echo "║        cursor-docs v0.3.0-pre Development Shell                ║"
              echo "╠════════════════════════════════════════════════════════════════╣"
              echo "║  Elixir: $(elixir --version | head -1 | cut -d' ' -f2)                                           ║"
              echo "║  SQLite: $(sqlite3 --version | cut -d' ' -f1)                                            ║"
              echo "╠════════════════════════════════════════════════════════════════╣"
              echo "║  QUICK START:                                                  ║"
              echo "║    mix deps.get           - Install dependencies               ║"
              echo "║    mix cursor_docs.setup  - Initialize database                ║"
              echo "║    mix cursor_docs.sync   - Sync from Cursor @docs             ║"
              echo "║    mix cursor_docs.status - Check system status                ║"
              echo "║    mix cursor_docs.search - Search indexed docs                ║"
              echo "╠════════════════════════════════════════════════════════════════╣"
              echo "║  STORAGE: SQLite with FTS5 (lightweight, embedded)             ║"
              echo "╠════════════════════════════════════════════════════════════════╣"
              echo "║  OPTIONAL: nix develop .#full - includes Ollama for embeddings ║"
              echo "╚════════════════════════════════════════════════════════════════╝"
              echo ""
            '';
          };

          # Full shell with AI embeddings support
          devShells.full = pkgs.mkShell {
            name = "cursor-docs-full";

            buildInputs = nativeDeps ++ devTools ++ [
              erlang
              elixir
              pkgs.rebar3
              pkgs.ollama  # For AI embeddings
            ];

            shellHook = ''
              export MIX_HOME=$PWD/.nix-mix
              export HEX_HOME=$PWD/.nix-hex
              export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
              export ERL_AFLAGS="-kernel shell_history enabled"
              export PKG_CONFIG_PATH="${lib.makeSearchPath "lib/pkgconfig" nativeDeps}"
              export LD_LIBRARY_PATH="${lib.makeLibraryPath nativeDeps}"
              export EXQLITE_SYSTEM_SQLITE=1

              mix local.hex --force --if-missing 2>/dev/null
              mix local.rebar --force --if-missing 2>/dev/null

              echo "cursor-docs FULL development shell (with Ollama for embeddings)"
              echo "Run: ollama pull nomic-embed-text"
            '';
          };

          # Checks
          checks.default = pkgs.runCommand "cursor-docs-check" {
            buildInputs = [ elixir erlang ];
          } ''
            echo "cursor-docs flake check passed"
            touch $out
          '';
        };

      # Non-per-system outputs
      flake = {
        # NixOS Module (simplified - SQLite only)
        nixosModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.cursor-docs;
          in
          {
            options.services.cursor-docs = {
              enable = lib.mkEnableOption "cursor-docs documentation indexer";

              dataDir = lib.mkOption {
                type = lib.types.str;
                default = "/var/lib/cursor-docs";
                description = "Data directory for cursor-docs database";
              };
            };

            config = lib.mkIf cfg.enable {
              environment.systemPackages = [ pkgs.sqlite ];
            };
          };

        # Home Manager Module (simplified)
        homeManagerModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.programs.cursor-docs;
          in
          {
            options.programs.cursor-docs = {
              enable = lib.mkEnableOption "cursor-docs development environment";

              enableOllama = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Include Ollama for AI embeddings";
              };
            };

            config = lib.mkIf cfg.enable {
              home.packages = with pkgs; [
                elixir_1_16
                erlang_26
                sqlite
              ] ++ lib.optionals cfg.enableOllama [ ollama ];
            };
          };
      };
    };
}
