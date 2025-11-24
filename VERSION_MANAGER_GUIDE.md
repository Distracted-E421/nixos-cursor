# Cursor Version Manager & Community Solution

## 🚀 The Complete Solution

We have implemented a **robust, community-ready solution** for managing multiple Cursor versions on NixOS. This system addresses the deprecation of custom modes by allowing you to run specific, stable versions of Cursor that preserve this functionality.

### Key Features

1.  **Targeted Stable Versions**:
    *   **2.0.77**: Latest 2.0.x version with working custom modes.
    *   **1.7.54**: Classic pre-2.0 version preferred by many.
    *   **2.0.64**: Reliable fallback.

2.  **Pure, Reproducible Builds**:
    *   Uses direct S3 URLs (bypassing DNS issues).
    *   Verified SRI hashes for security.
    *   No more manual downloading or local AppImages required!

3.  **Cursor Manager GUI (Themed)**:
    *   A Python-based GUI that **matches your editor theme** (Dark/Light).
    *   Launches specific versions alongside each other.
    *   **Smart Data Sync**: Automatically copies your `settings.json`, `keybindings.json`, and snippets to isolated versions.
    *   **Global State Sync**: Optional experimental support for sharing Docs and Auth state via symlinking.

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

### 2. Data Persistence & Docs

The Manager now handles data migration for you!

*   **Settings Sync**: When launching a version for the first time, it checks for your main configuration and offers to sync `settings.json` and `keybindings.json`.
*   **Docs & Auth**: Check the "Sync Global State [Experimental]" box to symlink your `globalStorage`. This allows your indexed Docs to be shared between versions (use with caution).

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
