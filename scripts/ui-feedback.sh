#!/usr/bin/env bash
# UI Screenshot Capture for AI Visual Feedback
# Captures screenshots for Cursor Studio development

set -euo pipefail

SCREENSHOT_DIR="${HOME}/nixos-cursor/screenshots"
WINDOW_TITLE="${1:-Cursor Studio}"
OUTPUT="${2:-}"
MODE="${3:-window}"  # window, full, or region

mkdir -p "$SCREENSHOT_DIR"

# Generate filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="cursor-studio-${TIMESTAMP}.png"
fi
OUTPUT_PATH="${SCREENSHOT_DIR}/${OUTPUT}"

echo "📸 Capturing: $WINDOW_TITLE (mode: $MODE)"

case "$MODE" in
    full|f)
        # Full screen capture
        spectacle -b -f -n -o "$OUTPUT_PATH" 2>/dev/null
        ;;
    window|w)
        # Active window capture (user should focus the window first)
        echo "⚠️ Please focus the '$WINDOW_TITLE' window..."
        sleep 1
        spectacle -b -a -n -o "$OUTPUT_PATH" 2>/dev/null
        ;;
    region|r)
        # Region selection
        echo "📐 Select region to capture..."
        spectacle -b -r -n -o "$OUTPUT_PATH" 2>/dev/null
        ;;
    *)
        # Default: full screen
        spectacle -b -f -n -o "$OUTPUT_PATH" 2>/dev/null
        ;;
esac

# Wait for file to be written
sleep 0.5

# Verify and report
if [[ -f "$OUTPUT_PATH" ]] && [[ -s "$OUTPUT_PATH" ]]; then
    # Create latest symlink
    ln -sf "$OUTPUT_PATH" "${SCREENSHOT_DIR}/latest.png"
    
    # Get file info
    SIZE=$(ls -lh "$OUTPUT_PATH" | awk '{print $5}')
    DIMENSIONS=$(file "$OUTPUT_PATH" | grep -oP '\d+\s*x\s*\d+' | head -1 || echo "unknown")
    
    echo "✅ Saved: $OUTPUT_PATH"
    echo ""
    echo "📊 Screenshot Info:"
    echo "  Path: $OUTPUT_PATH"
    echo "  Latest: ${SCREENSHOT_DIR}/latest.png"
    echo "  Size: $SIZE"
    echo "  Dimensions: $DIMENSIONS"
    
    # Output JSON for AI consumption
    echo ""
    cat << EOF
{
  "success": true,
  "path": "$OUTPUT_PATH",
  "latest": "${SCREENSHOT_DIR}/latest.png",
  "size": "$SIZE",
  "dimensions": "$DIMENSIONS",
  "timestamp": "$TIMESTAMP"
}
EOF
else
    echo "❌ Screenshot failed or empty"
    exit 1
fi
