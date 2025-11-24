# Forum Update: Release Candidate 3 (RC3) - Multi-Version Manager

## 🎉 RC3 is Live!

We're excited to announce **Release Candidate 3** with a major new feature that addresses the custom modes deprecation head-on.

## 🔑 Key Update: Multi-Version Manager

**The Problem:** Cursor 2.1.x deprecated custom agent modes, breaking workflows for many users (including ourselves). We refuse to have our workflows dictated on a whim.

**The Solution:** A comprehensive multi-version system that lets you run **2.0.77, 1.7.54, and 2.0.64 side-by-side** with isolated configurations.

### What's New in RC3

- ✅ **GUI Version Manager**: Launch different Cursor versions from a simple interface
- ✅ **Direct S3 URLs**: No more DNS issues with `downloader.cursor.sh`
- ✅ **Isolated User Data**: Each version maintains its own settings, extensions, and custom modes
- ✅ **Config Sync**: Automatically syncs `settings.json`, `keybindings.json`, and snippets across versions
- ✅ **Experimental Docs Sharing**: Symlink `globalStorage` to share docs and auth state (opt-in)
- ✅ **Verified Hashes**: All AppImages use SRI hashes for security and reproducibility

### Try It Now

```bash
# Launch the GUI manager
nix run github:Distracted-E421/nixos-cursor#cursor-manager

# Or run specific versions directly
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
```

## 📚 Documentation

- **[Multi-Version Guide](https://github.com/Distracted-E421/nixos-cursor/blob/pre-release/VERSION_MANAGER_GUIDE.md)** - Complete usage guide
- **[GitHub Repo](https://github.com/Distracted-E421/nixos-cursor)** - Source code and installation
- **[Version Tracking](https://github.com/Distracted-E421/nixos-cursor/blob/pre-release/CURSOR_VERSION_TRACKING.md)** - All tracked versions

## 🙏 Credits

Special thanks to [@oslook](https://github.com/oslook) for maintaining [cursor-ai-downloads](https://github.com/oslook/cursor-ai-downloads) with reliable direct download links and version tracking. This made the multi-version system possible.

## 🔧 Technical Details

### DNS Resolution Fixed
Previous RC2 had issues with `downloader.cursor.sh` DNS resolution. RC3 uses direct S3 URLs:
- `https://downloads.cursor.com/production/[hash]/linux/x64/Cursor-[version]-x86_64.AppImage`

### User Data Strategies
Three approaches to managing data across versions:
1. **Isolated** (default): Each version gets `~/.cursor-VERSION/` for complete separation
2. **Shared**: All versions use `~/.config/Cursor/` (risky with incompatible DBs)
3. **Sync**: Base config shared, version-specific overrides (balanced)

### Runtime Fixes
Fixed critical `$HOME` expansion bug that caused `SQLITE_CANTOPEN` errors. Now properly expands at runtime instead of build time.

## 🐛 What Was Fixed Since RC2

1. **DNS Issues**: All versions now use S3 URLs (no more DNS failures)
2. **Runtime Path Expansion**: Fixed `$HOME` being expanded to `/homeless-shelter` at build time
3. **Isolated User Data**: Each version now properly maintains separate configs
4. **GUI Theming**: Manager now matches Cursor's light/dark theme from `settings.json`
5. **Data Sync**: Automatic syncing of base configs across isolated instances

## 🚀 What's Next

- Testing from the community
- Potential promotion to `main` branch for stable release
- Additional version support (2.0.75, 2.0.73, etc.) on request
- Improved sync mechanisms for workspace state

## 💬 Feedback Welcome

If you've been affected by the custom modes deprecation, give RC3 a try! We'd love to hear:
- Does the multi-version system work on your NixOS setup?
- Are the isolated configs maintaining your custom modes properly?
- Any issues with the GUI manager?

Report issues: https://github.com/Distracted-E421/nixos-cursor/issues

---

**TLDR:** We built a multi-version manager so you can keep using Cursor 2.0.77 (with custom modes) while having access to older or newer versions as needed. No more being forced to upgrade and lose features you rely on.
