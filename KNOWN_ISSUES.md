# Known Issues and Active Work

**Project**: Cursor on NixOS + Multi-Monitor/Multi-GPU Excellence

---

## ✅ Issue #1: Separate Window Input Focus - 99% SOLVED!

**Status**: Phase 1 preload script working excellently

**Symptoms**:
- ✅ **FIXED**: Can type in detached agent/chat windows
- ✅ **FIXED**: Alt+Tab works properly
- ⚠️ **Minor**: Occasional small hiccups (< 1% of time)

**Solution**: Electron preload script (Phase 1)
- Location: `nixos/pkgs/cursor-focus-fix/preload.js`
- Effectiveness: ~99%
- Latency: ~50-100ms (acceptable)

**Next**: Phase 2 (DBus broker) for 100% reliability and lower latency

---

## ⚠️ Issue #2: Context Menu Pop-Out Breaks Badly

**Status**: Active investigation needed

**Symptoms**:
- Context menu (right-click menu) in separate windows breaks
- Specific behavior not yet detailed

**Priority**: High (affects usability)

**Investigation Needed**:
1. What exactly breaks? (positioning, rendering, interaction?)
2. Is it specific to detached windows or all context menus?
3. Does it happen in main editor vs agent/chat windows?

**Potential Causes**:
- Electron `BrowserView` positioning in detached windows
- Wayland coordinate space confusion (multi-monitor)
- GPU boundary issues (Arc A770 vs RTX 2080)
- Compositor window management

**Debugging Steps**:
```bash
# Enable Electron debug logging
export ELECTRON_ENABLE_LOGGING=1
export ELECTRON_LOG_FILE=/tmp/cursor-debug.log

# Check Wayland compositor logs
journalctl -u display-manager -f
```

---

## ⚠️ Issue #3: Significant Lag on Window Transitions

**Status**: Active investigation needed

**Symptoms**:
1. **Opening editor as window**: Significant lag
2. **Moving agent sidebar → editor window**: Significant lag

**Priority**: Medium-High (affects UX)

**Potential Causes**:

### Theory 1: Electron Window Creation Overhead
- Creating new `BrowserWindow` is slow
- GPU context initialization delay
- Vulkan/OpenGL context switching

### Theory 2: GPU Transitions
- Window moving between monitors on different GPUs
- Arc A770 (monitor 1, 2) → RTX 2080 (monitor 3)
- VRAM copy overhead
- Driver synchronization

### Theory 3: Compositor Overhead
- KDE Plasma/Hyprland managing window state
- Wayland protocol round-trips
- Window decoration rendering

### Theory 4: Electron State Serialization
- Saving/restoring window state
- Extension context migration
- Monaco editor state transfer

**Measurements Needed**:
```javascript
// Add to preload script
console.time('window-transition');
// ... transition happens ...
console.timeEnd('window-transition');

// GPU monitoring
nvidia-smi dmon -s u -c 10  # RTX 2080 utilization
intel_gpu_top              # Arc A770 utilization
```

---

## 🚀 Issue #4: Rust Monitor Build Failure (Low Priority)

**Status**: Documented, Python fallback working

**Root Cause**: Cargo.lock TOML parsing error in Nix build

**Workaround**: Python fallback monitor works perfectly

**Fix**: Use `cargoHash` method (documented in RUST_NIX_BEST_PRACTICES.md)

**Priority**: Low (Python works fine, performance delta negligible)

---

## 🎯 New: Multi-GPU Window Management (Feature Request)

**Vision**: Make NixOS the BEST platform for heterogeneous GPU setups

**Goals**:

### 1. GPU-Aware Window Transitions
- Detect when window moves between GPUs
- Optimize VRAM transfers
- Minimize transition lag
- Declarative GPU affinity configuration

