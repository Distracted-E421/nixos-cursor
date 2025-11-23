#!/bin/bash
# Hook: safety-command-check.sh
# Trigger: before_command_execution
# Purpose: Detect dangerous commands that resemble the October 18, 2025 incident and halt

HOOK_NAME="safety-command-check"
HOOK_LOG="/tmp/cursor-hooks-${HOOK_NAME}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$HOOK_LOG"
}

# Read the proposed command from stdin or argument
PROPOSED_COMMAND="${1:-$(cat)}"

log "=== Safety Command Check Hook Triggered ==="
log "Checking command: $PROPOSED_COMMAND"

# Define dangerous command patterns
declare -a DANGER_PATTERNS=(
    "rm -rf ~/\*"
    "rm -rf ~/\.\*"
    "find ~ -delete"
    "sqlite3.*VACUUM"
    "history -c"
    "> ~/\.bash_history"
    "rm ~/\.bash_history"
    "pkill -u \$USER"
    "pkill -9 -u"
    "loginctl terminate-session"
    "rm ~/\.ssh/id_"
    "rm ~/\.bashrc"
    "rm ~/\.profile"
    "rm -rf ~/\.config/Cursor"
    "rm -rf ~/\.config/\*"
    "rm -rf ~/\.local/\*"
    "sudo shutdown.*-h now"
    "sudo reboot"
    "systemctl.*--force.*reboot"
    "git reset --hard"
    "git clean -fdx"
    "git push --force"
    "rm -rf \.git"
)

# Check if command matches any danger pattern
DANGER_DETECTED=false
MATCHED_PATTERN=""

for pattern in "${DANGER_PATTERNS[@]}"; do
    if echo "$PROPOSED_COMMAND" | grep -qiE "$pattern"; then
        DANGER_DETECTED=true
        MATCHED_PATTERN="$pattern"
        break
    fi
done

if [ "$DANGER_DETECTED" = true ]; then
    log "🚨 DANGER DETECTED: Command matches pattern: $MATCHED_PATTERN"
    
    cat << EOF

🚨🚨🚨 **SAFETY HALT - DANGEROUS COMMAND DETECTED** 🚨🚨🚨

**Proposed Command**: \`$PROPOSED_COMMAND\`

**Matched Pattern**: \`$MATCHED_PATTERN\`

**Risk Assessment**: This command resembles operations from the October 18, 2025 incident that caused:
- Data loss (Cursor conversations, bash history, AppImages)
- Session invalidation (all app tokens cleared)
- System disruption (forced shutdown/logout)
- SQLite corruption (VACUUM on Cursor database)
- File deletion (SSH keys, configs)

**INCIDENT REPORT**: See OBSIDIAN_REPAIR_SUMMARY.md

**ACTION REQUIRED**: This command will **NOT** be executed automatically.

If you truly want to proceed, you must:
1. **Understand the full impact** of this command
2. **Have a backup** of any data that might be affected
3. **Type the exact command manually** to confirm

**Safer Alternatives**:
- For cleanup: Specify exact files/directories to remove
- For database operations: Never use VACUUM on active databases
- For history: Don't clear history automatically
- For configs: Back up before modifying
- For git operations: Use safer commands (git stash, git branch, etc.)

**The command has been BLOCKED for your safety.**

EOF
    
    log "Command blocked, user notified"
    exit 1  # Non-zero exit = block the command
else
    log "✅ Command passed safety check"
    exit 0  # Zero exit = allow the command
fi
