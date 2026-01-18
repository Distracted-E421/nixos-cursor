# Interactive Dialog System Architecture

**Status**: MVP Complete (D-Bus + egui)
**Created**: 2026-01-17
**Author**: e421 + Maxim (Claude Opus 4)

## Problem Statement

AI agents in Cursor need user input mid-task (e.g., "How detailed should this summary be?"), but have only bad options:

1. **Ask in chat** → Burns an API request, breaks flow
2. **Assume a default** → May not match user preference

Claude Coworker demonstrated inline affordances (multiple choice in response), but Cursor's UI doesn't support this.

## Solution: D-Bus Dialog Daemon

A standalone daemon that:

1. Registers as D-Bus service `sh.cursor.studio.Dialog`
2. Exposes structured dialog methods (choice, text, confirm, slider, etc.)
3. Renders native dialogs via egui
4. Returns results synchronously via D-Bus

```
┌───────────────────────────────────────────────────────────────────────┐
│                         ARCHITECTURE                                   │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   Agent (in Cursor)                          User                     │
│   ┌──────────────────┐                      ┌────────────────────┐    │
│   │ run_terminal_cmd │  D-Bus call          │ Dialog Daemon      │    │
│   │ cursor-dialog-cli│ ────────────────────▶│ (egui window)      │    │
│   │                  │                       │                    │    │
│   │                  │ ◀──────────────────── │  ○ Minimal         │    │
│   │                  │  D-Bus response       │  ● Standard        │    │
│   └──────────────────┘                       │  ○ Verbose         │    │
│                                              └────────────────────┘    │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

## Why D-Bus?

| Alternative | Pros | Cons |
|-------------|------|------|
| **D-Bus** (chosen) | Type-safe, synchronous, Linux-native, service discovery | Linux-only |
| Unix Sockets | Cross-platform, simple | Manual protocol, no discovery |
| File Watcher | Simple, reliable | Non-deterministic timing |
| MCP | Cursor-native | npm supply chain, flaky, text-only |

D-Bus provides the **determinism** we need for reliable agent flows, vs heuristic-based file watching.

## Components

### 1. Dialog Daemon (`cursor-dialog-daemon`)

- **Language**: Rust
- **GUI**: egui/eframe
- **IPC**: zbus (D-Bus bindings)
- **Binary Size**: ~15MB (release, stripped)

Capabilities:
- Multiple choice (single/multi-select)
- Text input (single/multiline, with validation)
- Confirmation (yes/no with custom labels)
- Slider (numeric range with units)
- Progress notifications (non-blocking)
- File picker (file/folder/save)

### 2. CLI Tool (`cursor-dialog-cli`)

- Lightweight CLI for testing and agent integration
- Binary Size: ~4MB
- Outputs JSON for easy parsing in shell scripts

### 3. Cursor Rules (`.cursor/rules/interactive-dialogs.mdc`)

Teaches agents how to use the dialog system:
- When to use (user preference, confirmation, input)
- How to call (CLI examples)
- Response parsing
- Error handling
- Best practices

## D-Bus Interface

**Service**: `sh.cursor.studio.Dialog`
**Path**: `/sh/cursor/studio/Dialog`
**Interface**: `sh.cursor.studio.Dialog1`

### Methods

| Method | Arguments | Returns |
|--------|-----------|---------|
| `ShowChoice` | title, prompt, options (JSON), default, allow_multiple, timeout_ms | JSON response |
| `ShowTextInput` | title, prompt, placeholder, default, multiline, validation, timeout_ms | JSON response |
| `ShowConfirmation` | title, prompt, yes_label, no_label, default_yes, timeout_ms | JSON response |
| `ShowSlider` | title, prompt, min, max, step, default, unit, timeout_ms | JSON response |
| `ShowFilePicker` | title, prompt, mode, filters, default_path | JSON response |
| `ShowProgress` | title, message, progress | notification ID |
| `Ping` | - | "pong" |
| `GetInfo` | - | JSON with version and capabilities |

### Response Format

```json
{
  "id": "uuid",
  "selection": <value>,
  "cancelled": false,
  "error": null,
  "timestamp": 1705512345
}
```

## Agent Integration Example

```bash
# In a Cursor agent session:
result=$(cursor-dialog-cli choice \
  --title "Refactoring Approach" \
  --prompt "How should I approach this refactor?" \
  --options '[
    {"value":"minimal","label":"Minimal","description":"Fix only the reported issue"},
    {"value":"thorough","label":"Thorough","description":"Also update related code"},
    {"value":"comprehensive","label":"Comprehensive","description":"Full modernization"}
  ]' \
  --timeout 30)

approach=$(echo "$result" | jq -r '.selection // "minimal"')

# Agent proceeds based on user choice without burning another API request
```

## Trade-offs & Decisions

### Decision 1: D-Bus over MCP

**Rationale**: MCP's npm dependency introduces supply chain risk, and its text-only output doesn't support rich UI. D-Bus provides type-safe, synchronous IPC.

**Trade-off**: Linux-only. Darwin users need fallback (Option B: Unix sockets).

### Decision 2: egui over GTK/Qt

**Rationale**: egui is pure Rust, compiles easily, looks modern, and has no runtime dependencies beyond OpenGL.

**Trade-off**: Doesn't use native widgets (but can look native with theming).

### Decision 3: Separate Daemon vs Cursor Integration

**Rationale**: Cursor's UI is locked down. A separate window is the only option without modifying Cursor itself.

**Trade-off**: Extra window management, but also flexibility (can be used outside Cursor).

## Future Work

1. **Darwin/Windows Support**
   - Implement Option B (Unix sockets) as fallback
   - Or use native dialog libraries (Cocoa/Win32)

2. **Cursor Integration**
   - Monitor for official affordance support
   - Potential extension point if discovered

3. **Context Summarization Fix**
   - Related but separate: intercept `ConversationSummaryStrategy` via proxy
   - Prevent aggressive truncation after 10-20+ messages

4. **Theme Sync**
   - Read Cursor's theme settings
   - Match dialog appearance to IDE

## Related Files

- `tools/cursor-dialog-daemon/` - Main implementation
- `.cursor/rules/interactive-dialogs.mdc` - Agent integration rules
- `docs/designs/INTERACTIVE_DIALOG_SYSTEM.md` - This document

## Balance: Determinism vs Heuristics

This system exemplifies the balance we're pursuing:

- **Deterministic**: D-Bus provides structured, reliable IPC
- **Heuristic**: Agent decides *when* to use dialogs based on context

The dialog system is a tool for the heuristic agent to use when it determines user input would be valuable. The tool itself is deterministic; the decision to use it is learned.

This pattern will continue as we move toward neurosymbolic approaches:
- Symbolic/deterministic components for reliable operations
- Neural/heuristic components for decision-making
- Clear interfaces between them

