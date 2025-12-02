# Integration Test Report - 2025-12-02

## Executive Summary

Comprehensive testing of the `pre-release` branch revealed several critical issues preventing proper functionality of both the CLI and GUI components. The primary root cause is the **deprecation of `downloader.cursor.sh`** domain (returns NXDOMAIN), which affects multiple components across the project.

---

## Test Environment

- **Machine**: Obsidian (NixOS 25.11)
- **CPU**: Intel i9-9900KS
- **Branch Tested**: `pre-release`
- **Repositories**:
  - `nixos-cursor` (main flake)
  - `cursor-studio-egui` (GUI + CLI)

---

## Critical Issues Found

### 1. 🔴 `downloader.cursor.sh` Domain is Dead

**Status**: CRITICAL - Affects multiple components

**Symptoms**:
```bash
$ host downloader.cursor.sh
Host downloader.cursor.sh not found: 3(NXDOMAIN)
```

**Impact**:
- All packages without explicit `srcUrl` fail to build
- Old version URLs (1.6.x, 1.7.x) in cursor-studio-egui fail
- GUI download functionality broken
- Default overlay broken

**Affected Files**:
| File | Status |
|------|--------|
| `cursor/default.nix` | ⚠️ Has broken fallback URL |
| `cursor-studio-egui/src/versions.rs` | ✅ Fixed in this session |
| `flake.nix` (cursor-test) | ✅ Fixed in this session |
| `flake.nix` (overlay) | ✅ Fixed in this session |

**Resolution Required**:
- Remove all `downloader.cursor.sh` references
- Always require explicit `srcUrl` with `downloads.cursor.com` format
- Update documentation to reflect this change

---

### 2. 🔴 cursor-studio-cli Not Installed/Accessible

**Status**: CRITICAL - CLI unusable out of the box

**Symptoms**:
```bash
$ cursor-studio-cli --help
command not found
```

**Root Cause**:
- `cursor-studio-egui` is a separate Rust project
- Not integrated into NixOS system configuration
- No installation method documented
- Must be manually built with `cargo build --release`

**Current Workaround**:
```bash
cd /path/to/cursor-studio-egui
cargo build --release --bin cursor-studio-cli
./target/release/cursor-studio-cli --help
```

**Resolution Required**:
- Add `cursor-studio-egui` packages to main `flake.nix`
- Or: Create installation instructions for standalone use
- Or: Add Home Manager module for cursor-studio

---

### 3. 🔴 GUI Download Functionality Broken

**Status**: CRITICAL - Cannot download versions via GUI

**Symptoms**:
- Download button in cursor-studio GUI fails
- Network errors when attempting to fetch versions
- No visible error message to user

**Likely Causes**:
1. `versions.rs` was using dead `downloader.cursor.sh` URLs (fixed)
2. Hash verification failing due to mismatched/missing hashes
3. GUI not properly handling download errors

**Resolution Required**:
- Verify `versions.rs` URLs match `cursor-versions.nix`
- Add proper error handling/display in GUI
- Test download flow end-to-end after URL fixes

---

### 4. 🟡 cursor-manager (tkinter) Has Fatal Bug

**Status**: MEDIUM - Being deprecated anyway

**Symptoms**:
```python
AttributeError: '_tkinter.tkapp' object has no attribute 'on_close'
```

**Resolution**: 
- Mark as deprecated in documentation
- Remove from active development
- Direct users to cursor-studio instead

---

### 5. 🟡 cursor-chat-library CLI Unclear

**Status**: LOW - Needs documentation

**Symptoms**:
```bash
$ nix run .#cursor-chat-library -- --help
# No output
```

**Resolution Required**:
- Document proper usage
- Add `--help` support if missing
- Consider renaming to avoid confusion

---

## Fixes Applied This Session

### nixos-cursor Repository

| Commit | Description |
|--------|-------------|
| `69fe4b8` | Fix cursor-test and overlay with explicit srcUrl |

**Files Modified**:
- `flake.nix`: Added version, hash, srcUrl to cursor-test and overlay
- `cursor/default.nix`: Updated documentation to warn about deprecated URL

### cursor-studio-egui Repository

