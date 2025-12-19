# Home Manager module for cursor-studio
# Provides integrated Cursor IDE launcher with proxy support
#
# Usage in home.nix:
#   imports = [ ./path/to/cursor-studio.nix ];
#   programs.cursor-studio = {
#     enable = true;
#     proxy.enable = true;
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.programs.cursor-studio;
  
  # Path to cursor-studio tools (adjust if installed elsewhere)
  cursorStudioPath = "${config.home.homeDirectory}/nixos-cursor/tools";
  
  # Proxy configuration file
  proxyConfig = pkgs.writeText "proxy.toml" ''
    [proxy]
    enabled = ${lib.boolToString cfg.proxy.enable}
    port = ${toString cfg.proxy.port}
    verbose = ${lib.boolToString cfg.proxy.verbose}
    upstream_timeout_ms = ${toString cfg.proxy.upstreamTimeout}
    
    [ca]
    cert_path = "${cfg.proxy.ca.certPath}"
    key_path = "${cfg.proxy.ca.keyPath}"
    trust_system_wide = ${lib.boolToString cfg.proxy.ca.trustSystemWide}
    cert_validity_days = ${toString cfg.proxy.ca.validityDays}
    
    [capture]
    enabled = ${lib.boolToString cfg.proxy.capture.enable}
    directory = "${cfg.proxy.capture.directory}"
    retention_days = ${toString cfg.proxy.capture.retentionDays}
    
    [iptables]
    auto_manage = ${lib.boolToString cfg.proxy.iptables.autoManage}
    cleanup_on_exit = ${lib.boolToString cfg.proxy.iptables.cleanupOnExit}
    targets = [${lib.concatMapStringsSep ", " (t: "\"${t}\"") cfg.proxy.iptables.targets}]
  '';

in {
  options.programs.cursor-studio = {
    enable = lib.mkEnableOption "cursor-studio - Enhanced Cursor IDE launcher";
    
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cursor;
      description = "The Cursor IDE package to use";
    };
    
    proxy = {
      enable = lib.mkEnableOption "transparent proxy for Cursor AI traffic";
      
      port = lib.mkOption {
        type = lib.types.port;
        default = 8443;
        description = "Port for the proxy server";
      };
      
      verbose = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable verbose logging";
      };
      
      upstreamTimeout = lib.mkOption {
        type = lib.types.int;
        default = 30000;
        description = "Timeout for upstream connections in milliseconds";
      };
      
      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically start proxy when launching Cursor";
      };
      
      ca = {
        certPath = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.cursor-proxy/ca-cert.pem";
          description = "Path to CA certificate";
        };
        
        keyPath = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.cursor-proxy/ca-key.pem";
          description = "Path to CA private key";
        };
        
        trustSystemWide = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Add CA to system trust store (requires NixOS config)";
        };
        
        validityDays = lib.mkOption {
          type = lib.types.int;
          default = 3650;
          description = "CA certificate validity in days";
        };
      };
      
      capture = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable payload capture";
        };
        
        directory = lib.mkOption {
          type = lib.types.str;
          default = "${config.home.homeDirectory}/.cursor-proxy/captures";
          description = "Directory for captured payloads";
        };
        
        retentionDays = lib.mkOption {
          type = lib.types.int;
          default = 7;
          description = "Days to retain captured payloads";
        };
      };
      
      iptables = {
        autoManage = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Automatically manage iptables rules";
        };
        
        cleanupOnExit = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Clean up iptables rules on proxy exit";
        };
        
        targets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "api2.cursor.sh" ];
          description = "Domains to intercept";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure Cursor package is installed
    home.packages = [ cfg.package ];
    
    # Create proxy config directory and config file
    home.file.".config/cursor-studio/proxy.toml".source = proxyConfig;
    
    # Create cursor-studio wrapper script
    home.file.".local/bin/cursor-studio" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Auto-generated wrapper for cursor-studio
        exec ${cursorStudioPath}/cursor-studio "$@"
      '';
    };
    
    # Create cursor-with-proxy shortcut
    home.file.".local/bin/cursor-with-proxy" = lib.mkIf cfg.proxy.enable {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        # Launch Cursor with proxy support
        exec ${cursorStudioPath}/cursor-studio --proxy "$@"
      '';
    };
    
    # Add to PATH
    home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];
    
    # Desktop entry for cursor-studio
    xdg.desktopEntries.cursor-studio = {
      name = "Cursor Studio";
      genericName = "Code Editor";
      comment = "Enhanced Cursor IDE with proxy support";
      exec = "${config.home.homeDirectory}/.local/bin/cursor-studio %F";
      icon = "cursor";
      terminal = false;
      categories = [ "Development" "IDE" "TextEditor" ];
      mimeType = [ "text/plain" "inode/directory" ];
    };
    
    # Desktop entry for cursor with proxy
    xdg.desktopEntries.cursor-studio-proxy = lib.mkIf cfg.proxy.enable {
      name = "Cursor Studio (Proxy)";
      genericName = "Code Editor";
      comment = "Cursor IDE with AI traffic proxy";
      exec = "${config.home.homeDirectory}/.local/bin/cursor-with-proxy %F";
      icon = "cursor";
      terminal = false;
      categories = [ "Development" "IDE" "TextEditor" ];
      mimeType = [ "text/plain" "inode/directory" ];
    };
    
    # Warnings for system-wide CA trust
    warnings = lib.optional (cfg.proxy.enable && cfg.proxy.ca.trustSystemWide) ''
      cursor-studio: To trust the proxy CA system-wide, add this to your NixOS configuration:
      
        security.pki.certificateFiles = [ "${cfg.proxy.ca.certPath}" ];
      
      Then run: sudo nixos-rebuild switch
    '';
  };
}

