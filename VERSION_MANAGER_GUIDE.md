# Cursor Version Manager & Community Solution

## 🚀 RC3.2 - The Complete Multi-Version Solution

We have implemented a **robust, production-ready solution** for managing **37 historical Cursor versions** on NixOS. This system addresses the deprecation of custom modes by allowing you to run any stable version of Cursor that preserves your workflow.

### Key Features

1. **37 Available Versions Across 3 Eras**:
    * **2.0.x Custom Modes Era**: 17 versions (2.0.11 - 2.0.77)
    * **1.7.x Classic Era**: 19 versions (1.7.11 - 1.7.54)
    * **1.6.x Legacy Era**: 1 version (1.6.45)

2. **Modern Dropdown GUI**:
    * Two-tier selection: Choose era → Choose specific version
    * Themed to match your Cursor editor (Dark/Light)
    * Organized, scalable interface for 37 versions
    * Emoji status indicators (✓✗⚠ℹ🚀)

3. **Pure, Reproducible Builds**:
    * Uses stable S3 URLs (no DNS dependency)
    * Verified SRI hashes for all 37 versions
    * No manual downloading required!
    * Builds via Nix for reproducibility

4. **Data Management**:
    * **Isolated User Data**: Each version in `~/.cursor-VERSION/`
    * **Settings Sync**: Auto-copy `settings.json`, `keybindings.json`, snippets
    * **Global State Sync**: Optional experimental Docs/Auth sharing via symlink
    * **Concurrent Launches**: Run multiple versions simultaneously

## 🙏 Credits

**Massive thanks** to [@oslook](https://github.com/oslook) for maintaining comprehensive version tracking and stable download links for all 37 Cursor versions. Their meticulous work cataloging S3 URLs made this multi-version system possible. [cursor-ai-downloads](https://github.com/oslook/cursor-ai-downloads)

---

## 🛠️ Usage Guide

### 1. Launching the Cursor Manager (GUI)

The graphical manager provides dropdown menus for all 37 versions:

```bash
# If installed in your system packages:
cursor-manager

# Or run directly from the flake:
nix run github:Distracted-E421/nixos-cursor#cursor-manager
```

**GUI Features:**
- **Era Dropdown**: Select from 2.0.x, 1.7.x, 1.6.x, or System Default
- **Version Dropdown**: Lists all versions for selected era
- **Options**: Settings sync + optional Docs/Auth sharing
- **Launch Button**: Starts selected version with configured options

**Example Workflow:**
1. Select "2.0.x - Custom Modes Era" from first dropdown
2. Select "2.0.77 (Stable - Recommended)" from second dropdown
3. Check "Sync Settings & Keybindings" (recommended)
4. Optionally check "Share Docs & Auth" (experimental)
5. Click "🚀 Launch Selected Version"

### 2. Direct CLI Launch (Without GUI)

Run any version directly via command line:

```bash
# Latest stable (2.0.77) - Default
nix run github:Distracted-E421/nixos-cursor#cursor

# Specific 2.0.x version
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_11  # First custom modes

# Specific 1.7.x version
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54  # Latest pre-2.0
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_28

# Legacy 1.6.x
nix run github:Distracted-E421/nixos-cursor#cursor-1_6_45
```

**Note**: Replace dots with underscores in version numbers (`2.0.77` → `cursor-2_0_77`).

### 2. Data Persistence & Docs

The Manager now handles data migration for you!

* **Settings Sync**: When launching a version for the first time, it checks for your main configuration and offers to sync `settings.json` and `keybindings.json`.
* **Docs & Auth**: Check the "Sync Global State [Experimental]" box to symlink your `globalStorage`. This allows your indexed Docs to be shared between versions (use with caution).

### 3. Installing Permanently

Add to your `configuration.nix` or `home.nix` to have `cursor` (2.0.77), `cursor-manager`, and other versions available in PATH:

```nix
{
  inputs = {
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  };
  
  # ...
  
  environment.systemPackages = [
    inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Aliased to 2.0.77
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-manager  # The GUI launcher
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # Optional: keep classic available
  ];
}
```
