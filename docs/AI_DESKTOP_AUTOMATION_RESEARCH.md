# AI Desktop Automation Research

**Date**: 2026-01-18  
**Status**: Phase 1 IMPLEMENTED ✅  
**Goal**: Enable AI agents to interact with native desktop applications independently, without interfering with user's input

## 📊 Implementation Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1: Basic Infrastructure | ✅ Complete | kdotool, dotool, ydotool installed via NixOS module |
| Phase 2: Custom Service | 🔄 In Progress | Python/Nushell agent-service.py created |
| Phase 3: Vision Integration | 📋 Planned | UI-TARS model integration |
| Phase 4: Full Integration | 📋 Planned | Cursor Studio integration |

### What's Working Now

**NixOS Configuration** (committed to homelab repo):

- `homelab.apps.desktop-automation.enable = true` in Obsidian config
- New module: `modules/apps/desktop-automation.nix`
- User `e421` added to `input` group
- `uinput` kernel module loaded
- `ydotoold` service configured

**Tools Available After Rebuild**:

- `kdotool` - KDE Wayland window control via KWin DBus
- `dotool` - Simple input simulation (recommended)
- `ydotool` - Full-featured input simulation
- `grim` + `slurp` - Wayland screenshot tools

**Scripts Created** (in nixos-cursor repo):

- `/tools/desktop-automation/agent-service.py` - Direct LLM tool execution (NO MCP)
- `/tools/desktop-automation/desktop-agent.nu` - Nushell automation commands
- `/tools/desktop-automation/nixos-module.nix` - Reference module (now in homelab)

## 🔬 Related Projects Analysis

### 1. UI-TARS Desktop (ByteDance) - ⭐ 24K stars

**Repository**: <https://github.com/bytedance/UI-TARS-desktop>

**What it is:**

- A multimodal AI agent stack with two components:
  - **Agent TARS**: CLI + Web UI for general multimodal AI tasks with MCP integration
  - **UI-TARS Desktop**: Native desktop app for GUI automation using the UI-TARS vision model

**Key Features:**

- Vision-language model (UI-TARS-1.5-7B) that understands screenshots
- `@ui-tars/sdk` - Cross-platform toolkit for building GUI automation agents
- Operators: NutJSOperator (desktop), WebOperator (browser), MobileOperator
- MCP (Model Context Protocol) integration built-in
- Local and remote computer/browser control
- Works on macOS, Windows (Linux support unclear)

**Architecture:**

```
User → GUIAgent → UITarsModel (vision) → Operator → System
                     ↓
              screenshot() + execute()
```

**Fit for Our Use Case:**

| Aspect | Fit | Notes |
|--------|-----|-------|
| Vision Model | ✅ Excellent | Can understand UI elements from screenshots |
| Linux/Wayland | ⚠️ Unknown | Primarily macOS/Windows, may need adaptation |
| MCP Integration | ✅ Excellent | Native MCP support |
| Isolation | ❌ Poor | Designed for single-user control, not parallel operation |
| Cursor Integration | ⚠️ Possible | Could complement Cursor's lack of computer-use |

**How to Adapt:**

1. The SDK (`@ui-tars/sdk`) could be wrapped as an MCP server
2. Create a Linux/Wayland operator using our kdotool/ydotool stack
3. Run UI-TARS model locally via Ollama or remote API
4. Integrate screenshot capture from our existing tooling

---

### 2. Open Interpreter - ⭐ 61K stars

**Repository**: <https://github.com/openinterpreter/open-interpreter>

**What it is:**

- Natural language interface for computers
- LLMs run code (Python, JS, Shell) locally
- Terminal-based ChatGPT-like interface

**Key Features:**

- Code execution with approval workflow
- Browser control via code
- File manipulation
- Multi-language support (Python, JS, Shell)
- Voice interface available

**Architecture:**

```
User → "interpreter" CLI → LLM → Code Generation → Local Execution
                                      ↓
                              User Approval → Run
```

**Fit for Our Use Case:**

| Aspect | Fit | Notes |
|--------|-----|-------|
| Code Execution | ✅ Excellent | Already runs arbitrary code |
| Vision/GUI | ❌ Poor | Text-based, no native GUI understanding |
| Linux/Wayland | ✅ Good | Works anywhere Python works |
| Isolation | ⚠️ Medium | Runs in terminal, but shares system |
| Cursor Integration | ⚠️ Possible | Could run alongside Cursor |

**How to Adapt:**

