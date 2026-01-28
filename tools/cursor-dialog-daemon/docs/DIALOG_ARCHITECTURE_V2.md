# Dialog System Architecture v2

## 🎯 Design Philosophy

**Dialogs are the primary human-AI communication channel.** They should:

1. **Default to blocking** - AI waits for immediate feedback
2. **Support async when needed** - For AFK scenarios with notification
3. **Enable rich content** - Beyond simple text prompts
4. **Allow user-initiated contact** - Human can poke AI anytime

---

## 📋 Dialog Modes

### Mode 1: Blocking (Default)

```bash
# AI waits for response - THIS IS THE DEFAULT
result=$(cursor-dialog-cli confirm --title "Question" --prompt "Yes or no?")
# Execution continues only after user responds
```

**When to use:**

- ✅ All normal interactions
- ✅ Decision points requiring immediate feedback
- ✅ Confirmation before actions

### Mode 2: Async with Callback (AFK Mode)

```bash
# AI continues but gets notified when user responds
cursor-dialog-cli --async --callback-file /tmp/dialog-response.json confirm ...
# AI can poll /tmp/dialog-response.json or receive notification
```

**When to use:**

- ⚠️ ONLY when user explicitly says they're AFK
- ⚠️ For low-priority questions that can wait
- ⚠️ Never for decisions affecting current work

### Implementation TODO

- [ ] Add `--async` flag to CLI
- [ ] Add `--callback-file <path>` for response storage
- [ ] Add `--callback-dbus <signal>` for D-Bus notification
- [ ] Add `--callback-webhook <url>` for remote notification

---

## 🖼️ Rich Content Support

### Current (v0.5.0)

- Plain text prompts
- Simple newline formatting
- Basic unicode emoji

### Proposed Enhancements

#### Markdown Rendering

