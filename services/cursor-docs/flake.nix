{
  description = "cursor-docs - Local documentation indexing for Cursor with semantic search (v0.3.0-pre)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;  # SurrealDB has BSL license
        };

        # Elixir/Erlang versions
        erlang = pkgs.erlang_26;
        elixir = pkgs.elixir_1_16;

        # Native dependencies for NIFs
        nativeDeps = with pkgs; [
          sqlite
          openssl
          zlib
        ];

        # Development tools
        devTools = with pkgs; [
          # Elixir tooling
          elixir-ls

          # Database tools  
          sqlite
          litecli

          # Optional backends (tier 2/3)
          surrealdb
          ollama

          # Utilities
          jq
          curl
        ];

      in
      {
        # =====================================================================
        # Development Shell
        # =====================================================================
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
            export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPath "lib/pkgconfig" nativeDeps}"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeDeps}"
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
            echo "║  STORAGE TIERS:                                                ║"
            echo "║    Tier 1: Disabled - FTS5 keyword search (default)            ║"
            echo "║    Tier 2: sqlite-vss - Embedded vector search                 ║"
            echo "║    Tier 3: SurrealDB - Full vector + graph features            ║"
            echo "╠════════════════════════════════════════════════════════════════╣"
            echo "║  OPTIONAL BACKENDS:                                            ║"
            echo "║    ollama pull nomic-embed-text  - Enable AI embeddings        ║"
            echo "║    surreal start ...             - Enable SurrealDB            ║"
            echo "╚════════════════════════════════════════════════════════════════╝"
            echo ""
          '';
        };

        # Full shell with all optional backends pre-configured
        devShells.full = pkgs.mkShell {
          name = "cursor-docs-full";

          buildInputs = nativeDeps ++ devTools ++ [
            erlang
            elixir
            pkgs.rebar3
            # Additional tools for power users
            pkgs.chromedriver
            pkgs.chromium
          ];

          shellHook = ''
            export MIX_HOME=$PWD/.nix-mix
            export HEX_HOME=$PWD/.nix-hex
            export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
            export ERL_AFLAGS="-kernel shell_history enabled"
            export PKG_CONFIG_PATH="${pkgs.lib.makeSearchPath "lib/pkgconfig" nativeDeps}"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath nativeDeps}"
            export EXQLITE_SYSTEM_SQLITE=1

            mix local.hex --force --if-missing 2>/dev/null
            mix local.rebar --force --if-missing 2>/dev/null

            echo "cursor-docs FULL development shell (with all backends)"
          '';
        };

        # =====================================================================
        # Checks
        # =====================================================================
        checks.default = pkgs.runCommand "cursor-docs-check" {
          buildInputs = [ elixir erlang ];
        } ''
          echo "cursor-docs flake check passed"
          touch $out
        '';
      }
    ) // {
      # =====================================================================
      # NixOS Module (for system-wide installation)
      # =====================================================================
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
              description = "Data directory for cursor-docs databases";
            };

            surrealdb = {
              enable = lib.mkEnableOption "SurrealDB backend (Tier 3)";

              graceful = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Use graceful startup (low priority, doesn't block boot)";
              };
            };
          };

          config = lib.mkIf cfg.enable {
            # SurrealDB service
            systemd.services.cursor-docs-surrealdb = lib.mkIf cfg.surrealdb.enable {
              description = "SurrealDB for cursor-docs (Tier 3 storage)";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                Type = "simple";
                ExecStart = "${pkgs.surrealdb}/bin/surreal start --user root --pass root --bind 127.0.0.1:8000 file:${cfg.dataDir}/surreal.db";
                StateDirectory = "cursor-docs";

                # Graceful startup - doesn't slow down boot
                Nice = lib.mkIf cfg.surrealdb.graceful 19;
                IOSchedulingClass = lib.mkIf cfg.surrealdb.graceful "idle";
                CPUWeight = lib.mkIf cfg.surrealdb.graceful 10;
                MemoryMax = "2G";

                Restart = "on-failure";
                RestartSec = "30s";
              };
            };

            environment.systemPackages = [ pkgs.sqlite ]
              ++ lib.optionals cfg.surrealdb.enable [ pkgs.surrealdb ];
          };
        };

      # =====================================================================
      # Home Manager Module (for user-level installation)
      # =====================================================================
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

            enableSurrealdb = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Include SurrealDB for Tier 3 storage";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = with pkgs; [
              elixir_1_16
              erlang_26
              sqlite
            ] ++ lib.optionals cfg.enableOllama [ ollama ]
              ++ lib.optionals cfg.enableSurrealdb [ surrealdb ];
          };
        };
    };
}