1. Could serve as execution layer for GUI commands
2. Add vision capabilities by integrating screenshot + UI-TARS model
3. Wrap as MCP server for Cursor integration
4. Use its code approval pattern for safety

---

### Comparison Matrix

| Feature | UI-TARS Desktop | Open Interpreter | Our Approach |
|---------|-----------------|------------------|--------------|
| **Vision/GUI Understanding** | ✅ Native (UI-TARS model) | ❌ None | 🔨 Need to add |
| **Code Execution** | ⚠️ Limited | ✅ Native | 🔨 Via shell |
| **Linux/Wayland** | ⚠️ Unknown | ✅ Works | ✅ Native focus |
| **MCP Integration** | ✅ Native | ❌ None | 🔨 Building |
| **Input Isolation** | ❌ None | ❌ None | 🔨 Key goal |
| **Cursor Integration** | ⚠️ Possible | ⚠️ Possible | ✅ Native |
| **Local Model Support** | ✅ Yes | ✅ Yes | ✅ Via Ollama |
| **Safety/Approval** | ⚠️ Basic | ✅ Good | 🔨 Need to add |

---

### 🎯 Recommended Integration Strategy

**Hybrid Approach: Best of All Worlds**

```
┌─────────────────────────────────────────────────────────────┐
│                     Cursor Studio                            │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Desktop Automation MCP                  │   │
│  │                                                      │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │   │
│  │  │ UI-TARS SDK  │  │   kdotool    │  │  ydotool  │ │   │
│  │  │ (Vision)     │  │ (Windows)    │  │  (Input)  │ │   │
│  │  └──────────────┘  └──────────────┘  └───────────┘ │   │
│  │           │               │               │        │   │
│  │           ▼               ▼               ▼        │   │
│  │  ┌─────────────────────────────────────────────┐  │   │
│  │  │          Unified Operator Layer             │  │   │
│  │  │  (screenshot, click, type, window mgmt)     │  │   │
│  │  └─────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Workspace Isolation Layer              │   │
│  │         (Virtual Desktop / Nested Compositor)       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**Phase 1: Basic Infrastructure**

- Implement kdotool + ydotool wrapper
- Create basic MCP server for desktop actions
- Test virtual desktop isolation

**Phase 2: Vision Integration**

- Run UI-TARS model locally (7B fits in 16GB VRAM)
- Add screenshot → model → action pipeline
- Implement element detection from screenshots

**Phase 3: Full Integration**

- Merge into Cursor Studio
- Add safety/approval workflows
- Polish isolation and handoff

## 🎯 The Vision

Create a "second cursor" capability where the AI can:

- Navigate and interact with applications autonomously
- Work on a separate workspace/screen from the user
- Not conflict with user's mouse/keyboard input
- Capture screenshots and observe application state

## 📊 Available Tools Discovery

### Window Management (KDE/Wayland)

| Tool | Status | Capabilities |
|------|--------|--------------|
| **kdotool** | ✅ Available (nixpkgs) | Search windows, activate, resize, move, get geometry |
| **KWin DBus** | ✅ Built-in | queryWindowInfo, window manipulation, virtual desktops |
| **KWin Scripting** | ✅ Built-in | JavaScript API for advanced window automation |

### Input Simulation

| Tool | Status | Capabilities |
|------|--------|--------------|
| **ydotool** | 📦 In nixpkgs | Mouse, keyboard simulation (needs ydotoold daemon) |
| **dotool** | 📦 In nixpkgs | Mouse, keyboard via uinput (simpler than ydotool) |
| **libei** | 📦 In nixpkgs | Modern Wayland input emulation (needs RemoteDesktop portal) |
| **wtype** | ❌ Not found | Wayland typing (would need to check) |

### Virtual Displays / Isolation

| Tool | Status | Use Case |
|------|--------|----------|
| **cage** | 📦 In nixpkgs | Kiosk compositor - run single app in window |
| **weston** | 📦 In nixpkgs | Full compositor with headless backend |
| **wayvnc** | 📦 In nixpkgs | VNC server for wlroots compositors |
| **KDE Virtual Desktops** | ✅ Built-in | Separate workspaces via DBus |
| **KDE Activities** | ✅ Built-in | Separate app contexts |

### Current System Status

```
✅ kdotool - Can find "Cursor Studio" windows
✅ KWin DBus - queryWindowInfo working
✅ xdg-desktop-portal - Running (for permissions)
❌ User not in input group (needed for uinput)
❌ ydotoold not running
❌ RemoteDesktop portal not enabled
```

## 🏗️ Architecture Options

### Option A: Virtual Desktop Isolation (Simplest)

```
┌─────────────────────────────────────────────────┐
│                  KDE Plasma                      │
│  ┌──────────────┐    ┌──────────────────────┐   │
│  │  Desktop 1   │    │     Desktop 2        │   │
│  │  (User)      │    │     (AI Agent)       │   │
│  │              │    │                      │   │
│  │  Browser     │    │  Cursor Studio       │   │
│  │  Terminal    │    │  Test Apps           │   │
│  │              │    │                      │   │
│  └──────────────┘    └──────────────────────┘   │
│         ↑                      ↑                 │
│    User Input          kdotool + ydotool        │
└─────────────────────────────────────────────────┘
```

**Implementation:**

```bash
# Create AI workspace
qdbus org.kde.KWin /VirtualDesktopManager createDesktop 1 "AI Workspace"

