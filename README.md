# nixos-cursor

**Status**: Release Candidate 3.3 (v2.0.77) - **37 Versions Available**  
**License**: MIT  
**Maintained by**: e421  
**Credits**: Version tracking by [oslook](https://github.com/oslook)

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers**, automated updates, and a **Multi-Version Manager** with **37 historical versions** spanning three eras for ultimate workflow stability.

> **Why Release Candidate 3.3?**
> We are targeting **Cursor 2.0.77** as our primary stable release. With the deprecation of custom agent modes in Cursor 2.1.x, many users (ourselves included) found their workflows disrupted. This package now includes a comprehensive **Version Manager** with a polished GUI that allows you to run any of **37 versions** (spanning 2.0.x, 1.7.x, and 1.6.x) side-by-side with isolated configurations. We refuse to have our workflows dictated on a whim, so we built the tools to take control back.

**Version Coverage:**
- **2.0.x Custom Modes Era**: 17 versions (2.0.11 - 2.0.77)
- **1.7.x Classic Era**: 19 versions (1.7.11 - 1.7.54)
- **1.6.x Legacy Era**: 1 version (1.6.45)

See [CURSOR_VERSION_TRACKING.md](CURSOR_VERSION_TRACKING.md) for the full manifest.

---

## Features

- Native NixOS packaging of Cursor IDE 2.0.77 (Stable)
- **🎯 Multi-Version Manager**: **37 versions** available (2.0.x, 1.7.x, 1.6.x)
- **🖥️ Modern GUI**: Dropdown menus organized by era for easy selection
- **🔒 Isolated User Data**: Each version keeps its own settings/extensions
- **⚡ Concurrent Launches**: Run multiple versions simultaneously
- **🔄 Settings Sync**: Optional sync of keybindings and settings
- Wayland + X11 support with GPU acceleration
- MCP server integration (filesystem, memory, NixOS, GitHub, Playwright)
- Automated update system with daily notifications
- One-command updates (`cursor-update`)
- GPU fixes (libGL, libxkbfile) for NixOS compatibility

---

## 🚀 Quick Start

### **Multi-Version Manager (37 Versions)**
Choose from **37 historical Cursor versions** spanning three major eras!

```bash
# Launch the version manager GUI (dropdown menus with persistent settings)
nix run github:Distracted-E421/nixos-cursor#cursor-manager

# Or run specific versions directly:

# Latest stable with custom modes
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77

# Latest pre-2.0 (community favorite)
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54

# First custom modes release
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_11

# Oldest available
nix run github:Distracted-E421/nixos-cursor#cursor-1_6_45

# Run multiple versions concurrently:
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77 &
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54 &
```

**For Local Development:**
```bash
# Set CURSOR_FLAKE_URI to use local flake
CURSOR_FLAKE_URI=. nix run .#cursor-manager --impure
```

**Full Version List** (replace dots with underscores):
- **2.0.x**: 2.0.77, 2.0.75, 2.0.74, 2.0.73, 2.0.69, 2.0.64, 2.0.63, 2.0.60, 2.0.57, 2.0.54, 2.0.52, 2.0.43, 2.0.40, 2.0.38, 2.0.34, 2.0.32, 2.0.11
- **1.7.x**: 1.7.54, 1.7.53, 1.7.52, 1.7.46, 1.7.44, 1.7.43, 1.7.40, 1.7.39, 1.7.38, 1.7.36, 1.7.33, 1.7.28, 1.7.25, 1.7.23, 1.7.22, 1.7.17, 1.7.16, 1.7.12, 1.7.11
- **1.6.x**: 1.6.45

See [VERSION_MANAGER_GUIDE.md](VERSION_MANAGER_GUIDE.md) for full details.

### Install via Home Manager

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  
  outputs = { nixos-cursor, home-manager, ... }: {
    homeConfigurations.youruser = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixos-cursor.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            updateCheck.enable = true;  # Daily update notifications
            mcp.enable = false;  # Optional: MCP servers
          };
        }
      ];
    };
  };
}
```

---

## Update System

Cursor includes an automated update system that:

- Checks for updates daily via systemd timer
- Shows desktop notifications when updates available
- Provides one-command updates: `cursor-update`
- Maintains Nix reproducibility guarantees

**Why?** Cursor can't self-update on NixOS (read-only `/nix/store`). Our system provides convenience while respecting Nix principles.

---

## 🌿 Development & Contributing

This is a personal project maintained by e421. If you'd like to contribute or have suggestions, feel free to open an issue or reach out!

**Branch Strategy:**
- **`main`**: Stable releases
- **`pre-release`**: Release candidates for testing (currently RC3.3)

### Documentation

- [Version Manager Guide](VERSION_MANAGER_GUIDE.md) - Complete guide to managing 37 versions
- [Test Suite](tests/multi-version-test.sh) - Automated testing for all versions
- [Integration Success](INTEGRATION_SUCCESS_RC3.2.md) - User-facing quick start

---

## ⚖️ License & Proprietary Note

**Packaging Code**: MIT License - See [LICENSE](LICENSE) file.

**Cursor Binary**: Proprietary (Unfree).
This flake downloads the official AppImage from Cursor's servers (`downloader.cursor.sh` or `downloads.cursor.com`) and wraps it for NixOS compatibility. We do not redistribute the binary itself. You must comply with Cursor's Terms of Service when using this software.
