# Cursor with MCP - Home Manager Module
# MIT License - Copyright (c) 2025 e421 (distracted.e421@gmail.com)
#
# Production-ready Home Manager module for Cursor IDE with MCP server integration.
# No user-specific hardcoded paths - works for any user out of the box.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.cursor;
  
  # Detect browser executable path automatically
  getBrowserPath = browser: package:
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

  # Generate MCP configuration JSON
  mcpConfig = {
    mcpServers = mkMerge [
      # Filesystem MCP Server (always enabled if mcp.enable = true)
      (mkIf cfg.mcp.enable {
        filesystem = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-filesystem"
          ] ++ cfg.mcp.filesystemPaths;
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
      
      # GitHub MCP Server (repository operations)
      (mkIf (cfg.mcp.enable && cfg.mcp.github.enable) {
        github = {
          command = "npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-github"
          ];
          env = mkIf (cfg.mcp.github.token != null) {
            GITHUB_PERSONAL_ACCESS_TOKEN = cfg.mcp.github.token;
          };
        };
      })
      
      # Playwright MCP Server (browser automation)
      (mkIf (cfg.mcp.enable && cfg.mcp.playwright.enable) (
        let
          browserPath = getBrowserPath cfg.mcp.playwright.browser cfg.mcp.playwright.browserPackage;
          playwrightArgs = [
            "--browser" cfg.mcp.playwright.browser
            "--executable-path" browserPath
          ] ++ optionals cfg.mcp.playwright.headless [ "--headless" ]
            ++ optionals (cfg.mcp.playwright.userDataDir != null) [ "--user-data-dir" cfg.mcp.playwright.userDataDir ]
            ++ optionals cfg.mcp.playwright.saveTrace [ "--save-trace" ]
            ++ optionals cfg.mcp.playwright.saveVideo [ "--save-video" ]
            ++ optionals cfg.mcp.playwright.saveSession [ "--save-session" ]
            ++ optionals (cfg.mcp.playwright.timeout != null) [ "--timeout-navigation" (toString cfg.mcp.playwright.timeout) ];
        in {
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

in {
  options.programs.cursor = {
    enable = mkEnableOption "Cursor IDE with MCP server integration";

    package = mkOption {
      type = types.package;
      default = pkgs.cursor or (throw "Cursor package not available. Please add cursor-with-mcp flake input.");
      description = ''
        The Cursor IDE package to use.
        Defaults to the enhanced Cursor package from this flake.
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

        token = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = literalExpression ''"ghp_xxxxxxxxxxxxxxxxxxxx"'';
          description = ''
            GitHub Personal Access Token for authenticated API requests.
            
            If null, only public repository operations are available.
            
            Security: Consider using agenix or sops-nix for secret management
            instead of storing tokens in plain text.
            
            Create token at: https://github.com/settings/tokens
            Required scopes: repo, read:org
          '';
        };
      };

      playwright = {
        enable = mkEnableOption "Playwright browser automation MCP server";

        browser = mkOption {
          type = types.enum [ "chrome" "chromium" "firefox" "webkit" ];
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
    };
  };

  config = mkIf cfg.enable {
    # Install Cursor package and optional browser
    home.packages = [ cfg.package ]
      ++ optionals cfg.mcp.playwright.enable [ cfg.mcp.playwright.browserPackage ];

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

    # Ensure playwright browser directory exists
    home.activation.playwrightBrowserDir = mkIf cfg.mcp.playwright.enable (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p ${config.home.homeDirectory}/.local/share/playwright
      ''
    );
  };
}
