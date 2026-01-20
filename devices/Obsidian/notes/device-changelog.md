## 2026-01-19 16:30:00 - [FIX]

**Description**: Fixed dialog daemon inconsistent toggling and systemd integration

**Files**: 
- home-manager-module/default.nix (added mcp.dialog options with systemd service)
- tools/cursor-studio (improved systemd user service support, Nix package detection)
- tools/cursor-dialog-daemon/README.md (updated installation docs)
- .cursor/rules/interactive-dialogs.mdc (updated with systemd commands)

**Notes**:
- **Home Manager Integration**: Added `programs.cursor.mcp.dialog.enable` option
  - Creates systemd user service that starts on login
  - Installs cursor rules automatically
  - Adds `cursor-dialog-cli` to PATH
  - Options: `autoStart`, `installRules`, `addToPath`
- **cursor-studio Improvements**:
  - Now prefers Nix-built package (properly wrapped with Wayland libs)
  - Creates systemd user service instead of `nohup` for lifecycle management
  - Auto-enables systemd service on `dialog enable`
  - Detects Home Manager managed services to avoid conflicts
  - Updated status output shows autostart state and service manager
- **Root Cause**: The old `nohup` approach didn't survive reboots and the cargo-built
  binary lacked proper library wrapping for Wayland/egui GUI mode

---

## 2026-01-18 02:00:00 - [UPDATE]

**Description**: Comprehensive documentation update for v0.3.x release

**Files**: 
- README.md (complete rewrite)
- .github/workflows/build.yml (removed 1.6.x)
- .github/workflows/release.yml (removed 1.6.x, updated highlights)
- CHANGELOG.md (added v0.3.1)

**Notes**:
- Updated version badge to v0.3.1
- Fixed version count (69 versions, not 64+)
- Updated roadmap (v0.3.x current, not v0.2.x)
- Added Interactive Dialog System documentation
- Removed 1.6.x from CI (EOL by Cursor)
- Created GitHub releases for v0.3.0 and v0.3.1
- All documentation links verified

---

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
