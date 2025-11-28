# Cursor Manager Redesign - Architecture Document

> **Goal**: Unify `cursor` and `cursor-manager` behavior, add settings persistence, and provide comprehensive disk/data management.

## 📊 Current State Analysis

### Problem: Fragmented User Experience

| Command | Behavior | Data Sync | Settings | Version Select |
|---------|----------|-----------|----------|----------------|
| `cursor` | Launches default version | ❌ None | ❌ None | ❌ None |
| `cursor-manager` | GUI launcher | ✅ Yes | ⚠️ Basic | ✅ Yes |

**Issues:**
1. Running `cursor` doesn't use manager's data sync features
2. No way to set a "default version" that `cursor` respects
3. Settings are scattered between Home Manager and manager's JSON
4. No persistent window option for repeated launches

## 🎯 Proposed Architecture

### Unified Configuration Model

```
~/.config/cursor-manager/
├── config.json          # Main configuration
├── default-version      # Symlink to active version (cursor reads this)
├── versions/            # Installed versions metadata
│   ├── 2.0.77.json
│   └── 2.1.34.json
└── cache/               # Transient data
    └── size-cache.json
```

**config.json Schema:**
```json
{
  "version": "2.0",
  "defaultVersion": "2.0.77",
  "settings": {
    "syncSettingsOnLaunch": true,
    "syncGlobalStorage": false,
    "persistentWindow": false,
    "theme": "auto",
    "autoCleanup": {
      "enabled": false,
      "keepVersions": 3,
      "olderThanDays": 30
    }
  },
  "dataControl": {
    "isolatedVersionDirs": true,
    "sharedExtensions": false,
    "syncSnippets": true
  },
  "security": {
    "npmSecurityEnabled": true,
    "scanNewPackages": true,
    "blocklistEnabled": true
  }
}
```

### New Command Behavior

#### `cursor` (default command)
```
1. Read default version from ~/.config/cursor-manager/config.json
2. If no version set → use system default (2.0.77 or flake-specified)
3. Apply data sync settings before launch
4. Launch the correct version binary
```

#### `cursor-manager` (GUI)
```
1. Load config.json
2. Display version selector with settings panel
3. If persistentWindow=true → stay open after launch
4. Provide tabs for:
   - Version Management
   - Settings
   - Data Control  
   - Disk Management
   - Security (npm scanning)
```

## 🖼️ UI Mockup: New cursor-manager

