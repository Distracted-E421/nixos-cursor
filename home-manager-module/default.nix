# Cursor with MCP - Home Manager Module
# MIT License - Copyright (c) 2025 e421 (distracted.e421@gmail.com)
#
# Production-ready Home Manager module for Cursor IDE with MCP server integration.
# No user-specific hardcoded paths - works for any user out of the box.
# Supports secrets via agenix, sops-nix, or any file-based secret manager.

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.cursor;

  # Dialog daemon package (either from pkgs overlay or built from source)
  dialogDaemonPkg = cfg.mcp.dialog.package;

  updateCheckService = {
    Unit = {
      Description = "Check for Cursor updates";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${cfg.package}/bin/cursor-check-update";
      Environment = [ "DISPLAY=:0" ];
    };
  };

  updateCheckTimer = {
    Unit = {
      Description = "Check for Cursor updates daily";
    };
    Timer = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # Detect browser executable path automatically
  getBrowserPath =
    browser: package:
    if browser == "chrome" then
      "${package}/bin/google-chrome-stable"
    else if browser == "chromium" then
      "${package}/bin/chromium"
    else if browser == "firefox" then
      "${package}/bin/firefox"
    else if browser == "webkit" then
      # WebKit typically comes from playwright's own bundle
      "webkit"
    else
      throw "Unsupported browser: ${browser}";

  # Generate wrapper script for npx-based MCP servers
  # This wrapper provides feedback and handles first-run scenarios properly
  mkNpxMcpWrapper =
    {
      name,
      package,
      extraArgs ? [ ],
      env ? { },
    }:
    pkgs.writeShellScript "mcp-${name}-wrapper" ''
      #!${pkgs.bash}/bin/bash
      # MCP Server Wrapper: ${name}
      # Provides proper feedback and handles first-run package installation

      # Ensure we're not in interactive mode for npx
      export NPM_CONFIG_YES=true
      export CI=true

      # Set any additional environment variables
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=\"${v}\"") env)}

      # Run the MCP server
      # The -y flag auto-confirms any npx prompts
      exec ${pkgs.nodejs_22}/bin/npx -y "${package}" ${lib.escapeShellArgs extraArgs} "$@"
    '';

  # Generate wrapper script for MCP servers that need secrets
  # This script reads the token from a file at RUNTIME, not build time
  mkSecretWrapper =
    {
      name,
      tokenFile,
      envVar,
      command,
      args ? [ ],
    }:
    pkgs.writeShellScript "mcp-${name}-wrapper" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      # Ensure non-interactive mode for any npm operations
      export NPM_CONFIG_YES=true
      export CI=true

      TOKEN_FILE="${tokenFile}"

      if [[ ! -f "$TOKEN_FILE" ]]; then
        echo "ERROR: Token file not found: $TOKEN_FILE" >&2
        echo "Please ensure your secrets manager (agenix/sops-nix) has decrypted the secret." >&2
        exit 1
      fi

      if [[ ! -r "$TOKEN_FILE" ]]; then
        echo "ERROR: Cannot read token file: $TOKEN_FILE" >&2
        echo "Check file permissions (should be 0400 or 0600)." >&2
        exit 1
      fi

      export ${envVar}="$(cat "$TOKEN_FILE")"
      exec ${command} ${lib.escapeShellArgs args}
    '';

  # Filesystem MCP wrapper
  filesystemMcpWrapper = mkNpxMcpWrapper {
    name = "filesystem";
    package = "@modelcontextprotocol/server-filesystem";
    extraArgs = cfg.mcp.filesystemPaths;
  };

  # GitHub MCP wrapper (with secrets support)
  githubMcpWrapperWithToken = mkSecretWrapper {
    name = "github";
    tokenFile = cfg.mcp.github.tokenFile;
    envVar = "GITHUB_PERSONAL_ACCESS_TOKEN";
    command = "${pkgs.nodejs_22}/bin/npx";
    args = [
      "-y"
      "@modelcontextprotocol/server-github"
    ];
  };

  # GitHub MCP wrapper (without authentication)
  githubMcpWrapperNoAuth = mkNpxMcpWrapper {
    name = "github-noauth";
    package = "@modelcontextprotocol/server-github";
  };

  # Generate MCP configuration JSON
  mcpConfig = {
    mcpServers = mkMerge [
      # Filesystem MCP Server (always enabled if mcp.enable = true)
      (mkIf cfg.mcp.enable {
        filesystem = {
          command = "${filesystemMcpWrapper}";
          # Args are baked into the wrapper
        };
      })

      # Memory MCP Server
      (mkIf (cfg.mcp.enable && cfg.mcp.memory.enable) {
        memory = {
          command = "${cfg.mcp.memory.package}/bin/mcp-server-memory";
        };
      })

      # NixOS MCP Server (package/option search)
      (mkIf (cfg.mcp.enable && cfg.mcp.nixos.enable) {
        nixos = {
          command = "${pkgs.uv}/bin/uvx";
          args = [ "mcp-nixos" ];
        };
      })

      # GitHub MCP Server - WITH secrets support via tokenFile
      (mkIf (cfg.mcp.enable && cfg.mcp.github.enable && cfg.mcp.github.tokenFile != null) {
        github = {
          command = "${githubMcpWrapperWithToken}";
          # No args needed - wrapper handles everything
        };
      })

      # GitHub MCP Server - WITHOUT authentication (public repos only)
      (mkIf (cfg.mcp.enable && cfg.mcp.github.enable && cfg.mcp.github.tokenFile == null) {
        github = {
          command = "${githubMcpWrapperNoAuth}";
          # Args are baked into the wrapper
        };
      })

      # Playwright MCP Server (browser automation)
      (mkIf (cfg.mcp.enable && cfg.mcp.playwright.enable) (
        let
          browserPath = getBrowserPath cfg.mcp.playwright.browser cfg.mcp.playwright.browserPackage;
          playwrightArgs = [
            "--browser"
            cfg.mcp.playwright.browser
            "--executable-path"
            browserPath
          ]
          ++ optionals cfg.mcp.playwright.headless [ "--headless" ]
          ++ optionals (cfg.mcp.playwright.userDataDir != null) [
            "--user-data-dir"
            cfg.mcp.playwright.userDataDir
          ]
          ++ optionals cfg.mcp.playwright.saveTrace [ "--save-trace" ]
          ++ optionals cfg.mcp.playwright.saveVideo [ "--save-video" ]
          ++ optionals cfg.mcp.playwright.saveSession [ "--save-session" ]
          ++ optionals (cfg.mcp.playwright.timeout != null) [
            "--timeout-navigation"
            (toString cfg.mcp.playwright.timeout)
          ];
        in
        {
          playwright = {
            command = "${cfg.mcp.playwright.package}/bin/mcp-server-playwright";
            args = playwrightArgs;
            env = {
              PLAYWRIGHT_BROWSERS_PATH = "${config.home.homeDirectory}/.local/share/playwright";
              PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
            };
          };
        }
      ))
    ];
  };

