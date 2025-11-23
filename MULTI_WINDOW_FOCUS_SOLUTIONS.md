# Multi-Window Focus Tracking: Creative Solutions

**Problem**: Electron apps (Cursor) lose keyboard input focus when using separate windows on Wayland  
**Goal**: Build a robust, cross-compositor solution for multi-window focus tracking  
**Philosophy**: Don't wait for upstream - build it ourselves!

---

## 🎯 Core Requirements

1. **Cross-Desktop Environment**: Works on Hyprland, KDE Plasma, Sway, niri, etc.
2. **Multi-Monitor Support**: Track focus across multiple displays
3. **Keyboard & Mouse Awareness**: Both input methods tracked
4. **Low Latency**: < 10ms focus change detection
5. **Nix-Native**: Declarative, reproducible configuration
6. **Non-Invasive**: Doesn't break existing window management

---

## 🚀 Solution Categories

### Category A: Wayland Protocol Extensions

#### Solution A1: Custom Foreign-Toplevel Extension

**Concept**: Extend `wlr-foreign-toplevel-management-unstable-v1` protocol

**How It Works**:
1. Create custom Wayland protocol (`cursor-focus-tracking-v1`)
2. Compositor broadcasts focus events with:
   - Window ID
   - App ID (Cursor instance)
   - Input type (keyboard/mouse)
   - Timestamp
   - Monitor ID
3. Cursor subscribes to focus events
4. Route input to correct window based on events

**Implementation Path**:
```nix
# nixos/pkgs/wayland-protocols/cursor-focus-tracking/
{
  protocolXML = ./cursor-focus-tracking-v1.xml;
  
  compositorIntegrations = {
    hyprland = ./hyprland-patch.nix;
    sway = ./sway-patch.nix;
    kwin = ./kwin-patch.nix;
  };
}
```

**Pros**:
- Native Wayland solution
- Clean architecture
- Low overhead
- Works at compositor level

**Cons**:
- Requires patching each compositor
- Needs upstream buy-in for long-term maintenance
- Compositor-specific implementations

**Feasibility**: ⭐⭐⭐ (3/5) - Medium-High complexity

---

#### Solution A2: Layer-Shell Input Overlay

**Concept**: Invisible overlay that captures and redirects input

**How It Works**:
1. Use `wlr-layer-shell` to create transparent overlay
2. Overlay sits above all windows
3. Captures ALL input events
4. Determines target window (via foreign-toplevel)
5. Re-injects input to correct Cursor window

**Implementation**:
```rust
// cursor-input-router/src/main.rs
use wayland_client::protocol::*;
use zwlr_layer_shell_v1::*;

struct InputRouter {
    layer_surface: LayerSurface,
    focus_tracker: FocusTracker,
    cursor_windows: Vec<WindowHandle>,
}

impl InputRouter {
    fn route_input(&self, event: InputEvent) {
        let target = self.focus_tracker.determine_target(event.position);
        self.inject_input(target, event);
    }
}
```

**Pros**:
- Works with ANY compositor (layer-shell widely supported)
- No compositor patching required
- Can fix focus for ALL Electron apps

**Cons**:
- Input latency (capture + re-inject)
- Complex input event handling
- Security implications (captures all input)

**Feasibility**: ⭐⭐⭐⭐ (4/5) - Medium complexity, high compatibility

---

### Category B: DBus/IPC Solutions

#### Solution B1: Compositor DBus Focus Broker

**Concept**: DBus service that brokers focus events between compositor and apps

**Architecture**:
```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  Compositor │─────▶│ Focus Broker │◀────▶│   Cursor    │
│  (Hyprland) │ IPC  │  (DBus Svc)  │ DBus │  (patched)  │
└─────────────┘      └──────────────┘      └─────────────┘
         │                    │                     │
         └────────────────────┴─────────────────────┘
                       Focus Events
```

**Implementation**:
```python
# cursor-focus-broker.py
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop

class CursorFocusBroker(dbus.service.Object):
    def __init__(self):
        self.compositor_watcher = CompositorWatcher()
        self.cursor_clients = {}
    
    @dbus.service.signal('com.cursor.FocusTracking', signature='ssi')
    def FocusChanged(self, window_id, app_id, input_type):
        """Broadcast focus change to all Cursor instances"""
        pass
    
    @dbus.service.method('com.cursor.FocusTracking')
    def RegisterWindow(self, window_id, process_id):
        """Cursor windows register themselves"""
        self.cursor_clients[window_id] = process_id
```

**Compositor Integration**:
```nix
# Hyprland example
programs.hyprland.extraConfig = ''
  # Exec focus broker on startup
  exec-once = cursor-focus-broker
  
  # Hook window focus events
  windowrule = workspace special:cursor-focus, ^(cursor)$
'';
```

