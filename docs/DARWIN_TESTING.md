# 🍎 Darwin (macOS) Testing Guide

**Status**: 🧪 Experimental - Help Wanted!

Thank you for helping make Cursor work seamlessly on macOS with Nix! This guide will walk you through testing and contributing hashes for Darwin support.

---

## 📋 Table of Contents

- [Why We Need Your Help](#-why-we-need-your-help)
- [Prerequisites](#-prerequisites)
- [Quick Start (5 minutes)](#-quick-start-5-minutes)
- [Computing Hashes](#-computing-hashes)
- [Testing Packages](#-testing-packages)
- [Submitting Your Contribution](#-submitting-your-contribution)
- [Troubleshooting](#-troubleshooting)
- [Version Priority List](#-version-priority-list)

---

## 🎯 Why We Need Your Help

We've built full multi-version infrastructure for macOS (48 versions!), but we can't compute the **SHA256 hashes** for DMG files without access to macOS hardware. Nix requires these hashes for reproducible builds.

**What you'll be doing:**
1. Download Cursor DMG files
2. Compute their SHA256 hashes
3. Test that the packages build and run
4. Submit the hashes back to us

**Time commitment**: ~5 minutes per version, or ~30 minutes to verify several priority versions.

---

## 🔧 Prerequisites

### 1. Install Nix on macOS

If you don't have Nix installed:

```bash
# Recommended: Determinate Systems installer (better macOS support)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh

# Alternative: Official installer
sh <(curl -L https://nixos.org/nix/install)
```

After installation, restart your terminal or run:
```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### 2. Enable Flakes (if not already)

Add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:
```
experimental-features = nix-command flakes
```

### 3. Verify Setup

```bash
nix --version
# Should show: nix (Nix) 2.x.x

nix flake --help
# Should show flake commands
```

---

## 🚀 Quick Start (5 minutes)

Want to help immediately? Here's the fastest path:

```bash
# 1. Download the most important version (2.0.77 - our stable default)
curl -L -o cursor-2.0.77-universal.dmg \
  "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/universal/Cursor-darwin-universal.dmg"

# 2. Compute the hash
nix hash file cursor-2.0.77-universal.dmg
# Output: sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=

# 3. Open an issue or PR with your result!
# https://github.com/Distracted-E421/nixos-cursor/issues/new
```

That's it! Even one hash helps tremendously.

---

## 🔢 Computing Hashes

### Method 1: Using Nix (Recommended)

```bash
# Download a DMG
curl -L -o cursor.dmg "URL_FROM_TABLE_BELOW"

# Compute SRI hash (the format Nix expects)
nix hash file cursor.dmg
```

The output will look like: `sha256-NPs0P+cnPo3KMdezhAkPR4TwpcvIrSuoX+40NsKyfzA=`

### Method 2: Using OpenSSL + Base64

```bash
# Compute raw SHA256
openssl dgst -sha256 -binary cursor.dmg | base64
# Then prefix with: sha256-
```

### Method 3: Using shasum

```bash
shasum -a 256 cursor.dmg
# Note: This outputs hex, needs conversion to base64 for Nix
```

---

## 🧪 Testing Packages

Once you have a hash, you can test the package builds correctly:

### Step 1: Clone and Update Hash

```bash
git clone https://github.com/Distracted-E421/nixos-cursor.git
cd nixos-cursor
```

Edit `cursor-versions-darwin.nix` and replace the placeholder hash for your version:

```nix
# Find the version you're testing, e.g.:
cursor-2_0_77 = mkCursorDarwinVersion {
  version = "2.0.77";
  commitHash = commits."2.0.77";
  hashUniversal = "sha256-YOUR_COMPUTED_HASH_HERE=";  # <-- Update this
  binaryName = "cursor-2.0.77";
};
```

### Step 2: Test the Build

```bash
# Test evaluation (fast, no download)
nix flake check --no-build

# Test actual build
nix build .#cursor-2_0_77

# Run it!
./result/bin/cursor-2.0.77
```

### Step 3: Verify Functionality

Check these work:
- [ ] App launches without crashing
- [ ] Window appears correctly
- [ ] Can open a file/folder
- [ ] Settings menu accessible
- [ ] Extensions panel loads

---

## 📤 Submitting Your Contribution

### Option A: GitHub Issue (Easiest)

Create an issue at: https://github.com/Distracted-E421/nixos-cursor/issues/new

Title: `Darwin Hash: Cursor X.Y.Z`

Body:
```markdown
## Version
Cursor X.Y.Z

## Platform
- [ ] x86_64-darwin (Intel Mac)
- [ ] aarch64-darwin (Apple Silicon)

## Hashes Computed

### Universal Binary (Recommended)
- URL: `https://downloads.cursor.com/production/COMMIT/darwin/universal/Cursor-darwin-universal.dmg`
- Hash: `sha256-XXXXXX=`

### Intel (x64) - Optional
- URL: `https://downloads.cursor.com/production/COMMIT/darwin/x64/Cursor-darwin-x64.dmg`
- Hash: `sha256-XXXXXX=`

### Apple Silicon (arm64) - Optional
- URL: `https://downloads.cursor.com/production/COMMIT/darwin/arm64/Cursor-darwin-arm64.dmg`
- Hash: `sha256-XXXXXX=`

## Testing Results
- [ ] Package builds successfully
- [ ] App launches
- [ ] Basic functionality works

## Your System
- macOS version: 
- Chip: Intel / Apple Silicon
- Nix version: 
```

### Option B: Pull Request (Best)

1. Fork the repository
2. Update the hashes in `cursor-versions-darwin.nix`
3. Submit PR with title: `feat(darwin): Add hashes for Cursor X.Y.Z`

---

## 🔥 Version Priority List

Help us by focusing on these versions first:

### 🔴 Critical (Default/Stable)
| Version | Commit Hash | Status |
|---------|-------------|--------|
| **2.0.77** | `ba90f2f88e4911312761abab9492c42442117cfe` | ⏳ Needs Hash |

### 🟠 High Priority (Popular)
| Version | Commit Hash | Status |
|---------|-------------|--------|
| 2.1.34 | `609c37304ae83141fd217c4ae638bf532185650f` | ⏳ Needs Hash |
| 2.0.64 | `25412918da7e74b2686b25d62da1f01cfcd27683` | ⏳ Needs Hash |
| 1.7.54 | `5c17eb2968a37f66bc6662f48d6356a100b67be8` | ⏳ Needs Hash |

### 🟡 Medium Priority
| Version | Commit Hash | Status |
|---------|-------------|--------|
| 2.1.32 | `ef979b1b43d85eee2a274c25fd62d5502006e425` | ⏳ Needs Hash |
| 2.0.75 | `9e7a27b76730ca7fe4aecaeafc58bac1e2c82121` | ⏳ Needs Hash |
| 2.0.69 | `63fcac100bd5d5749f2a98aa47d65f6eca61db39` | ⏳ Needs Hash |
| 1.7.46 | `b9e5948c1ad20443a5cecba6b84a3c9b99d62582` | ⏳ Needs Hash |

### Download URL Template

```
Universal: https://downloads.cursor.com/production/{COMMIT}/darwin/universal/Cursor-darwin-universal.dmg
Intel:     https://downloads.cursor.com/production/{COMMIT}/darwin/x64/Cursor-darwin-x64.dmg  
ARM64:     https://downloads.cursor.com/production/{COMMIT}/darwin/arm64/Cursor-darwin-arm64.dmg
```

---

## 🛠️ Troubleshooting

### "Hash mismatch" Error

```
error: hash mismatch in fixed-output derivation
  specified: sha256-AAAA...
  got:       sha256-BBBB...
```

**Solution**: The "got" hash is the correct one! Update the file with that hash.

### "Cannot download" Error

Some older versions may have been removed from Cursor's servers. If you get a 404:
1. Try the x64 or arm64 specific URLs instead of universal
2. Check if the version exists at https://cursor.com/changelog
3. Report the missing version in your issue

### App Won't Launch

If the app builds but crashes on launch:
```bash
# Check console logs
/Applications/Cursor.app/Contents/MacOS/Cursor --verbose

# Or from our package
./result/bin/cursor --verbose
```

### Gatekeeper Issues

If macOS blocks the app:
```bash
# Remove quarantine attribute
xattr -cr ./result/Applications/Cursor.app
```

### "undmg: command not found"

The `undmg` tool should be provided by Nix. If missing:
```bash
nix-shell -p undmg
```

---

## 📊 Current Status

| Platform | Versions | Hash Status | Build Status |
|----------|----------|-------------|--------------|
| x86_64-linux | 48 | ✅ Complete | ✅ Working |
| aarch64-linux | 48 | ⚠️ Placeholders | ⚠️ Untested |
| x86_64-darwin | 48 | ⏳ Need Hashes | 🧪 Experimental |
| aarch64-darwin | 48 | ⏳ Need Hashes | 🧪 Experimental |

---

## 🙏 Contributors

Thank you to everyone who helps make this possible!

<!-- Contributors will be listed here as they submit hashes -->

---

## 📚 Related Documentation

- [Main README](../README.md)
- [Version Tracking](../CURSOR_VERSION_TRACKING.md)
- [User Data Persistence](./USER_DATA_PERSISTENCE.md)

---

## 💬 Questions?

- Open an issue: https://github.com/Distracted-E421/nixos-cursor/issues
- Or reach out to [@Distracted-E421](https://github.com/Distracted-E421)

**Every hash you contribute brings us closer to full macOS support!** 🎉
