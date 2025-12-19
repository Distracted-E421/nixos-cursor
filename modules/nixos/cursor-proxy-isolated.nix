# NixOS module for isolated Cursor proxy testing
#
# This module creates:
# 1. A network namespace for isolated testing
# 2. Runs cursor-proxy INSIDE the namespace
# 3. Uses iptables REDIRECT within the namespace
# 4. A wrapper script to run Cursor in the isolated namespace
#
# Traffic flow (all contained in namespace):
#   Test Cursor → iptables REDIRECT → cursor-proxy → real Cursor API
#   Main Cursor → direct to internet (completely unaffected)
#
# Does NOT interfere with: Tailscale, Mullvad VPN, qBittorrent, etc.
# because all proxy activity happens in an isolated network namespace.

{ config, lib, pkgs, ... }:

let
  cfg = config.services.cursor-proxy-isolated;
  
  # Network namespace configuration
  nsName = "cursor-test";
  vethHost = "veth-cproxy0";
  vethNs = "veth-cproxy1";
  hostIP = "10.200.1.1";
  nsIP = "10.200.1.2";
  subnet = "10.200.1.0/24";
  
  # Proxy configuration
  proxyPort = cfg.proxyPort;
  
  # Build cursor-proxy from source
  cursor-proxy = cfg.package;
  
  # Script to set up the network namespace (run on host)
  setup-namespace = pkgs.writeShellScript "cursor-proxy-setup-ns" ''
    set -euo pipefail
    
    NS="${nsName}"
    VETH_HOST="${vethHost}"
    VETH_NS="${vethNs}"
    HOST_IP="${hostIP}"
    NS_IP="${nsIP}"
    
    # Check if namespace already exists
    if ip netns list | grep -q "^$NS"; then
      echo "Namespace $NS already exists"
      exit 0
    fi
    
    echo "Creating network namespace: $NS"
    
    # Create namespace
    ip netns add "$NS"
    
    # Create veth pair
    ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
    
    # Move one end to namespace
    ip link set "$VETH_NS" netns "$NS"
    
    # Configure host side
    ip addr add "$HOST_IP/24" dev "$VETH_HOST"
    ip link set "$VETH_HOST" up
    
    # Configure namespace side
    ip netns exec "$NS" ip addr add "$NS_IP/24" dev "$VETH_NS"
    ip netns exec "$NS" ip link set "$VETH_NS" up
    ip netns exec "$NS" ip link set lo up
    
    # Set default route in namespace to go through host
    ip netns exec "$NS" ip route add default via "$HOST_IP"
    
    # Enable IP forwarding on host (for namespace internet access)
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # NAT for namespace traffic going to internet (through host)
    # Use specific interface to avoid touching Mullvad/Tailscale
    iptables -t nat -A POSTROUTING -s ${subnet} -o "$VETH_HOST" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s ${subnet} ! -d ${subnet} -j MASQUERADE
    
    # Allow forwarding for namespace traffic
    iptables -A FORWARD -i "$VETH_HOST" -j ACCEPT
    iptables -A FORWARD -o "$VETH_HOST" -j ACCEPT
    
    echo "Namespace $NS configured successfully"
    echo "  Host: $VETH_HOST ($HOST_IP)"
    echo "  NS:   $VETH_NS ($NS_IP)"
    echo ""
    echo "Namespace has internet access through host."
    echo "Main system VPN/Tailscale unaffected."
  '';
  
  # Script to set up iptables REDIRECT inside the namespace
  setup-namespace-iptables = pkgs.writeShellScript "cursor-proxy-setup-ns-iptables" ''
    set -euo pipefail
    
    PROXY_PORT="${toString proxyPort}"
    
    echo "Setting up transparent proxy redirect in namespace..."
    
    # Redirect all outgoing port 443 traffic to local proxy
    # This uses REDIRECT which works with SO_ORIGINAL_DST
    iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port "$PROXY_PORT"
    
    # Also catch port 80 for any HTTP redirects
    iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port "$PROXY_PORT"
    
    echo "Transparent redirect active:"
    echo "  Port 443 → localhost:$PROXY_PORT"
    echo "  Port 80  → localhost:$PROXY_PORT"
  '';
  
  # Script to tear down the namespace
  teardown-namespace = pkgs.writeShellScript "cursor-proxy-teardown-ns" ''
    set -euo pipefail
    
    NS="${nsName}"
    VETH_HOST="${vethHost}"
    
    echo "Tearing down namespace: $NS"
    
    # Remove iptables rules (best effort)
    iptables -t nat -D POSTROUTING -s ${subnet} -o "$VETH_HOST" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s ${subnet} ! -d ${subnet} -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$VETH_HOST" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o "$VETH_HOST" -j ACCEPT 2>/dev/null || true
    
    # Delete namespace (also removes veth pair and namespace iptables)
    ip netns del "$NS" 2>/dev/null || true
    
    # Clean up any orphaned veth
    ip link del "$VETH_HOST" 2>/dev/null || true
    
    echo "Namespace $NS removed"
  '';
  
  # Script to run the proxy inside the namespace
  run-proxy-in-ns = pkgs.writeShellScript "cursor-proxy-run-in-ns" ''
    set -euo pipefail
    
    NS="${nsName}"
    CA_DIR="${cfg.caDir}"
    CAPTURE_DIR="${cfg.captureDir}"
    PROXY_PORT="${toString proxyPort}"
    
    # Ensure CA exists
    if [ ! -f "$CA_DIR/ca-cert.pem" ]; then
      echo "Generating CA certificate..."
      ${cursor-proxy}/bin/cursor-proxy generate-ca --output "$CA_DIR"
    fi
    
    echo "Starting cursor-proxy in namespace $NS..."
    
    # Run proxy inside the namespace
    exec ip netns exec "$NS" ${cursor-proxy}/bin/cursor-proxy start \
      --port "$PROXY_PORT" \
      --ca-cert "$CA_DIR/ca-cert.pem" \
      --ca-key "$CA_DIR/ca-key.pem" \
      --capture-dir "$CAPTURE_DIR" \
      --verbose
  '';
  
  # Wrapper script to run Cursor in the namespace
  cursor-test-wrapper = pkgs.writeShellScriptBin "cursor-test" ''
    #!/usr/bin/env bash
    #
    # Run Cursor in isolated network namespace with transparent proxy
    #
    # Usage:
    #   cursor-test [workspace]           # Run with proxy
    #   cursor-test --no-proxy [workspace] # Run isolated without proxy
    #   cursor-test --status              # Show status
    #   cursor-test --start-proxy         # Start proxy service manually
    #   cursor-test --help                # Show help
    
    set -euo pipefail
    
    NS="${nsName}"
    NS_IP="${nsIP}"
    HOST_IP="${hostIP}"
    PROXY_PORT="${toString proxyPort}"
    DATA_DIR="$HOME/.cursor-test-isolated"
    CA_DIR="${cfg.caDir}"
    
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
    
    log_info() { echo -e "''${BLUE}[cursor-test]''${NC} $1"; }
    log_ok() { echo -e "''${GREEN}[✓]''${NC} $1"; }
    log_warn() { echo -e "''${YELLOW}[!]''${NC} $1"; }
    log_error() { echo -e "''${RED}[✗]''${NC} $1"; }
    
    show_help() {
      echo -e "''${CYAN}╔══════════════════════════════════════════════════════════════╗''${NC}"
      echo -e "''${CYAN}║          cursor-test - Isolated Proxy Environment            ║''${NC}"
      echo -e "''${CYAN}╚══════════════════════════════════════════════════════════════╝''${NC}"
      echo ""
      echo "Usage:"
      echo "  cursor-test [workspace]        Run Cursor with transparent proxy"
      echo "  cursor-test --no-proxy [ws]    Run in namespace without proxy"
      echo "  cursor-test --status           Show namespace and proxy status"
      echo "  cursor-test --start-proxy      Manually start proxy in namespace"
      echo "  cursor-test --logs             View proxy logs"
      echo "  cursor-test --cleanup          Remove isolated data directory"
      echo "  cursor-test --help             Show this help"
      echo ""
      echo "Configuration:"
      echo "  Namespace: $NS"
      echo "  Data dir:  $DATA_DIR"
      echo "  CA cert:   $CA_DIR/ca-cert.pem"
      echo "  Proxy:     localhost:$PROXY_PORT (inside namespace)"
      echo ""
      echo -e "''${GREEN}Your main Cursor and system VPN are NOT affected.''${NC}"
      echo "All proxy activity is isolated in a network namespace."
    }
    
    show_status() {
      echo -e "''${CYAN}╔══════════════════════════════════════════════════════════════╗''${NC}"
      echo -e "''${CYAN}║           CURSOR ISOLATED TEST ENVIRONMENT                   ║''${NC}"
      echo -e "''${CYAN}╠══════════════════════════════════════════════════════════════╣''${NC}"
      
      # Check namespace
      if ip netns list 2>/dev/null | grep -q "^$NS"; then
        echo -e "║ ''${GREEN}✓''${NC} Namespace: $NS (active)                                 ║"
        
        # Check namespace connectivity
        if sudo ip netns exec "$NS" ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
          echo -e "║ ''${GREEN}✓''${NC} Namespace internet: working                             ║"
        else
          echo -e "║ ''${RED}✗''${NC} Namespace internet: no connectivity                     ║"
        fi
        
        # Check iptables rules in namespace
        local redirect_count=$(sudo ip netns exec "$NS" iptables -t nat -L OUTPUT -n 2>/dev/null | grep -c "REDIRECT" || echo 0)
        if [ "$redirect_count" -gt 0 ]; then
          echo -e "║ ''${GREEN}✓''${NC} Transparent redirect: active ($redirect_count rules)             ║"
        else
          echo -e "║ ''${YELLOW}!''${NC} Transparent redirect: not configured                   ║"
        fi
      else
        echo -e "║ ''${RED}✗''${NC} Namespace: $NS (not created)                            ║"
      fi
      
      # Check proxy service
      if systemctl is-active cursor-proxy-isolated.service &>/dev/null; then
        echo -e "║ ''${GREEN}✓''${NC} Proxy service: running                                   ║"
      else
        echo -e "║ ''${RED}✗''${NC} Proxy service: not running                               ║"
      fi
      
      # Check CA certificate
      if [[ -f "$CA_DIR/ca-cert.pem" ]]; then
        echo -e "║ ''${GREEN}✓''${NC} CA certificate: present                                  ║"
      else
        echo -e "║ ''${YELLOW}!''${NC} CA certificate: not generated yet                       ║"
      fi
      
      # Check data directory
      if [[ -d "$DATA_DIR" ]]; then
        local size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
        echo -e "║ ''${GREEN}✓''${NC} Data directory: $size                                   ║"
      else
        echo -e "║ ''${YELLOW}!''${NC} Data directory: not created yet                         ║"
      fi
      
      # Check main system VPN
      if ip link show mullvad &>/dev/null 2>&1 || ip link show wg0 &>/dev/null 2>&1; then
        echo -e "║ ''${GREEN}✓''${NC} System VPN: detected (unaffected)                        ║"
      fi
      
      if tailscale status &>/dev/null 2>&1; then
        echo -e "║ ''${GREEN}✓''${NC} Tailscale: connected (unaffected)                        ║"
      fi
      
      echo -e "''${CYAN}╚══════════════════════════════════════════════════════════════╝''${NC}"
      
      # Show recent proxy logs if available
      if systemctl is-active cursor-proxy-isolated.service &>/dev/null; then
        echo ""
        echo -e "''${BLUE}Recent proxy activity:''${NC}"
        journalctl -u cursor-proxy-isolated.service -n 10 --no-pager 2>/dev/null || true
      fi
    }
    
    show_logs() {
      journalctl -u cursor-proxy-isolated.service -f
    }
    
    cleanup_data() {
      if [[ -d "$DATA_DIR" ]]; then
        log_warn "This will delete: $DATA_DIR"
        read -p "Are you sure? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
          rm -rf "$DATA_DIR"
          log_ok "Data directory removed"
        fi
      else
        log_info "No data directory to clean"
      fi
    }
    
    start_proxy_manual() {
      log_info "Starting proxy service..."
      sudo systemctl start cursor-proxy-ns-setup.service
      sudo systemctl start cursor-proxy-isolated.service
      log_ok "Proxy started. Check status with: cursor-test --status"
    }
    
    run_cursor() {
      local use_proxy=true
      local workspace=""
      
      # Parse args
      while [[ $# -gt 0 ]]; do
        case $1 in
          --no-proxy) use_proxy=false; shift ;;
          *) workspace="$1"; shift ;;
        esac
      done
      
      # Check namespace exists
      if ! ip netns list 2>/dev/null | grep -q "^$NS"; then
        log_error "Namespace $NS not found"
        log_info "Starting namespace setup..."
        sudo systemctl start cursor-proxy-ns-setup.service
        sleep 1
      fi
      
      # Check proxy service if using proxy
      if $use_proxy; then
        if ! systemctl is-active cursor-proxy-isolated.service &>/dev/null; then
          log_info "Starting proxy service..."
          sudo systemctl start cursor-proxy-isolated.service
          sleep 2
        fi
      fi
      
      # Create data directory
      mkdir -p "$DATA_DIR"
      
      # Copy auth from main Cursor if needed
      if [[ ! -f "$DATA_DIR/User/globalStorage/state.vscdb" ]]; then
        log_info "First run - copying auth from main Cursor..."
        mkdir -p "$DATA_DIR/User/globalStorage"
        if [[ -f "$HOME/.config/Cursor/User/globalStorage/state.vscdb" ]]; then
          # Extract just auth tokens (not entire database)
          ${pkgs.sqlite}/bin/sqlite3 "$HOME/.config/Cursor/User/globalStorage/state.vscdb" \
            ".dump ItemTable" 2>/dev/null | grep -E "cursorAuth" | \
          ${pkgs.sqlite}/bin/sqlite3 "$DATA_DIR/User/globalStorage/state.vscdb" 2>/dev/null || true
          
          if [[ -f "$DATA_DIR/User/globalStorage/state.vscdb" ]]; then
            log_ok "Auth tokens copied"
          else
            log_warn "Could not copy auth - you may need to login"
          fi
        else
          log_warn "No main Cursor auth found - you'll need to login"
        fi
      fi
      
      echo ""
      echo -e "''${CYAN}╔══════════════════════════════════════════════════════════════╗''${NC}"
      echo -e "''${CYAN}║              Starting Cursor in Isolated Mode                ║''${NC}"
      echo -e "''${CYAN}╚══════════════════════════════════════════════════════════════╝''${NC}"
      log_info "Namespace: $NS"
      log_info "Data dir:  $DATA_DIR"
      
      if $use_proxy; then
        log_info "Proxy:     TRANSPARENT (port 443 redirected)"
        log_info "CA cert:   $CA_DIR/ca-cert.pem"
        
        # Trust CA for Node.js/Electron
        export NODE_EXTRA_CA_CERTS="$CA_DIR/ca-cert.pem"
      else
        log_warn "Proxy:     DISABLED (--no-proxy)"
      fi
      
      echo ""
      log_ok "Launching Cursor..."
      echo ""
      
      # Run Cursor inside the namespace
      # sudo to enter namespace, then drop back to user
      sudo ip netns exec "$NS" sudo -u "$USER" \
        env HOME="$HOME" \
        DISPLAY="''${DISPLAY:-}" \
        WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-}" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        NODE_EXTRA_CA_CERTS="''${NODE_EXTRA_CA_CERTS:-}" \
        cursor --user-data-dir="$DATA_DIR" $workspace
    }
    
    # Main
    case "''${1:-}" in
      --help|-h) show_help ;;
      --status) show_status ;;
      --logs) show_logs ;;
      --cleanup) cleanup_data ;;
      --start-proxy) start_proxy_manual ;;
      *) run_cursor "$@" ;;
    esac
  '';

