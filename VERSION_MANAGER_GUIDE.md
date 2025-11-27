# Cursor Version Manager Guide

## v0.1.2 - The Complete Multi-Version Solution

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
    * Persistent settings across sessions

3. **Pure, Reproducible Builds**:
    * Uses stable S3 URLs (no DNS dependency)
    * Verified SRI hashes for all 37 versions
    * No manual downloading required!
    * Builds via Nix for reproducibility

4. **Data Management** (*Unique - Not Possible in Base Cursor*):
    * **Isolated User Data**: Each version in `~/.cursor-VERSION/`
    * **Settings Sync**: Auto-copy `settings.json`, `keybindings.json`, snippets
    * **Shared Auth & Docs**: Optionally share your Cursor login AND indexed documentation across ALL versions via globalStorage symlink - base Cursor cannot do this!
    * **Concurrent Launches**: Run multiple versions simultaneously with separate or shared state

5. **Multi-Version Installation**:
    * All versions install to unique paths (no Nix store conflicts)
    * Can install `cursor`, `cursor-2.0.64`, `cursor-1.7.54` simultaneously
    * Each gets its own binary, desktop entry, and icons

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
* **Era Dropdown**: Select from 2.0.x, 1.7.x, 1.6.x, or System Default
* **Version Dropdown**: Lists all versions for selected era
* **Options**: Settings sync + optional Docs/Auth sharing (persistent across sessions)
* **Launch Button**: Starts selected version with configured options

**Example Workflow:**

1. Select "2.0.x - Custom Modes Era" from first dropdown
2. Select "2.0.77 (Stable - Recommended)" from second dropdown
3. Check "Sync Settings & Keybindings" (recommended)
4. Optionally check "Share Docs & Auth" (experimental)
5. Click "Launch Selected Version"

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

### 3. Data Persistence & Sync

The Manager handles data migration for you!

* **Settings Sync**: When launching a version for the first time, it checks for your main configuration and offers to sync `settings.json` and `keybindings.json`.

* **Shared Auth & Docs** (*Unique Feature*): Check the "Share Docs & Auth" box to symlink your `globalStorage` directory. This enables:
  * **Single Login**: Authenticate once, use across all versions
  * **Shared Indexed Docs**: Your `@Docs` indexed documentation is available in every version
  * **Persistent Context**: AI context from one version carries over to others
  
  > **Why is this special?** Base Cursor stores auth and docs in the user data directory. Since each Cursor installation has its own data directory, you'd normally need to re-authenticate and re-index docs for each version. Our symlink approach shares this state globally - something the official Cursor doesn't support.

### 4. Installing Permanently

Add to your `configuration.nix` or `home.nix` to have multiple versions available in PATH:

```nix
{
  inputs = {
    nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  };
  
  # ...
  
  home.packages = [
    inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Latest (2.0.77)
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-manager  # The GUI launcher
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_0_64   # Specific version
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # Classic version
  ];
}
```

**After installation, you'll have these commands available:**
* `cursor` → Launches 2.0.77 (latest)
* `cursor-2.0.64` → Launches 2.0.64
* `cursor-1.7.54` → Launches 1.7.54
* `cursor-manager` → Opens the GUI picker

---

## 🔧 Troubleshooting

### Version won't launch

- Check that the version was built successfully: `nix build .#cursor-2_0_64`
* Look for errors in terminal output when launching
* Ensure isolated data directory exists: `ls -la ~/.cursor-2.0.64/`

### Settings not syncing

- Settings sync only happens on first launch of a version
* Delete the version's data directory to trigger re-sync: `rm -rf ~/.cursor-VERSION/`
* Check that source settings exist: `ls ~/.config/Cursor/User/`

### Multiple versions conflict

- Each version should have its own binary name and paths
* Check with: `which cursor-2.0.64` and `which cursor-1.7.54`
* If you see conflicts, ensure you're using the latest flake version

---

## 📋 Full Version List

**2.0.x Custom Modes Era (17 versions):**
`2.0.77`, `2.0.75`, `2.0.74`, `2.0.73`, `2.0.69`, `2.0.64`, `2.0.63`, `2.0.60`, `2.0.57`, `2.0.54`, `2.0.52`, `2.0.43`, `2.0.40`, `2.0.38`, `2.0.34`, `2.0.32`, `2.0.11`

**1.7.x Classic Era (19 versions):**
`1.7.54`, `1.7.53`, `1.7.52`, `1.7.46`, `1.7.44`, `1.7.43`, `1.7.40`, `1.7.39`, `1.7.38`, `1.7.36`, `1.7.33`, `1.7.28`, `1.7.25`, `1.7.23`, `1.7.22`, `1.7.17`, `1.7.16`, `1.7.12`, `1.7.11`

**1.6.x Legacy Era (1 version):**
`1.6.45`
