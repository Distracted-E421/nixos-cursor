# nixos-cursor

**Status**: Release Candidate 3 (v2.0.77)  
**License**: MIT  
**Maintained by**: e421

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers**, automated updates, and a **Multi-Version Manager** for maintaining workflow stability.

> **Why Release Candidate 3?**
> We are targeting **Cursor 2.0.77** as our primary stable release. With the depreciation of custom agent modes in Cursor 2.1.x, many users (ourselves included) found their workflows disrupted. This package now includes a dedicated **Version Manager** that allows you to run specific, pinned versions of Cursor (like 2.0.77 and 1.7.54) side-by-side with isolated configurations. We refuse to have our workflows dictated on a whim, so we built the tools to take control back.

See [CURSOR_VERSION_TRACKING.md](CURSOR_VERSION_TRACKING.md) for the full manifest.

---

## Features

- Native NixOS packaging of Cursor IDE 2.0.77 (Stable)
- **Multi-Version Manager**: Run 2.0.77, 1.7.54, and 2.0.64 side-by-side
- **Isolated User Data**: Each version keeps its own settings/extensions to prevent corruption
- Wayland + X11 support with GPU acceleration
- MCP server integration (filesystem, memory, NixOS, GitHub, Playwright)
- Automated update system with daily notifications
- One-command updates (`cursor-update`)
- GPU fixes (libGL, libxkbfile) for NixOS compatibility

---

## 🚀 Quick Start

### **New! Multi-Version Manager**
We now support running specific stable versions (2.0.77, 1.7.54) side-by-side!

```bash
# Launch the version manager GUI
nix run github:Distracted-E421/nixos-cursor#cursor-manager

# Or run specific versions directly
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
```

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

This project uses a **public/private branching strategy**:

- **`main`**: Stable releases (public)
- **`pre-release`**: Release candidates for testing (public)
- **`dev`**: Active development (private)

See [BRANCHING_STRATEGY.md](BRANCHING_STRATEGY.md) for full details.

### Quick Links

- [Branching Strategy](BRANCHING_STRATEGY.md) - Development workflow
- [Scripts Documentation](scripts/README.md) - Automation tools
- [Release Strategy](RELEASE_STRATEGY.md) - Versioning and releases
- [Version Manager Guide](VERSION_MANAGER_GUIDE.md) - Managing multiple versions

---

## ⚖️ License & Proprietary Note

**Packaging Code**: MIT License - See [LICENSE](LICENSE) file.

**Cursor Binary**: Proprietary (Unfree).
This flake downloads the official AppImage from Cursor's servers (`downloader.cursor.sh` or `downloads.cursor.com`) and wraps it for NixOS compatibility. We do not redistribute the binary itself. You must comply with Cursor's Terms of Service when using this software.
