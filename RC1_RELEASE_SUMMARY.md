# RC1 Release Summary - nixos-cursor v2.1.20-rc1

**Date**: 2025-11-22  
**Status**: Ready for Community Testing  
**Version**: v2.1.20-rc1

---

## What's Ready

### Core Functionality

1. **Native Cursor Packaging**
   - Cursor IDE 2.1.20 AppImage properly patched for NixOS
   - GPU acceleration (libGL, libxkbfile fixes)
   - Wayland + X11 support
   - Both x86_64 and aarch64 architectures

2. **Auto-Update System** (NEW)
   - **Daily update notifications** via systemd timer
   - **One-command updates**: `cursor-update`
   - **Manual check**: `cursor-check-update`
   - Auto-detects flake directory or uses `$NIXOS_CURSOR_FLAKE_DIR`
   - Maintains Nix reproducibility while providing convenience
   - Built-in updater disabled (`--update=false`) to prevent errors

3. **MCP Integration Framework**
   - Filesystem MCP (enabled by default)
   - Memory MCP (persistent knowledge)
   - NixOS MCP (package/option search)
   - GitHub MCP (full Git workflow)
   - Playwright MCP (browser automation)

4. **Home Manager Module**
   - Declarative configuration
   - Automatic MCP server management
   - Browser integration (Chromium/Chrome/Firefox/WebKit)
   - Update notification configuration
   - Flake directory setting

5. **Test Instance**
   - `cursor-test` package with isolated profile
   - Safe testing without affecting main installation

---

## Installation Methods

### Method 1: Try Without Installing (Recommended for Testing)

```bash
# Run directly from GitHub
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor
```

### Method 2: Home Manager (Full Installation)

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.1.20-rc1";
  
  outputs = { nixos-cursor, ... }: {
    homeConfigurations.youruser = {
      modules = [
        nixos-cursor.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            
            # Update system (enabled by default)
            updateCheck.enable = true;
            updateCheck.interval = "daily";
            flakeDir = "/path/to/your/flake";  # Optional
            
            # MCP servers (optional)
            mcp.enable = false;
          };
        }
      ];
    };
  };
}
```

### Method 3: NixOS System Package

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.1.20-rc1";
  
  environment.systemPackages = [
    nixos-cursor.packages.${system}.cursor
  ];
}
```

### Method 4: Overlay

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.1.20-rc1";
  
  nixpkgs.overlays = [ nixos-cursor.overlays.default ];
  environment.systemPackages = [ pkgs.cursor ];
}
```

---

## Using the Update System

### Automatic Notifications (Default)

After installation, Cursor will check for updates daily:

```bash
# Check systemd timer status
systemctl --user status cursor-update-check.timer

# View when next check will run
systemctl --user list-timers cursor-update-check

# Force a check now
systemctl --user start cursor-update-check.service
```

### Manual Updates

```bash
# Check if update available
cursor-check-update

# Update Cursor (one command does everything)
cursor-update