# Move window to AI desktop
kdotool search --name "Cursor Studio" set_desktop_for_window %1 2

# Switch to AI desktop for operations
qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.setCurrent <desktop-id>

# Do work with ydotool
echo "mousemove 100 100" | dotool
echo "click left" | dotool
echo "type 'Hello World'" | dotool

# Switch back to user desktop
```

**Pros:**

- Uses native KDE features
- Minimal additional setup
- Apps still "native"

**Cons:**

- Shared input devices (potential glitches)
- Need uinput access
- User can accidentally switch to AI desktop

---

### Option B: Nested Compositor (cage/weston)

```
┌─────────────────────────────────────────────────┐
│                  KDE Plasma                      │
│  ┌──────────────────────────────────────────┐   │
│  │            Regular Desktop                │   │
│  │                                           │   │
│  │   ┌─────────────────────────────────┐    │   │
│  │   │     Cage/Weston Window          │    │   │
│  │   │   (Nested Wayland Compositor)   │    │   │
│  │   │                                 │    │   │
│  │   │   ┌───────────────────────┐    │    │   │
│  │   │   │   Cursor Studio       │    │    │   │
│  │   │   │   (runs inside cage)  │    │    │   │
│  │   │   └───────────────────────┘    │    │   │
│  │   │         AI has full control    │    │   │
│  │   └─────────────────────────────────┘    │   │
│  │                                           │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**Implementation:**

```bash
# Start cage with Cursor Studio inside
cage -- cursor-studio &

# Get cage window ID
CAGE_WIN=$(kdotool search --class cage)

# Now we can:
# 1. Take screenshots of the cage window
# 2. Send input ONLY to cage (via wayvnc or wl-paste/wtype inside)
```

**Pros:**

- Complete input isolation
- AI can't affect user's apps
- Clean separation

**Cons:**

- Apps look "embedded" in a window
- Slightly different visual appearance
- More complex setup

---

### Option C: Headless Session + VNC (Most Isolated)

```
┌────────────────────────────────────────┐
│            User's KDE Session          │
│   (Normal desktop, unaffected)         │
└────────────────────────────────────────┘
           │ VNC Viewer (optional)
           ↓
┌────────────────────────────────────────┐
│      Headless Weston Session           │
│  WAYLAND_DISPLAY=wayland-ai            │
│                                        │
│   ┌────────────────────────────────┐   │
│   │       Cursor Studio            │   │
│   │    (AI has full control)       │   │
│   └────────────────────────────────┘   │
│                                        │
│      ← wayvnc for remote access        │
│      ← grim for screenshots            │
│      ← ydotool for input               │
└────────────────────────────────────────┘
```

**Implementation:**

```bash
# Start headless Wayland session
weston --backend=headless --width=1920 --height=1080 &
export WAYLAND_DISPLAY=wayland-1

# Or with VNC access
weston --backend=vnc --width=1920 --height=1080 --vnc-port=5900 &

# Start app in that session
WAYLAND_DISPLAY=wayland-1 cursor-studio &

# AI connects via VNC or uses tools directly
# Screenshots: WAYLAND_DISPLAY=wayland-1 grim screenshot.png
# Input: WAYLAND_DISPLAY=wayland-1 ydotool mousemove 100 100
```

**Pros:**

- Complete isolation
- Can run without any visible window
- Perfect for CI/testing scenarios
- User completely unaffected

**Cons:**

- Most complex setup
- User can't see AI's work without VNC viewer
- Potential performance overhead

---

### Option D: KDE Activities (Native Separation)

