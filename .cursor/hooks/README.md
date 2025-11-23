---
alwaysApply: true
---

# Cursor Hooks Documentation

## 📋 **Overview**

Cursor hooks are automated scripts that execute at specific points during development to enhance workflow, maintain quality, and prevent errors.

**Hook Location**: `.cursor/hooks/`

**Available Hooks**:
1. **track-edits.sh** - Tracks file edits during sessions
2. **log-session-completion.sh** - Logs session metrics and quality
3. **analyze-query-scope.sh** - Analyzes query complexity
4. **check-streaming-window.sh** - Detects Sunday streaming window on neon-laptop
5. **safety-command-check.sh** - Blocks dangerous commands like the October 18 incident
6. **monitor-ssh-git-configs.sh** - Monitors SSH/Git config changes and updates rules

---

## 🔧 **Hook Descriptions**

### **1. track-edits.sh**

**Trigger**: `file_edit`  
**Purpose**: Track all file edits during a session for continuous planning feedback

**What it does**:
- Logs every file edit with timestamp
- Creates edit history per conversation
- Feeds into session completion analysis

**Output**: `.cursor/logs/edits-<conversation_id>.log`

---

### **2. log-session-completion.sh**

**Trigger**: `conversation_end`  
**Purpose**: Analyze and log session accomplishments

**What it does**:
- Counts files edited in session
- Categorizes session quality (excellent, good, minimal)
- Generates session summary with timing
- Maintains historical session log

**Output**:
- `.cursor/logs/sessions.log` - Timestamped session entries
- `.cursor/logs/session-stats.json` - Aggregated statistics

**Example Output**:
```
[2025-10-21 10:30:00] Session abc123 completed (excellent)
  - Files edited: 8
  - Duration: 45m
  - Quality: excellent (8+ files, productive session)
```

---

### **3. analyze-query-scope.sh**

**Trigger**: `conversation_start`  
**Purpose**: Analyze user query complexity to guide token usage

**What it does**:
- Determines if query is open-ended or bounded
- Suggests maximization strategy
- Helps AI decide when to continue vs. return control

**Scope Categories**:
- **Open-ended**: Research, exploration, building features
- **Bounded**: Specific lookups, quick checks, narrow debugging

---

### **4. check-streaming-window.sh** 🆕

**Trigger**: `conversation_start`  
**Purpose**: Detect if on neon-laptop during Sunday church streaming window

**What it does**:
- Checks current device hostname
- Verifies current time in Central Time
- Detects Sunday 7:30 AM - 12:30 PM streaming window
- Automatically suggests attaching `streaming-window-awareness.mdc` rule

**Critical Features**:
- **Device-specific**: Only activates on neon-laptop
- **Time-aware**: Uses Central Time timezone
- **Auto-attach**: Signals Cursor to attach streaming rule

**Output Example**:
```
🚨 **STREAMING WINDOW DETECTED**

**Device**: neon-laptop
**Time**: Sunday October 21, 2025 09:45 AM CDT
**Status**: Church streaming window (Sunday 7:30 AM - 12:30 PM CT)

**CRITICAL**: The streaming-window-awareness rule should be attached.
```

**Log**: `/tmp/cursor-hooks-check-streaming-window.log`

---

### **5. safety-command-check.sh** 🆕

**Trigger**: `before_command_execution`  
**Purpose**: Block dangerous commands that could repeat the October 18, 2025 incident

**What it does**:
- Intercepts commands before execution
- Matches against dangerous command patterns
- HALTS execution if match detected
- Provides detailed safety warning with incident context

**Blocked Command Patterns**:
- `rm -rf ~/*` - Bulk home directory deletion
- `sqlite3 <db> "VACUUM;"` - SQLite operations on user databases
- `history -c` - History clearing
- `pkill -u $USER` - Force killing all user processes
- `rm ~/.ssh/id_*` - SSH key deletion
- `rm ~/.bashrc` - Shell config deletion
- `git reset --hard` - Destructive git operations
- `git push --force` - Force pushing
- And 15+ more dangerous patterns

**Safety Features**:
- **Pre-execution check**: Stops commands BEFORE they run
- **Pattern matching**: Uses regex to catch variations
- **Detailed warning**: Explains WHY command is dangerous
- **Incident reference**: Links to OBSIDIAN_REPAIR_SUMMARY.md
- **Safer alternatives**: Suggests better approaches

