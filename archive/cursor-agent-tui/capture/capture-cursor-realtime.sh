#!/usr/bin/env bash
# Capture Cursor traffic using SSLKEYLOGFILE (non-intrusive method)

set -e

CAPTURE_DIR="$HOME/.cursor-proxy/captures/raw"
KEYLOG_FILE="$CAPTURE_DIR/sslkeys.log"
PCAP_FILE="$CAPTURE_DIR/cursor-$(date +%Y%m%d-%H%M%S).pcap"
DECODED_FILE="${PCAP_FILE%.pcap}-decoded.txt"

mkdir -p "$CAPTURE_DIR"
chmod 700 "$CAPTURE_DIR"

echo "═══════════════════════════════════════════════════════════════════"
echo "  Cursor Traffic Capture (SSLKEYLOGFILE Method)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "  Keylog:  $KEYLOG_FILE"
echo "  PCAP:    $PCAP_FILE"
echo "  Decoded: $DECODED_FILE"
echo ""

# Clean old keylog
> "$KEYLOG_FILE"
chmod 600 "$KEYLOG_FILE"

echo "[1/4] Starting packet capture in background..."
# Capture only to api2.cursor.sh (port 443)
sudo tshark -i any \
    -f "host api2.cursor.sh and tcp port 443" \
    -w "$PCAP_FILE" \
    -q &
TSHARK_PID=$!
echo "      tshark PID: $TSHARK_PID"

# Give tshark time to start
sleep 2

echo "[2/4] Starting Cursor with SSLKEYLOGFILE..."
echo "      Make some chat requests, then press Ctrl+C here"
echo ""

# Start Cursor with keylog enabled
SSLKEYLOGFILE="$KEYLOG_FILE" cursor &
CURSOR_PID=$!

# Wait for user to make requests
echo "═══════════════════════════════════════════════════════════════════"
echo "  Cursor started (PID: $CURSOR_PID)"
echo "  "
echo "  1. Make a chat request in Cursor"
echo "  2. Press ENTER here when done"
echo "═══════════════════════════════════════════════════════════════════"
read -r

echo ""
echo "[3/4] Stopping capture..."
# Kill Cursor and tshark
kill $CURSOR_PID 2>/dev/null || true
sudo kill $TSHARK_PID 2>/dev/null || true
sleep 1

echo "[4/4] Decoding captured traffic..."
if [ -s "$PCAP_FILE" ]; then
    # Decrypt and export HTTP2 traffic
    tshark -r "$PCAP_FILE" \
        -o "tls.keylog_file:$KEYLOG_FILE" \
        -o "http2.decompress_body:true" \
        -Y "http2" \
        -V > "$DECODED_FILE" 2>&1 || echo "Decode warning (may be empty)"
    
    # Show summary
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  CAPTURE RESULTS"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    # Count HTTP2 streams
    STREAMS=$(grep -c "Stream ID:" "$DECODED_FILE" 2>/dev/null || echo "0")
    echo "  HTTP2 streams found: $STREAMS"
    
    # Show paths accessed
    echo ""
    echo "  Paths accessed:"
    grep ":path:" "$DECODED_FILE" 2>/dev/null | head -20 || echo "  (none found)"
    
    echo ""
    echo "  Full decoded output: $DECODED_FILE"
    echo "  Raw PCAP file: $PCAP_FILE"
    
    # Extract just the POST data for analysis
    PROTO_FILE="${PCAP_FILE%.pcap}-protobuf.bin"
    echo ""
    echo "  Attempting to extract protobuf bodies..."
    tshark -r "$PCAP_FILE" \
        -o "tls.keylog_file:$KEYLOG_FILE" \
        -Y "http2.data.data" \
        -T fields -e http2.data.data \
        2>/dev/null | xxd -r -p > "$PROTO_FILE" || true
    
    if [ -s "$PROTO_FILE" ]; then
        echo "  Protobuf data saved: $PROTO_FILE ($(wc -c < "$PROTO_FILE") bytes)"
    fi
else
    echo "  No traffic captured!"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
