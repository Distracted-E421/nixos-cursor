#!/usr/bin/env bash
#
# Network Namespace Setup for Cursor Proxy Testing
# 
# This script creates an isolated network environment where only
# the Cursor instance running inside the namespace has its traffic
# proxied. All other system traffic is completely unaffected.
#
# Usage:
#   ./setup-network-namespace.sh setup     # Create namespace and configure
#   ./setup-network-namespace.sh teardown  # Clean up everything
#   ./setup-network-namespace.sh status    # Show current state
#   ./setup-network-namespace.sh run       # Run a command in namespace
#
# See NETWORK_NAMESPACE_SETUP.md for detailed documentation.

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════════

NAMESPACE="cursor-proxy-ns"
VETH_HOST="veth-host"
VETH_NS="veth-proxy"
SUBNET="10.200.1"
HOST_IP="${SUBNET}.1"
NS_IP="${SUBNET}.2"
PROXY_PORT=8443
PROXY_CHAIN="CURSOR_NS_PROXY"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════

log()     { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (or with sudo)"
        exit 1
    fi
}

namespace_exists() {
    # Note: ip netns list may output "name (id: X)" format, so match just the beginning
    ip netns list 2>/dev/null | grep -q "^${NAMESPACE}\( \|$\)"
}

veth_exists() {
    ip link show "$VETH_HOST" &>/dev/null
}

