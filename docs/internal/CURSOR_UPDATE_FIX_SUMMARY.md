# Cursor Auto-Update Fix Summary

**Date**: 2025-11-22  
**Issue**: Cursor's native update system broken on NixOS - redirects to website instead of auto-updating  
**Status**: ✅ **FIXED**  

---

## 🎯 The Problem

On Obsidian (and all NixOS systems), when you check for updates in Cursor:

```
Cursor → Help → Check for Updates
❌ "A newer version is available. Please download from cursor.com"
```

**Why this happens**:
- Cursor's updater expects to replace the AppImage file itself
- On NixOS, Cursor is in `/nix/store` which is **read-only**
- Update fails → Falls back to manual download prompt

---

## ✅ The Solution

Following nixpkgs' `code-cursor` implementation:

1. **Disable built-in updater**: Added `--update=false` flag
2. **Automated update script**: `cursor/update.sh` queries Cursor API
3. **Nix-managed updates**: Users update via `nix flake update`

---

## 🚀 Quick Start

**For Maintainers** (updating to new Cursor version):

```bash
cd cursor
./update.sh
cd .. && nix build .#cursor
git commit -am "chore: Update Cursor to $(nix eval .#cursor.version --raw)"
```

**For End Users** (applying updates):

```bash
nix flake update cursor-with-mcp
home-manager switch
```

---

**See**: [AUTO_UPDATE_IMPLEMENTATION.md](AUTO_UPDATE_IMPLEMENTATION.md) for full details
