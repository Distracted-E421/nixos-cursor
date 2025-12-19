#!/usr/bin/env bash
# Quick capture of Cursor API traffic

CAPTURE_DIR="$HOME/.cursor-proxy/captures/raw"
mkdir -p "$CAPTURE_DIR"

KEYLOG="$CAPTURE_DIR/keys.log"
PCAP="$CAPTURE_DIR/capture-$(date +%H%M%S).pcap"

echo "Starting capture..."
echo "  Keylog: $KEYLOG"
echo "  PCAP:   $PCAP"

# Clean keylog
> "$KEYLOG"
chmod 600 "$KEYLOG"

# Resolve api2.cursor.sh IP
API_IP=$(dig +short api2.cursor.sh | head -1)
echo "  API IP: $API_IP"

# Start capture (run in background)
echo ""
echo "Starting tshark (needs sudo)..."
sudo tshark -i any -f "host $API_IP" -w "$PCAP" -q &
TSHARK_PID=$!
sleep 2

echo ""
echo "Now run Cursor in another terminal:"
echo "  SSLKEYLOGFILE=$KEYLOG cursor"
echo ""
echo "Make a chat request, then press ENTER here to stop..."
read -r

echo "Stopping capture..."
sudo kill $TSHARK_PID 2>/dev/null || true
sleep 1

# Decode
echo ""
echo "Decoding captured packets..."
DECODED="$CAPTURE_DIR/decoded-$(date +%H%M%S).txt"

tshark -r "$PCAP" \
    -o "tls.keylog_file:$KEYLOG" \
    -Y "http2" \
    -T fields \
    -e frame.number \
    -e http2.streamid \
    -e http2.headers.path \
    -e http2.headers.method \
    -e http2.headers.content_type \
    -e http2.data.data \
    > "$DECODED" 2>&1

echo ""
echo "Results:"
echo "  PCAP: $PCAP ($(du -h "$PCAP" | cut -f1))"
echo "  Decoded: $DECODED"

# Show what we captured
echo ""
echo "Captured paths:"
awk '{print $3}' "$DECODED" | sort -u | grep -v "^$" | head -20

echo ""
echo "Full decoded file at: $DECODED"
