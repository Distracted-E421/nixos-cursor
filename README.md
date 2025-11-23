# nixos-cursor

> **🚀 Release Candidate**: This is **v2.1.20-rc1** - currently in testing phase.  
> **👉 Want to help test?** See **[TESTING_RC.md](TESTING_RC.md)** for instructions.

**License**: [MIT](LICENSE) | **Maintained by**: e421  
**Repository**: https://github.com/Distracted-E421/nixos-cursor

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers** and automated updates.

---

## 🔗 Related Projects

This package focuses on Cursor IDE packaging and MCP integration. For additional functionality:

- **[wayland-gpu-affinity](../wayland-gpu-affinity)** - General Wayland multi-monitor/GPU management (works with Niri, Hyprland, KDE, Cursor, etc.)
- **[cursor-focus-fix](../cursor-focus-fix)** - Fix multi-window focus issues on X11/Wayland
- **[cursor-cdp-daemon](../cursor-cdp-daemon)** - Chrome DevTools Protocol integration

---

## 🎯 Overview

This flake provides a **native** NixOS packaging of Cursor IDE. It solves the common issues users face when trying to run Cursor on NixOS: auto-updates, binary patching, and extension management.

### Key Features
- ✅ **Native Packaging**: Uses `autoPatchelfHook` for high performance and stability.
- ✅ **Auto-Update System**: Automated script (`update.sh`) + Nix declarative updates.
- ✅ **MCP Integration**: Pre-configured support for 5+ MCP servers (Filesystem, GitHub, etc.).
- ✅ **Playwright Support**: Solved the browser path configuration challenge.
- ✅ **Declarative Config**: Home Manager module for consistent setup.

---

## 🏗️ Architecture & Extension Management

For users coming from other distributions or standard VS Code on NixOS, it's important to understand how this package works.

### Native vs. FHS
- **This Package (Native)**: We patch the official AppImage binary's ELF headers to use NixOS libraries directly.
  - **Pros**: Faster startup, better integration, "cleaner" process tree.
  - **Cons**: Binary patching can be fragile (though we have a robust pipeline).
- **Code-Cursor-FHS (Legacy)**: Creates a "bubble" (FHS chroot) that looks like Ubuntu/Debian.
  - **Pros**: Runs unpatched binaries.
  - **Cons**: Heavier resource usage, complex to debug, often breaks interaction with system tools.

**Verdict**: This project uses the **Native** approach for the best long-term experience.

### Extension Management
Cursor (like VS Code) downloads extensions at runtime.

- **Method 1: Mutable (Default)**
  - Extensions are downloaded to `~/.cursor/extensions/`.
  - You install/update them via the Cursor UI.
  - **Pros**: Easy, familiar user experience.
  - **Cons**: Not declarative (reinstalling OS loses extensions unless backed up).

- **Method 2: Declarative (via Home Manager)**
  - You list extensions in your `home.nix`.
  - **Pros**: Reproducible setup across machines.
  - **Cons**: Cursor's marketplace is proprietary; getting hashes for extensions can be tedious.

**Recommendation**: Start with **Method 1 (Mutable)** for ease of use. Switch to Method 2 only if you strictly require reproducibility.

---

## 🔄 Auto-Update System

**Important**: Cursor's native updater **does not work** on NixOS!

### Why Updates Fail
On typical Linux systems, Cursor can update itself by replacing the AppImage file. On NixOS:
- Cursor is installed in `/nix/store` (read-only, immutable).
- Cursor's updater tries to replace the file → **Permission denied**.
- Falls back to "Please download from cursor.com" message.

### How to Update

**For End Users**:
```bash
# Update your flake inputs (fetches new Cursor version)
nix flake update cursor-with-mcp

# Apply the update
home-manager switch  # For Home Manager users
# OR
nixos-rebuild switch  # For system package
```

**For Maintainers**:
```bash
# Automatically fetch latest Cursor version and update hashes
cd cursor
./update.sh

# Test and commit
cd .. && nix build .#cursor
git add cursor/default.nix
git commit -m "chore: Update Cursor to $(nix eval .#cursor.version --raw)"
```

---

## 🚀 Quick Start

### Testing RC1 (No Installation)

**Fastest way to try it**:

```bash
# Run directly from GitHub (RC1 release)
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor
```

See **[TESTING_RC.md](TESTING_RC.md)** for full testing instructions.

---

### Installing RC1 via Home Manager

Add to your `flake.nix`:

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
            mcp.enable = false;  # Optional: MCP servers
          };
        }
      ];
    };
  };
}
```

Then: `home-manager switch`

See [`examples/`](examples/) for more configurations.

---

## 📚 Documentation

### Getting Started
- **[TESTING_RC.md](TESTING_RC.md)** - RC1 testing guide (START HERE)
- **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** - MCP server setup
- **[examples/](examples/)** - Example configurations

### Technical Details
- **[docs/AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md)** - Update system
- **[KNOWN_ISSUES.md](KNOWN_ISSUES.md)** - Known problems
- **[cursor/README.md](cursor/README.md)** - Package documentation

### Project Info
- **[LICENSE](LICENSE)** - MIT License
- **[RELEASE_STRATEGY.md](RELEASE_STRATEGY.md)** - Release process

---

## 🐛 Reporting Issues

Found a bug in RC1? Please report it!

1. Go to [GitHub Issues](https://github.com/Distracted-E421/nixos-cursor/issues)
2. Include system information (see [TESTING_RC.md](TESTING_RC.md#-system-information))
3. Describe the problem clearly

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file.

```
MIT License - Copyright (c) 2025 e421

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

[Full license text in LICENSE file]
```
