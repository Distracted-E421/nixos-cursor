# Multi-Window Cursor Fix with GPU Awareness

> **⚠️ Internal Roadmap Document**  
> This is a planning document for a future feature (multi-window focus handling).  
> It is **not currently implemented** in nixos-cursor v0.1.1.  
> See the [Roadmap](../README.md#-roadmap) for planned features.

**Date**: 2025-11-19  
**Target**: Fix typing in multiple Cursor agent chat windows on KDE  
**Status**: Planning → Implementation  
**Priority**: HIGH (blocking daily workflow)

---

## 🎯 **Objectives**

1. **Fix typing in multiple Cursor windows** - Each agent chat window should handle input independently
2. **GPU-aware focus handling** - Track which GPU each window is on
3. **KDE-first testing** - Implement and test on stable KDE environment before Niri
4. **Minimal latency** - <50ms focus restoration
5. **Zero conflicts** - Windows don't fight over focus

---

## 📊 **Problem Analysis**

### **Current Behavior** (cursor-focus-fix v1)

**Single Window**: ✅ Works perfectly (99% success)

- Detects focus mismatch
- Restores keyboard focus
- ~100ms latency

**Multiple Windows**: ❌ Broken

- All windows share same global focus state
- Focus restoration conflicts between windows
- Each window fights to restore focus
- Result: typing doesn't work in any window

### **Root Causes**

1. **Global State**: All window instances share same `isRestoringFocus`, `focusRestoreTimeout`
2. **No Window Identity**: Can't distinguish between Cursor instances
3. **No GPU Awareness**: Doesn't know which GPU a window is on
4. **Race Conditions**: Multiple windows trigger focus restoration simultaneously

---

## 🏗️ **Solution Architecture**

### **Phase 1: Per-Window State Isolation** (Week 1, Day 1-2)

**Goal**: Each Cursor window manages its own focus independently

**Changes to preload.js**:

```javascript
// OLD (global state - causes conflicts):
let isRestoringFocus = false;
let focusRestoreTimeout = null;

// NEW (per-window instance):
const WINDOW_INSTANCE_ID = `cursor-${Date.now()}-${Math.random()}`;
const windowState = {
  instanceId: WINDOW_INSTANCE_ID,
  isRestoringFocus: false,
  focusRestoreTimeout: null,
  lastFocusCheck: 0,
  gpuId: null,  // Will be populated by GPU manager
  monitorId: null
};

// Store in global namespace but namespaced by instance
window.__CURSOR_FOCUS_FIX__ = windowState;
```

**Benefits**:

- Each window has isolated state
- No global conflicts
- Can track per-window metrics
- Enables GPU-aware logic later

### **Phase 2: Window → GPU Mapping** (Week 1, Day 3-4)

**Goal**: Know which GPU each Cursor window is on

**Integration with gpu-window-manager**:

**A. Extend DBus Interface** (`src/dbus_service.rs`):

```rust
#[dbus_interface(name = "com.github.e421.GpuWindowManager")]
impl GpuWindowManagerInterface {
    // ... existing methods ...
    
    /// Get GPU for current window (by PID + window title)
    async fn get_window_gpu(&self, pid: u32, window_title: &str) -> Result<u32, zbus::fdo::Error> {
        // Query X11/Wayland for window geometry
        // Determine which monitor(s) window is on
        // Return primary GPU ID
    }
    
    /// Subscribe to GPU transition events for a window
    async fn watch_window_gpu(&self, pid: u32, window_title: &str) -> Result<(), zbus::fdo::Error> {
        // Emit signal when window moves to different GPU
    }
    
    // Signal emitted when window changes GPU
    #[dbus_interface(signal)]
    async fn window_gpu_changed(
        &self, 
        pid: u32, 
        window_title: &str, 
        old_gpu: u32, 
        new_gpu: u32
    ) -> zbus::Result<()>;
}
```

**B. Add DBus Client to preload.js**:

```javascript
// Query GPU manager for window's GPU
async function queryWindowGpu() {
  try {
    const pid = process.pid;
    const windowTitle = document.title;
    
    // Call DBus via Electron's remote
    const { execSync } = require('child_process');
    const result = execSync(
      `busctl --user call com.github.e421.GpuWindowManager ` +
      `/com/github/e421/GpuWindowManager ` +
      `com.github.e421.GpuWindowManager GetWindowGpu ` +
      `"us" ${pid} "${windowTitle}"`
    ).toString();
    
    // Parse result: "u 1" → GPU ID 1
    const gpuId = parseInt(result.match(/u (\d+)/)[1]);
    
    windowState.gpuId = gpuId;
    log(`Window on GPU ${gpuId}`);
    
    return gpuId;
  } catch (e) {
    warn('Failed to query window GPU, continuing without GPU awareness:', e);
    return null;
  }
}

// Subscribe to GPU transition signals
function subscribeToGpuTransitions() {
  // Use DBus monitor to watch for WindowGpuChanged signals
  // When signal received, update windowState.gpuId and adjust focus logic
}
```

**C. KDE Window Tracking** (`src/window_kde.rs` - NEW):

```rust
use anyhow::{Result, Context};
use std::process::Command;

/// Get window geometry from X11 (KDE on X11)
pub fn get_window_geometry_x11(pid: u32, title: &str) -> Result<(i32, i32, u32, u32)> {
    // Use xdotool or wmctrl to query window geometry
    let output = Command::new("xdotool")
        .args(&["search", "--pid", &pid.to_string(), "--name", title])
        .output()?;
    
    let window_id = String::from_utf8(output.stdout)?.trim().to_string();
    
    let geometry = Command::new("xdotool")
        .args(&["getwindowgeometry", &window_id])
        .output()?;
    
    // Parse: "Position: X,Y (screen: 0)\n  Geometry: WxH"
    // Return (x, y, w, h)
    parse_xdotool_geometry(&geometry.stdout)
}

/// Get window geometry from Wayland (KDE on Wayland)
pub fn get_window_geometry_wayland(pid: u32, title: &str) -> Result<(i32, i32, u32, u32)> {
    // Use KWin's scripting API or foreign-toplevel protocol
    // Parse kwin window list, match by PID + title
    // Return geometry
    query_kwin_geometry(pid, title)
}
```

### **Phase 3: GPU-Aware Focus Restoration** (Week 1, Day 5-7)

**Goal**: Adjust focus behavior based on GPU transitions

**Enhanced Focus Logic**:

```javascript
function restoreFocus() {
  if (windowState.isRestoringFocus) {
    return; // This instance is already restoring
  }
  
  windowState.isRestoringFocus = true;
  
  try {
    log(`[${windowState.instanceId}] Restoring focus (GPU: ${windowState.gpuId})`);
    
    // GPU-aware focus target priority
    const target = findFocusTarget();
    
    if (target) {
      // Check if we crossed GPU boundary
      if (windowState.gpuId !== null && windowState.lastGpuId !== windowState.gpuId) {
        log(`GPU transition detected: ${windowState.lastGpuId} → ${windowState.gpuId}`);
        // Add extra delay for GPU transitions (NVIDIA ↔ Intel Arc)
        await sleep(50);
      }
      
      // Focus using multiple methods
      target.focus({ preventScroll: true });
      target.dispatchEvent(new FocusEvent('focus', { bubbles: true }));
      
      log(`Focus restored to: ${target.tagName} (GPU: ${windowState.gpuId})`);
      
      windowState.lastGpuId = windowState.gpuId;
    }
  } finally {
    setTimeout(() => {
      windowState.isRestoringFocus = false;
    }, 200);
  }
}
```

---

## 📋 **Implementation Phases**

### **Week 1: Multi-Window Fix on KDE**

#### **Day 1-2: Per-Window State**

- [ ] Modify `preload.js` to use instance-scoped state
- [ ] Add window instance ID generation
- [ ] Test with 2-3 Cursor windows
- [ ] Verify no focus conflicts
- [ ] Measure latency (<50ms target)

#### **Day 3-4: GPU Manager Integration**

- [ ] Extend DBus interface (`GetWindowGpu`, `WatchWindowGpu`)
- [ ] Implement KDE window geometry queries (X11 + Wayland)
- [ ] Add window → monitor → GPU mapping logic
- [ ] Test DBus calls from preload.js
- [ ] Verify GPU detection for each window

#### **Day 5-7: GPU-Aware Focus**

- [ ] Integrate GPU awareness into focus restoration
- [ ] Handle GPU transition events
- [ ] Add extra delay for NVIDIA ↔ Intel Arc transitions
- [ ] Test with windows spanning both GPUs
- [ ] Measure GPU transition latency

### **Week 2: Testing & Refinement**

#### **Day 8-10: Multi-Window Testing**

- [ ] Test 2 windows same GPU (Arc A770)
- [ ] Test 2 windows different GPUs (Arc + NVIDIA)
- [ ] Test 4+ windows (real workload simulation)
- [ ] Test window moves between monitors
- [ ] Test GPU hot-plug (if supported)

#### **Day 11-14: Performance Optimization**

- [ ] Reduce DBus call overhead (cache results)
- [ ] Optimize focus detection loop
- [ ] Add metrics export (focus restoration time per window)
- [ ] Create Prometheus dashboard for focus stats
- [ ] Document optimal configuration

---

## 🧪 **Testing Strategy**

### **Test Environment**

**Hardware**: Obsidian

- Intel Arc A770 (16GB) - 3 monitors (DP-1, DP-3, DP-4)
- NVIDIA RTX 2080 (8GB) - 1 monitor (HDMI-A-5)

**Software**: KDE Plasma 6 on NixOS 25.11

- Test both X11 and Wayland sessions
- Test with real agent chat workloads

### **Test Cases**

#### **TC1: Basic Multi-Window**

- Open 2 Cursor windows (same GPU)
- Open agent chat in both
- Type in window 1
- Switch to window 2
- Type in window 2
- **Expected**: Both windows accept input correctly

#### **TC2: Cross-GPU Windows**

- Window 1 on Arc monitor (DP-3)
- Window 2 on NVIDIA monitor (HDMI-A-5)
- Type in both alternately
- **Expected**: Focus restoration works on both GPUs

#### **TC3: Window Movement**

- Open window on Arc monitor
- Drag to NVIDIA monitor
- Type in window
- **Expected**: GPU transition detected, typing works

#### **TC4: Rapid Switching**

- Open 3 windows
- Alt+Tab between them rapidly
- Type in each
- **Expected**: No focus conflicts, all accept input

#### **TC5: Stress Test**

- Open 5+ Cursor windows across all monitors
- Open agent chats in all
- Type in each sequentially
- **Expected**: No degradation, <50ms focus latency

### **Success Criteria**

- ✅ **100% typing success** in all windows
- ✅ **<50ms focus restoration** latency
- ✅ **Zero focus conflicts** between windows
- ✅ **GPU transitions detected** within 100ms
- ✅ **No performance impact** (<1% CPU overhead)

---

## 🔧 **Technical Implementation**

### **File Structure**

```
nixos/pkgs/
├── cursor-focus-fix/
│   ├── preload.js                    # [MODIFY] Add per-window state
│   └── default.nix
├── gpu-window-manager/
│   ├── src/
│   │   ├── main.rs
│   │   ├── dbus_service.rs           # [MODIFY] Add GetWindowGpu, WatchWindowGpu
│   │   ├── window.rs                 # [EXISTING] Window tracking
│   │   ├── window_kde.rs             # [NEW] KDE-specific window queries
│   │   ├── window_x11.rs             # [NEW] X11 geometry queries
│   │   └── window_wayland_kde.rs     # [NEW] KWayland window queries
│   ├── Cargo.toml                    # [MODIFY] Add x11/kwin dependencies
│   └── default.nix
└── cursor-with-mcp/                  # Integration package
    └── default.nix                   # [MODIFY] Include both fixes
```

### **Dependencies**

**Rust (`Cargo.toml`)**:

```toml
[dependencies]
# Existing...
# Add for KDE support:
x11rb = "0.13"           # X11 protocol (KDE on X11)
xcb = "1.4"              # X11 C bindings
kdbus = "0.3"            # KDE DBus bindings (optional)
```

**NixOS (system packages)**:

```nix
environment.systemPackages = with pkgs; [
  xdotool          # X11 window queries
  wmctrl           # X11 window control
  kdialog          # KDE dialogs (optional)
  dbus             # DBus tools (busctl, dbus-monitor)
];
```

---

## 📊 **Metrics & Monitoring**

### **Focus Restoration Metrics** (Prometheus)

```prometheus
# Focus restoration latency per window instance
cursor_focus_restore_duration_ms{instance_id="cursor-123", gpu="1"} 42

# Focus restoration attempts
cursor_focus_restore_attempts_total{instance_id="cursor-123", result="success"} 156

# GPU transitions
cursor_gpu_transitions_total{from_gpu="0", to_gpu="1"} 12

# Focus conflicts (should be 0)
cursor_focus_conflicts_total{instance_id="cursor-123"} 0
```

### **Dashboard Queries**

```promql
# Average focus restoration time
avg(cursor_focus_restore_duration_ms) by (gpu)

# Success rate
sum(rate(cursor_focus_restore_attempts_total{result="success"}[5m])) 
/ 
sum(rate(cursor_focus_restore_attempts_total[5m]))

# GPU transition latency
histogram_quantile(0.95, cursor_gpu_transition_duration_ms_bucket)
```

---

## 🎯 **Immediate Next Steps**

### **Today (Day 1)**

1. **Backup current preload.js**

   ```bash
   cp nixos/pkgs/cursor-focus-fix/preload.js{,.backup}
   ```

2. **Implement per-window state**
   - Add window instance ID generation
   - Convert global state to instance state
   - Test with 2 windows

3. **Test on KDE**
   - Build and deploy
   - Open 2 Cursor windows
   - Verify typing works in both

### **Tomorrow (Day 2)**

1. **Add GPU query stub**
   - Integrate DBus call to gpu-window-manager
   - Handle fallback if daemon not running
   - Log GPU ID per window

2. **Extend gpu-window-manager**
   - Add `GetWindowGpu` DBus method
   - Implement basic window geometry query (X11 first)
   - Test with `busctl` manually

3. **Integration test**
   - Open windows on different GPUs
   - Verify GPU detection
   - Document any issues

---

## 💡 **Design Decisions**

### **Why Per-Window State?**

- **Isolation**: Each window independent
- **No conflicts**: Windows don't interfere
- **Scalability**: Supports 10+ windows
- **Debugging**: Per-window metrics

### **Why DBus Communication?**

- **Standard IPC**: Well-supported on Linux
- **Async**: Non-blocking queries
- **Monitoring**: Can use `dbus-monitor` to debug
- **Future-proof**: Easy to extend with new methods

### **Why KDE First?**

- **Stability**: Main development environment
- **Dual GPU**: Real multi-GPU testing
- **X11 + Wayland**: Test both protocols
- **Faster iteration**: No Niri boot/reboot cycle

### **Why Not Wayland Protocol Extension?**

- **Complexity**: Requires compositor changes
- **Time**: Months to get upstream acceptance
- **Compatibility**: DBus works on X11 + Wayland
- **Phase 3**: Can add Wayland protocol later

---

## 🚀 **Success Vision**

### **End State (2 weeks)**

**User Experience**:

- Open 5 Cursor windows across 4 monitors (2 GPUs)
- Each agent chat window types perfectly
- Alt+Tab between windows is instant
- Moving windows between monitors "just works"
- Zero focus conflicts
- Imperceptible latency (<50ms)

**Technical Metrics**:

- 100% typing success rate (up from ~0% with multiple windows)
- <50ms focus restoration (maintained from single-window)
- <1% CPU overhead for focus monitoring
- <10ms GPU transition detection

**Foundation for Future**:

- GPU-aware window management proven on KDE
- DBus architecture ready for Niri integration
- Metrics pipeline for optimization
- Reference implementation for Wayland protocol (Phase 3)

---

## 📚 **Related Documentation**

- `PHASE_2A_GPU_DAEMON_PLAN.md` - GPU manager architecture
- `multi_gpu_vision_progress.md` - Overall project progress
- `nixos/pkgs/cursor-focus-fix/preload.js` - Current single-window fix
- `nixos/pkgs/gpu-window-manager/src/window.rs` - Window tracking foundation

---

**Status**: 📝 **PLAN COMPLETE** - Ready for implementation  
**Next**: Implement per-window state in preload.js (Day 1)  
**Timeline**: 2 weeks to production-ready multi-window support on KDE
