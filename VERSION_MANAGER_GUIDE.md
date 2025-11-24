# Cursor Version Manager & Community Solution

## 🚀 The Complete Solution

We have implemented a **robust, community-ready solution** for managing multiple Cursor versions on NixOS. This system addresses the deprecation of custom modes by allowing you to run specific, stable versions of Cursor that preserve this functionality.

### Key Features

1.  **Targeted Stable Versions**:
    *   **2.0.77**: Latest 2.0.x version with working custom modes.
    *   **1.7.54**: Classic pre-2.0 version preferred by many.
    *   **2.0.64**: Reliable fallback.

2.  **Pure, Reproducible Builds**:
    *   Uses direct S3 URLs (bypassing DNS issues with `downloader.cursor.sh`).
    *   Verified SRI hashes for security.
    *   No more manual downloading or local AppImages required!

3.  **Cursor Manager GUI**:
    *   A sidecar "launcher" window to easily switch between versions.
    *   Launch specific versions alongside each other.
    *   Isolated user data for each version (safe concurrency).

---

## 🛠️ Usage Guide

### 1. Launching the Cursor Manager

You can launch the graphical manager to select your version:

```bash
# If installed in your system packages:
cursor-manager

# Or run directly from the flake:
nix run github:Distracted-E421/nixos-cursor#cursor-manager
```

This opens a window "alongside" your editor where you can spawn instances of:
*   **Stable (2.0.77)**: Your daily driver with custom modes.
*   **Classic (1.7.54)**: For legacy stability.
*   **System Default**: Whatever `cursor` maps to.

### 2. Running Specific Versions Directly

You can also run specific versions directly from the terminal:

```bash
# Run 2.0.77 (Recommended)
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77

# Run 1.7.54
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
```

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

---

## 💡 Technical Details

### Pure Builds
We updated the flake to use **direct download URLs** from `downloads.cursor.com` instead of the flaky `downloader.cursor.sh` redirector. This ensures:
*   **Reliability**: Builds won't fail due to DNS/Redirector issues.
*   **Reproducibility**: We use strict SRI hashes (`sha256-...`) so everyone gets the exact same bits.
*   **No Impurity**: `localAppImage` is no longer required for these targeted versions.

### Data Isolation
To prevent configuration corruption when running multiple versions:
*   **2.0.77** uses `~/.cursor-2.0.77/`
*   **1.7.54** uses `~/.cursor-1.7.54/`
*   **Default** uses `~/.config/Cursor/`

This allows you to run **1.7.54** and **2.0.77** at the exact same time without them fighting over SQLite databases.

### Extending
To add more versions, edit `cursor-versions.nix`. Just add a new block with the `srcUrl` and `hash`:

```nix
  cursor-NEW_VER = mkCursorVersion {
    version = "X.Y.Z";
    hash = "sha256-SRI_HASH...";
    srcUrl = "https://downloads.cursor.com/...";
    binaryName = "cursor-X.Y.Z";
    dataStrategy = "isolated";
  };
```