```bash
cursor-dialog-cli --markdown choice \
  --title "Code Review" \
  --prompt "## Changes Summary\n\n- **5 files** modified\n- Added `AuthService`\n- Fixed bug in \`utils.rs\`\n\n```rust\nfn example() {\n    println!(\"Preview\");\n}\n```" \
  --options '[...]'
```

#### Image/Screenshot Embedding

```bash
cursor-dialog-cli --image /tmp/screenshot.png choice \
  --title "Visual Confirmation" \
  --prompt "Does this look correct?" \
  --options '[{"value":"yes","label":"Yes"},{"value":"no","label":"No"}]'
```

#### Diagram Support (D2/Mermaid)

```bash
cursor-dialog-cli --diagram "
direction: right
User -> Dialog: Request
Dialog -> AI: Response
AI -> Action: Execute
" choice --title "Workflow Confirmation" ...
```

#### Graph/Chart Templates

```bash
# Progress bar
cursor-dialog-cli progress \
  --title "Build Progress" \
  --current 45 --total 100 \
  --message "Compiling module 45/100..."

# Summary card
cursor-dialog-cli summary \
  --title "Session Progress" \
  --completed '["Task A","Task B"]' \
  --pending '["Task C"]' \
  --stats '{"files_changed":12,"lines_added":340}'
```

---

## 🔔 User-Initiated Dialog ("Poke the AI")

### Desktop Methods

1. **Global Hotkey** (e.g., `Super+Shift+D`)
   - Opens dialog: "What would you like to tell the AI?"
   - Response written to watched file or D-Bus signal

2. **System Tray Icon**
   - Click to open "Talk to AI" dialog
   - Shows queue status, active dialogs

3. **KRunner Integration**
   - Type "ai: message here" to send to AI

### Mobile Methods

1. **Persistent Notification Action**
   - "Send Message to AI" button in notification

2. **Quick Tile**
   - Android quick settings tile to open dialog

3. **Widget**
   - Home screen widget for quick messages

### Implementation

```rust
// New D-Bus method for user-initiated messages
interface sh.cursor.studio.Dialog1 {
    // Existing...
    
    // NEW: User wants to talk
    method UserMessage(message: String) -> (id: String, queued: Boolean);
    
    // Signal when user sends message
    signal UserMessageReceived(id: String, message: String, timestamp: u64);
}
```

---

## 📊 Session Summary Anti-Pattern Co-option

### The Problem

AI agents often try to "conclude" sessions with summaries, burning requests without productive work.

### The Solution: Make Summary Part of Dialog

Instead of AI generating text summaries, use the dialog system:

```bash
# AI uses this instead of printing summary
cursor-dialog-cli summary \
  --title "Session Progress" \
  --format "card" \
  --completed '[
    "Fixed dialog daemon lock contention",
    "Created Synapsix project",
    "Integrated Zig NIF"
  ]' \
  --in_progress '["Testing Android app"]' \
  --pending '["Expand harness capabilities"]' \
  --stats '{"requests_used":4,"files_changed":23}' \
  --prompt "Continue working or end session?" \
  --options '[
    {"value":"continue","label":"Continue","description":"Keep working on pending tasks"},
    {"value":"next","label":"Next Priority","description":"Move to next priority item"},
    {"value":"done","label":"Done for now","description":"End session"}
  ]'
```

**Benefits:**

- Summary is actionable (user chooses next step)
- Doesn't burn request on pure summary
- User controls session flow
- History is preserved in daemon

---

## 🔄 Sync Architecture

### Current Flow

```
┌─────────────┐    D-Bus     ┌──────────────┐    WebSocket    ┌───────────┐
│   AI Agent  │ ──────────►  │    Daemon    │ ◄────────────►  │  Phone App│
│  (Cursor)   │ ◄──────────  │  (Desktop)   │                 │           │
└─────────────┘   Response   └──────────────┘                 └───────────┘
```

### Enhanced Flow with Notifications

```
┌─────────────┐    D-Bus     ┌──────────────┐    WebSocket    ┌───────────┐
│   AI Agent  │ ──────────►  │    Daemon    │ ◄────────────►  │  Phone App│
│  (Cursor)   │ ◄──────────  │  (Desktop)   │                 │           │
└──────┬──────┘   Response   └──────┬───────┘                 └─────┬─────┘
       │                            │                               │
       │                            │  Desktop Notification         │
       │                      ┌─────▼─────┐                        │
       │                      │ KDE/Plasma│                        │
       │                      │Notification│                       │
       │                      └───────────┘                        │
       │                                                           │
       │                    User Poke (any device)                 │
       └───────────────────────────────────────────────────────────┘
```

---

## 📱 Phone App Enhancements

### Required Updates

1. **Rich Content Rendering**
   - Markdown parser (commonmark)
   - Image display
   - Code syntax highlighting

2. **User Poke Button**
   - Floating action button: "Message AI"
   - Opens text input dialog
   - Sends via WebSocket

3. **Notification Actions**
   - "Reply" action on dialog notifications
   - Quick responses without opening app

4. **Widget**
   - Shows current dialog status
   - One-tap to open active dialog

---

## 🛠️ Implementation Priority

### Phase 1: Core Fixes (This Session)

- [x] Blocking dialog as default behavior
- [x] Phone app connection verified
- [ ] Document blocking vs async patterns

### Phase 2: User Poke Mechanism

- [ ] Add global hotkey (KDE shortcut)
- [ ] Add system tray icon
- [ ] Add UserMessage D-Bus method

### Phase 3: Rich Content

- [ ] Markdown rendering in daemon
- [ ] Image embedding support
- [ ] Summary dialog type

### Phase 4: Async Callbacks

- [ ] --async flag
- [ ] --callback-file support
- [ ] D-Bus signal for async responses

---

## 📝 Agent Guidelines

### DO

- ✅ Use blocking dialogs by default
- ✅ Wait for user response before continuing
- ✅ Use summary dialogs instead of text summaries
- ✅ Check for user poke messages regularly

### DON'T

- ❌ Run dialogs in background unless user is AFK
- ❌ Generate text summaries (use summary dialog)
- ❌ Assume user saw non-blocking dialog
- ❌ Continue work without dialog response
