#!/usr/bin/env bash
#
# restart-capture.sh - Capture Cursor traffic from fresh start
#
# Run this from a regular terminal AFTER closing Cursor:
#   ./restart-capture.sh
#

set -euo pipefail

CAPTURE_DIR="/var/tmp/cursor-capture"
PCAP="$CAPTURE_DIR/cursor-full.pcap"
KEYS="$HOME/.cursor-capture/sslkeys.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[1/4]${NC} Cleaning up..."
sudo pkill -f "tshark.*cursor" 2>/dev/null || true
# Don't kill cursor processes - user should close them manually
sleep 1

rm -f "$PCAP" "$KEYS"
mkdir -p "$CAPTURE_DIR" "$(dirname "$KEYS")"
touch "$KEYS"
chmod 666 "$KEYS"

echo -e "${GREEN}[2/4]${NC} Starting packet capture..."
sudo tshark -i eno2 -f "tcp port 443" -w "$PCAP" 2>/dev/null &
TSHARK_PID=$!
sleep 2

if ! ps -p $TSHARK_PID > /dev/null 2>&1; then
    echo -e "${RED}ERROR:${NC} tshark failed to start"
    exit 1
fi

echo -e "${GREEN}[3/4]${NC} Launching Cursor with SSL key logging..."
echo "      SSLKEYLOGFILE=$KEYS"
export SSLKEYLOGFILE="$KEYS"

# Launch Cursor
nohup cursor > /dev/null 2>&1 &
CURSOR_PID=$!

echo ""
echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}  Cursor launched! (PID: $CURSOR_PID)${NC}"
echo -e "${YELLOW}==========================================${NC}"
echo ""
echo "Now:"
echo "  1. Wait for Cursor to fully load"
echo "  2. Open Agent/Chat and send: 'Say hello'"
echo "  3. Wait for complete response"
echo "  4. Come back here and press Enter"
echo ""
read -p "Press Enter when ready to stop and decode..."

echo -e "${GREEN}[4/4]${NC} Stopping capture and decoding..."
sudo kill $TSHARK_PID 2>/dev/null || true
sleep 1
sudo chmod 644 "$PCAP"

# Report
echo ""
echo "Capture saved: $PCAP ($(du -h "$PCAP" | cut -f1))"
echo "SSL keys: $KEYS ($(wc -l < "$KEYS") keys)"
echo ""

echo "=== All HTTP/2 traffic ==="
HTTP2_COUNT=$(tshark -r "$PCAP" -o "tls.keylog_file:$KEYS" -Y "http2" 2>/dev/null | wc -l)
echo "$HTTP2_COUNT HTTP/2 frames decoded"

echo ""
echo "=== API paths to api2.cursor.sh ==="
tshark -r "$PCAP" -o "tls.keylog_file:$KEYS" \
    -Y 'http2.headers.authority == "api2.cursor.sh"' \
    -T fields -e http2.headers.path 2>/dev/null | sort | uniq -c | sort -rn | head -20

echo ""
echo "=== Looking for ChatService/AiService traffic ==="
tshark -r "$PCAP" -o "tls.keylog_file:$KEYS" \
    -Y 'http2.headers.path contains "aiserver" or http2.headers.path contains "Chat"' \
    -T fields -e frame.number -e http2.headers.authority -e http2.headers.path 2>/dev/null | head -30

echo ""
echo "=== To extract protobuf data, run: ==="
echo "tshark -r $PCAP -o 'tls.keylog_file:$KEYS' -Y 'http2.headers.path contains \"ChatService\"' -T fields -e http2.data.data"