in {
  options.services.cursor-proxy-isolated = {
    enable = lib.mkEnableOption "Isolated Cursor proxy testing environment";
    
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../tools/proxy-test/cursor-proxy { };
      description = "The cursor-proxy package to use";
    };
    
    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Port for the proxy to listen on (inside namespace)";
    };
    
    caDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cursor-proxy";
      description = "Directory for CA certificates";
    };
    
    captureDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cursor-proxy/captures";
      description = "Directory for captured traffic";
    };
    
    user = lib.mkOption {
      type = lib.types.str;
      default = "e421";
      description = "User who will run cursor-test";
    };
  };
  
  config = lib.mkIf cfg.enable {
    # Install the cursor-test wrapper
    environment.systemPackages = [ cursor-test-wrapper ];
    
    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.caDir} 0755 root root -"
      "d ${cfg.captureDir} 0755 ${cfg.user} users -"
    ];
    
    # Service to set up network namespace (one-shot, remains after exit)
    systemd.services.cursor-proxy-ns-setup = {
      description = "Set up network namespace for Cursor proxy testing";
      after = [ "network.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setup-namespace;
        ExecStartPost = "${pkgs.bash}/bin/bash -c 'ip netns exec ${nsName} ${setup-namespace-iptables}'";
        ExecStop = teardown-namespace;
      };
    };
    
    # The proxy service runs INSIDE the namespace
    systemd.services.cursor-proxy-isolated = {
      description = "Cursor AI Transparent Proxy (in namespace)";
      after = [ "network.target" "cursor-proxy-ns-setup.service" ];
      requires = [ "cursor-proxy-ns-setup.service" ];
      # Don't auto-start - user starts via cursor-test
      # wantedBy = [ "multi-user.target" ];
      
      environment = {
        RUST_LOG = "info,cursor_proxy=debug";
      };
      
      # Generate CA cert if missing
      preStart = ''
        if [ ! -f "${cfg.caDir}/ca-cert.pem" ]; then
          echo "Generating CA certificate..."
          ${cursor-proxy}/bin/cursor-proxy generate-ca --output "${cfg.caDir}"
          chown ${cfg.user}:users "${cfg.caDir}/ca-cert.pem" "${cfg.caDir}/ca-key.pem"
          chmod 644 "${cfg.caDir}/ca-cert.pem"
          chmod 600 "${cfg.caDir}/ca-key.pem"
        fi
      '';
      
      serviceConfig = {
        Type = "simple";
        ExecStart = run-proxy-in-ns;
        Restart = "on-failure";
        RestartSec = "5s";
        
        # Must run as root for namespace access
        User = "root";
        
        # Security hardening
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [ cfg.caDir cfg.captureDir ];
        PrivateTmp = true;
      };
    };
    
    # Allow user to manage these services without password
    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          {
            command = "/run/current-system/sw/bin/ip netns exec ${nsName} *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl start cursor-proxy-ns-setup.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl stop cursor-proxy-ns-setup.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl start cursor-proxy-isolated.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl stop cursor-proxy-isolated.service";
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/systemctl restart cursor-proxy-isolated.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
