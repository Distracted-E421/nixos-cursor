# NixOS module for Cursor Proxy service
# 
# This module provides transparent interception of Cursor AI traffic
# for context injection and enhanced control.
#
# Usage in configuration.nix:
#   services.cursor-proxy = {
#     enable = true;
#     mode = "dns";  # or "iptables" (legacy)
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.cursor-proxy;
  
  # Build cursor-proxy from source
  cursor-proxy = pkgs.rustPlatform.buildRustPackage {
    pname = "cursor-proxy";
    version = "0.2.0";
    
    src = ../../tools/cursor-proxy;
    
    cargoLock = {
      lockFile = ../../tools/cursor-proxy/Cargo.lock;
    };
    
    nativeBuildInputs = with pkgs; [ pkg-config ];
    buildInputs = with pkgs; [ openssl ];
    
    meta = with lib; {
      description = "Transparent proxy for Cursor AI traffic interception";
      license = licenses.mit;
    };
  };
in {
  options.services.cursor-proxy = {
    enable = lib.mkEnableOption "Cursor AI transparent proxy";
    
    mode = lib.mkOption {
      type = lib.types.enum [ "dns" "iptables" ];
      default = "dns";
      description = ''
        Interception mode:
        - dns: Uses /etc/hosts override (recommended, more reliable)
        - iptables: Uses NAT redirect (legacy, has DNS rotation issues)
      '';
    };
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = ''
        Port for the proxy to listen on.
        For DNS mode, this must be 443.
        For iptables mode, this can be any port.
      '';
    };
    
    caDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cursor-proxy";
      description = "Directory for CA certificate storage";
    };
    
    captureDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cursor-proxy/captures";
      description = "Directory for captured payloads";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "cursor-proxy";
      description = "User to run the proxy service as";
    };
    
    group = lib.mkOption {
      type = lib.types.str;
      default = "cursor-proxy";
      description = "Group to run the proxy service as";
    };
    
    verbose = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable verbose logging";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # DNS mode: Override api2.cursor.sh to localhost
    networking.hosts = lib.mkIf (cfg.mode == "dns") {
      "127.0.0.1" = [ "api2.cursor.sh" ];
    };
    
    # Create service user/group
    users.users.${cfg.user} = lib.mkIf (cfg.user != "root") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.caDir;
      createHome = true;
    };
    
    users.groups.${cfg.group} = lib.mkIf (cfg.group != "root") {};
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.caDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.captureDir} 0750 ${cfg.user} ${cfg.group} -"
    ];
    
    # The proxy service
    systemd.services.cursor-proxy = {
      description = "Cursor AI Transparent Proxy";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      
      environment = {
        CURSOR_PROXY_CA_DIR = cfg.caDir;
        CURSOR_PROXY_CAPTURE_DIR = cfg.captureDir;
      };
      
      serviceConfig = {
        Type = "simple";
        ExecStart = let
          modeFlag = if cfg.mode == "dns" then "--dns-mode" else "--transparent";
          verboseFlag = if cfg.verbose then "--verbose" else "";
        in ''
          ${cursor-proxy}/bin/cursor-proxy start \
            --port ${toString cfg.port} \
            ${modeFlag} \
            ${verboseFlag} \
            --foreground
        '';
        
        Restart = "always";
        RestartSec = "2s";
        
        # User/group
        User = cfg.user;
        Group = cfg.group;
        
        # Allow binding to privileged ports
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
        
        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.caDir cfg.captureDir ];
        PrivateTmp = true;
        
        # Resource limits
        MemoryMax = "512M";
        TasksMax = "100";
      };
    };
    
    # Trust the proxy CA system-wide
    # Note: CA must be generated first with `cursor-proxy init`
    security.pki.certificates = lib.mkIf (builtins.pathExists "${cfg.caDir}/ca-cert.pem") [
      (builtins.readFile "${cfg.caDir}/ca-cert.pem")
    ];
    
    # Open firewall port if enabled
    networking.firewall.allowedTCPPorts = lib.mkIf config.networking.firewall.enable [ cfg.port ];
    
    # Package available for CLI use
    environment.systemPackages = [ cursor-proxy ];
    
    # Helpful assertion
    assertions = [
      {
        assertion = cfg.mode == "dns" -> cfg.port == 443;
        message = "DNS mode requires port 443 (got ${toString cfg.port})";
      }
    ];
  };
}

