# First-Time Setup Guide

This guide covers setting up nixos-cursor and cursor-studio from scratch.

## Prerequisites

### System Requirements
- NixOS 24.05+ (or any Linux with Nix installed)
- ~500MB disk space for builds
- Internet connection for downloads

### Required Tools
- `nix` with flakes enabled
- `git`
- For cursor-studio-egui: `cargo` (Rust toolchain)

---

## Quick Start (NixOS Users)

### 1. Add to Your Flake

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  };

  outputs = { self, nixpkgs, nixos-cursor, ... }: {
    # For NixOS system configuration
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        # ... your other modules
      ];
    };

    # For Home Manager
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixos-cursor.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            mcp.enable = true;  # Enable MCP servers
          };
        }
      ];
    };
  };
}
```

### 2. Build and Test

```bash
# Test the flake
nix flake check github:Distracted-E421/nixos-cursor

# Build cursor
nix build github:Distracted-E421/nixos-cursor#cursor

# Run directly
nix run github:Distracted-E421/nixos-cursor#cursor
```

---

## cursor-studio-egui Setup

cursor-studio is a separate Rust application for managing Cursor versions and viewing chat history.

### Option A: Build from Source (Recommended for Development)

```bash
# Clone the repository
git clone https://github.com/Distracted-E421/nixos-cursor.git
cd nixos-cursor/cursor-studio-egui

# Build release binaries
cargo build --release

# The binaries are now available at:
# ./target/release/cursor-studio       (GUI)
# ./target/release/cursor-studio-cli   (CLI)

# Test CLI
./target/release/cursor-studio-cli --help

# Test GUI
./target/release/cursor-studio
```

### Option B: Build with Nix

```bash
cd cursor-studio-egui
nix build

# Run GUI
./result/bin/cursor-studio

# Run CLI
./result/bin/cursor-studio-cli --help
```

### Option C: Add to PATH

After building, you can add to your PATH:

```bash
# Temporary (current session)
export PATH="$PATH:$(pwd)/target/release"

# Permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export PATH="$PATH:/path/to/cursor-studio-egui/target/release"' >> ~/.bashrc
```

---

## Verifying Installation

### Test Cursor Package

```bash
# Check if cursor is available
which cursor || nix run .#cursor -- --version

# List available versions
nix build .#cursor-2_1_34 --no-link --print-out-paths
```

### Test cursor-studio-cli

```bash
# Show help
cursor-studio-cli --help

# List available versions
cursor-studio-cli list --available

# Show cache info
cursor-studio-cli cache
```

### Test GUI

```bash
# Launch cursor-studio
cursor-studio

# Or via nix
nix run .#cursor-studio  # (if added to flake)
```

---

## Common Issues

### "downloader.cursor.sh" DNS Error

**Symptom**: Build fails with "Could not resolve host: downloader.cursor.sh"

**Cause**: The old download domain is dead (NXDOMAIN)

**Fix**: Ensure you're using the latest `pre-release` branch which has fixes for this:
```bash
git checkout pre-release
git pull origin pre-release
```

### CLI "command not found"

**Symptom**: `cursor-studio-cli: command not found`

**Cause**: The CLI isn't in your PATH

**Fix**: Either:
1. Run with full path: `./target/release/cursor-studio-cli`
2. Add to PATH (see Option C above)
3. Create alias: `alias cursor-studio-cli='/path/to/target/release/cursor-studio-cli'`

### GUI Download Fails

**Symptom**: Downloads fail silently in GUI

**Cause**: URLs may be outdated or network issues

**Fix**:
1. Update to latest pre-release branch
2. Check network connectivity
3. Try manual download via CLI:
   ```bash
   cursor-studio-cli urls 2.0.77
   # Then download manually and import
   cursor-studio-cli import ~/Downloads/Cursor-2.0.77-x86_64.AppImage --version 2.0.77
   ```

### Hash Verification Fails

**Symptom**: "Hash mismatch" errors

**Cause**: Cached hashes may be outdated

**Fix**:
```bash
# Compute actual hash
cursor-studio-cli hash 2.0.77

# If different from expected, the registry needs updating
cursor-studio-cli import ~/Downloads/file.AppImage --version 2.0.77 --update-registry
```

---

## Directory Structure

After setup, you'll have:

```
~/.config/cursor-studio/
├── config.json          # Settings (theme, etc.)
├── version-registry.json # Hash registry
└── cache/               # Downloaded AppImages

~/.config/Cursor/        # Cursor IDE data
├── User/
│   └── workspaceStorage/
│       └── */state.vscdb  # Chat databases (SQLite)
└── ...
```

---

## Development Setup

For contributing to cursor-studio:

```bash
# Enter dev shell with all tools
cd cursor-studio-egui
nix develop

# Or with full features
nix develop .#full

# Run tests
cargo test

# Build with minimal features (faster)
cargo build --no-default-features --features minimal

# Format code
cargo fmt

# Lint
cargo clippy
```

---

## Next Steps

1. **Configure MCP Servers**: See [MCP_GITHUB_SETUP.md](MCP_GITHUB_SETUP.md)
2. **Manage Versions**: Use `cursor-studio-cli list` and `cursor-studio-cli install`
3. **View Chat History**: Launch `cursor-studio` GUI
4. **Customize**: Edit `~/.config/cursor-studio/config.json`

---

*Last updated: 2025-12-02*
