#!/usr/bin/env bash
#
# capture-cursor-traffic.sh - Capture and decode Cursor API traffic
#
# This script captures TLS-encrypted traffic from Cursor to api2.cursor.sh
# and decrypts it using SSLKEYLOGFILE.
#
# Usage:
#   ./capture-cursor-traffic.sh start    # Start capture, then launch Cursor
#   ./capture-cursor-traffic.sh stop     # Stop capture and decode
#   ./capture-cursor-traffic.sh analyze  # Analyze captured protobuf messages
#

set -euo pipefail

# Use /var/tmp for capture files (avoids sticky bit permission issues)
CAPTURE_DIR="/var/tmp/cursor-capture"
PCAP_FILE="${CAPTURE_DIR}/cursor-traffic.pcap"
# Keep keylog in user dir for Electron to write
KEYLOG_FILE="${HOME}/.cursor-capture/sslkeys.log"
DECODED_DIR="${CAPTURE_DIR}/decoded"
PID_FILE="${CAPTURE_DIR}/tshark.pid"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[Capture]${NC} $1"; }
log_success() { echo -e "${GREEN}[Capture]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[Capture]${NC} $1"; }
log_error() { echo -e "${RED}[Capture]${NC} $1"; }

cmd_start() {
    log_info "Setting up traffic capture..."
    
    # Create directories
    mkdir -p "$CAPTURE_DIR" "$DECODED_DIR"
    mkdir -p "$(dirname "$KEYLOG_FILE")"
    
    # Clean old captures
    rm -f "$PCAP_FILE" "$KEYLOG_FILE"
    touch "$KEYLOG_FILE"
    chmod 666 "$KEYLOG_FILE"  # Ensure Electron can write
    
    # Find network interface
    IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    log_info "Using network interface: $IFACE"
    
    # Get Cursor API server IPs (for filtering)
    log_info "Resolving api2.cursor.sh..."
    # Filter to only IP addresses (not CNAME records)
    API_IPS=$(dig +short api2.cursor.sh | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -8 | tr '\n' ' ')
    log_info "API IPs: $API_IPS"
    
    if [[ -z "$API_IPS" ]]; then
        log_error "Could not resolve api2.cursor.sh"
        return 1
    fi
    
    # Build IP filter
    IP_FILTER=""
    for ip in $API_IPS; do
        if [[ -n "$IP_FILTER" ]]; then
            IP_FILTER="$IP_FILTER or host $ip"
        else
            IP_FILTER="host $ip"
        fi
    done
    
    log_info "Starting packet capture..."
    log_info "Filter: $IP_FILTER"
    
    # Start tshark in background
    # Need sudo for raw packet capture
    sudo tshark -i "$IFACE" -f "($IP_FILTER) and tcp port 443" -w "$PCAP_FILE" &
    TSHARK_PID=$!
    echo "$TSHARK_PID" > "$PID_FILE"
    
    log_success "Capture started (PID: $TSHARK_PID)"
    
    # Export SSLKEYLOGFILE and print instructions
    echo ""
    log_warn "=== IMPORTANT: Launch Cursor with SSL key logging ==="
    echo ""
    echo "Run this command to start Cursor with key logging:"
    echo ""
    echo -e "  ${GREEN}SSLKEYLOGFILE=$KEYLOG_FILE cursor${NC}"
    echo ""
    echo "Or if using cursor-studio:"
    echo ""
    echo -e "  ${GREEN}SSLKEYLOGFILE=$KEYLOG_FILE cursor-studio${NC}"
    echo ""
    log_info "Then use Cursor normally - send some chat messages."
    log_info "When done, run: $0 stop"
    echo ""
    
    # Also create a launcher script
    cat > "${CAPTURE_DIR}/start-cursor.sh" << EOF
#!/bin/bash
export SSLKEYLOGFILE="$KEYLOG_FILE"
exec cursor "\$@"
EOF
    chmod +x "${CAPTURE_DIR}/start-cursor.sh"
    log_info "Created launcher: ${CAPTURE_DIR}/start-cursor.sh"
}

cmd_stop() {
    log_info "Stopping capture..."
    
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            sudo kill "$PID"
            log_success "Stopped tshark (PID: $PID)"
        else
            log_warn "tshark already stopped"
        fi
        rm -f "$PID_FILE"
    else
        # Try to find and kill any tshark capturing to our file
        sudo pkill -f "tshark.*cursor-traffic.pcap" || true
    fi
    
    # Wait a moment for file to be written
    sleep 1
    
    if [[ -f "$PCAP_FILE" ]]; then
        PCAP_SIZE=$(du -h "$PCAP_FILE" | cut -f1)
        log_success "Capture saved: $PCAP_FILE ($PCAP_SIZE)"
    else
        log_error "No capture file found!"
        return 1
    fi
    
    if [[ -f "$KEYLOG_FILE" ]]; then
        KEY_COUNT=$(wc -l < "$KEYLOG_FILE")
        log_success "SSL keys captured: $KEY_COUNT keys"
    else
        log_error "No SSL keys captured! Did you run Cursor with SSLKEYLOGFILE?"
        return 1
    fi
    
    # Decode the capture
    cmd_decode
}