get_default_interface() {
    ip route | grep default | head -1 | awk '{print $5}'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Setup Functions
# ═══════════════════════════════════════════════════════════════════════════════

setup_namespace() {
    log "Creating network namespace: $NAMESPACE"
    
    if namespace_exists; then
        warn "Namespace $NAMESPACE already exists"
        return 0
    fi
    
    ip netns add "$NAMESPACE"
    success "Created namespace: $NAMESPACE"
}

setup_veth() {
    log "Creating virtual ethernet pair: $VETH_HOST <-> $VETH_NS"
    
    if veth_exists; then
        warn "veth pair already exists"
        return 0
    fi
    
    # Create veth pair
    ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
    
    # Move one end to namespace
    ip link set "$VETH_NS" netns "$NAMESPACE"
    
    # Configure host end
    ip addr add "${HOST_IP}/24" dev "$VETH_HOST"
    ip link set "$VETH_HOST" up
    
    # Configure namespace end
    ip netns exec "$NAMESPACE" ip addr add "${NS_IP}/24" dev "$VETH_NS"
    ip netns exec "$NAMESPACE" ip link set "$VETH_NS" up
    ip netns exec "$NAMESPACE" ip link set lo up
    
    success "Created and configured veth pair"
}

setup_routing() {
    log "Configuring routing and NAT"
    
    local default_if
    default_if=$(get_default_interface)
    
    if [[ -z "$default_if" ]]; then
        error "Could not determine default interface"
        return 1
    fi
    
    log "Default interface: $default_if"
    
    # Set default route in namespace
    ip netns exec "$NAMESPACE" ip route add default via "$HOST_IP" 2>/dev/null || true
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    
    # NAT for outgoing traffic from namespace
    if ! iptables -t nat -C POSTROUTING -s "${SUBNET}.0/24" -o "$default_if" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -s "${SUBNET}.0/24" -o "$default_if" -j MASQUERADE
    fi
    
    # Allow forwarding between veth and default interface
    if ! iptables -C FORWARD -i "$VETH_HOST" -o "$default_if" -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i "$VETH_HOST" -o "$default_if" -j ACCEPT
    fi
    
    if ! iptables -C FORWARD -i "$default_if" -o "$VETH_HOST" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -i "$default_if" -o "$VETH_HOST" -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi
    
    success "Routing and NAT configured"
}

setup_dns() {
    log "Configuring DNS for namespace"
    
    local dns_dir="/etc/netns/$NAMESPACE"
    mkdir -p "$dns_dir"
    
    # Use public DNS (Cloudflare + Google)
    cat > "$dns_dir/resolv.conf" << EOF
# DNS for $NAMESPACE
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
EOF
    
    success "DNS configured (1.1.1.1, 8.8.8.8, 9.9.9.9)"
}

setup_proxy_redirect() {
    log "Setting up proxy redirect rules"
    
    # Create our chain if it doesn't exist
    iptables -t nat -N "$PROXY_CHAIN" 2>/dev/null || true
    
    # Flush existing rules in our chain
    iptables -t nat -F "$PROXY_CHAIN"
    
    # SELECTIVE INTERCEPTION: Only intercept Cursor AI API traffic
    # This allows other services (marketplace, GitHub, telemetry) to work normally
    log "Resolving api2.cursor.sh for selective interception..."
    local cursor_ips
    cursor_ips=$(dig +short api2.cursor.sh 2>/dev/null | grep -E '^[0-9]' || echo "")
    
    if [[ -z "$cursor_ips" ]]; then
        warn "Could not resolve api2.cursor.sh - falling back to all HTTPS traffic"
        iptables -t nat -A "$PROXY_CHAIN" -p tcp --dport 443 -j REDIRECT --to-port "$PROXY_PORT"
    else
        local ip_count=0
        for ip in $cursor_ips; do
            iptables -t nat -A "$PROXY_CHAIN" -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port "$PROXY_PORT"
            ((ip_count++)) || true
        done
        log "Added redirect rules for $ip_count Cursor API IPs"
    fi
    
    # Hook into PREROUTING for traffic from namespace
    if ! iptables -t nat -C PREROUTING -i "$VETH_HOST" -j "$PROXY_CHAIN" 2>/dev/null; then
        iptables -t nat -A PREROUTING -i "$VETH_HOST" -j "$PROXY_CHAIN"
    fi
    
    # CRITICAL: Allow traffic to reach the proxy port on the veth interface
    # Without this, NixOS firewall blocks the redirected traffic
    if ! iptables -C INPUT -i "$VETH_HOST" -p tcp --dport "$PROXY_PORT" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -i "$VETH_HOST" -p tcp --dport "$PROXY_PORT" -j ACCEPT
    fi
    
    success "Proxy redirect configured (Cursor API only → $PROXY_PORT on interface $VETH_HOST)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Teardown Functions
# ═══════════════════════════════════════════════════════════════════════════════

teardown_proxy_redirect() {
    log "Removing proxy redirect rules"
    
    # Remove INPUT rule for proxy port
    iptables -D INPUT -i "$VETH_HOST" -p tcp --dport "$PROXY_PORT" -j ACCEPT 2>/dev/null || true
    
    # Remove from PREROUTING
    iptables -t nat -D PREROUTING -i "$VETH_HOST" -j "$PROXY_CHAIN" 2>/dev/null || true
    
    # Flush and delete our chain
    iptables -t nat -F "$PROXY_CHAIN" 2>/dev/null || true
    iptables -t nat -X "$PROXY_CHAIN" 2>/dev/null || true
    
    success "Proxy redirect rules removed"
}

teardown_routing() {
    log "Removing routing and NAT rules"
    
    local default_if
    default_if=$(get_default_interface)
    
    # Remove NAT rule
    iptables -t nat -D POSTROUTING -s "${SUBNET}.0/24" -o "$default_if" -j MASQUERADE 2>/dev/null || true
    
    # Remove forwarding rules
    iptables -D FORWARD -i "$VETH_HOST" -o "$default_if" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$default_if" -o "$VETH_HOST" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    success "Routing rules removed"
}

teardown_veth() {
    log "Removing virtual ethernet pair"
    
    # Deleting host end automatically removes namespace end
    ip link del "$VETH_HOST" 2>/dev/null || true
    
    success "veth pair removed"
}

teardown_namespace() {
    log "Removing network namespace"
    
    ip netns del "$NAMESPACE" 2>/dev/null || true
    
    success "Namespace removed"
}

teardown_dns() {
    log "Removing DNS configuration"
    
    rm -rf "/etc/netns/$NAMESPACE" 2>/dev/null || true
    
    success "DNS configuration removed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Status Function
# ═══════════════════════════════════════════════════════════════════════════════

show_status() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Network Namespace Status${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Namespace
    echo -n "Namespace ($NAMESPACE): "
    if namespace_exists; then
        echo -e "${GREEN}EXISTS${NC}"
    else
        echo -e "${RED}NOT FOUND${NC}"
    fi
    
    # Veth
    echo -n "Veth pair ($VETH_HOST): "
    if veth_exists; then
        echo -e "${GREEN}EXISTS${NC}"
    else
        echo -e "${RED}NOT FOUND${NC}"
    fi
    
    # IP addresses
    if veth_exists; then
        echo ""
        echo "Host IP:      $(ip addr show $VETH_HOST 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo 'N/A')"
    fi
    
    if namespace_exists; then
        echo "Namespace IP: $(ip netns exec $NAMESPACE ip addr show $VETH_NS 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo 'N/A')"
    fi
    
    # iptables
    echo ""
    echo "iptables NAT PREROUTING chain ($PROXY_CHAIN):"
    if iptables -t nat -L "$PROXY_CHAIN" -n 2>/dev/null | grep -q REDIRECT; then
        iptables -t nat -L "$PROXY_CHAIN" -n -v 2>/dev/null | head -5
    else
        echo "  (not configured)"
    fi
    
    # DNS
    echo ""
    echo -n "DNS config: "
    if [[ -f "/etc/netns/$NAMESPACE/resolv.conf" ]]; then
        echo -e "${GREEN}EXISTS${NC}"
        cat "/etc/netns/$NAMESPACE/resolv.conf" | sed 's/^/  /'
    else
        echo -e "${YELLOW}NOT FOUND${NC}"
    fi
    
    # Connectivity test
    if namespace_exists; then
        echo ""
        echo "Connectivity test:"
        echo -n "  Ping 8.8.8.8: "
        if ip netns exec "$NAMESPACE" ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
        
        echo -n "  DNS lookup (google.com): "
        if ip netns exec "$NAMESPACE" nslookup google.com &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi
    
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run Command in Namespace
# ═══════════════════════════════════════════════════════════════════════════════

run_in_namespace() {
    if ! namespace_exists; then
        error "Namespace $NAMESPACE does not exist. Run 'setup' first."
        exit 1
    fi
    
    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(getent passwd "$real_user" | cut -d: -f6)
    
    shift  # Remove 'run' from arguments
    
    if [[ $# -eq 0 ]]; then
        error "Usage: $0 run <command> [args...]"
        echo ""
        echo "Examples:"
        echo "  $0 run bash                    # Interactive shell in namespace"
        echo "  $0 run ping 8.8.8.8            # Test connectivity"
        echo "  $0 run cursor                  # Run Cursor in namespace"
        exit 1
    fi
    
    log "Running in namespace as user '$real_user': $*"
    
    # Run command as original user with proper environment
    ip netns exec "$NAMESPACE" sudo -u "$real_user" \
        HOME="$real_home" \
        USER="$real_user" \
        NODE_EXTRA_CA_CERTS="${real_home}/.cursor-proxy/ca-cert.pem" \
        "$@"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

usage() {
    echo "Network Namespace Setup for Cursor Proxy Testing"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  setup      Create namespace and configure networking"
    echo "  teardown   Remove namespace and all configuration"
    echo "  status     Show current state"
    echo "  run        Run a command inside the namespace"
    echo ""
    echo "Examples:"
    echo "  sudo $0 setup"
    echo "  sudo $0 run cursor"
    echo "  sudo $0 teardown"
    echo ""
    echo "See NETWORK_NAMESPACE_SETUP.md for detailed documentation."
}

main() {
    case "${1:-}" in
        setup)
            check_root
            echo ""
            echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
            echo -e "${BLUE}  Setting Up Network Namespace for Cursor Proxy${NC}"
            echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
            echo ""
            setup_namespace
            setup_veth
            setup_routing
            setup_dns
            setup_proxy_redirect
            echo ""
            success "Network namespace setup complete!"
            echo ""
            echo "Next steps:"
            echo "  1. Start the proxy:    ./cursor-proxy-launcher --test"
            echo "  2. Run Cursor:         sudo $0 run cursor"
            echo "  3. Clean up when done: sudo $0 teardown"
            echo ""
            ;;
        teardown)
            check_root
            echo ""
            echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
            echo -e "${BLUE}  Tearing Down Network Namespace${NC}"
            echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
            echo ""
            teardown_proxy_redirect
            teardown_routing
            teardown_veth
            teardown_namespace
            teardown_dns
            echo ""
            success "Network namespace teardown complete!"
            echo ""
            ;;
        status)
            show_status
            ;;
        run)
            check_root
            run_in_namespace "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

