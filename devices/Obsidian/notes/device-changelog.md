## 2026-01-18 01:30:00 - [UPDATE]

**Description**: Released cursor-studio v0.3.0 with Interactive Dialog System

**Files**: 
- flake.nix (added cursor-dialog-daemon, cursor-dialog-cli packages)
- tools/cursor-dialog-daemon/default.nix (updated to v0.3.0)
- CHANGELOG.md (release notes)
- All dialog daemon source files committed

**Notes**:
- Tagged and pushed v0.3.0 to GitHub
- Flake packages now include: cursor-dialog-daemon, cursor-dialog-cli
- Apps: cursor-dialog-daemon, cursor-dialog-cli available via `nix run`
- cursor-studio dialog commands: enable, disable, start, stop, status, test
- Merged pre-release → main
- Full feature set: dialogs, toasts, sidebar, comments, pause timer, sounds, window attention

---

## 2026-01-17 15:00:00 - [SCRIPT]

**Description**: Created D-Bus Interactive Dialog System for AI Agent Feedback

**Files**: 
- tools/cursor-dialog-daemon/ (new Rust project)
- .cursor/rules/interactive-dialogs.mdc (agent integration rule)
- docs/designs/INTERACTIVE_DIALOG_SYSTEM.md (architecture doc)
- docs/PROJECT_MAP.md (updated)

**Notes**:
- Built `cursor-dialog-daemon` - D-Bus service (`sh.cursor.studio.Dialog`) for AI agents to request user input mid-task
- Supports: multiple choice, text input, confirmation, slider, file picker dialogs
- GUI rendered with egui/eframe, D-Bus via zbus
- CLI tool `cursor-dialog-cli` for testing and agent integration
- Inspired by Claude Coworker's inline affordances pattern
- Linux-only (D-Bus); Darwin fallback (Unix sockets) planned as Option B
- Binary sizes: daemon ~15MB, CLI ~4MB
- Successfully tested: ping, info endpoints working via D-Bus

---

## YYYY-MM-DD HH:MM:SS - [FIX]

**Description**: Fixed critical Streaming Deadlock in Cursor Proxy and verified Context Injection

**Files**: tools/proxy-test/cursor-proxy/src/main.rs, tools/proxy-test/cursor-proxy/src/injection.rs

**Notes**:
- Implemented "Framing-Aware Buffering" to handle bi-directional gRPC streams without deadlock.
- Implemented "Context File Strategy" for injection: injecting `system-context.md` into the Protobuf `ConversationHistory` avoids checksum validation issues and schema corruption.
- Verified with "Red Team" prompt: Agent successfully ignored user prompt and focused on injected "Stratum Project" instruction.
- Documented Sidecar Agent and Headless Cursor research.
