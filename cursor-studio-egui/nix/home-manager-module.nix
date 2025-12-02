# Home Manager module for Cursor Studio
# Add to your flake or home-manager configuration
#
# Example usage in home.nix:
# {
#   programs.cursor-studio = {
#     enable = true;
#     defaultVersion = "2.0.77";  # Use this version by default
#     versions = [ "2.1.34" "2.0.77" "1.7.54" ];  # Versions to keep available
#     hashRegistry = {
#       "2.1.34".linux-x64 = "sha256-NPs0P+cnPo3KMdezhAkPR4TwpcvIrSuoX+40NsKyfzA=";
#       "2.0.77".linux-x64 = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=";
#     };
#     settings = {
#       theme = "nord";
#       fontScale = 1.0;
#       messageSpacing = 12.0;
#     };
#   };
# }

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.cursor-studio;
  
  # JSON settings file
  settingsJson = pkgs.writeText "cursor-studio-settings.json" (builtins.toJSON {
    theme = cfg.settings.theme;
    font_scale = cfg.settings.fontScale;
    message_spacing = cfg.settings.messageSpacing;
    status_bar_font_size = cfg.settings.statusBarFontSize;
    show_timestamps = cfg.settings.showTimestamps;
    show_thinking_blocks = cfg.settings.showThinkingBlocks;
  });
  
  # Version registry JSON
  registryJson = pkgs.writeText "version-registry.json" (builtins.toJSON {
    schema_version = 1;
    updated = "2025-12-01";
    versions = lib.mapAttrsToList (version: hashes: {
      inherit version;
      commit_hash = builtins.getAttr version cfg.versionCommitHashes or "";
      release_date = null;
      is_stable = true;
      notes = null;
      inherit hashes;
    }) cfg.hashRegistry;
  });

in {
  options.programs.cursor-studio = {
    enable = lib.mkEnableOption "Cursor Studio - Cursor IDE version manager";
    
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cursor-studio or (throw "cursor-studio package not found");
      description = "The cursor-studio package to use.";
    };
    
    defaultVersion = lib.mkOption {
      type = lib.types.str;
      default = "2.0.77";
      description = "Default Cursor version to use (recommended: 2.0.77 for custom modes).";
    };
    
    versions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "2.1.34" "2.0.77" ];
      description = "List of Cursor versions to keep available.";
    };
    
    hashRegistry = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = {};
      example = {
        "2.1.34" = { "linux-x64" = "sha256-NPs0P+cnPo3KMdezhAkPR4TwpcvIrSuoX+40NsKyfzA="; };
        "2.0.77" = { "linux-x64" = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0="; };
      };
      description = "Hash registry for version verification. Keys are version strings, values are platform->hash maps.";
    };
    
    versionCommitHashes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        "2.1.34" = "609c37304ae83141fd217c4ae638bf532185650f";
        "2.1.32" = "ef979b1b43d85eee2a274c25fd62d5502006e425";
        "2.1.26" = "f628a4761be40b8869ca61a6189cafd14756dff4";
        "2.0.77" = "ba90f2f88e4911312761abab9492c42442117cfe";
        "1.7.54" = "5c17eb2968a37f66bc6662f48d6356a100b67be8";
      };
      description = "Git commit hashes for each version (used for download URLs).";
    };
    
    settings = {
      theme = lib.mkOption {
        type = lib.types.enum [ "dark" "light" "nord" "dracula" "one-dark" "catppuccin" "gruvbox" ];
        default = "dark";
        description = "UI theme.";
      };
      
      fontScale = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        description = "Font scale factor (0.7-1.6).";
      };
      
      messageSpacing = lib.mkOption {
        type = lib.types.float;
        default = 12.0;
        description = "Spacing between messages in pixels.";
      };
      
      statusBarFontSize = lib.mkOption {
        type = lib.types.float;
        default = 11.0;
        description = "Status bar font size in pixels.";
      };
      
      showTimestamps = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Show timestamps on messages.";
      };
      
      showThinkingBlocks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Show AI thinking blocks.";
      };
    };
    
    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically update to latest version.";
    };
    
    cacheDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.cacheHome}/cursor-studio";
      description = "Directory for cached downloads.";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/cursor-studio";
      description = "Directory for application data.";
    };
  };
  
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    
    # Create config directory
    xdg.configFile."cursor-studio/settings.json".source = settingsJson;
    
    # Install version registry
    xdg.configFile."cursor-studio/version-registry.json".source = registryJson;
    
    # Desktop entry
    xdg.desktopEntries.cursor-studio = {
      name = "Cursor Studio";
      genericName = "Cursor Version Manager";
      exec = "${cfg.package}/bin/cursor-studio";
      terminal = false;
      categories = [ "Development" "IDE" ];
      comment = "Manage Cursor IDE versions and chat history";
    };
  };
}