in
{
  options.programs.cursor = {
    enable = mkEnableOption "Cursor IDE with MCP server integration";

    package = mkOption {
      type = types.package;
      default =
        pkgs.cursor or (throw "Cursor package not available. Please add cursor-with-mcp flake input.");
      description = ''
        The Cursor IDE package to use.
        Defaults to the enhanced Cursor package from this flake.
      '';
    };

    updateCheck = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable daily checks for Cursor updates.
          Shows desktop notification when new version is available.
        '';
      };

      interval = mkOption {
        type = types.str;
        default = "daily";
        example = "weekly";
        description = ''
          How often to check for updates.
          Accepts systemd.time calendar event format.
        '';
      };
    };

    flakeDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/user/.config/home-manager";
      description = ''
        Directory containing your flake.nix that uses nixos-cursor.
        Used by `cursor-update` command for automatic updates.
        If not set, will try to auto-detect.
      '';
    };

    mcp = {
      enable = mkEnableOption "MCP (Model Context Protocol) servers";

      filesystemPaths = mkOption {
        type = types.listOf types.str;
        default = [ config.home.homeDirectory ];
        example = literalExpression ''
          [
            config.home.homeDirectory
            "$\{config.home.homeDirectory}/projects"
            "/etc/nixos"
          ]
        '';
        description = ''
          Paths accessible to the filesystem MCP server.
          The AI assistant can read and write files in these directories.

          Security note: Only include paths you trust the AI to access.
        '';
      };

      memory = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable the memory MCP server for persistent AI context across sessions.
          '';
        };

        package = mkOption {
          type = types.package;
          default = pkgs.mcp-server-memory or (throw "mcp-server-memory not available");
          description = "Package providing mcp-server-memory";
        };
      };

      nixos = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable the NixOS MCP server for package and option search.
            Requires 'uv' and 'mcp-nixos' to be available.
          '';
        };
      };

      github = {
        enable = mkEnableOption "GitHub MCP server for repository operations";

        tokenFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = literalExpression ''
            # Using agenix:
            "/run/agenix/github-mcp-token"

            # Using sops-nix:
            config.sops.secrets.github-mcp-token.path

            # Using plain file (less secure):
            "''${config.home.homeDirectory}/.config/cursor-secrets/github-token"
          '';
          description = ''
            Path to a file containing the GitHub Personal Access Token.
            The token is read at runtime, never stored in the Nix store.

            Supports any secrets manager that writes to a file path:
            - agenix: /run/agenix/<secret-name>
            - sops-nix: config.sops.secrets.<name>.path
            - Plain file: ~/.config/cursor-secrets/github-token

            If null, GitHub MCP runs without authentication (public repos only).

            Required token permissions: repo, read:org
            Create at: https://github.com/settings/tokens
          '';
        };
      };

      playwright = {
        enable = mkEnableOption "Playwright browser automation MCP server";

        browser = mkOption {
          type = types.enum [
            "chrome"
            "chromium"
            "firefox"
            "webkit"
          ];
          default = "chrome";
          description = ''
            Which browser to use for automation.

            - chrome: Google Chrome (requires google-chrome package)
            - chromium: Chromium (open-source)
            - firefox: Mozilla Firefox
            - webkit: Safari's engine (macOS primarily)
          '';
        };

        browserPackage = mkOption {
          type = types.package;
          default = pkgs.google-chrome;
          defaultText = literalExpression "pkgs.google-chrome";
          example = literalExpression "pkgs.chromium";
          description = ''
            Nix package providing the browser executable.

            Common options:
            - pkgs.google-chrome (Chrome)
            - pkgs.chromium (Chromium)
            - pkgs.firefox (Firefox)
          '';
        };

        package = mkOption {
          type = types.package;
          default = pkgs.playwright-mcp or (throw "playwright-mcp not available");
          description = "Package providing mcp-server-playwright";
        };

        headless = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Run browser in headless mode (no visible window).

            Useful for:
            - CI/CD automation
            - Server environments without displays
            - Background scraping tasks

            Set to false (default) to see the browser window during development.
          '';
        };

        userDataDir = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = literalExpression ''"$\{config.home.homeDirectory}/.local/share/playwright/profile"'';
          description = ''
            Directory for persistent browser profile (cookies, cache, etc).
            If null, a temporary profile is used for each session.
          '';
        };

        saveSession = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Save browser session state (cookies, localStorage) between runs.
            Requires userDataDir to be set.
          '';
        };

        saveTrace = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Save Playwright trace files for debugging.
            Traces include screenshots, network logs, and DOM snapshots.
          '';
        };

        saveVideo = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Record video of browser sessions.
            Useful for debugging test failures.
          '';
        };

        timeout = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = 60000;
          description = ''
            Navigation timeout in milliseconds.
            If null, uses Playwright's default (60000ms).
          '';
        };
      };

      dialog = {
        enable = mkEnableOption "Interactive dialog daemon for AI agent feedback";

        package = mkOption {
          type = types.package;
          default = pkgs.cursor-dialog-daemon or (throw "cursor-dialog-daemon not available. Add nixos-cursor overlay or use packages.cursor-dialog-daemon from the flake.");
          defaultText = literalExpression "pkgs.cursor-dialog-daemon";
          description = ''
            The cursor-dialog-daemon package providing both the daemon and CLI.
            This package is exported from the nixos-cursor flake.
          '';
        };

        autoStart = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Automatically start the dialog daemon when the graphical session starts.
            When enabled, a systemd user service is created.

            If false, you must manually start the daemon with:
              systemctl --user start cursor-dialog-daemon
            or:
              cursor-dialog-daemon &
          '';
        };

        installRules = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Install the interactive-dialogs.mdc cursor rules file.
            This teaches AI agents how to use the dialog system.

            The rules file is installed to ~/.cursor/rules/interactive-dialogs.mdc
          '';
        };

        addToPath = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Add cursor-dialog-cli to PATH.

            This makes the `cursor-dialog-cli` command available globally,
            which is required for AI agents to invoke dialogs from shell commands.
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable {
    # Install Cursor package and optional browser/dialog CLI
    home.packages = [
      cfg.package
    ]
    ++ optionals cfg.mcp.playwright.enable [ cfg.mcp.playwright.browserPackage ]
    ++ optionals (cfg.mcp.dialog.enable && cfg.mcp.dialog.addToPath) [ dialogDaemonPkg ];

    # Set flake directory for update command
    home.sessionVariables = mkIf (cfg.flakeDir != null) {
      NIXOS_CURSOR_FLAKE_DIR = cfg.flakeDir;
    };

    # Enable update checking service
    systemd.user.services.cursor-update-check = mkIf cfg.updateCheck.enable updateCheckService;
    systemd.user.timers.cursor-update-check = mkIf cfg.updateCheck.enable (
      updateCheckTimer
      // {
        Timer.OnCalendar = mkForce cfg.updateCheck.interval;
      }
    );

    # Dialog daemon systemd user service
    systemd.user.services.cursor-dialog-daemon = mkIf (cfg.mcp.dialog.enable && cfg.mcp.dialog.autoStart) {
      Unit = {
        Description = "Cursor Dialog Daemon for AI Agent Feedback";
        Documentation = "https://github.com/e421/nixos-cursor";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${dialogDaemonPkg}/bin/cursor-dialog-daemon";
        Restart = "on-failure";
        RestartSec = "5s";
        # Environment for egui/wayland
        Environment = [
          "DISPLAY=:0"
          "WAYLAND_DISPLAY=wayland-0"
        ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    # Generate MCP configuration file
    home.file.".cursor/mcp.json" = mkIf cfg.mcp.enable {
      text = builtins.toJSON mcpConfig;

      # Kill running MCP servers when config changes
      onChange = ''
        ${pkgs.procps}/bin/pkill -f 'mcp-server' || true
        ${pkgs.procps}/bin/pkill -f 'mcp-nixos' || true
        ${pkgs.procps}/bin/pkill -f 'npx.*mcp' || true
        echo "MCP configuration updated. MCP servers will restart automatically."
      '';
    };

    # Install interactive dialog rules for AI agents
    home.file.".cursor/rules/interactive-dialogs.mdc" = mkIf (cfg.mcp.dialog.enable && cfg.mcp.dialog.installRules) {
      text = ''
        ---
        alwaysApply: true
        ---

        # Interactive Dialog System for AI Agents

        **Status**: Active
        **Dependencies**: `cursor-dialog-daemon` running as systemd user service

        ## Overview

        This system enables AI agents to request interactive user input mid-task without burning API requests.

        ## Quick Reference

        ### Check if Daemon is Running

        ```bash
        cursor-dialog-cli ping
        # Expected: "pong"

        # Or check systemd status
        systemctl --user status cursor-dialog-daemon
        ```

        ### Multiple Choice Dialog

        ```bash
        result=$(cursor-dialog-cli -t 60 choice \
          --title "Summary Detail Level" \
          --prompt "How detailed should the task summary be?" \
          --options '[
            {"value":"minimal","label":"Minimal","description":"Just the changes made"},
            {"value":"standard","label":"Standard","description":"Changes + brief reasoning"},
            {"value":"verbose","label":"Verbose","description":"Full analysis and alternatives considered"}
          ]' \
          --default "standard")

        selection=$(echo "$result" | jq -r '.selection')
        cancelled=$(echo "$result" | jq -r '.cancelled')
        ```

        ### Text Input Dialog

        ```bash
        result=$(cursor-dialog-cli -t 60 text \
          --title "Component Name" \
          --prompt "Enter a name for the new component:" \
          --placeholder "MyComponent")

        name=$(echo "$result" | jq -r '.selection')
        ```

        ### Confirmation Dialog

        ```bash
        result=$(cursor-dialog-cli -t 30 confirm \
          --title "Apply Changes" \
          --prompt "Apply 15 file modifications to the codebase?" \
          --yes "Apply Changes" \
          --no "Review First")

        if [ "$(echo "$result" | jq -r '.selection')" = "true" ]; then
          # Proceed with changes
        fi
        ```

        ### Slider Dialog

        ```bash
        result=$(cursor-dialog-cli -t 45 slider \
          --title "Context Budget" \
          --prompt "Maximum tokens for injected context:" \
          --min 1000 --max 50000 --step 1000 --default 10000 \
          --unit " tokens")

        tokens=$(echo "$result" | jq -r '.selection')
        ```

        ### Toast Notifications (Non-blocking)

        ```bash
        cursor-dialog-cli toast -m "Build complete!" -l success -d 3000
        cursor-dialog-cli toast -m "Warning: low memory" -l warning -d 5000
        cursor-dialog-cli toast -m "Error occurred" -l error -d 8000
        ```

        ## Response Format

        All dialogs return JSON:

        ```json
        {
          "id": "uuid",
          "selection": "standard",
          "comment": "Optional user context",
          "cancelled": false,
          "timestamp": 1705512345
        }
        ```

        ## Best Practices

        1. **Always provide a default** - Don't block on required input
        2. **Keep prompts concise** - User should understand in <5 seconds
        3. **Limit options** - 2-5 choices max
        4. **Set reasonable timeouts** - 30s for simple, 60s for complex
        5. **Handle cancellation gracefully** - Never fail on cancelled dialog
        6. **Check the comment field** - Users may add helpful context

        ## Error Handling

        If the daemon isn't running:

        ```bash
        if ! cursor-dialog-cli ping 2>/dev/null; then
          echo "Dialog daemon not running, using defaults"
          # Fall back to sensible defaults
        fi
        ```

        ## Service Management

        ```bash
        # Start daemon
        systemctl --user start cursor-dialog-daemon

        # Stop daemon
        systemctl --user stop cursor-dialog-daemon

        # Check status
        systemctl --user status cursor-dialog-daemon

        # View logs
        journalctl --user -u cursor-dialog-daemon -f
        ```
      '';

      # Restart dialog daemon when rules change to pick up any format changes
      onChange = ''
        if ${pkgs.systemd}/bin/systemctl --user is-active cursor-dialog-daemon >/dev/null 2>&1; then
          echo "Dialog rules updated."
        fi
      '';
    };

    # Ensure playwright browser directory exists
    home.activation.playwrightBrowserDir = mkIf cfg.mcp.playwright.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${config.home.homeDirectory}/.local/share/playwright
      ''
    );

    # Pre-cache MCP npm packages during activation to avoid first-run prompts
    # This runs npx with --yes to download packages ahead of time, so when
    # Cursor starts the MCP servers, they're already cached and don't prompt
    home.activation.preCacheMcpPackages = mkIf cfg.mcp.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        echo "Pre-caching MCP server packages..."

        # Set non-interactive mode for npm
        export NPM_CONFIG_YES=true
        export CI=true

        # Pre-cache filesystem MCP server
        # The --help flag triggers download without starting the server
        if ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-filesystem --help >/dev/null 2>&1; then
          echo "  ✓ @modelcontextprotocol/server-filesystem ready"
        else
          echo "  ⚠ Downloading @modelcontextprotocol/server-filesystem (first run)..."
          ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-filesystem --version >/dev/null 2>&1 || true
          echo "  ✓ @modelcontextprotocol/server-filesystem cached"
        fi

        ${optionalString cfg.mcp.github.enable ''
          # Pre-cache GitHub MCP server
          if ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-github --help >/dev/null 2>&1; then
            echo "  ✓ @modelcontextprotocol/server-github ready"
          else
            echo "  ⚠ Downloading @modelcontextprotocol/server-github (first run)..."
            ${pkgs.nodejs_22}/bin/npx -y @modelcontextprotocol/server-github --version >/dev/null 2>&1 || true
            echo "  ✓ @modelcontextprotocol/server-github cached"
          fi
        ''}

        echo "MCP packages ready. No prompts will appear on first Cursor launch."
      ''
    );

    # Warn if GitHub MCP is enabled without authentication
    warnings =
      optional (cfg.mcp.github.enable && cfg.mcp.github.tokenFile == null)
        "GitHub MCP server is enabled without authentication. Only public repository operations will be available. Set programs.cursor.mcp.github.tokenFile for full access.";
  };
}
