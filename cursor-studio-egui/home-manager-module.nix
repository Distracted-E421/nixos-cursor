# Cursor Studio - Home Manager Module
# Declarative configuration for the Cursor Studio GUI
#
# This allows NixOS users to configure cursor-studio settings in their
# home.nix/flake.nix instead of manually through the GUI.
#
# The settings are written to a JSON config file that the GUI reads on startup.

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.cursor-studio;

  # Generate the config JSON that cursor-studio will read
  configFile = pkgs.writeText "cursor-studio-config.json" (builtins.toJSON {
    # UI Settings
    theme = cfg.ui.theme;
    font_scale = cfg.ui.fontScale;
    message_spacing = cfg.ui.messageSpacing;
    status_bar_font_size = cfg.ui.statusBarFontSize;

    # Display Preferences
    display_prefs = map (p: {
      content_type = p.contentType;
      alignment = p.alignment;
      style = p.style;
      collapsed = p.collapsed;
    }) cfg.display.preferences;

    # Security Settings
    security = {
      npm_scanning = cfg.security.npmScanning;
      sensitive_data_scan = cfg.security.sensitiveDataScan;
      blocklist_path = cfg.security.blocklistPath;
    };

    # Export Settings
    export = {
      default_format = cfg.export.defaultFormat;
      include_thinking = cfg.export.includeThinking;
      include_tool_calls = cfg.export.includeToolCalls;
    };

    # Resource Limits (advisory for future enforcement)
    resources = {
      max_cpu_threads = cfg.resources.maxCpuThreads;
      max_ram_mb = cfg.resources.maxRamMb;
      max_vram_mb = cfg.resources.maxVramMb;
      storage_limit_mb = cfg.resources.storageLimitMb;
    };

    # Paths
    cursor_data_dir = cfg.cursorDataDir;
  });

in
{
  options.programs.cursor-studio = {
    enable = mkEnableOption "Cursor Studio - Chat history manager and security scanner";

    package = mkOption {
      type = types.package;
      default = pkgs.cursor-studio or (throw "cursor-studio package not available");
      description = ''
        The cursor-studio package to use.
      '';
    };

    cursorDataDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.config/Cursor/User/workspaceStorage";
      description = ''
        Path to Cursor's workspace storage directory.
        This is where chat history databases are stored.
      '';
    };

    # UI Configuration
    ui = {
      theme = mkOption {
        type = types.enum [ "dark" "light" "system" ];
        default = "dark";
        description = "Color theme for the GUI.";
      };

      fontScale = mkOption {
        type = types.float;
        default = 1.0;
        description = "Font scaling factor (0.5 to 2.0).";
      };

      messageSpacing = mkOption {
        type = types.int;
        default = 12;
        description = "Spacing between messages in pixels.";
      };

      statusBarFontSize = mkOption {
        type = types.float;
        default = 12.0;
        description = "Font size for the status bar.";
      };
    };

    # Display Preferences per content type
    display = {
      preferences = mkOption {
        type = types.listOf (types.submodule {
          options = {
            contentType = mkOption {
              type = types.enum [ "user" "assistant" "tool" "thinking" "system" ];
              description = "Message type to configure.";
            };
            alignment = mkOption {
              type = types.enum [ "left" "center" "right" ];
              default = "left";
              description = "Text alignment for this message type.";
            };
            style = mkOption {
              type = types.str;
              default = "default";
              description = "Style preset for this message type.";
            };
            collapsed = mkOption {
              type = types.bool;
              default = false;
              description = "Whether to collapse this message type by default.";
            };
          };
        });
        default = [
          { contentType = "user"; alignment = "right"; style = "default"; collapsed = false; }
          { contentType = "assistant"; alignment = "left"; style = "default"; collapsed = false; }
          { contentType = "tool"; alignment = "left"; style = "compact"; collapsed = true; }
          { contentType = "thinking"; alignment = "left"; style = "dimmed"; collapsed = true; }
        ];
        description = ''
          Display preferences for different message types.
          Controls alignment, styling, and default collapsed state.
        '';
      };
    };

    # Security Settings
    security = {
      npmScanning = mkOption {
        type = types.bool;
        default = true;
        description = "Enable NPM package security scanning.";
      };

      sensitiveDataScan = mkOption {
        type = types.bool;
        default = true;
        description = "Scan chat history for sensitive data (API keys, passwords).";
      };

      blocklistPath = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to custom NPM blocklist JSON file.
          If null, uses the embedded blocklist.
        '';
      };
    };

    # Export Settings
    export = {
      defaultFormat = mkOption {
        type = types.enum [ "markdown" "json" ];
        default = "markdown";
        description = "Default export format for conversations.";
      };

      includeThinking = mkOption {
        type = types.bool;
        default = false;
        description = "Include AI thinking blocks in exports.";
      };

      includeToolCalls = mkOption {
        type = types.bool;
        default = true;
        description = "Include tool call details in exports.";
      };
    };

    # Resource Limits (advisory - for future enforcement)
    resources = {
      maxCpuThreads = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Maximum CPU threads for processing (null = auto).";
      };

      maxRamMb = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Maximum RAM usage in MB (null = unlimited).";
      };

      maxVramMb = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Maximum VRAM usage in MB (null = unlimited).";
      };

      storageLimitMb = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Maximum storage for cache/database in MB.";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the cursor-studio package
    home.packages = [ cfg.package ];

    # Create config directory and file
    xdg.configFile."cursor-studio/config.json" = {
      source = configFile;
    };

    # Create data directory
    home.activation.cursorStudioDataDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${config.xdg.dataHome}/cursor-studio
    '';
  };
}