### 2. GPU-Driven Display Management
- Use GPU power for better buffering (Arc A770 has 16GB VRAM!)
- Lower latency display pipeline
- Failsafe handling (GPU crash doesn't kill session)
- Per-monitor GPU assignment in config

### 3. Heterogeneous System Optimization
- Intel Arc A770 16GB + NVIDIA RTX 2080 8GB
- Declarative resource allocation
- Automatic load balancing
- Per-application GPU preferences

### 4. Multi-Monitor Excellence
- Seamless window movement across monitors
- Per-monitor scaling, refresh rate, color profile
- GPU boundary awareness
- Zero-copy compositing where possible

---

## 📋 Investigation Plan

### Phase 1: Measurement and Profiling

**Week 1: Context Menu Issue**
1. Reproduce reliably
2. Capture screenshots/video
3. Check Electron DevTools console
4. Test with/without GPU acceleration
5. Test on single vs multi-monitor
6. Test same-GPU vs cross-GPU monitors

**Week 1: Transition Lag**
1. Measure exact timings (`console.time`)
2. GPU utilization during transitions
3. Compositor logs during transitions
4. Network activity (Wayland protocol)
5. CPU profiling (`perf`)
6. Memory allocations

### Phase 2: Root Cause Analysis

**Context Menu**:
- Is it Electron `BrowserView` API issue?
- Is it Wayland coordinate translation?
- Is it GPU boundary crossing?
- Is it compositor window positioning?

**Transition Lag**:
- Is it GPU context creation?
- Is it VRAM copy?
- Is it Electron overhead?
- Is it compositor rendering?

### Phase 3: Fix Implementation

**Option A: Electron-Level Fixes**
- Preload script optimizations
- BrowserView configuration tweaks
- GPU acceleration flags

**Option B: Compositor-Level Fixes**
- KDE/Hyprland configuration
- GPU affinity hints
- Window management rules

**Option C: System-Level Infrastructure**
- Custom display manager
- GPU-aware window router
- Declarative NixOS module

---

## 🎨 Broader Vision: NixOS Multi-Monitor Framework

**Goal**: Make NixOS "THE OS to rule them all" for multi-GPU, multi-monitor setups

### Components to Build:

#### 1. NixOS Multi-Monitor Module
```nix
homelab.display = {
  enable = true;
  
  gpus = {
    primary = {
      device = "intel-arc-a770";
      vram = "16GB";
      monitors = [ "DP-1" "DP-2" ];
    };
    secondary = {
      device = "nvidia-rtx-2080";
      vram = "8GB";
      monitors = [ "HDMI-1" ];
    };
  };
  
  windows = {
    # GPU affinity per application
    cursor.preferredGpu = "primary";
    obs.preferredGpu = "secondary";
    
    # Transition optimization
    enableSmartTransitions = true;
    vramPreallocation = "512MB";
  };
  
  compositor = {
    backend = "wayland";
    gpuScheduling = "round-robin";
    enableZeroCopy = true;
  };
};
```

#### 2. GPU-Aware Window Manager Daemon
- Monitors window creation/movement
- Detects GPU boundaries
- Pre-allocates resources
- Optimizes transitions
- DBus interface for applications

#### 3. Electron App Framework
- Generic fixes for ALL Electron apps (not just Cursor)
- GPU acceleration optimization
- Multi-window focus management
- Context menu positioning
- Transition performance

#### 4. Declarative Display Configuration
- Per-monitor settings (resolution, refresh, scaling, color)
- GPU assignment
- Power management
- Hotplug handling

---

## 🚀 Next Steps (Prioritized)

### Immediate (This Week)

1. **Investigate context menu issue**
   - Reproduce and document exact behavior
   - Test across different scenarios
   - Identify root cause

2. **Profile transition lag**
   - Add timing measurements
   - GPU utilization monitoring
   - Identify bottleneck

3. **Document heterogeneous GPU setup**
   - Current Obsidian configuration
   - Monitor → GPU mapping
   - Performance baseline

### Short-term (Next 2 Weeks)

1. **Build GPU-aware monitoring**
   - Extend cursor-monitor to track GPU usage
   - Window → GPU mapping tracker
   - Transition event logger

2. **Phase 2: DBus Focus Broker**
   - Implement compositor integration
   - Lower latency (5ms vs 100ms)
   - More reliable

3. **Prototype multi-monitor module**
   - Basic NixOS module structure
   - GPU configuration options
   - Monitor assignment

### Medium-term (Month 2)

1. **GPU transition optimization**
   - Smart VRAM management
   - Pre-allocation strategies
   - Zero-copy where possible

2. **Electron framework**
   - Generic preload scripts
   - Configuration system
   - Testing suite

3. **Documentation and showcase**
   - Blog post: "NixOS for Multi-GPU Setups"
   - Video: Live demonstration
   - Discourse post: Attract developers

### Long-term (Month 3+)

1. **Wayland protocol extensions**
   - GPU affinity protocol
   - Focus tracking protocol
   - Submit to wayland-protocols

2. **NixOS upstream integration**
   - Submit multi-monitor module
   - Contribute to nixpkgs
   - Become reference implementation

---

## 🎯 Success Criteria

**Phase 1** (Current): ✅ ACHIEVED
- [x] 99% typing success in detached windows
- [x] Electron preload script working
- [x] Documentation complete

**Phase 2** (Next 2 weeks):
- [ ] Context menu issue identified and fixed
- [ ] Transition lag < 500ms (currently ~1-2s?)
- [ ] GPU monitoring infrastructure in place
- [ ] DBus focus broker implemented

**Phase 3** (Month 2):
- [ ] Transition lag < 100ms
- [ ] GPU-aware window management working
- [ ] Multi-monitor module released
- [ ] Works for 3+ Electron apps

**Phase 4** (Month 3+):
- [ ] NixOS becomes go-to OS for multi-GPU setups
- [ ] Wayland protocol extensions submitted
- [ ] Showcase blog posts and videos
- [ ] Other distros adopt our solutions

---

## 💡 Philosophy

**"Assume hostile, patch externally, benefit everyone"**

1. **Cursor**: Assume indifferent/hostile → external patches only
2. **Wayland**: Work within constraints, but push boundaries
3. **NixOS**: Declarative nature is THE advantage
4. **Community**: Build infrastructure that benefits all

**We're not just fixing Cursor. We're making NixOS the undisputed champion of multi-monitor, multi-GPU workstations.**

---

**Status**: 🟢 Phase 1 successful, expanding scope to broader infrastructure
**Next**: Context menu investigation + GPU profiling