cmd_decode() {
    log_info "Decoding captured traffic..."
    
    if [[ ! -f "$PCAP_FILE" ]]; then
        log_error "No capture file found at $PCAP_FILE"
        return 1
    fi
    
    if [[ ! -f "$KEYLOG_FILE" ]] || [[ ! -s "$KEYLOG_FILE" ]]; then
        log_error "No SSL keys found. Cannot decrypt traffic."
        log_warn "Make sure Cursor was started with SSLKEYLOGFILE=$KEYLOG_FILE"
        return 1
    fi
    
    # Decode HTTP/2 traffic with SSL keys
    log_info "Extracting HTTP/2 streams..."
    
    # Extract all HTTP/2 data
    tshark -r "$PCAP_FILE" \
        -o "tls.keylog_file:$KEYLOG_FILE" \
        -Y "http2" \
        -T fields \
        -e frame.number \
        -e http2.streamid \
        -e http2.headers.path \
        -e http2.headers.content_type \
        -e http2.data.data \
        -E separator='|' \
        > "${DECODED_DIR}/http2_streams.txt" 2>/dev/null || true
    
    # Count decoded requests
    if [[ -f "${DECODED_DIR}/http2_streams.txt" ]]; then
        STREAM_COUNT=$(wc -l < "${DECODED_DIR}/http2_streams.txt")
        log_success "Decoded $STREAM_COUNT HTTP/2 frames"
    fi
    
    # Extract just the ChatService requests
    log_info "Looking for ChatService requests..."
    tshark -r "$PCAP_FILE" \
        -o "tls.keylog_file:$KEYLOG_FILE" \
        -Y 'http2.headers.path contains "ChatService"' \
        -T fields \
        -e frame.number \
        -e http2.streamid \
        -e http2.headers.path \
        -e http2.data.data \
        > "${DECODED_DIR}/chat_requests.txt" 2>/dev/null || true
    
    if [[ -f "${DECODED_DIR}/chat_requests.txt" ]]; then
        CHAT_COUNT=$(grep -c "ChatService" "${DECODED_DIR}/chat_requests.txt" 2>/dev/null || echo "0")
        log_success "Found $CHAT_COUNT ChatService requests"
    fi
    
    # Also save as JSON for easier parsing
    log_info "Exporting to JSON..."
    tshark -r "$PCAP_FILE" \
        -o "tls.keylog_file:$KEYLOG_FILE" \
        -Y "http2" \
        -T json \
        > "${DECODED_DIR}/traffic.json" 2>/dev/null || true
    
    log_success "Decoded files saved to: $DECODED_DIR"
    echo ""
    log_info "Run '$0 analyze' to extract protobuf schemas"
}

