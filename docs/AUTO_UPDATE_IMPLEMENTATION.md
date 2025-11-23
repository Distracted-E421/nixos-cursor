# Cursor Auto-Update System

**Status**: DONE: **Implemented** in v2.1.20-rc1

---

## Overview

Cursor's native update system is incompatible with NixOS because the application lives in the read-only `/nix/store`. This document explains our solution: **automated update notifications + convenience commands**.

---

## Why Cursor Can't Self-Update on NixOS

### The Technical Problem

**Before Nix (Manual AppImage)**:
```bash
# Cursor can update itself:
1. Download new AppImage
2. Replace ~/Downloads/cursor.AppImage
3. Done! ✅
```

**With Nix (Read-Only Store)**:
```bash
# Cursor lives in /nix/store (read-only)
/nix/store/abc123-cursor-2.1.20/bin/cursor

# During build, autoPatchelfHook:
- Rewrites ELF headers for NixOS
- Points to Nix-managed libraries
- Fixes library paths

# If Cursor tries to self-update:
1. Downloads new AppImage (UNPATCHED)
2. Can't modify /nix/store (read-only) ❌
3. Unpatched binary won't run on NixOS ❌
```

**Core Issue**: Every Cursor update needs to be re-patched via Nix build, which Cursor itself cannot do.

---

## Our Solution: Hybrid Update System

We provide **three components**:

### 1. Daily Update Notifications (Automatic)

A systemd user timer checks for updates daily and shows desktop notifications:

```nix
programs.cursor = {
  enable = true;
  updateCheck.enable = true;  # Default: true
  updateCheck.interval = "daily";  # or "weekly", etc.
};
```

**How it works**:
- Queries Cursor's API: `https://api2.cursor.sh/updates/api/download/stable`
- Compares current version (2.1.20) vs latest available
- Shows notification if update available: "Cursor 2.1.21 available!"

**Manual check**: `cursor-check-update`

---

### 2. Convenience Update Command

One command to update Cursor via Nix:

```bash
# Automatic update (finds your flake, runs update)
cursor-update
```

**What it does**:
```bash
1. Auto-detects your flake directory
   (or uses $NIXOS_CURSOR_FLAKE_DIR)
2. Runs: nix flake update nixos-cursor
3. Rebuilds: home-manager switch OR nixos-rebuild switch
4. Reports: "2.1.20 → 2.1.21"
```

**Set flake directory** (optional):
```nix
programs.cursor = {
  enable = true;
  flakeDir = "/home/user/.config/home-manager";
};
```

Or export it:
```bash
export NIXOS_CURSOR_FLAKE_DIR=/home/user/.config/home-manager
```

---

### 3. Disabled Built-In Updater

Cursor's internal updater is **automatically disabled** via `--update=false` flag to prevent confusing error messages.

---

## Usage Examples

### Check for Updates Manually

```bash
cursor-check-update
# Output:
# Checking for Cursor updates...
# Current version: 2.1.20
# Latest version:  2.1.21
# Update available: 2.1.20 → 2.1.21
# 
# [Desktop notification appears]
```

### Update Cursor

```bash
cursor-update
# Output:
#  Cursor Nix Updater
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 
# Flake directory: /home/user/.config/home-manager
# Current version: 2.1.20
# 
#  Updating nixos-cursor flake input...
# DONE: Flake input updated
# 
# Rebuilding Home Manager configuration...
# DONE: Home Manager rebuilt successfully
# 
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DONE: Update complete!
#    2.1.20 → 2.1.21
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Update Manually (Traditional Nix Way)

```bash
# Still works if you prefer manual control:
cd ~/.config/home-manager
nix flake update nixos-cursor
home-manager switch
```

---

## Configuration Options

### Home Manager Module

```nix
programs.cursor = {
  enable = true;
  
  # Update notifications (default: enabled)
  updateCheck = {
    enable = true;  # Show desktop notifications for updates
    interval = "daily";  # "daily", "weekly", "Mon 09:00", etc.
  };
  
  # Flake directory for cursor-update command
  flakeDir = "/home/user/.config/home-manager";  # Optional: auto-detects if not set
  
  # MCP servers, etc.
  mcp.enable = false;
};
```

### Disable Update Notifications

```nix
programs.cursor = {
  enable = true;
  updateCheck.enable = false;  # No automatic checks
};
```

---

## Implementation Details

### Components

1. **`cursor/check-update.sh`** - Queries Cursor API, shows notifications
2. **`cursor/nix-update.sh`** - Convenience wrapper for Nix update workflow
3. **`cursor/default.nix`** - Installs scripts as `cursor-check-update` and `cursor-update`
4. **Home Manager Module** - Configures systemd timer for daily checks

### Systemd Timer

Automatically enabled when `updateCheck.enable = true`:

```bash
# Check status
systemctl --user status cursor-update-check.timer