```
┌─────────────────────────────────────────────────┐
│                  KDE Plasma                      │
│  ┌──────────────────────────────────────────┐   │
│  │         Activity: "Default"               │   │
│  │         (User's normal work)              │   │
│  └──────────────────────────────────────────┘   │
│                      ↕ Switch                    │
│  ┌──────────────────────────────────────────┐   │
│  │         Activity: "AI Agent"              │   │
│  │         (AI's workspace)                  │   │
│  │         - Different app set               │   │
│  │         - Different wallpaper (visual cue)│   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**Pros:**

- Native KDE feature
- Apps can have different states per activity
- Visual distinction

**Cons:**

- Still shares input devices
- Activities aren't as isolated as virtual displays

---

## 🛠️ Required Setup for Each Option

### Common Requirements

```nix
# Add to NixOS configuration
environment.systemPackages = with pkgs; [
  kdotool        # Window management
  ydotool        # Input simulation (needs daemon)
  dotool         # Simpler input simulation
  spectacle      # Screenshots
  grim           # Wayland screenshots
];

# For ydotool/dotool (uinput access)
users.users.e421.extraGroups = [ "input" ];

# Enable ydotool daemon
systemd.user.services.ydotoold = {
  description = "ydotool daemon";
  wantedBy = [ "graphical-session.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.ydotool}/bin/ydotoold";
    Restart = "on-failure";
  };
};
```

### For Option B (Nested Compositor)

```nix
environment.systemPackages = with pkgs; [
  cage
  # or
  weston
  wayvnc
];
```

### For Option C (Headless Session)

```nix
environment.systemPackages = with pkgs; [
  weston
  wayvnc
];

# Optionally create a systemd service for the headless session
systemd.user.services.ai-wayland-session = {
  description = "AI Headless Wayland Session";
  wantedBy = [ "graphical-session.target" ];
  serviceConfig = {
    ExecStart = "${pkgs.weston}/bin/weston --backend=headless --width=1920 --height=1080";
    Environment = "WAYLAND_DISPLAY=wayland-ai";
  };
};
```

## 🎮 Proposed MCP Tool Interface

Create an MCP server that exposes these capabilities:

```typescript
interface DesktopAutomationMCP {
  // Window Management
  listWindows(): Window[];
  focusWindow(windowId: string): void;
  getWindowGeometry(windowId: string): Geometry;
  moveWindow(windowId: string, x: number, y: number): void;
  
  // Input Simulation
  mouseMove(x: number, y: number): void;
  mouseClick(button: 'left' | 'right' | 'middle'): void;
  type(text: string): void;
  keyPress(key: string): void;
  
  // Screenshot
  captureWindow(windowId: string): Image;
  captureRegion(x: number, y: number, w: number, h: number): Image;
  
  // Workspace Management
  switchToAIWorkspace(): void;
  switchToUserWorkspace(): void;
  isOnAIWorkspace(): boolean;
}
```

## 📋 Recommended Implementation Path

### Phase 1: Basic Capability (1-2 days)

1. Add user to `input` group
2. Install and configure ydotoold
3. Create wrapper scripts for basic operations
4. Test kdotool window targeting

### Phase 2: Virtual Desktop Isolation (1 day)

1. Create "AI Workspace" virtual desktop
2. Script to move target apps there
3. Script to switch desktops safely
4. Test input isolation

### Phase 3: MCP Integration (2-3 days)

1. Create MCP server wrapping the tools
2. Add screenshot capabilities
3. Add input simulation
4. Test with Claude/AI agent

### Phase 4: Advanced Isolation (Optional)

1. Implement nested compositor approach
2. Or implement headless session approach
3. Add VNC viewer integration
4. Performance optimization

## 🔒 Safety Considerations

1. **Input Isolation**: AI should never be able to affect user's active workspace without explicit permission
2. **Rate Limiting**: Limit input simulation speed to prevent runaway automation
3. **Kill Switch**: Global hotkey to immediately stop all AI input simulation
4. **Audit Logging**: Log all AI actions for debugging and safety
5. **Visual Indicator**: Show when AI is actively controlling something

## 📚 References

- [ydotool documentation](https://github.com/ReimuNotMoe/ydotool)
- [libei - Linux Input Emulation](https://gitlab.freedesktop.org/libinput/libei)
- [KDE KWin Scripting](https://develop.kde.org/docs/plasma/kwin/api/)
- [Wayland Input Method Protocol](https://wayland.freedesktop.org/docs/html/)
- [cage compositor](https://github.com/cage-kiosk/cage)