cmd_analyze() {
    log_info "Analyzing captured protobuf messages..."
    
    CHAT_FILE="${DECODED_DIR}/chat_requests.txt"
    
    if [[ ! -f "$CHAT_FILE" ]] || [[ ! -s "$CHAT_FILE" ]]; then
        log_error "No ChatService requests found. Run capture first."
        return 1
    fi
    
    # Create Python analyzer
    cat > "${DECODED_DIR}/analyze_proto.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Analyze captured protobuf messages and reconstruct schema.
"""

import sys
import json
import struct
from pathlib import Path

def decode_varint(data, pos=0):
    """Decode a protobuf varint."""
    result = 0
    shift = 0
    while pos < len(data):
        byte = data[pos]
        result |= (byte & 0x7F) << shift
        pos += 1
        if not (byte & 0x80):
            break
        shift += 7
    return result, pos

def decode_protobuf(data, depth=0):
    """Decode protobuf wire format and print field structure."""
    pos = 0
    fields = []
    indent = "  " * depth
    
    while pos < len(data):
        if pos >= len(data):
            break
            
        try:
            # Read tag
            tag, pos = decode_varint(data, pos)
            field_num = tag >> 3
            wire_type = tag & 0x07
            
            field_info = {
                "field": field_num,
                "wire_type": wire_type,
            }
            
            if wire_type == 0:  # Varint
                value, pos = decode_varint(data, pos)
                field_info["type"] = "varint"
                field_info["value"] = value
                print(f"{indent}Field {field_num}: varint = {value}")
                
            elif wire_type == 1:  # 64-bit
                value = struct.unpack('<Q', data[pos:pos+8])[0]
                pos += 8
                field_info["type"] = "fixed64"
                field_info["value"] = value
                print(f"{indent}Field {field_num}: fixed64 = {value}")
                
            elif wire_type == 2:  # Length-delimited
                length, pos = decode_varint(data, pos)
                value = data[pos:pos+length]
                pos += length
                
                # Try to decode as string
                try:
                    string_val = value.decode('utf-8')
                    if string_val.isprintable() or len(string_val) < 100:
                        field_info["type"] = "string"
                        field_info["value"] = string_val[:100]
                        print(f"{indent}Field {field_num}: string ({length} bytes) = {string_val[:80]}...")
                    else:
                        raise UnicodeDecodeError("not printable", b"", 0, 0, "")
                except (UnicodeDecodeError, ValueError):
                    # Try to decode as nested message
                    field_info["type"] = "bytes/message"
                    field_info["length"] = length
                    print(f"{indent}Field {field_num}: bytes/message ({length} bytes)")
                    if length > 0 and length < 10000:
                        # Try recursive decode
                        try:
                            decode_protobuf(value, depth + 1)
                        except:
                            print(f"{indent}  (binary data)")
                
            elif wire_type == 5:  # 32-bit
                value = struct.unpack('<I', data[pos:pos+4])[0]
                pos += 4
                field_info["type"] = "fixed32"
                field_info["value"] = value
                print(f"{indent}Field {field_num}: fixed32 = {value}")
                
            else:
                print(f"{indent}Field {field_num}: unknown wire type {wire_type}")
                break
                
            fields.append(field_info)
            
        except Exception as e:
            print(f"{indent}Error at pos {pos}: {e}")
            break
    
    return fields

def main():
    # Read from decoded files
    decoded_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / ".cursor-capture/decoded"
    
    # Try to read HTTP/2 data
    streams_file = decoded_dir / "http2_streams.txt"
    if streams_file.exists():
        print("=" * 60)
        print("Analyzing HTTP/2 streams...")
        print("=" * 60)
        
        with open(streams_file) as f:
            for line in f:
                parts = line.strip().split('|')
                if len(parts) >= 5:
                    frame, stream_id, path, content_type, data_hex = parts[:5]
                    if 'ChatService' in path and data_hex:
                        print(f"\n--- Stream {stream_id}: {path} ---")
                        try:
                            # Remove Connect envelope if present
                            data = bytes.fromhex(data_hex.replace(':', ''))
                            if len(data) > 5:
                                # Check for Connect envelope
                                flags = data[0]
                                length = struct.unpack('>I', data[1:5])[0]
                                if length == len(data) - 5:
                                    print(f"Connect envelope: flags={flags}, length={length}")
                                    data = data[5:]
                            
                            print(f"Protobuf data ({len(data)} bytes):")
                            decode_protobuf(data)
                        except Exception as e:
                            print(f"Error decoding: {e}")
    
    # Also try JSON export
    json_file = decoded_dir / "traffic.json"
    if json_file.exists() and json_file.stat().st_size < 50_000_000:  # < 50MB
        print("\n" + "=" * 60)
        print("Checking JSON export for ChatService...")
        print("=" * 60)
        
        try:
            with open(json_file) as f:
                packets = json.load(f)
            
            chat_packets = []
            for pkt in packets:
                layers = pkt.get('_source', {}).get('layers', {})
                http2 = layers.get('http2', {})
                
                # Check for ChatService
                if isinstance(http2, dict):
                    path = http2.get('http2.headers.path', '')
                    if 'ChatService' in str(path):
                        chat_packets.append(pkt)
            
            print(f"Found {len(chat_packets)} ChatService packets in JSON")
            
        except Exception as e:
            print(f"Error reading JSON: {e}")

if __name__ == "__main__":
    main()
PYEOF
    
    chmod +x "${DECODED_DIR}/analyze_proto.py"
    
    # Run analyzer
    python3 "${DECODED_DIR}/analyze_proto.py" "$DECODED_DIR"
}

cmd_status() {
    log_info "Capture status:"
    echo ""
    
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            log_success "Capture running (PID: $PID)"
        else
            log_warn "Capture process ended"
        fi
    else
        log_info "No capture in progress"
    fi
    
    echo ""
    log_info "Files:"
    [[ -f "$PCAP_FILE" ]] && echo "  PCAP: $PCAP_FILE ($(du -h "$PCAP_FILE" | cut -f1))" || echo "  PCAP: not found"
    [[ -f "$KEYLOG_FILE" ]] && echo "  Keys: $KEYLOG_FILE ($(wc -l < "$KEYLOG_FILE") keys)" || echo "  Keys: not found"
    [[ -d "$DECODED_DIR" ]] && echo "  Decoded: $DECODED_DIR" || echo "  Decoded: not created"
}

cmd_clean() {
    log_info "Cleaning capture files..."
    rm -rf "$CAPTURE_DIR"
    log_success "Cleaned $CAPTURE_DIR"
}

show_help() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  start    Start packet capture (requires sudo)"
    echo "  stop     Stop capture and decode traffic"
    echo "  decode   Decode existing capture file"
    echo "  analyze  Analyze decoded protobuf messages"
    echo "  status   Show capture status"
    echo "  clean    Remove all capture files"
    echo ""
    echo "Workflow:"
    echo "  1. Run '$0 start' to begin capture"
    echo "  2. Launch Cursor with the printed command"
    echo "  3. Use Cursor's chat feature - send messages"
    echo "  4. Run '$0 stop' when done"
    echo "  5. Run '$0 analyze' to decode protobuf schemas"
}

case "${1:-}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    decode)  cmd_decode ;;
    analyze) cmd_analyze ;;
    status)  cmd_status ;;
    clean)   cmd_clean ;;
    *)       show_help ;;
esac

