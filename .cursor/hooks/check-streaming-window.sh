#!/bin/bash
# Hook: check-streaming-window.sh
# Trigger: conversation_start
# Purpose: Check if on neon-laptop during Sunday streaming window and attach appropriate rule

HOOK_NAME="check-streaming-window"
HOOK_LOG="/tmp/cursor-hooks-${HOOK_NAME}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$HOOK_LOG"
}

log "=== Streaming Window Check Hook Triggered ==="

# Check if we're on neon-laptop
HOSTNAME=$(hostname)
log "Current hostname: $HOSTNAME"

if [[ "$HOSTNAME" != "neon-laptop" ]]; then
    log "Not on neon-laptop, skipping streaming window check"
    exit 0
fi

# Get current Central Time
CURRENT_TIME=$(TZ="America/Chicago" date '+%H%M')
DAY_OF_WEEK=$(TZ="America/Chicago" date '+%u')  # 1-7, 7=Sunday
CURRENT_DATETIME=$(TZ="America/Chicago" date '+%Y-%m-%d %A %I:%M %p %Z')

log "Current time: $CURRENT_DATETIME"
log "Day of week: $DAY_OF_WEEK, Time: $CURRENT_TIME"

# Check if Sunday (7) and between 07:30 (0730) and 12:30 (1230)
if [ "$DAY_OF_WEEK" -eq 7 ] && [ "$CURRENT_TIME" -ge 0730 ] && [ "$CURRENT_TIME" -le 1230 ]; then
    log "🚨 STREAMING WINDOW ACTIVE - Attaching streaming rule"
    
    # Output instruction to attach the streaming-window-awareness rule
    cat << EOF

🚨 **STREAMING WINDOW DETECTED**

**Device**: neon-laptop
**Time**: $CURRENT_DATETIME
**Status**: Church streaming window (Sunday 7:30 AM - 12:30 PM CT)

**CRITICAL**: The streaming-window-awareness rule should be attached.

**Priorities during this window**:
1. Keep streaming operational at all costs
2. Maintain system stability
3. NO system changes without explicit user confirmation
4. Defer all non-essential operations

EOF
    
    # Signal that the streaming rule should be attached
    # (Cursor will read this and suggest attaching the rule)
    echo "CURSOR_ATTACH_RULE:streaming-window-awareness"
    
    log "Streaming window notification displayed"
else
    log "Outside streaming window - no action needed"
fi

log "=== Streaming Window Check Complete ===" 
exit 0