| Commit | Description |
|--------|-------------|
| `a3e62ad` | Rename cursor-cli to cursor-studio-cli |
| `026d092` | Update old version URLs from dead downloader.cursor.sh |

**Files Modified**:
- `Cargo.toml`: Renamed binary
- `src/bin/cursor_cli.rs`: Updated name, version, examples
- `src/versions.rs`: Fixed all 1.6.x/1.7.x URLs and added hashes
- `CHANGELOG.md`: Updated all references
- `src/main.rs`: Updated hint text

---

## Recommended Next Steps

### Priority 1: Fix Download Flow

1. **Verify all URLs work**:
   ```bash
   # Test a URL from versions.rs
   curl -I "https://downloads.cursor.com/production/609c37304ae83141fd217c4ae638bf532185650f/linux/x64/Cursor-2.1.34-x86_64.AppImage"
   ```

2. **Add GUI error handling**:
   - Show download errors in GUI
   - Add retry mechanism
   - Log errors for debugging

3. **Sync versions.rs with cursor-versions.nix**:
   - Ensure same URLs and hashes
   - Consider generating versions.rs from cursor-versions.nix

### Priority 2: CLI Installation

**Option A: Add to main flake.nix**
```nix
# In nixos-cursor/flake.nix packages section
cursor-studio = pkgs.callPackage ./cursor-studio-egui { };
cursor-studio-cli = cursor-studio.cursor-studio-cli;
```

**Option B: Standalone Installation Script**
```bash
#!/usr/bin/env bash
cd /path/to/cursor-studio-egui
cargo build --release
sudo ln -sf $(pwd)/target/release/cursor-studio-cli /usr/local/bin/
sudo ln -sf $(pwd)/target/release/cursor-studio /usr/local/bin/
```

**Option C: Home Manager Module**
```nix
programs.cursor-studio = {
  enable = true;
  cli.enable = true;
};
```

### Priority 3: Documentation

1. Update README.md with:
   - Clear installation instructions
   - Known issues section
   - Troubleshooting guide

2. Add SETUP.md with:
   - First-time setup steps
   - Dependencies list
   - Build instructions

3. Add TROUBLESHOOTING.md with:
   - Common errors and fixes
   - URL migration guide
   - Hash verification guide

---

## Test Results Summary

| Component | Test | Result |
|-----------|------|--------|
| `nix flake check` | Syntax validation | ✅ Pass |
| `nix build .#default` | Default package | ✅ Pass |
| `nix build .#cursor-2_1_34` | Version package | ✅ Pass |
| `nix build .#cursor-test` | Test instance | ✅ Pass (after fix) |
| `nix build .#cursor-manager` | Tkinter manager | ✅ Builds, ❌ Runtime error |
| `nix build .#cursor-chat-library` | Chat library | ✅ Builds, ⚠️ Unclear usage |
| `nix develop` | DevShell | ✅ Pass |
| `overlays.default` | Overlay | ✅ Pass (after fix) |
| `homeManagerModules.default` | HM Module | ✅ Evaluates |
| `cursor-studio` GUI | Download | ❌ Fails |
| `cursor-studio-cli` | Installation | ❌ Not installed |
| Multi-version build | 1.6.45, 1.7.54, 2.0.64 | ✅ Pass |

---

## Appendix: URL Format Reference

### Working URL Format (downloads.cursor.com)
```
https://downloads.cursor.com/production/{COMMIT_HASH}/linux/x64/Cursor-{VERSION}-x86_64.AppImage
```

### Dead URL Format (downloader.cursor.sh) - DO NOT USE
```
https://downloader.cursor.sh/linux/appImage/x64/{VERSION}
```

### Example Valid URLs
```
# 2.1.34
https://downloads.cursor.com/production/609c37304ae83141fd217c4ae638bf532185650f/linux/x64/Cursor-2.1.34-x86_64.AppImage

# 2.0.77
https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage

# 1.7.54
https://downloads.cursor.com/production/5c17eb2968a37f66bc6662f48d6356a100b67be8/linux/x64/Cursor-1.7.54-x86_64.AppImage
```

---

*Report generated: 2025-12-02*
*Tester: Maxim (Claude Opus 4.5) on Obsidian*
