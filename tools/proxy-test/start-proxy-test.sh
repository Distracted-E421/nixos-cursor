#!/usr/bin/env bash
# Cursor AI Proxy Testing Quick Start
# Usage: ./start-proxy-test.sh [workspace_path]

set -e

WORKSPACE="${1:-/home/e421/homelab}"
PROXY_DIR="$(dirname "$0")/cursor-proxy"
PROXY_LOG="/tmp/cursor-proxy.log"

echo "🚀 Cursor AI Proxy Test Environment"
echo "===================================="
echo "Workspace: $WORKSPACE"
echo ""

# Check if proxy is running
if ss -tlnp | grep -q ":8443"; then
    echo "✅ Proxy already running on port 8443"
else
    echo "🔧 Starting proxy..."
    pkill -f "cursor-proxy start" 2>/dev/null || true
    sleep 1
    
    cd "$PROXY_DIR"
    nohup ./target/release/cursor-proxy start \
        --port 8443 \
        --verbose \
        --inject \
        --inject-prompt "INJECTED CONTEXT: You are being tested through a transparent proxy." \
        > "$PROXY_LOG" 2>&1 &
    sleep 2
    
    if ss -tlnp | grep -q ":8443"; then
        echo "✅ Proxy started (log: $PROXY_LOG)"
    else
        echo "❌ Failed to start proxy. Check $PROXY_LOG"
        exit 1
    fi
fi

echo ""
echo "🖥️  Launching Cursor in namespace..."
echo "   Workspace: $WORKSPACE"
echo ""

# Launch Cursor
sudo ip netns exec cursor-proxy-ns sudo -u e421 \
    DISPLAY=:0 \
    WAYLAND_DISPLAY=wayland-0 \
    XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    SSL_CERT_FILE=/home/e421/.cursor-proxy/ca-bundle-with-proxy.pem \
    NODE_EXTRA_CA_CERTS=/home/e421/.cursor-proxy/ca-cert.pem \
    cursor "$WORKSPACE" &

echo ""
echo "📊 Monitor proxy with: tail -f $PROXY_LOG"
echo "🛑 Stop proxy with: pkill -f \"cursor-proxy start\""
