#!/bin/bash
# Cursor Hook: afterFileEdit
# Tracks file edits for session quality analytics

# Read JSON input from stdin
INPUT=$(cat)

# Extract edit info
CONVERSATION_ID=$(echo "$INPUT" | jq -r '.conversation_id // "unknown"')
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // "unknown"')
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Set up logging
LOG_DIR="/home/e421/homelab/.cursor/logs"
mkdir -p "$LOG_DIR"

# Track this edit for the current session
SESSION_EDITS="$LOG_DIR/edits-$CONVERSATION_ID.log"
echo "[$TIMESTAMP] $FILE_PATH" >> "$SESSION_EDITS"

# Track all edits globally for analytics
ALL_EDITS="$LOG_DIR/all-edits.log"
echo "[$TIMESTAMP] Session: $CONVERSATION_ID | File: $FILE_PATH" >> "$ALL_EDITS"

# Track edit frequency per file (for identifying frequently modified files)
FILE_STATS="$LOG_DIR/file-edit-frequency.json"
if [ ! -f "$FILE_STATS" ]; then
  echo '{}' > "$FILE_STATS"
fi

# Update file edit frequency
TEMP_STATS=$(mktemp)
jq --arg file "$FILE_PATH" \
   '.[$file] = ((.[$file] // 0) + 1)' \
   "$FILE_STATS" > "$TEMP_STATS" && mv "$TEMP_STATS" "$FILE_STATS"

# Check if this file is being edited frequently (potential for refactoring)
EDIT_COUNT=$(jq -r --arg file "$FILE_PATH" '.[$file] // 0' "$FILE_STATS")
if [ "$EDIT_COUNT" -ge 10 ]; then
  echo "[$TIMESTAMP] ⚠️ High edit frequency for $FILE_PATH ($EDIT_COUNT edits). Consider refactoring or stabilizing." >> "$LOG_DIR/high-frequency-edits.log"
fi

exit 0
