#!/usr/bin/env bash
# Test script for capturing Cursor traffic through the proxy
#
# This script:
# 1. Initializes the proxy if needed
# 2. Starts the proxy in capture mode (no injection)
# 3. Temporarily enables hosts redirect
# 4. Captures traffic
# 5. Restores hosts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_BIN="$SCRIPT_DIR/target/release/cursor-proxy"
CAPTURE_DIR="$HOME/.cursor-proxy/captures"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}    Cursor Proxy Traffic Capture Test${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""

# Check if proxy binary exists
if [ ! -f "$PROXY_BIN" ]; then
    echo -e "${RED}Error: Proxy binary not found. Build with: cargo build --release${NC}"
    exit 1
fi

# Initialize proxy if needed
if [ ! -f "$HOME/.cursor-proxy/ca-cert.pem" ]; then
    echo -e "${YELLOW}Initializing proxy (generating CA)...${NC}"
    $PROXY_BIN init
    echo ""
fi

# Disable injection for pure capture
echo -e "${YELLOW}Disabling injection for pure capture mode...${NC}"
$PROXY_BIN inject disable 2>/dev/null || true

# Show status
echo ""
echo -e "${GREEN}Proxy Status:${NC}"
$PROXY_BIN status || true

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}IMPORTANT: Before proceeding, you need to:${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo "1. Trust the CA certificate:"
echo "   $PROXY_BIN trust-ca"
echo ""
echo "2. Add hosts entry (requires sudo):"
echo "   sudo sh -c 'echo \"127.0.0.1 api2.cursor.sh\" >> /etc/hosts'"
echo ""
echo "3. Start the proxy:"
echo "   $PROXY_BIN start --dns-mode"
echo ""
echo "4. In another terminal, make a request in Cursor"
echo ""
echo "5. Check captures:"
echo "   ls -la $CAPTURE_DIR"
echo "   cat $CAPTURE_DIR/*.json | jq ."
echo ""
echo "6. When done, remove hosts entry:"
echo "   sudo sed -i '/api2.cursor.sh/d' /etc/hosts"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"

# Optional: Start proxy in foreground if requested
if [ "$1" == "--start" ]; then
    echo ""
    echo -e "${GREEN}Starting proxy in foreground...${NC}"
    echo "Press Ctrl+C to stop"
    echo ""
    $PROXY_BIN start --dns-mode --foreground
fi