**Pros**:
- Cross-compositor (if they support DBus hooks)
- Can be language-agnostic (Python, Rust, C++)
- Easy to extend (just add DBus methods)
- Works for multiple apps (not just Cursor)

**Cons**:
- Requires compositor hooks/plugins
- DBus overhead (~1-5ms latency)
- Needs Cursor to be patched to subscribe

**Feasibility**: ⭐⭐⭐⭐⭐ (5/5) - Most practical, good performance

---

#### Solution B2: Systemd User Service + Socket Activation

**Concept**: Lightweight daemon that monitors compositor state

**How It Works**:
1. Systemd user service: `cursor-focus-daemon.service`
2. Socket-activated for efficiency
3. Polls compositor via IPC (Hyprland socket, KWin DBus, etc.)
4. Maintains focus state in shared memory (`/dev/shm/cursor-focus`)
5. Cursor reads shared memory for focus state

**Implementation**:
```nix
# nixos/modules/services/cursor-focus-daemon.nix
systemd.user.services.cursor-focus-daemon = {
  description = "Cursor Multi-Window Focus Tracker";
  wantedBy = [ "graphical-session.target" ];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.cursor-focus-daemon}/bin/cursor-focus-daemon";
    Restart = "on-failure";
    
    # Shared memory for IPC
    RuntimeDirectory = "cursor-focus";
    StateDirectory = "cursor-focus";
  };
};
```

```rust
// cursor-focus-daemon/src/main.rs
use memmap2::MmapMut;
use std::sync::Arc;

struct FocusState {
    active_window_id: u64,
    keyboard_focus_pid: u32,
    mouse_hover_pid: u32,
    last_update_ms: u64,
}

impl FocusDaemon {
    fn update_shared_memory(&mut self, state: FocusState) {
        unsafe {
            let ptr = self.shm.as_mut_ptr() as *mut FocusState;
            ptr.write(state);
        }
    }
}
```

**Pros**:
- Very low latency (shared memory)
- Systemd integration (reliable)
- No DBus overhead
- Socket activation (efficient)

**Cons**:
- Still needs compositor integration
- Shared memory coordination complexity
- Per-compositor implementations

**Feasibility**: ⭐⭐⭐⭐ (4/5) - Good performance, medium complexity

---

### Category C: Electron-Specific Workarounds

#### Solution C1: Electron BrowserWindow Focus Hook

**Concept**: Patch Electron to properly handle Wayland focus events

**How It Works**:
1. Fork Electron (or use preload script)
2. Hook into `BrowserWindow.on('focus')` and `('blur')`
3. Add custom focus detection using Wayland protocols
4. Force focus to input elements when window activated

**Implementation**:
```javascript
// cursor-focus-preload.js (injected via ELECTRON_PRELOAD)
const { ipcRenderer } = require('electron');

// Listen for Wayland focus events
const waylandFocusObserver = new MutationObserver(() => {
  const hasWaylandFocus = checkWaylandFocus();
  if (hasWaylandFocus && !hasKeyboardFocus()) {
    forceFocusToInput();
  }
});

function forceFocusToInput() {
  const activeElement = document.activeElement;
  if (activeElement && activeElement.blur) {
    activeElement.blur();
  }
  
  // Find first focusable input
  const input = document.querySelector('input, textarea, [contenteditable="true"]');
  if (input) {
    input.focus();
    // Emit fake input event to trigger Electron's focus handling
    input.dispatchEvent(new Event('focus', { bubbles: true }));
  }
}
```

**Nix Integration**:
```nix
# Inject preload script
programs.cursor = {
  enable = true;
  extraElectronFlags = [
    "--preload=${pkgs.cursor-focus-preload}/share/cursor-focus-preload.js"
  ];
};
```

**Pros**:
- App-level fix (no compositor changes)
- Can be deployed immediately
- Works on any Wayland compositor

**Cons**:
- Hacky (may break with Electron updates)
- Only fixes Cursor (not general solution)
- May interfere with normal focus handling

**Feasibility**: ⭐⭐⭐⭐⭐ (5/5) - Easiest to implement, immediate

---

#### Solution C2: X11 Backend with Custom Window Manager

**Concept**: Run Cursor in XWayland with custom window manager that handles focus properly

**How It Works**:
1. Force Cursor to use X11 backend
2. Run minimal X window manager (dwm/i3)
3. Window manager handles focus correctly
4. Bridge X11 focus to Wayland compositor