# View logs
journalctl --user -u cursor-update-check.service

# Force check now
systemctl --user start cursor-update-check.service
```

### Update Script Logic

```bash
# Flake directory detection priority:
1. $NIXOS_CURSOR_FLAKE_DIR environment variable
2. Auto-detect common locations:
   - ~/.config/home-manager
   - ~/.config/nixos
   - ~/nixos
   - ~/.nixos
3. If not found, show manual instructions
```

---

## Comparison with Other Solutions

### NOT: Option 1: Let Cursor Self-Update

**Problem**: Requires Nix rebuild after every update (autoPatchelfHook)
**Status**: Not feasible

### NOT: Option 2: Background Service Auto-Patching

**Problem**: Complex, breaks reproducibility, security concerns
**Status**: Rejected

### DONE: Option 3: Notifications (What We Implemented)

**Benefits**:
- Simple and reliable
- Maintains Nix reproducibility
- User stays informed
- Still uses proper Nix workflow

### DONE: Option 4: Convenience Command (What We Implemented)

**Benefits**:
- One-command updates
- Auto-detects flake location
- Handles both Home Manager and NixOS
- User-friendly while using Nix properly

---

## Testing

### Test Update Checker

```bash
# Check current version
cursor --version

# Manually test update check
cursor-check-update

# Should output:
# - Current version
# - Latest version from API
# - Desktop notification if update available
```

### Test Update Command

```bash
# Dry-run (won't actually update)
# Set environment to test path detection
export NIXOS_CURSOR_FLAKE_DIR=/path/to/test

cursor-update

# Should:
# 1. Find your flake directory
# 2. Run nix flake update nixos-cursor
# 3. Rebuild Home Manager or NixOS
# 4. Report old → new version
```

### Test Systemd Timer

```bash
# Check timer status
systemctl --user status cursor-update-check.timer

# List next scheduled run
systemctl --user list-timers cursor-update-check

# Force run now
systemctl --user start cursor-update-check.service

# Check logs
journalctl --user -u cursor-update-check.service -f
```

---

## Troubleshooting

### "Could not find your flake directory"

**Solution 1**: Set environment variable
```bash
export NIXOS_CURSOR_FLAKE_DIR=/path/to/your/flake
cursor-update
```

**Solution 2**: Set in Home Manager config
```nix
programs.cursor.flakeDir = "/path/to/your/flake";
```

**Solution 3**: Update manually
```bash
cd /path/to/your/flake
nix flake update nixos-cursor
home-manager switch
```

### Update notification not showing

**Check timer status**:
```bash
systemctl --user status cursor-update-check.timer
```

**Check if notification daemon is running**:
```bash
# Should have a notification daemon (dunst, mako, etc.)
ps aux | grep -E 'dunst|mako|notification'
```

**Manual test**:
```bash
cursor-check-update
# Should show desktop notification
```

### Update check fails with HTTP error

**Check network**:
```bash
# Test Cursor API directly
curl -s https://api2.cursor.sh/updates/api/download/stable | jq
```

**Check logs**:
```bash
journalctl --user -u cursor-update-check.service
```

---

## Future Enhancements

### Potential Improvements

1. **Auto-Update Option** - Automatically run `nix flake update` on notification
   ```nix
   programs.cursor.autoUpdate = true;  # Runs update automatically
   ```

2. **Update Cadence Control** - More granular control over update timing
   ```nix
   programs.cursor.updateCheck.interval = "Mon,Wed,Fri 09:00";
   ```

3. **Version Pinning** - Opt-out of updates for stability
   ```nix
   programs.cursor.version = "2.1.20";  # Pin to specific version
   ```

4. **Changelog Integration** - Show what's new in updates
   ```bash
   cursor-update --show-changelog
   ```

---

## Summary

**Problem**: Cursor can't self-update on NixOS (read-only /nix/store + autoPatchelfHook requirement)

**Solution**: 
- DONE: Daily update notifications (systemd timer)
- DONE: Convenience command: `cursor-update`
- DONE: Automatic flake detection
- DONE: Works with Home Manager and NixOS

**Result**: Cursor updates are **easy, automatic, and Nix-native**. Users get the best of both worlds: convenience of auto-updates + reproducibility of Nix. 

---

**Status**: DONE: Implemented in v2.1.20-rc1  
**Last Updated**: 2025-11-22
