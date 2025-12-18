#!/usr/bin/env bash
# Robust Cursor AI Streaming Interception Test
# 
# This script sets up transparent proxying to intercept Cursor's AI traffic
# at the kernel level using iptables NAT redirect.
#
# Usage: ./robust_intercept_test.sh [start|stop|status]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROXY_PORT=8080
LOG_FILE="/tmp/cursor_intercept.log"
PID_FILE="/tmp/cursor_intercept.pid"
ULIMIT_FILES=65535

# Cursor API domains to intercept
CURSOR_DOMAINS=(
    "api2.cursor.sh"
    "api3.cursor.sh"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Resolve domain to IPs
resolve_ips() {
    local domain=$1
    dig +short "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
}

# Add iptables rules for selective interception
add_iptables_rules() {
    header "Setting up iptables NAT redirect"
    
    local uid=$(id -u)
    local rules_added=0
    
    for domain in "${CURSOR_DOMAINS[@]}"; do
        log "Resolving $domain..."
        local ips=$(resolve_ips "$domain")
        
        if [ -z "$ips" ]; then
            warn "Could not resolve $domain"
            continue
        fi
        
        for ip in $ips; do
            log "Adding redirect for $ip ($domain)"
            if sudo iptables -t nat -C OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT 2>/dev/null; then
                warn "Rule already exists for $ip"
            else
                sudo iptables -t nat -A OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT
                ((rules_added++))
            fi
        done
    done
    
    success "Added $rules_added iptables rules"
    
    # Also add blanket rule for user's traffic (with marker comment)
    # This catches any IPs we might have missed
    log "Adding fallback rule for all :443 traffic from uid $uid"
    if ! sudo iptables -t nat -C OUTPUT -p tcp --dport 443 -m owner --uid-owner "$uid" -m comment --comment "cursor-intercept" -j REDIRECT --to-port $PROXY_PORT 2>/dev/null; then
        sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$uid" -m comment --comment "cursor-intercept" -j REDIRECT --to-port $PROXY_PORT
        success "Added fallback rule"
    else
        warn "Fallback rule already exists"
    fi
}

# Remove iptables rules
remove_iptables_rules() {
    header "Removing iptables rules"
    
    local uid=$(id -u)
    
    # Remove IP-specific rules
    for domain in "${CURSOR_DOMAINS[@]}"; do
        local ips=$(resolve_ips "$domain")
        for ip in $ips; do
            if sudo iptables -t nat -D OUTPUT -p tcp -d "$ip" --dport 443 -j REDIRECT --to-port $PROXY_PORT 2>/dev/null; then
                log "Removed rule for $ip"
            fi
        done
    done
    
    # Remove fallback rule
    if sudo iptables -t nat -D OUTPUT -p tcp --dport 443 -m owner --uid-owner "$uid" -m comment --comment "cursor-intercept" -j REDIRECT --to-port $PROXY_PORT 2>/dev/null; then
        success "Removed fallback rule"
    else
        warn "Fallback rule not found"
    fi
    
    success "Cleanup complete"
}

# Check current status
show_status() {
    header "Current Status"
    
    echo "=== iptables NAT OUTPUT rules ==="
    sudo iptables -t nat -L OUTPUT -n --line-numbers 2>/dev/null | grep -E "REDIRECT|cursor" || echo "No intercept rules found"
    
    echo ""
    echo "=== Proxy process ==="
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            success "Proxy running (PID: $pid)"
            ps -f -p "$pid"
        else
            warn "PID file exists but process not running"
        fi
    else
        warn "No proxy PID file found"
    fi
    
    echo ""
    echo "=== Recent log entries ==="
    if [ -f "$LOG_FILE" ]; then
        tail -20 "$LOG_FILE"
    else
        warn "No log file found"
    fi
    
    echo ""
    echo "=== Cursor processes ==="
    pgrep -a cursor | head -5 || echo "No Cursor processes found"
}

# Start the interception
start_intercept() {
    header "Starting Cursor AI Interception"
    
    # Check for existing proxy
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            error "Proxy already running (PID: $pid)"
            exit 1
        fi
    fi
    
    # Check mitmproxy
    if ! command -v mitmdump &> /dev/null; then
        error "mitmproxy not found. Install with: nix shell nixpkgs#mitmproxy"
        exit 1
    fi
    
    # Increase file descriptor limit
    log "Setting ulimit to $ULIMIT_FILES"
    ulimit -n $ULIMIT_FILES 2>/dev/null || warn "Could not increase ulimit (may need root)"
    
    # Start proxy in background
    log "Starting mitmproxy on port $PROXY_PORT..."
    mitmdump \
        -s "$SCRIPT_DIR/test_cursor_proxy.py" \
        -p $PROXY_PORT \
        --ssl-insecure \
        --set stream_large_bodies=1 \
        --set keep_host_header=true \
        2>&1 | tee "$LOG_FILE" &
    
    local proxy_pid=$!
    echo $proxy_pid > "$PID_FILE"
    
    sleep 2
    
    if ps -p $proxy_pid > /dev/null 2>&1; then
        success "Proxy started (PID: $proxy_pid)"
    else
        error "Proxy failed to start"
        rm -f "$PID_FILE"
        exit 1
    fi
    
    # Add iptables rules
    add_iptables_rules
    
    header "Interception Active"
    echo "📝 Log file: $LOG_FILE"
    echo "🔍 Monitor with: tail -f $LOG_FILE"
    echo ""
    echo "To test:"
    echo "  1. Open Cursor (any window, doesn't need special launch)"
    echo "  2. Start an AI chat conversation"
    echo "  3. Watch the log for 🤖 AI ENDPOINT entries"
    echo ""
    echo "To stop: $0 stop"
}

# Stop the interception
stop_intercept() {
    header "Stopping Cursor AI Interception"
    
    # Remove iptables rules first
    remove_iptables_rules
    
    # Stop proxy
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            log "Stopping proxy (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            sleep 1
            if ps -p "$pid" > /dev/null 2>&1; then
                warn "Proxy didn't stop gracefully, force killing..."
                kill -9 "$pid" 2>/dev/null || true
            fi
            success "Proxy stopped"
        else
            warn "Proxy process not running"
        fi
        rm -f "$PID_FILE"
    else
        warn "No PID file found"
    fi
    
    success "Interception stopped"
}

# Analyze captured data
analyze_capture() {
    header "Analyzing Captured Data"
    
    if [ ! -f "$LOG_FILE" ]; then
        error "No log file found at $LOG_FILE"
        exit 1
    fi
    
    echo "=== AI Endpoints Captured ==="
    grep -E "🤖 AI ENDPOINT|aiserver\.v1\.AiService" "$LOG_FILE" 2>/dev/null | sort -u | head -20 || echo "None found"
    
    echo ""
    echo "=== Streaming Responses ==="
    grep -E "🌊 STREAMING|stream" "$LOG_FILE" 2>/dev/null | head -20 || echo "None found"
    
    echo ""
    echo "=== gRPC Endpoints ==="
    grep -oE "https://[^/]+/aiserver\.[^[:space:]]+" "$LOG_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -20 || echo "None found"
    
    echo ""
    echo "=== Errors ==="
    grep -iE "error|fail" "$LOG_FILE" 2>/dev/null | tail -10 || echo "None found"
    
    echo ""
    echo "=== Statistics ==="
    local total=$(grep -c "🎯 CURSOR" "$LOG_FILE" 2>/dev/null || echo 0)
    local ai=$(grep -c "🤖 AI ENDPOINT" "$LOG_FILE" 2>/dev/null || echo 0)
    local streaming=$(grep -c "🌊 STREAMING" "$LOG_FILE" 2>/dev/null || echo 0)
    local errors=$(grep -ciE "error" "$LOG_FILE" 2>/dev/null || echo 0)
    
    echo "Total Cursor requests: $total"
    echo "AI endpoints: $ai"
    echo "Streaming responses: $streaming"
    echo "Errors: $errors"
}

# Main
case "${1:-help}" in
    start)
        start_intercept
        ;;
    stop)
        stop_intercept
        ;;
    status)
        show_status
        ;;
    analyze)
        analyze_capture
        ;;
    restart)
        stop_intercept
        sleep 2
        start_intercept
        ;;
    help|*)
        echo "Cursor AI Streaming Interception Test"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  start    - Start transparent proxy interception"
        echo "  stop     - Stop interception and cleanup"
        echo "  status   - Show current status"
        echo "  analyze  - Analyze captured data"
        echo "  restart  - Stop and start"
        echo "  help     - Show this help"
        echo ""
        echo "This script uses iptables NAT redirect to intercept Cursor's"
        echo "AI traffic at the kernel level, bypassing Cursor's deliberate"
        echo "ignoring of proxy environment variables."
        ;;
esac