**Implementation**:
```nix
# cursor-x11-wrapper.nix
let
  cursorWithX11 = pkgs.writeShellScriptBin "cursor-x11" ''
    # Force X11 backend
    export ELECTRON_OZONE_PLATFORM_HINT=x11
    
    # Start minimal WM if not running
    if ! pgrep -x "cursor-wm" > /dev/null; then
      ${pkgs.cursor-wm}/bin/cursor-wm &
    fi
    
    # Launch Cursor
    exec ${pkgs.cursor}/bin/cursor "$@"
  '';
in cursorWithX11
```

**Pros**:
- Works immediately (XWayland is stable)
- Proven focus handling (X11 mature)
- Fallback option

**Cons**:
- Not native Wayland (defeats purpose)
- Extra layer (XWayland overhead)
- Scaling issues on mixed DPI

**Feasibility**: ⭐⭐⭐ (3/5) - Easy but not ideal

---

### Category D: Input Method Protocol (IME) Hijacking

#### Solution D1: Fake IME for Input Routing

**Concept**: Create "fake" input method that routes input to correct window

**How It Works**:
1. Register as Wayland input method (`zwp_input_method_v2`)
2. Compositor routes ALL keyboard input to our IME
3. IME determines target window
4. Forward input to correct Cursor window
5. Invisible to user (pass-through most of time)

**Implementation**:
```rust
// cursor-ime-router/src/main.rs
use wayland_protocols::misc::zwp_input_method_v2::*;

struct CursorIME {
    input_method: ZwpInputMethodV2,
    cursor_windows: HashMap<u32, WindowInfo>,
}

impl ZwpInputMethodV2Handler for CursorIME {
    fn key(&mut self, key: u32, state: KeyState) {
        let target_window = self.determine_target();
        self.forward_key(target_window, key, state);
    }
}
```

**Pros**:
- Works at protocol level
- Compositor-agnostic (uses standard protocol)
- Can intercept ALL input

**Cons**:
- Conflicts with real IME (CJK input, etc.)
- Complex protocol implementation
- May interfere with other apps

**Feasibility**: ⭐⭐ (2/5) - Complex, many edge cases

---

### Category E: Hybrid Solutions (Recommended)

#### Solution E1: Multi-Layer Focus Tracking System

**Concept**: Combine multiple approaches for robustness

**Architecture**:
```
┌─────────────────────────────────────────────────────┐
│                  Cursor Application                  │
│  ┌──────────────────────────────────────────────┐   │
│  │         Electron Focus Preload Script        │   │
│  │  (Category C1 - Immediate workaround)        │   │
│  └──────────────────────────────────────────────┘   │
└───────────────────┬─────────────────────────────────┘
                    │
         ┌──────────┴──────────┐
         │                     │
    ┌────▼─────┐       ┌──────▼──────┐
    │  DBus    │       │   Shared    │
    │  Broker  │◀─────▶│   Memory    │
    │ (Cat B1) │       │  (Cat B2)   │
    └────┬─────┘       └──────┬──────┘
         │                     │
    ┌────▼─────────────────────▼─────┐
    │    Compositor Integration       │
    │  ┌──────────────────────────┐  │
    │  │ Hyprland: IPC Socket     │  │
    │  │ KDE: KWin DBus           │  │
    │  │ Sway: IPC JSON           │  │
    │  │ niri: Custom Protocol    │  │
    │  └──────────────────────────┘  │
    └─────────────────────────────────┘
```

**Layered Approach**:

**Layer 1: Immediate Workaround (Electron Preload)**
- Deploy today, fixes 80% of cases
- No compositor changes needed
- Easy to maintain

**Layer 2: System Service (DBus Broker)**
- More robust, lower latency
- Requires compositor plugin/hook
- Better multi-app support

**Layer 3: Protocol Extension (Long-term)**
- Proper Wayland solution
- Submit to wayland-protocols
- Upstream integration path

**Implementation Timeline**:
1. **Week 1-2**: Layer 1 (Electron preload) - **You can use Cursor immediately**
2. **Week 3-4**: Layer 2 (DBus broker) - **Robust solution**
3. **Month 2-3**: Layer 3 (Protocol extension) - **Future-proof**

---

## 🔧 Recommended Implementation Path

### Phase 1: Quick Fix (This Week)

**Goal**: Make Cursor usable TODAY

