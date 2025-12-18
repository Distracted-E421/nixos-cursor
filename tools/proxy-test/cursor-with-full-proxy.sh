#!/bin/bash
# Launch Cursor with FULL proxy support (Chromium + Node.js)
# 
# The problem: Cursor has two network stacks
#   - Chromium: respects --proxy-server
#   - Node.js: ignores --proxy-server, needs env vars
#
# This script forces BOTH to use the proxy.

set -euo pipefail

PROXY_HOST="127.0.0.1"
PROXY_PORT="8080"
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"

# Ensure mitmproxy CA exists
if [ ! -f "$HOME/.mitmproxy/mitmproxy-ca-cert.pem" ]; then
    echo "❌ mitmproxy CA not found!"
    echo "Run mitmproxy once to generate it, or run run_test.sh first."
    exit 1
fi

# Handle options
KILL_EXISTING=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --kill)
            KILL_EXISTING=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Check if Cursor app is already running
# Exclude false positives: cursor-docs, mitmproxy scripts, grep itself
CURSOR_RUNNING=$(pgrep -f "cursor-[0-9].*share/cursor/cursor" 2>/dev/null | head -1 || true)

if [[ -n "$CURSOR_RUNNING" ]]; then
    if [[ "$KILL_EXISTING" == "true" ]]; then
        echo "🔄 Killing existing Cursor instances..."
        # Kill the main process tree
        pkill -9 -f "cursor-[0-9].*share/cursor/cursor" 2>/dev/null || true
        sleep 2
    else
        echo "⚠️  Cursor is already running! (PID: $CURSOR_RUNNING)"
        echo ""
        echo "Options:"
        echo "  1. Close Cursor manually (Ctrl+Q), then run this script again"
        echo "  2. Run with --kill flag: $0 --kill"
        echo "     (⚠️  Don't run --kill from Cursor's integrated terminal!)"
        echo ""
        echo "For safest testing, run from Konsole/Kitty AFTER closing Cursor."
        exit 1
    fi
fi

echo "🚀 Launching Cursor with full proxy support..."
echo "   Proxy: $PROXY_URL"
echo ""

# Environment variables for Node.js proxy support
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"

# Tell Node.js to accept the proxy's certificate
export NODE_TLS_REJECT_UNAUTHORIZED=0
export NODE_EXTRA_CA_CERTS="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"

# Additional SSL/TLS settings
export SSL_CERT_FILE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
export REQUESTS_CA_BUNDLE="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"

# Electron-specific proxy settings
export ELECTRON_GET_USE_PROXY=1

# Launch Cursor with Chromium proxy flags (for the renderer)
cursor \
    --proxy-server="$PROXY_URL" \
    --ignore-certificate-errors \
    "$@" &

CURSOR_PID=$!
echo "✅ Cursor launched (PID: $CURSOR_PID)"
echo ""
echo "🔍 Monitoring proxy traffic..."
echo "   Log file: /tmp/proxy.log"
echo ""
echo "To verify AI streaming is captured:"
echo "   tail -f /tmp/proxy.log | grep -E 'Stream|Chat|Conversation'"
echo ""
echo "Press Ctrl+C to exit (Cursor will keep running)"

# Wait for user interrupt
wait $CURSOR_PID 2>/dev/null || true