# Traditional Nix way (also works)
cd ~/.config/home-manager
nix flake update nixos-cursor
home-manager switch
```

### Configuration

```nix
programs.cursor = {
  enable = true;
  
  # Disable automatic checks (not recommended)
  updateCheck.enable = false;
  
  # Change check frequency
  updateCheck.interval = "weekly";  # or "Mon 09:00", etc.
  
  # Set flake directory (helps cursor-update find your config)
  flakeDir = "/home/user/.config/home-manager";
};
```

**Why this system?** Cursor can't self-update on NixOS because it lives in the read-only `/nix/store` and requires `autoPatchelfHook` re-patching. Our system provides the convenience of auto-updates while maintaining Nix's reproducibility guarantees.

See [docs/AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md) for technical details.

---

## Documentation

All essential docs are in place:

- **[README.md](README.md)** - Main entry point with quick start
- **[TESTING_RC.md](TESTING_RC.md)** - Comprehensive testing guide
- **[docs/AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md)** - Update system details
- **[KNOWN_ISSUES.md](KNOWN_ISSUES.md)** - Known limitations
- **[cursor/README.md](cursor/README.md)** - Package technical docs
- **[.github/ISSUE_TEMPLATE/bug_report.md](.github/ISSUE_TEMPLATE/bug_report.md)** - Bug reporting template
- **[examples/](examples/)** - Configuration examples

---

## Known Caveats for RC1

### 1. MCP Server Configuration

**Issue**: MCP server setup requires some manual steps (installing Node.js, uvx, etc.).

**Status**: Documented in INTEGRATION_GUIDE.md but not fully automated.

**Workaround**: Follow the integration guide step-by-step.

**For RC2**: Consider adding automatic dependency installation to Home Manager module.

---

### 2. ARM64 Testing

**Issue**: ARM64 build is untested (maintainer has x86_64 hardware only).

**Status**: Package builds successfully via CI, but runtime untested.

**Need**: ARM64 users to test and report issues.

---

### 3. Update Flake Detection

**Issue**: `cursor-update` tries to auto-detect flake location, may fail in non-standard setups.

**Workaround**: Set `programs.cursor.flakeDir` or export `NIXOS_CURSOR_FLAKE_DIR`.

**For RC2**: Improve detection heuristics, add more common paths.

---

### 4. Desktop Integration

**Issue**: `.desktop` file may not show proper icon on first install.

**Workaround**: Logout/login or run `update-desktop-database ~/.local/share/applications/`.

**For RC2**: Investigate automatic desktop database update via Home Manager.

---

## Pre-Release Checklist

- [x] Core package builds on x86_64
- [x] Core package builds on aarch64 (CI verified, runtime untested)
- [x] Home Manager module works
- [x] Test instance (`cursor-test`) builds
- [x] Update system implemented (notifications + commands)
- [x] Update documentation complete
- [x] Examples provided
- [x] Bug report template created
- [x] LICENSE file present and correct
- [x] README prominently features RC status and testing instructions
- [x] `nix flake check` passes
- [x] Testing guide (TESTING_RC.md) comprehensive

---

## Next Steps to Release

**1. Tag the Release**

```bash
# Create the RC1 tag
git tag -a v2.1.20-rc1 -m "Release Candidate 1 for v2.1.20

Features:
- Native NixOS packaging of Cursor IDE 2.1.20
- Wayland/X11 support with GPU acceleration
- MCP server integration framework
- Automated update system with daily notifications
- One-command updates (cursor-update)
- Comprehensive testing documentation

This is a release candidate for community testing.
See TESTING_RC.md for testing instructions."
```

**2. Push to GitHub**

```bash
# Push the branch
git push origin pre-release

# Push the tag
git push origin v2.1.20-rc1
```

**3. Create GitHub Release**

Go to: https://github.com/Distracted-E421/nixos-cursor/releases/new

- Tag: `v2.1.20-rc1`
- Title: `v2.1.20-rc1 - Release Candidate 1`
- Description:

```markdown
# 🚀 Release Candidate 1

This is the first release candidate of nixos-cursor. We're looking for community testing before the stable v2.1.20 release.

## ✨ What's New

- **Automated Update System**: Daily notifications + one-command updates
- **Native NixOS Packaging**: Cursor IDE 2.1.20 with full GPU support
- **MCP Server Integration**: Framework for 5+ MCP servers
- **Comprehensive Documentation**: Testing guides, examples, troubleshooting

## 🧪 Testing

See **[TESTING_RC.md](TESTING_RC.md)** for full instructions.

Quick start:
\`\`\`bash
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor
\`\`\`

## 🐛 Reporting Issues

Found a bug? Please report it: https://github.com/Distracted-E421/nixos-cursor/issues

## 📚 Documentation

- [README.md](README.md) - Quick start
- [TESTING_RC.md](TESTING_RC.md) - Testing guide
- [AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md) - Update system
- [examples/](examples/) - Configuration examples
```

---

## Post-Release Checklist

After tagging and creating GitHub Release:

- [ ] Announce in NixOS Discourse
- [ ] Share in relevant Reddit communities (r/NixOS)
- [ ] Monitor GitHub issues for bug reports
- [ ] Collect feedback on update system
- [ ] Address critical bugs with RC2 if needed
- [ ] Plan timeline for stable v2.1.20 release

---

## Success Criteria for Stable Release

RC1 graduates to stable v2.1.20 when:

1. At least 5 users test successfully on x86_64
2. At least 1 user tests successfully on aarch64
3. No critical bugs reported
4. Update system works reliably
5. MCP integration functional (even if setup manual)
6. Documentation complete and clear

Timeline: **1-2 weeks of testing** → stable release

---

**Prepared by**: AI Agent (Maxim)  
**Reviewed by**: e421  
**Status**: Ready for Tag & Push
