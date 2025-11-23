#!/bin/bash
# Hook: monitor-ssh-git-configs.sh  
# Trigger: file_change
# Purpose: Detect changes to SSH/Git configs and update corresponding rules

HOOK_NAME="monitor-ssh-git-configs"
HOOK_LOG="/tmp/cursor-hooks-${HOOK_NAME}.log"
WORKSPACE_ROOT="${CURSOR_WORKSPACE_ROOT:-/home/e421/homelab}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$HOOK_LOG"
}

log "=== SSH/Git Config Monitor Hook Triggered ==="

# Files to monitor
SSH_CONFIG="$HOME/.ssh/config"
GIT_CONFIG="$HOME/.gitconfig"
SSH_RULE="$WORKSPACE_ROOT/.cursor/rules/ssh-efficiency.mdc"
GIT_RULE="$WORKSPACE_ROOT/.cursor/rules/git-integration-testing.mdc"

# Check if SSH config changed
if [ -f "$SSH_CONFIG" ]; then
    SSH_MTIME=$(stat -c %Y "$SSH_CONFIG" 2>/dev/null || stat -f %m "$SSH_CONFIG" 2>/dev/null)
    SSH_RULE_MTIME=$(stat -c %Y "$SSH_RULE" 2>/dev/null || stat -f %m "$SSH_RULE" 2>/dev/null)
    
    if [ "$SSH_MTIME" -gt "$SSH_RULE_MTIME" ]; then
        log "⚠️ SSH config modified more recently than rule file"
        
        cat << EOF

⚠️ **SSH Configuration Change Detected**

**File**: $SSH_CONFIG
**Last Modified**: $(date -r "$SSH_CONFIG" '+%Y-%m-%d %H:%M:%S')

**Action Recommended**: 
The ssh-efficiency.mdc rule file may need updating to reflect current SSH configuration.

**Current SSH Hosts**:
$(grep -E "^Host " "$SSH_CONFIG" 2>/dev/null | head -10)

**Suggestions**:
1. Review changes in $SSH_CONFIG
2. Update $SSH_RULE if needed
3. Test SSH connections: ssh e421@<host>
4. Document any new patterns or issues

EOF
        log "SSH config change notification sent"
    fi
fi

# Check if Git config changed
if [ -f "$GIT_CONFIG" ]; then
    GIT_MTIME=$(stat -c %Y "$GIT_CONFIG" 2>/dev/null || stat -f %m "$GIT_CONFIG" 2>/dev/null)
    GIT_RULE_MTIME=$(stat -c %Y "$GIT_RULE" 2>/dev/null || stat -f %m "$GIT_RULE" 2>/dev/null)
    
    if [ "$GIT_MTIME" -gt "$GIT_RULE_MTIME" ]; then
        log "⚠️ Git config modified more recently than rule file"
        
        # Extract current git config
        GIT_USER=$(git config --global user.name 2>/dev/null)
        GIT_EMAIL=$(git config --global user.email 2>/dev/null)
        
        cat << EOF

⚠️ **Git Configuration Change Detected**

**File**: $GIT_CONFIG
**Last Modified**: $(date -r "$GIT_CONFIG" '+%Y-%m-%d %H:%M:%S')

**Current Git Configuration**:
- User: $GIT_USER
- Email: $GIT_EMAIL

**Action Recommended**:
The git-integration-testing.mdc rule file may need updating.

**Suggestions**:
1. Verify git config is correct: git config --list --global
2. Update $GIT_RULE if user/email changed
3. Test git operations: git status
4. Document changes in device changelog

EOF
        log "Git config change notification sent"
    fi
fi

# Check for new SSH hosts in /etc/hosts or Tailscale
if command -v tailscale &> /dev/null; then
    TAILSCALE_HOSTS=$(tailscale status 2>/dev/null | grep -v "^#" | awk '{print $2}' | grep -v "^$" | head -5)
    if [ -n "$TAILSCALE_HOSTS" ]; then
        log "Tailscale hosts detected: $(echo $TAILSCALE_HOSTS | tr '\n' ' ')"
    fi
fi

log "=== SSH/Git Config Monitor Complete ===" 
exit 0
