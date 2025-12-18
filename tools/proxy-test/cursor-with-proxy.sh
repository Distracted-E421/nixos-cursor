#!/usr/bin/env bash
# Launch Cursor with our proxy CA trusted
#
# Usage:
#   ./cursor-with-proxy.sh start   # Start proxy + iptables + Cursor
#   ./cursor-with-proxy.sh stop    # Stop proxy + cleanup iptables
#   ./cursor-with-proxy.sh status  # Show status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_BIN="$SCRIPT_DIR/cursor-proxy/target/release/cursor-proxy"
CA_CERT="$HOME/.cursor-proxy/ca-cert.pem"
PROXY_PORT=8443
PID_FILE="/tmp/cursor-proxy.pid"
LOG_FILE="/tmp/cursor-proxy.log"
CAPTURE_DIR="$SCRIPT_DIR/rust-captures"

log() { echo -e "\033[0;34m[*]\033[0m $1"; }
success() { echo -e "\033[0;32m[✓]\033[0m $1"; }
error() { echo -e "\033[0;31m[✗]\033[0m $1"; }
warn() { echo -e "\033[0;33m[!]\033[0m $1"; }

setup_iptables() {
    log "Setting up iptables rules..."
    
    for ip in $(dig +short api2.cursor.sh 2>/dev/null | grep -E '^[0-9]'); do
        sudo iptables -t nat -C OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT 2>/dev/null || \
        sudo iptables -t nat -A OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT
        log "  Added rule for $ip"
    done
    
    success "iptables configured"
}

cleanup_iptables() {
    log "Cleaning up iptables rules..."
    
    # Remove rules for current DNS IPs
    for ip in $(dig +short api2.cursor.sh 2>/dev/null | grep -E '^[0-9]'); do
        sudo iptables -t nat -D OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT 2>/dev/null || true
    done
    
    # Also remove ANY lingering rules pointing to our proxy port
    # (DNS IPs can change, leaving stale rules)
    for ip in $(sudo iptables -t nat -L OUTPUT -n 2>/dev/null | grep "$PROXY_PORT" | awk '{print $5}'); do
        sudo iptables -t nat -D OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT 2>/dev/null || true
    done
    
    success "iptables cleaned"
}

start_proxy() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        warn "Proxy already running (PID: $(cat "$PID_FILE"))"
        return 0
    fi
    
    log "Starting Cursor proxy..."
    
    mkdir -p "$CAPTURE_DIR"
    
    "$PROXY_BIN" start \
        --port $PROXY_PORT \
        --verbose \
        --capture-dir "$CAPTURE_DIR" \
        > "$LOG_FILE" 2>&1 &
    
    local pid=$!
    echo $pid > "$PID_FILE"
    
    sleep 1
    if kill -0 $pid 2>/dev/null; then
        success "Proxy started (PID: $pid)"
        success "Logs: $LOG_FILE"
        success "Captures: $CAPTURE_DIR"
    else
        error "Proxy failed to start"
        cat "$LOG_FILE"
        return 1
    fi
}

stop_proxy() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping proxy (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
            success "Proxy stopped"
        fi
        rm -f "$PID_FILE"
    fi
}

start_cursor() {
    log "Starting Cursor with proxy CA..."
    
    # Trust our CA via environment variable
    export NODE_EXTRA_CA_CERTS="$CA_CERT"
    
    # Also try to pass to Electron
    export SSL_CERT_FILE="$CA_CERT"
    export REQUESTS_CA_BUNDLE="$CA_CERT"
    
    log "Launching Cursor..."
    log "  NODE_EXTRA_CA_CERTS=$CA_CERT"
    
    # Launch Cursor in background
    cursor "$@" &
    
    success "Cursor launched"
    echo ""
    echo "📊 Monitor proxy logs with:"
    echo "   tail -f $LOG_FILE"
    echo ""
    echo "📦 Captured streams in:"
    echo "   $CAPTURE_DIR"
}

status() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║             CURSOR PROXY STATUS                                ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    
    # Proxy status
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "║ ✅ Proxy: Running (PID: $(cat "$PID_FILE"))                        ║"
    else
        echo "║ ❌ Proxy: Not running                                          ║"
    fi
    
    # CA certificate
    if [[ -f "$CA_CERT" ]]; then
        echo "║ ✅ CA Certificate: $CA_CERT         ║"
    else
        echo "║ ❌ CA Certificate: Not found                                   ║"
    fi
    
    # iptables
    local rule_count=$(sudo iptables -t nat -L OUTPUT -n 2>/dev/null | grep -c ":$PROXY_PORT" || echo 0)
    echo "║ 📡 iptables rules: $rule_count                                        ║"
    
    # Captures
    if [[ -d "$CAPTURE_DIR" ]]; then
        local capture_count=$(find "$CAPTURE_DIR" -name "*.bin" 2>/dev/null | wc -l)
        echo "║ 📦 Captured streams: $capture_count                                     ║"
    fi
    
    echo "╚════════════════════════════════════════════════════════════════╝"
    
    echo ""
    echo "Recent log entries:"
    tail -10 "$LOG_FILE" 2>/dev/null || echo "No logs yet"
}

case "${1:-}" in
    start)
        start_proxy
        setup_iptables
        shift || true
        start_cursor "$@"
        ;;
    stop)
        stop_proxy
        cleanup_iptables
        ;;
    status)
        status
        ;;
    proxy-only)
        start_proxy
        setup_iptables
        echo ""
        echo "Proxy running. Start Cursor manually with:"
        echo "  NODE_EXTRA_CA_CERTS=$CA_CERT cursor"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|proxy-only}"
        echo ""
        echo "Commands:"
        echo "  start      - Start proxy, iptables, and Cursor"
        echo "  stop       - Stop proxy and cleanup iptables"
        echo "  status     - Show current status"
        echo "  proxy-only - Start proxy without launching Cursor"
        exit 1
        ;;
esac