```nix
# nixos/pkgs/cursor-focus-fix/preload.js
// Electron preload script
const { ipcRenderer, remote } = require('electron');

let lastFocusCheck = 0;
const FOCUS_CHECK_INTERVAL = 100; // 100ms

// Poll for Wayland focus
setInterval(() => {
  const now = Date.now();
  if (now - lastFocusCheck < FOCUS_CHECK_INTERVAL) return;
  lastFocusCheck = now;
  
  // Check if window has Wayland focus but no keyboard focus
  const hasWaylandFocus = remote.getCurrentWindow().isFocused();
  const hasKeyboardFocus = document.hasFocus();
  
  if (hasWaylandFocus && !hasKeyboardFocus) {
    console.log('[Cursor Focus Fix] Restoring keyboard focus');
    
    // Try multiple focus restoration methods
    window.focus();
    document.body.focus();
    
    // Find and focus first input element
    const inputs = document.querySelectorAll('input, textarea, [contenteditable="true"], [tabindex]');
    for (const input of inputs) {
      if (input.offsetParent !== null) { // is visible
        input.focus();
        break;
      }
    }
  }
}, FOCUS_CHECK_INTERVAL);

// Also hook window focus events
window.addEventListener('focus', () => {
  console.log('[Cursor Focus Fix] Window focus event');
  // Force focus to first available input
  setTimeout(() => {
    if (!document.hasFocus()) {
      document.body.focus();
    }
  }, 50);
});

console.log('[Cursor Focus Fix] Preload script loaded');
```

**Deploy**:
```nix
# nixos/modules/apps/cursor-ide.nix
environment.variables = {
  ELECTRON_PRELOAD = "${pkgs.cursor-focus-fix}/share/preload.js";
};
```

**Test Tonight**: Rebuild, test separate windows, iterate

---

### Phase 2: Compositor Integration (Next Week)

**For Hyprland**:
```nix
# nixos/pkgs/cursor-focus-broker/hyprland-plugin.nix
{
  hyprlandPlugin = pkgs.stdenv.mkDerivation {
    name = "hyprland-cursor-focus-plugin";
    src = ./hyprland-plugin;
    
    buildInputs = [ hyprland ];
    
    # Plugin hooks into Hyprland's focus events
    # Broadcasts to DBus when Cursor windows change focus
  };
}
```

**For KDE Plasma**:
```nix
# KWin script
programs.plasma.kwin.scripts = [
  {
    name = "cursor-focus-tracker";
    script = ./kwin-cursor-focus.js;
  }
];
```

---

### Phase 3: Universal Solution (Future)

**Submit to wayland-protocols**:
1. Write spec for `cursor-focus-tracking-v1.xml`
2. Implement in wlroots (reference implementation)
3. Submit PR to wayland-protocols
4. Get compositor buy-in

---

## 💡 Creative Wild Ideas

### Idea 1: Neural Network Focus Predictor

Train ML model to predict where user wants focus based on:
- Mouse movement patterns
- Keyboard activity timing
- Window switching history
- Time of day patterns

**Feasibility**: ⭐ (1/5) - Overkill, but cool!

---

### Idea 2: Hardware USB Focus Tracker

Physical device that monitors keyboard/mouse and broadcasts focus intent:
- USB HID device
- Monitors all input
- Separate from compositor
- Broadcasts focus via DBus

**Feasibility**: ⭐⭐ (2/5) - Works but requires hardware

---

### Idea 3: Eye Tracking Focus

Use webcam + eye tracking to determine focus:
- Where user is looking = where to send input
- Library: GazeTracking (Python)
- Zero compositor changes needed

**Feasibility**: ⭐⭐ (2/5) - Privacy concerns, latency

---

## 🎯 My Recommendation

**Start with Hybrid Solution E1**:

1. **Tonight**: Implement Electron preload script (Phase 1)
   - Quick, no rebuilds
   - 80% solution
   - Test and iterate

2. **This Week**: Build DBus focus broker (Phase 2)
   - Robust, performant
   - Hyprland plugin
   - KDE KWin script

3. **Next Month**: Wayland protocol extension (Phase 3)
   - Proper long-term solution
   - Submit to wayland-protocols
   - Path to upstream

**Why This Works**:
- ✅ Immediate usability (tonight)
- ✅ Robust middle layer (this week)
- ✅ Future-proof (upstream path)
- ✅ Cross-compositor support
- ✅ Nix-native (declarative)
- ✅ Multi-monitor support
- ✅ Low latency

---

## 📊 Solution Comparison

| Solution | Feasibility | Latency | Cross-DE | Upstream | Effort |
|----------|-------------|---------|----------|----------|--------|
| **Electron Preload** | ⭐⭐⭐⭐⭐ | ~100ms | ✅ Yes | ❌ No | Low |
| **DBus Broker** | ⭐⭐⭐⭐⭐ | ~5ms | ✅ Yes | ⚠️ Maybe | Medium |
| **Protocol Extension** | ⭐⭐⭐ | ~1ms | ✅ Yes | ✅ Yes | High |
| **Layer Shell Overlay** | ⭐⭐⭐⭐ | ~10ms | ✅ Yes | ❌ No | Medium |
| **X11 Fallback** | ⭐⭐⭐ | N/A | ✅ Yes | ❌ No | Low |

---

## 🚀 Let's Build It!

Ready to implement? Let's start with the Electron preload script tonight and have you testing within the hour!
