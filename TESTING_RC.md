# Testing nixos-cursor RC1

**Release**: v2.1.20-rc1  
**Status**: Release Candidate - Testing Phase  
**Date**: 2025-11-23

Welcome RC testers! This guide will help you test the pre-release candidate properly.

---

## 📋 What You're Testing

This is a **Release Candidate (RC)** for nixos-cursor - a native NixOS packaging of Cursor IDE with:
- Native Wayland/X11 support
- Hardware-accelerated graphics
- NixOS-specific fixes (keyboard mapping, GPU acceleration)
- MCP (Model Context Protocol) server integration framework
- Automatic update system

---

## 🎯 Testing Scope

### Critical (Please Test)
- [ ] Package builds successfully
- [ ] Cursor launches without errors
- [ ] Basic editing works
- [ ] Extensions can be installed
- [ ] Keyboard shortcuts work
- [ ] GPU acceleration functions (check `chrome://gpu`)

### Important (Please Test If Possible)
- [ ] Wayland mode works (if using Wayland)
- [ ] Multi-monitor setup works
- [ ] Different NixOS versions (24.05, 24.11, unstable)
- [ ] ARM64 hardware (if available)

### Optional (Nice to Have)
- [ ] MCP server integration (advanced users)
- [ ] Declarative extension management
- [ ] Dev shell environment

---

## 🚀 Quick Start - Testing RC1

### Method 1: Try Without Installing

**Fastest way to test**:

```bash
# Run directly from this flake (no installation)
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor
```

This will:
- Build the package (may take a few minutes first time)
- Launch Cursor with RC1 version
- Use your normal user profile (safe to test)

---

### Method 2: Install Temporarily

**For more thorough testing**:

```bash
# Create a test shell with cursor available
nix shell github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor

# Then run it
cursor
```

---

### Method 3: Install via Home Manager (Recommended)

**For daily use testing**:

Add to your `home.nix` or `flake.nix`:

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.1.20-rc1";
  
  outputs = { self, nixpkgs, nixos-cursor, home-manager, ... }: {
    homeConfigurations.youruser = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixos-cursor.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            # MCP servers optional for now
            mcp.enable = false;
          };
        }
      ];
    };
  };
}
```

Then apply:

```bash
home-manager switch
```

---

## 🔍 What to Look For

### ✅ Success Indicators

**Cursor launches and shows**:
- Normal Cursor interface
- Extensions can be browsed/installed
- Files can be opened and edited
- No obvious graphical glitches

**Terminal shows**:
```bash
$ cursor --version
Cursor 2.1.20
```

**About dialog** (Help → About):
- Version: 2.1.20
- No errors in logs

---

### ❌ Problems to Report

**Critical Issues** (please report ASAP):
- Cursor won't launch
- Immediate crashes
- Severe graphical corruption
- Complete loss of functionality

**Major Issues** (please report):
- Keyboard shortcuts don't work
- Extensions won't install
- Performance significantly worse than AppImage
- Multi-window issues

**Minor Issues** (nice to know):
- Small UI glitches
- Minor performance differences
- Documentation unclear
- Feature requests

---

## 📊 System Information

When reporting issues, please include:

```bash
# Your NixOS version
nixos-version

# Your system architecture
uname -m

# Your desktop environment
echo $XDG_CURRENT_DESKTOP

# Display server
echo $WAYLAND_DISPLAY  # or $DISPLAY for X11

# Graphics info
nix-shell -p glxinfo --run "glxinfo | grep 'OpenGL renderer'"
```

---

## 🐛 How to Report Issues

### Via GitHub Issues

1. Go to: https://github.com/Distracted-E421/nixos-cursor/issues
2. Click "New Issue"
3. Include:
   - **Title**: Brief description (e.g., "Cursor won't launch on Wayland")
   - **System Info**: Output from commands above
   - **Steps to reproduce**: What you did
   - **Expected**: What should happen
   - **Actual**: What actually happened
   - **Logs**: Any error messages

### Example Issue Report

```markdown
**Title**: Keyboard shortcuts not working on NixOS 24.11

**System**:
- NixOS: 24.11
- Architecture: x86_64
- Desktop: KDE Plasma 6
- Display: Wayland
- GPU: Intel Arc A770

**Steps**:
1. Installed via Home Manager
2. Launched Cursor
3. Tried Ctrl+P (command palette)
4. Nothing happened

**Expected**: Command palette should open

**Actual**: No response to keyboard shortcut

**Logs**: (paste any relevant logs here)
```

---

## 🧪 Advanced Testing

### Testing MCP Integration (Optional)

If you want to test MCP server integration, see:
- [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)
- [examples/with-mcp/](examples/with-mcp/)

**Note**: MCP setup is manual for RC1 - requires configuration.

---

### Testing Isolated Profile (Safe Testing)

To test without affecting your main Cursor profile:

```bash
# Run with isolated test profile
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor-test
```

This uses separate directories:
- Profile: `/tmp/cursor-test-profile`
- Extensions: `/tmp/cursor-test-extensions`

Safe to experiment with, won't touch your main setup.

---

## 📖 Additional Documentation

- **[README.md](README.md)** - Project overview
- **[LICENSE](LICENSE)** - MIT License
- **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** - MCP server setup
- **[KNOWN_ISSUES.md](KNOWN_ISSUES.md)** - Known problems
- **[docs/AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md)** - Update system

---

## ✅ What Happens After Testing?

Based on your feedback:

1. **No critical issues**: Move to stable release (v2.1.20)
2. **Minor issues found**: Release RC2 with fixes
3. **Major issues found**: Hold release, fix problems

Your testing helps make this better for everyone!

---

## 🙏 Thank You!

Testing RC releases is crucial for quality. We appreciate you taking the time to help!

**Questions?** Open a GitHub discussion or issue.

---

**Maintainer**: e421 (distracted.e421@gmail.com)  
**License**: MIT (see [LICENSE](LICENSE))  
**Repository**: https://github.com/Distracted-E421/nixos-cursor
