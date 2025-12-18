#!/usr/bin/env bash
# Payload Collection Script for Cursor API Reverse Engineering
#
# This script sets up iptables rules and starts the payload collector.
# Payloads are saved to payload-db/v{VERSION}/ for analysis.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_PORT=8080
PID_FILE="/tmp/payload_collector.pid"
LOG_FILE="/tmp/payload_collector.log"

# Detect Cursor version
detect_cursor_version() {
    local version
    # Try to get from nix store path
    version=$(readlink -f "$(which cursor)" 2>/dev/null | grep -oP 'cursor-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")
    
    if [[ -z "$version" ]]; then
        # Fallback to checking running process
        version=$(ps aux | grep -oP 'cursor-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
    fi
    
    if [[ -z "$version" ]]; then
        version="unknown"
    fi
    
    echo "$version"
}

CURSOR_VERSION=$(detect_cursor_version)
export CURSOR_VERSION

log() { echo -e "\033[0;34m[*]\033[0m $1"; }
success() { echo -e "\033[0;32m[✓]\033[0m $1"; }
error() { echo -e "\033[0;31m[✗]\033[0m $1"; }
warn() { echo -e "\033[0;33m[!]\033[0m $1"; }

setup_iptables() {
    log "Setting up iptables rules..."
    
    # Get all api2.cursor.sh IPs
    local ips
    ips=$(dig +short api2.cursor.sh 2>/dev/null | grep -E '^[0-9]' || echo "")
    
    for ip in $ips; do
        sudo iptables -t nat -C OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT 2>/dev/null || {
            sudo iptables -t nat -A OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT
            log "  Added rule for $ip"
        }
    done
    
    # Add fallback rule for all :443 from current user
    sudo iptables -t nat -C OUTPUT -p tcp --dport 443 -m owner --uid-owner "$(id -u)" -j REDIRECT --to-port $PROXY_PORT 2>/dev/null || {
        sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$(id -u)" -j REDIRECT --to-port $PROXY_PORT
        log "  Added fallback rule for all :443"
    }
    
    success "iptables rules configured"
}

cleanup_iptables() {
    log "Cleaning up iptables rules..."
    
    # Remove all NAT OUTPUT rules (be careful with this in production!)
    sudo iptables -t nat -F OUTPUT 2>/dev/null || true
    
    # Re-add Docker rule if it was there
    sudo iptables -t nat -A OUTPUT -d '!127.0.0.0/8' -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || true
    
    success "iptables rules cleaned"
}

start_collector() {
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        error "Collector already running (PID: $(cat "$PID_FILE"))"
        exit 1
    fi
    
    log "Starting payload collector..."
    log "  Cursor version: $CURSOR_VERSION"
    log "  Output dir: $SCRIPT_DIR/payload-db/v$CURSOR_VERSION/"
    
    # Increase file descriptor limit
    ulimit -n 65535 2>/dev/null || warn "Could not increase ulimit"
    
    setup_iptables
    
    # Start mitmproxy with payload collector addon
    # NOTE: Do NOT use stream_large_bodies - it prevents content capture!
    mitmdump \
        -s "$SCRIPT_DIR/payload_collector.py" \
        -p $PROXY_PORT \
        --ssl-insecure \
        --set keep_host_header=true \
        2>&1 | tee "$LOG_FILE" &
    
    local pid=$!
    echo $pid > "$PID_FILE"
    
    success "Collector started (PID: $pid)"
    echo ""
    echo "📦 Payloads will be saved to:"
    echo "   $SCRIPT_DIR/payload-db/v$CURSOR_VERSION/"
    echo ""
    echo "🔍 Monitor with:"
    echo "   tail -f $LOG_FILE"
    echo ""
    echo "🛑 Stop with:"
    echo "   $0 stop"
}

stop_collector() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log "Stopping collector (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
            success "Collector stopped"
        else
            warn "Process not running"
        fi
        rm -f "$PID_FILE"
    else
        warn "No PID file found"
    fi
    
    cleanup_iptables
}

status() {
    echo "=== Payload Collector Status ==="
    echo ""
    
    if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        success "Collector running (PID: $(cat "$PID_FILE"))"
    else
        warn "Collector not running"
    fi
    
    echo ""
    echo "Cursor version: $CURSOR_VERSION"
    echo ""
    echo "Payload database:"
    if [[ -d "$SCRIPT_DIR/payload-db" ]]; then
        find "$SCRIPT_DIR/payload-db" -type f -name "*.json" | wc -l | xargs echo "  Metadata files:"
        find "$SCRIPT_DIR/payload-db" -type f -name "*.bin" | wc -l | xargs echo "  Binary payloads:"
        du -sh "$SCRIPT_DIR/payload-db" | awk '{print "  Total size: " $1}'
    else
        echo "  No payloads collected yet"
    fi
    
    echo ""
    echo "iptables NAT rules:"
    sudo iptables -t nat -L OUTPUT -n --line-numbers 2>/dev/null | grep -E "REDIRECT|8080" || echo "  No redirect rules"
}

case "${1:-}" in
    start)
        start_collector
        ;;
    stop)
        stop_collector
        ;;
    restart)
        stop_collector
        sleep 2
        start_collector
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        echo ""
        echo "Collects Cursor API payloads for Protobuf reverse engineering."
        echo "Payloads are saved with full metadata for building a searchable database."
        exit 1
        ;;
esac

