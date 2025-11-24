# Cursor RC2 Issue - Status and Fix

**Date**: 2025-11-24
**Status**: BROKEN - Working on fix
**User Impact**: Cannot launch cursor

## What Went Wrong

### The Situation
1. User tried to switch from old cursor-ide system to nixos-cursor RC2 (2.0.64)
2. Build failed due to DNS issue (cannot resolve downloader.cursor.sh)
3. System was left with broken cursor wrapper
4. User rolled back 2 generations, but cursor still doesn't launch

### The Root Cause
The current system has a Python wrapper at `/run/current-system/sw/bin/cursor` that expects to find the actual cursor binary at `/run/current-system/sw/bin/.cursor-wrapped`, but that file doesn't exist.

The nixos-cursor flake build fails because:
- DNS cannot resolve downloader.cursor.sh
- The fetchurl in cursor/default.nix requires network access
- No cached version exists

### The Error Screenshot
The error shows cursor-0.42.5 crashing, which is WAY too old and suggests something is very broken in the extraction/patching process.

## Immediate Solution Options

### Option 1: Quick Fix - Direct AppImage Launch (NOW)

You have `/home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage` which has custom modes!

```bash
# Make executable
chmod +x /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage

# Launch directly (this works immediately)
/home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage

# Or create a wrapper
mkdir -p ~/.local/bin
cat > ~/.local/bin/cursor << 'WRAPPER'
#!/usr/bin/env bash
exec /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage "$@"
WRAPPER
chmod +x ~/.local/bin/cursor

# Now you can run: cursor
```

This gives you cursor IMMEDIATELY with custom modes (2.0.77 still has them).

### Option 2: Build from Local AppImage (Better)

Once DNS is working (or using the local file):

```bash
cd /home/e421/nixos-cursor

# Test that cursor package can build with correct settings
nix build .#cursor --option substitute false --show-trace

# If it fails with DNS, we need to fix the default.nix to use local files
```

### Option 3: Fix DNS and Rebuild (Proper)

```bash
# Check if DNS is actually broken
host downloader.cursor.sh
ping -c 1 downloader.cursor.sh

# If DNS works, rebuild nixos-cursor
cd /home/e421/nixos-cursor
nix build .#cursor

# If successful, rebuild homelab
cd /home/e421/homelab/nixos
nix flake update nixos-cursor
sudo nom-rebuild switch --impure --flake .#Obsidian
```

## Multi-Version System (In Progress)

### What We're Building
A system to run multiple Cursor versions simultaneously:
- `cursor` → 2.0.64 (default, last with custom modes)
- `cursor-2.0.64` → Explicit 2.0.64
- `cursor-2.0.77` → Latest 2.0.x
- `cursor-1.7.54` → Popular pre-2.0

### Files Created
- `cursor-versions.nix` - Multi-version system
- `cursor/default.nix` - Updated with version/hash parameters
- `flake.nix` - Exposes all versions

### Current Status
- ✅ cursor-versions.nix created
- ✅ cursor/default.nix parameterized
- ✅ flake.nix updated
- ❌ DNS issue blocks builds
- ❌ Need local-file fallback system

## The Real Problem: Network vs Local

The current cursor/default.nix uses fetchurl which REQUIRES network:
```nix
sources = {
  x86_64-linux = fetchurl {
    url = "https://downloader.cursor.sh/linux/appImage/x64/${version}";
    inherit hash;
  };
}
```

When DNS fails, this breaks completely.

### Solution: Hybrid System

We need to support BOTH network and local builds:

```nix
# Option A: Network fetch (normal)
let
  sources = if localAppImage != null
    then {
      # Use local file
      x86_64-linux = localAppImage;
    }
    else {
      # Use network
      x86_64-linux = fetchurl {
        url = "https://downloader.cursor.sh/linux/appImage/x64/${version}";
        hash = hash;
      };
    };
```

## Recommended Action Plan

### Right Now (Get Working)
1. Use Option 1 above - launch AppImage directly
2. This gives you cursor with custom modes immediately
3. No system changes needed

### Short Term (Fix nixos-cursor)
1. Fix DNS or implement local-file support in cursor/default.nix
2. Verify cursor 2.0.77 hash: `sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=`
3. Update cursor-versions.nix with correct hashes
4. Test build: `nix build .#cursor-2_0_77`

### Medium Term (Multi-Version System)
1. Add more version hashes to cursor-versions.nix
2. Test all versions build correctly
3. Create wrapper scripts for easy version switching
4. Document usage

### Long Term (Polish)
1. Add automatic version detection from local AppImages
2. Create update script that checks for new versions
3. Add migration helper from cursor-ide to nixos-cursor
4. Submit to nixpkgs

## Files Status

### Working Files
- ✅ `cursor/default.nix` - Parameterized, needs local-file support
- ✅ `cursor-versions.nix` - Multi-version definitions
- ✅ `flake.nix` - Exposes all versions

### Broken Files
- ❌ `cursor/from-local.nix` - Incomplete, needs rewrite

### Missing Files
- ❌ Local AppImage builder that works
- ❌ Version migration script
- ❌ DNS fallback system

## Next Steps

**Immediate** (you can do now):
```bash
chmod +x /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage
/home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage
```

**After DNS fixed** (or I implement local-file support):
```bash
cd /home/e421/nixos-cursor
nix build .#cursor-2_0_77
nix run .#cursor-2_0_77  # Test it works
```

**Then integrate into homelab**:
```bash
cd /home/e421/homelab/nixos
# Update flake input to latest nixos-cursor
nix flake update nixos-cursor
# Rebuild
sudo nom-rebuild switch --impure --flake .#Obsidian
```

## Questions

1. **Does DNS actually work?** - Run: `host downloader.cursor.sh`
2. **Do you want 2.0.77 or 2.0.64?** - Both have custom modes
3. **Do you need multiple versions simultaneously?** - We can build that
4. **Can you use the AppImage directly for now?** - Fastest solution

---

**Status**: Documented - Waiting for user input on preferred solution
