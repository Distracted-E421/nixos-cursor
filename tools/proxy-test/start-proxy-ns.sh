#!/usr/bin/env bash
# Cursor Proxy - Network Namespace Setup & Launch
# Usage: ./start-proxy-ns.sh [workspace-path]

set -e
WORKSPACE="${1:-/home/e421/nixos-cursor}"
PROXY_PORT=8443
PROXY_HOST="10.200.1.1"
NS_NAME="cursor-proxy-ns"
NS_IP="10.200.1.2"
USER_ID=$(id -u)
USER_NAME=$(whoami)

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; NC="\033[0m"
echo -e "${GREEN}=== Cursor Proxy Namespace Setup ===${NC}"

# Check proxy
if ! ss -tlnp | grep -q ":$PROXY_PORT"; then
    echo -e "${RED}Error: Proxy not running on port $PROXY_PORT${NC}"
    echo "Start it first: ./target/release/cursor-proxy start --port $PROXY_PORT --verbose"
    exit 1
fi
echo -e "${GREEN}✓ Proxy running on port $PROXY_PORT${NC}"

# Create namespace if needed
if ! sudo ip netns list | grep -q "^$NS_NAME"; then
    echo -e "${YELLOW}Creating network namespace...${NC}"
    sudo ip netns add $NS_NAME
    sudo ip link add veth-host type veth peer name veth-ns
    sudo ip link set veth-ns netns $NS_NAME
    sudo ip addr add $PROXY_HOST/24 dev veth-host 2>/dev/null || true
    sudo ip link set veth-host up
    sudo ip netns exec $NS_NAME ip addr add $NS_IP/24 dev veth-ns
    sudo ip netns exec $NS_NAME ip link set veth-ns up
    sudo ip netns exec $NS_NAME ip link set lo up
    sudo ip netns exec $NS_NAME ip route add default via $PROXY_HOST
    sudo sysctl -qw net.ipv4.ip_forward=1
    sudo iptables -t nat -C POSTROUTING -s 10.200.1.0/24 -j MASQUERADE 2>/dev/null || \
        sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -j MASQUERADE
    echo -e "${GREEN}✓ Namespace created${NC}"
else
    echo -e "${GREEN}✓ Namespace already exists${NC}"
fi

sudo ip link set veth-host up 2>/dev/null || true
sudo ip netns exec $NS_NAME ip link set veth-ns up 2>/dev/null || true

# iptables DNAT
sudo ip netns exec $NS_NAME iptables -t nat -F OUTPUT 2>/dev/null || true
sudo ip netns exec $NS_NAME iptables -t nat -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination $PROXY_HOST:$PROXY_PORT
sudo iptables -C nixos-fw -s 10.200.1.0/24 -p tcp --dport $PROXY_PORT -j nixos-fw-accept 2>/dev/null || \
    sudo iptables -I nixos-fw -s 10.200.1.0/24 -p tcp --dport $PROXY_PORT -j nixos-fw-accept
echo -e "${GREEN}✓ iptables configured${NC}"

# DNS
sudo mkdir -p /etc/netns/$NS_NAME
echo "nameserver 1.1.1.1" | sudo tee /etc/netns/$NS_NAME/resolv.conf > /dev/null

# Launch
echo -e "${GREEN}=== Launching Cursor ===${NC}"
echo -e "Workspace: ${YELLOW}$WORKSPACE${NC}"

sudo ip netns exec $NS_NAME sudo -u $USER_NAME \
    DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$USER_ID \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$USER_ID/bus \
    SSL_CERT_FILE=/home/$USER_NAME/.cursor-proxy/ca-bundle-with-proxy.pem \
    NODE_EXTRA_CA_CERTS=/home/$USER_NAME/.cursor-proxy/ca-cert.pem \
    cursor "$WORKSPACE" &

echo "Monitor: tail -f /tmp/cursor-proxy.log"
