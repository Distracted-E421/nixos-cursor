#!/usr/bin/env bash
# Cursor Proxy Interception Test
# Tests if we can intercept Cursor's API traffic

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_PORT=8080
CA_DIR="$HOME/.mitmproxy"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Cursor Streaming Proxy Interception Test           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check mitmproxy
if ! command -v mitmdump &> /dev/null; then
    echo "❌ mitmproxy not found. Install with: nix shell nixpkgs#mitmproxy"
    exit 1
fi

echo "Step 1: Checking CA certificate..."
if [ ! -f "$CA_DIR/mitmproxy-ca-cert.pem" ]; then
    echo "   Generating CA certificate (first-time setup)..."
    timeout 3 mitmdump -p $PROXY_PORT &>/dev/null &
    sleep 2
    kill %1 2>/dev/null || true
fi

if [ -f "$CA_DIR/mitmproxy-ca-cert.pem" ]; then
    echo "   ✅ CA certificate exists at: $CA_DIR/mitmproxy-ca-cert.pem"
else
    echo "   ⚠️  CA certificate not found. Will be generated on first run."
fi

echo ""
echo "Step 2: Starting proxy on port $PROXY_PORT..."
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 INSTRUCTIONS:"
echo ""
echo "   Option A: Launch Cursor with proxy (recommended for testing)"
echo "   ────────────────────────────────────────────────────────────"
echo "   cursor --proxy-server=http://127.0.0.1:$PROXY_PORT --ignore-certificate-errors"
echo ""
echo "   Option B: Use environment variables"
echo "   ────────────────────────────────────────────────────────────"
echo "   HTTP_PROXY=http://127.0.0.1:$PROXY_PORT \\"
echo "   HTTPS_PROXY=http://127.0.0.1:$PROXY_PORT \\"
echo "   NODE_TLS_REJECT_UNAUTHORIZED=0 \\"
echo "   cursor"
echo ""
echo "   Option C: If above fail (certificate pinning), try:"
echo "   ────────────────────────────────────────────────────────────"
echo "   1. Trust the CA system-wide (NixOS):"
echo "      Add to configuration.nix:"
echo "      security.pki.certificateFiles = [ $CA_DIR/mitmproxy-ca-cert.pem ];"
echo ""
echo "   2. Use Electron's built-in bypass:"
echo "      cursor --ignore-certificate-errors"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Press Ctrl+C to stop the proxy."
echo ""

# Run the proxy with our test addon (tee to log file)
echo "📝 Logging to: /tmp/proxy.log"
exec mitmdump -s "$SCRIPT_DIR/test_cursor_proxy.py" -p $PROXY_PORT --ssl-insecure 2>&1 | tee /tmp/proxy.log

