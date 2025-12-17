#!/usr/bin/env bash
# Launch Cursor with proxy settings for interception testing
# Usage: ./cursor-with-proxy.sh [--no-cert-check]

PROXY_PORT="${PROXY_PORT:-8080}"
PROXY_URL="http://127.0.0.1:$PROXY_PORT"

echo "🔌 Launching Cursor with proxy: $PROXY_URL"
echo ""

# Check if proxy is running
if ! nc -z 127.0.0.1 $PROXY_PORT 2>/dev/null; then
    echo "⚠️  Warning: No proxy detected on port $PROXY_PORT"
    echo "   Start the proxy first: ./run_test.sh"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build command based on options
CURSOR_ARGS=(
    "--proxy-server=$PROXY_URL"
)

# Add cert bypass if requested or by default for testing
if [[ "$1" == "--no-cert-check" ]] || [[ -z "$1" ]]; then
    CURSOR_ARGS+=("--ignore-certificate-errors")
    echo "   Certificate verification: DISABLED (for testing)"
else
    echo "   Certificate verification: ENABLED"
fi

echo "   Proxy: $PROXY_URL"
echo ""

# Also set environment variables for any Node.js subprocesses
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export NODE_TLS_REJECT_UNAUTHORIZED=0

echo "Launching: cursor ${CURSOR_ARGS[*]}"
echo ""

exec cursor "${CURSOR_ARGS[@]}" "$@"

