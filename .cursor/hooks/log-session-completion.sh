#!/bin/bash
# Cursor Hook: stop
# Logs session completion and analyzes work accomplished for continuous planning feedback

# Read JSON input from stdin
INPUT=$(cat)

# Extract session info
CONVERSATION_ID=$(echo "$INPUT" | jq -r '.conversation_id // "unknown"')
STATUS=$(echo "$INPUT" | jq -r '.status // "unknown"')
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Set up logging
LOG_DIR="/home/e421/homelab/.cursor/logs"
mkdir -p "$LOG_DIR"
SESSION_LOG="$LOG_DIR/sessions.log"
STATS_LOG="$LOG_DIR/session-stats.json"

# Count files edited in this session (from tracking log)
EDIT_COUNT=0
if [ -f "$LOG_DIR/edits-$CONVERSATION_ID.log" ]; then
  EDIT_COUNT=$(wc -l < "$LOG_DIR/edits-$CONVERSATION_ID.log")
fi

# Determine session quality based on edit count and status
SESSION_QUALITY="unknown"
if [ "$STATUS" = "completed" ]; then
  if [ "$EDIT_COUNT" -ge 5 ]; then
    SESSION_QUALITY="excellent"  # Many files edited, comprehensive work
  elif [ "$EDIT_COUNT" -ge 2 ]; then
    SESSION_QUALITY="good"       # Some files edited, decent work
  elif [ "$EDIT_COUNT" -ge 1 ]; then
    SESSION_QUALITY="mediocre"   # Only one file, could have done more
  else
    SESSION_QUALITY="minimal"    # No edits, information only
  fi
fi

# Log session completion
echo "[$TIMESTAMP] Session: $CONVERSATION_ID | Status: $STATUS | Edits: $EDIT_COUNT | Quality: $SESSION_QUALITY" >> "$SESSION_LOG"

# Update session statistics (JSON format for analytics)
if [ ! -f "$STATS_LOG" ]; then
  echo '{"total_sessions": 0, "completed": 0, "aborted": 0, "error": 0, "total_edits": 0, "quality_distribution": {}}' > "$STATS_LOG"
fi

# Use jq to update statistics
TEMP_STATS=$(mktemp)
jq --arg status "$STATUS" \
   --arg quality "$SESSION_QUALITY" \
   --argjson edits "$EDIT_COUNT" \
   '.total_sessions += 1 | 
    (.[$status] // 0) += 1 |
    .total_edits += $edits |
    .quality_distribution[$quality] = ((.quality_distribution[$quality] // 0) + 1)' \
   "$STATS_LOG" > "$TEMP_STATS" && mv "$TEMP_STATS" "$STATS_LOG"

# Provide feedback for continuous planning
FEEDBACK=""
case "$SESSION_QUALITY" in
  "excellent")
    FEEDBACK="✅ Excellent session! Comprehensive work accomplished with $EDIT_COUNT files edited."
    ;;
  "good")
    FEEDBACK="✅ Good session! Multiple files edited ($EDIT_COUNT). Consider if more related work could have been done."
    ;;
  "mediocre")
    FEEDBACK="⚠️ Mediocre session. Only $EDIT_COUNT file(s) edited. Remember to maximize work per interaction."
    ;;
  "minimal")
    FEEDBACK="ℹ️ Information-only session. No files edited. This is appropriate for defined-scope queries."
    ;;
esac

echo "[$TIMESTAMP] $FEEDBACK" >> "$SESSION_LOG"

# Clean up session-specific edit tracking
if [ -f "$LOG_DIR/edits-$CONVERSATION_ID.log" ]; then
  rm "$LOG_DIR/edits-$CONVERSATION_ID.log"
fi

# Generate weekly summary (if it's Sunday)
if [ "$(date +%u)" -eq 7 ]; then
  WEEK_START=$(date -d "7 days ago" +"%Y-%m-%d")
  echo "
===== WEEKLY SESSION SUMMARY =====
Week Starting: $WEEK_START
$(tail -n 100 "$SESSION_LOG" | grep -A 1 "$WEEK_START")
==================================
" >> "$LOG_DIR/weekly-summaries.log"
fi

exit 0
