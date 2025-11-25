# nixos-cursor

**Status**: v0.1.0 (Stable) - **37 Versions Available**  
**License**: MIT  
**Maintained by**: e421  
**Credits**: Version tracking by [oslook](https://github.com/oslook)

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers**, automated updates, and a **Multi-Version Manager** with **37 historical versions** spanning three eras for ultimate workflow stability.

> **Why Multi-Version Support?**
> With the deprecation of custom agent modes in Cursor 2.1.x, many users found their workflows disrupted. This package provides a comprehensive **Version Manager** with a polished GUI that allows you to run any of **37 versions** (spanning 2.0.x, 1.7.x, and 1.6.x) side-by-side with isolated configurations.
>
> Multi-version packages install to unique paths (`/share/cursor-VERSION/`, `/bin/cursor-VERSION`), enabling simultaneous installation without path conflicts. We refuse to have our workflows dictated on a whim, so we built the tools to take control back.

**Version Coverage:**
- **2.0.x Custom Modes Era**: 17 versions (2.0.11 - 2.0.77)
- **1.7.x Classic Era**: 19 versions (1.7.11 - 1.7.54)
- **1.6.x Legacy Era**: 1 version (1.6.45)

See [CURSOR_VERSION_TRACKING.md](CURSOR_VERSION_TRACKING.md) for the full manifest.

---

## Features

### Unique Capabilities (Not Possible in Base Cursor)

- **Shared Auth & Docs Across Versions**: Keep your Cursor login and indexed documentation synced across ALL versions via optional globalStorage sharing - something base Cursor cannot do to my knowledge (and has lost me a lot of time reindexing to have them again)
- **Concurrent Multi-Version Launches**: Run 2.0.77 and 1.7.54 simultaneously in separate windows with separate configs
- **Cross-Version Settings Sync**: Automatically copy your settings/keybindings to new version installs

### Core Features

- **Multi-Version Manager**: **37 versions** available (2.0.x, 1.7.x, 1.6.x)
- **Modern GUI**: Dropdown menus organized by era for easy selection
- **Isolated User Data**: Each version keeps its own settings/extensions in `~/.cursor-VERSION/`
- **Settings Sync**: Optional sync of keybindings and settings between versions
- Native NixOS packaging of Cursor IDE 2.0.77 (Stable)
- Wayland + X11 support with GPU acceleration
- MCP server integration (filesystem, memory, NixOS, GitHub, Playwright)
- Automated update system with daily notifications
- One-command updates (`cursor-update`)
- GPU fixes (libGL, libxkbfile) for NixOS compatibility

---

## Quick Start

### **Option A: Direct Package Installation (Recommended)**

Add to your `flake.nix` inputs:

```nix
{
  inputs.nixos-cursor = {
    url = "github:Distracted-E421/nixos-cursor";
    inputs.nixpkgs.follows = "nixpkgs";  # Optional
  };
}
```

Then in your Home Manager configuration:

```nix
{ inputs, pkgs, ... }: {
  home.packages = [
    # Install multiple versions simultaneously (no conflicts!)
    inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Latest (2.0.77)
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_0_64   # Specific version
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # Classic version
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-manager  # GUI launcher
  ];
}
```

**Important**: Pass `inputs` to Home Manager:

```nix
home-manager.extraSpecialArgs = { inherit inputs; };
```

After installation, you'll have:
- `cursor` → Launches 2.0.77
- `cursor-2.0.77` → Launches 2.0.77
- `cursor-1.x.xx` → Launches specified version (assuming it is supported, see below)
- `cursor-manager` → GUI version picker

### **Option B: nix run (No Installation)**

```bash
# Launch the version manager GUI
nix run github:Distracted-E421/nixos-cursor#cursor-manager

# Or run specific versions directly:
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
nix run github:Distracted-E421/nixos-cursor#cursor-1_6_45

# Run multiple versions concurrently:
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77 &
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54 &
```

**For Local Development:**
```bash
CURSOR_FLAKE_URI=. nix run .#cursor-manager --impure
```

**Available Versions**:
- **2_0_x**: 2_0_77, 2_0_75, 2_0_74, 2_0_73, 2_0_69, 2_0_64, 2_0_63, 2_0_60, 2_0_57, 2_0_54, 2_0_52, 2_0_43, 2_0_40, 2_0_38, 2_0_34, 2_0_32, 2_0_11
- **1_7_x**: 1_7_54, 1_7_53, 1_7_52, 1_7_46, 1_7_44, 1_7_43, 1_7_40, 1_7_39, 1_7_38, 1_7_36, 1_7_33, 1_7_28, 1_7_25, 1_7_23, 1_7_22, 1_7_17, 1_7_16, 1_7_12, 1_7_11
- **1_6_x**: 1_6_45

See [VERSION_MANAGER_GUIDE.md](VERSION_MANAGER_GUIDE.md) for full details.

### **Option C: Home Manager Module (Advanced)**

For declarative settings management:

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
            updateCheck.enable = true;
            mcp.enable = false;
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

**Why?** Cursor can't self-update on NixOS (read-only `/nix/store`). This system provides convenience while respecting Nix principles.

---

## Roadmap

I committed to making nixos-cursor the definitive way to run Cursor on NixOS. Here's what's planned:

### Near-Term (v0.2.x)

| Feature | Description | Status |
|---------|-------------|--------|
| **Newer Version Support** | Add 2.1.x versions as they release (with caveats documented) | Ongoing |
| **Missing Version Backfill** | Fill gaps in 1.6.x and early 1.7.x coverage | Planned |
| **ARM64 Support** | Add aarch64-linux packages for Apple Silicon & ARM devices | Planned |
| **Cachix Binary Cache** | Pre-built binaries for faster installation | Planned |

### Mid-Term (v0.3.x - v0.5.x)

| Feature | Description | Status |
|---------|-------------|--------|
| **Custom Modes Reimplementation** | Bring back custom agent modes for 2.1.x via patching/injection | Research |
| **Community Bug Patches** | Retroactively fix known bugs in popular versions (1.7.54, 2.0.77) | Research |
| **Extension Compatibility Layer** | Ensure Open VSX extensions work across all versions | Planned |
| **Declarative MCP Configuration** | Full MCP server management via Nix modules | Planned |

### Long-Term (v1.0+)

| Feature | Description | Status |
|---------|-------------|--------|
| **GPUI-based Manager** | Rewrite version manager in Rust/GPUI (Zed-style) | Exploring |
| **Electron Bypass Layer** | Native rendering layer to bypass Electron overhead | Exploring |
| **Cross-Version Workspace Sync** | Share workspaces and indexed docs between versions | Exploring |
| **Community Plugin System** | Allow community-contributed patches and features | Exploring |

### Community-Driven

**Want something? Ask for it!** We prioritize based on community interest:

- **Bug Reports**: [Open an issue](https://github.com/Distracted-E421/nixos-cursor/issues/new?template=bug_report.md)
- **Feature Requests**: [Start a discussion](https://github.com/Distracted-E421/nixos-cursor/discussions)
- **Contributions**: See [CONTRIBUTING.md](CONTRIBUTING.md)

**Current Community Requests:**
- *None yet - be the first!*

---

## Development & Contributing

This is a personal project maintained by e421. If you'd like to contribute or have suggestions, feel free to open an issue or reach out!

### Documentation

- [Version Manager Guide](VERSION_MANAGER_GUIDE.md) - Complete guide to managing 37 versions
- [Cursor Version Tracking](CURSOR_VERSION_TRACKING.md) - Full version manifest with URLs and hashes
- [Test Suite](tests/multi-version-test.sh) - Automated testing for all versions

---

## License & Proprietary Note

**Packaging Code**: MIT License - See [LICENSE](LICENSE) file.

**Cursor Binary**: Proprietary (Unfree).
This flake downloads the official AppImage from Cursor's servers (`downloader.cursor.sh` or `downloads.cursor.com`) and wraps it for NixOS compatibility. We do not redistribute the binary itself. You must comply with Cursor's Terms of Service when using this software.