```
┌────────────────────────────────────────────────────────────────────┐
│  🎯 Cursor Version Manager v3.0                          [_][□][X] │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─ Version Selection ─────────────────────────────────────────┐   │
│  │  Era: [ 2.0.x - Custom Modes Era              ▼]            │   │
│  │  Version: [ 2.0.77 (Stable - Recommended)     ▼]            │   │
│  │                                                              │   │
│  │  [ Set as Default ]  [ 🚀 Launch ]  [ ⚙️ Settings ]         │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─ Quick Status ───────────────────────────────────────────────┐   │
│  │  Default: 2.0.77 │ Installed: 3 │ Disk: 2.4 GB              │   │
│  │  Security: ✅ Active │ Last Scan: 2 hours ago               │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘

┌─ Settings Panel (slide out) ─────────────────────────────────────────┐
│                                                                       │
│  [Version] [Data] [Disk] [Security]                                  │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                                                       │
│  Version Settings                                                     │
│  ────────────────                                                     │
│  [✓] Keep window open after launch                                   │
│  [✓] Apply data sync before launch                                   │
│  [ ] Auto-update to latest in current era                            │
│                                                                       │
│  Default Version                                                      │
│  ────────────────                                                     │
│  Current: 2.0.77                                                      │
│  [ ] Use system default (from flake)                                 │
│  [●] Use custom default: [ 2.0.77 ▼]                                 │
│                                                                       │
│  Theme                                                                │
│  ─────                                                                │
│  [●] Auto (match Cursor theme)                                       │
│  [ ] Dark                                                             │
│  [ ] Light                                                            │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

┌─ Data Control Tab ───────────────────────────────────────────────────┐
│                                                                       │
│  Data Synchronization                                                 │
│  ────────────────────                                                 │
│  [✓] Sync settings.json between versions                             │
│  [✓] Sync keybindings.json                                           │
│  [✓] Sync snippets                                                   │
│  [ ] Share globalStorage (auth, docs) - Experimental                 │
│  [ ] Share extensions between versions                               │
│                                                                       │
│  Data Isolation                                                       │
│  ──────────────                                                       │
│  Each version gets: ~/.cursor-{version}/                             │
│  Shared config: ~/.config/Cursor/                                    │
│                                                                       │
│  [ Export All Settings ]  [ Import Settings ]  [ Reset to Default ]  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

┌─ Disk Management Tab ────────────────────────────────────────────────┐
│                                                                       │
│  Storage Analysis                                                     │
│  ────────────────                                                     │
│  Total Cursor Data:     2.4 GB                                       │
│  ├── Installed Versions: 1.8 GB (1 version)                          │
│  ├── User Data:          312 MB                                      │
│  ├── Caches:             156 MB (8 directories)                      │
│  └── Extensions:         134 MB                                      │
│                                                                       │
│  Version Directories                                                  │
│  ────────────────────                                                 │
│  📁 ~/.cursor-2.0.77/    312 MB    [Keep] [Delete]                   │
│  📁 ~/.cursor-2.0.64/    98 MB     [Keep] [Delete]                   │
│                                                                       │
│  Cleanup Actions                                                      │
│  ───────────────                                                      │
│  [ 🧹 Clean All Caches ]  Saves ~156 MB                              │
│  [ 🗑️ Remove Orphaned ]   Saves ~98 MB                               │
│  [ 🔄 Compact Storage ]   (Removes unused extensions)                │
│                                                                       │
│  Auto-Cleanup                                                         │
│  ────────────                                                         │
│  [ ] Enable automatic cleanup                                         │
│      Keep [ 3 ▼] most recent versions                                │
│      Remove versions older than [ 30 ▼] days                         │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

┌─ Security Tab ───────────────────────────────────────────────────────┐
│                                                                       │
│  NPM Package Security                                                 │
│  ────────────────────                                                 │
│  Status: ✅ Active                                                    │
│  Blocklist: 16 packages blocked (last updated: Nov 27, 2025)         │
│  Last scan: 2 hours ago                                              │
│                                                                       │
│  [✓] Enable npm security scanning                                    │
│  [✓] Block known malicious packages                                  │
│  [✓] Scan new MCP server packages                                    │
│  [ ] Strict mode (block packages with install scripts)               │
│                                                                       │
│  Recent Scan Results                                                  │
│  ───────────────────                                                  │
│  @modelcontextprotocol/server-filesystem  ✅ Clean                   │
│  @modelcontextprotocol/server-github      ✅ Clean                   │
│  @modelcontextprotocol/server-memory      ✅ Clean                   │
│                                                                       │
│  [ Run Full Scan ]  [ Update Blocklist ]  [ View Blocklist ]         │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

## 📦 Install Size Summary

### Scenario: Fresh NixOS 25.11 KDE Plasma Desktop

| Configuration | New Disk Space | Download (with Cachix) |
|---------------|----------------|------------------------|
| **Minimal** (cursor only) | ~500-800 MB | ~400 MB |
| **Standard** (+ MCP servers) | ~800-1200 MB | ~500 MB |
| **Full** (+ Playwright browser) | ~2-3 GB | ~1.5 GB |

### Breakdown by Component

| Component | Closure Size | Shared with KDE | Effective New |
|-----------|--------------|-----------------|---------------|
| Cursor 2.0.77 AppImage | 1798 MB | ~1300 MB (GTK3, mesa, etc.) | ~500 MB |
| cursor-manager (Python/tkinter) | 194 MB | ~150 MB (Python runtime) | ~50 MB |
| Node.js 22 (MCP servers) | 210 MB | ~100 MB | ~110 MB |
| uv (mcp-nixos) | 104 MB | ~80 MB | ~25 MB |
| Google Chrome (Playwright) | 1689 MB | ~800 MB | ~900 MB |

### Caching Strategy (Cachix)

**What's Pre-cached on `nixos-cursor.cachix.org`:**
- All 48 Cursor AppImage versions (pre-built, verified hashes)
- cursor-manager Python package
- Build dependencies

**Cache Hit Benefits:**
```
Without Cachix:  Build cursor from AppImage = ~5-10 minutes + 1.8GB download
With Cachix:     Fetch pre-built = ~30 seconds + 400MB download
```

**Flake Configuration (already present):**
```nix
nixConfig = {
  extra-substituters = [ "https://nixos-cursor.cachix.org" ];
  extra-trusted-public-keys = [
    "nixos-cursor.cachix.org-1:8YAZIsMXbzdSJh6YF71XIVR2OgnRXXZ+7e82dL5yCqI="
  ];
};
```

### Mitigation Strategies

1. **Shared Closure Optimization**: KDE desktop already includes GTK3, mesa, glib, etc.
   - Effective new space is ~50% of reported closure size

2. **Lazy Loading MCP Servers**: npm packages only download on first use
   - Initial install doesn't include npm package weight
   - Runtime download: ~50-100 MB to ~/.npm/

3. **Optional Components**: Playwright/browser only installed if explicitly enabled
   - Default config doesn't include browser (~1.5 GB saved)

4. **Version Cleanup**: Auto-cleanup removes old versions
   - Keep only 3 most recent by default
   - Saves ~500 MB per removed version

## 🔧 Implementation Plan

### Phase 1: Configuration Unification
1. Create unified config schema
2. Add config loader to cursor wrapper
3. Migrate cursor-manager settings

### Phase 2: Enhanced cursor-manager GUI
1. Rewrite in Nushell + Rust (egui) for better UX
2. Add settings panel with tabs
3. Implement persistent window option
4. Add slide-out side panel

### Phase 3: Data Control Features
1. Implement export/import settings
2. Add version-specific data isolation
3. Shared extensions option

### Phase 4: Security Integration
1. Connect npm security module to GUI
2. Add scan status display
3. Blocklist management UI

### Phase 5: Documentation
1. Update README with install sizes
2. Add caching documentation
3. Create user guide

## 🎯 Success Criteria

- [ ] `cursor` command respects default version setting
- [ ] Settings persist across Home Manager rebuilds
- [ ] Persistent window option works
- [ ] Disk usage clearly displayed
- [ ] Install sizes documented for new users
- [ ] Security status visible in GUI