**Output Example**:
```
🚨🚨🚨 **SAFETY HALT - DANGEROUS COMMAND DETECTED** 🚨🚨🚨

**Proposed Command**: `rm -rf ~/.config/*`

**Matched Pattern**: `rm -rf ~/\.config/\*`

**Risk Assessment**: This command resembles operations from the October 18, 2025 incident that caused:
- Data loss (Cursor conversations, bash history, AppImages)
- Session invalidation (all app session tokens cleared)
- System disruption (forced shutdown/logout)

**The command has been BLOCKED for your safety.**
```

**Log**: `/tmp/cursor-hooks-safety-command-check.log`

**Exit Codes**:
- `0` - Command is safe, proceed
- `1` - Command is dangerous, HALT

---

### **6. monitor-ssh-git-configs.sh** 🆕

**Trigger**: `file_change`  
**Purpose**: Detect changes to SSH/Git configs and remind to update rules

**What it does**:
- Monitors `~/.ssh/config` and `~/.gitconfig` for changes
- Compares modification times with corresponding rule files
- Alerts when configs are newer than rules
- Extracts current configuration for reference
- Checks Tailscale status for SSH hosts

**Monitored Files**:
- `~/.ssh/config` → `.cursor/rules/ssh-efficiency.mdc`
- `~/.gitconfig` → `.cursor/rules/git-integration-testing.mdc`

**Output Example**:
```
⚠️ **SSH Configuration Change Detected**

**File**: /home/e421/.ssh/config
**Last Modified**: 2025-10-21 14:30:00

**Action Recommended**: 
The ssh-efficiency.mdc rule file may need updating to reflect current SSH configuration.

**Current SSH Hosts**:
Host neon-laptop
Host evie@Evie-Desktop
Host e421@pi-server

**Suggestions**:
1. Review changes in /home/e421/.ssh/config
2. Update .cursor/rules/ssh-efficiency.mdc if needed
3. Test SSH connections: ssh e421@<host>
4. Document any new patterns or issues
```

**Log**: `/tmp/cursor-hooks-monitor-ssh-git-configs.log`

---

## 🎯 **Hook Integration Summary**

### **Continuous Planning Loop**

```
User Query
    ↓
analyze-query-scope.sh → Determine if open-ended/bounded
    ↓
[Work on task]
    ↓
track-edits.sh → Log each file edit
    ↓
[Session ends]
    ↓
log-session-completion.sh → Analyze accomplishments
```

### **Safety & Context Loop**

```
Conversation Start
    ↓
check-streaming-window.sh → Check time/device
    ↓  (if streaming window)
    └→ Auto-attach streaming-window-awareness.mdc
    ↓
[AI proposes command]
    ↓
safety-command-check.sh → Check for dangerous patterns
    ↓  (if dangerous)
    └→ HALT and warn user
    ↓
[Command executes if safe]
```

### **Configuration Sync Loop**

```
[SSH/Git config modified]
    ↓
monitor-ssh-git-configs.sh → Detect modification time change
    ↓
Alert: "Rule file may be outdated"
    ↓
[User/AI updates rule file]
```

---

## 📊 **Hook Metrics**

### **Session Quality Scoring**

From `log-session-completion.sh`:

| Files Edited | Quality | Description |
|--------------|---------|-------------|
| 10+ | Excellent | Highly productive, comprehensive work |
| 5-9 | Good | Multiple files, solid progress |
| 2-4 | Minimal | Small changes, focused work |
| 0-1 | Unknown | Read-only or incomplete session |

### **Safety Statistics**

From `safety-command-check.sh`:

| Metric | Count |
|--------|-------|
| Dangerous patterns monitored | 20+ |
| Commands blocked (lifetime) | Logged |
| Incidents prevented | 🎯 Goal: 100% |

---

## 🛠️ **Hook Management**

### **Testing a Hook**

```bash
# Test streaming window check
./.cursor/hooks/check-streaming-window.sh

# Test safety check (with mock command)
echo "rm -rf ~/.config/*" | ./.cursor/hooks/safety-command-check.sh

# Test SSH/Git monitor
./.cursor/hooks/monitor-ssh-git-configs.sh
```

### **Viewing Hook Logs**

```bash
# Streaming window log
tail -f /tmp/cursor-hooks-check-streaming-window.log

# Safety check log
tail -f /tmp/cursor-hooks-safety-command-check.log

# SSH/Git monitor log
tail -f /tmp/cursor-hooks-monitor-ssh-git-configs.log

# Session logs
tail -f .cursor/logs/sessions.log
```

### **Disabling a Hook**

```bash
# Temporarily disable (remove execute permission)
chmod -x .cursor/hooks/safety-command-check.sh

# Re-enable
chmod +x .cursor/hooks/safety-command-check.sh
```

---

## 🔗 **Related Documentation**

- [.cursor/rules/streaming-window-awareness.mdc](mdc:.cursor/rules/streaming-window-awareness.mdc) - Streaming window rule
- [.cursor/rules/safety-guardrails.mdc](mdc:.cursor/rules/safety-guardrails.mdc) - Safety rules
- [.cursor/rules/ssh-efficiency.mdc](mdc:.cursor/rules/ssh-efficiency.mdc) - SSH patterns
- [.cursor/rules/git-integration-testing.mdc](mdc:.cursor/rules/git-integration-testing.mdc) - Git workflows
- [OBSIDIAN_REPAIR_SUMMARY.md](mdc:OBSIDIAN_REPAIR_SUMMARY.md) - October 18 incident report

---

## 🎯 **Success Criteria**

These hooks are successful when:

- ✅ Sessions are automatically tracked and analyzed
- ✅ Dangerous commands are caught before execution
- ✅ Streaming window is detected and handled appropriately
- ✅ Configuration changes prompt rule updates
- ✅ Zero incidents resembling past mistakes
- ✅ AI has better context for decision-making

---

**Last Updated**: October 21, 2025  
**Hooks Version**: 2.0  
**Status**: ✅ Production Ready
