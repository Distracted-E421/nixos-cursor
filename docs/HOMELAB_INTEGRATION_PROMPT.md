# Homelab Integration Prompt: nixos-cursor v0.2.0-rc2

**Use this prompt with an LLM to integrate cursor-studio into your NixOS homelab flake.**

---

## Prompt

I need to update my NixOS homelab flake to use the latest `nixos-cursor` release (v0.2.0-rc2). My flake currently has an outdated configuration. Please make these changes:

### 1. Flake Inputs (flake.nix)

**REMOVE** the separate `cursor-studio` input if it exists - cursor-studio is now part of the main `nixos-cursor` flake:

```nix
# REMOVE this if present:
cursor-studio = {
  url = "github:Distracted-E421/nixos-cursor/pre-release?dir=cursor-studio-egui";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**UPDATE** the `nixos-cursor` input to use the `pre-release` branch:

```nix
nixos-cursor = {
  url = "github:Distracted-E421/nixos-cursor/pre-release";
  # NOTE: cursor-studio is now included - no separate input needed
};
```

### 2. Overlay Configuration

The `nixos-cursor` overlay provides these packages:
- `cursor` - The main Cursor IDE (latest stable)
- `cursor-X_Y_Z` - Specific versions (e.g., `cursor-2_0_77`)
- `cursor-studio` - Modern Rust/egui IDE manager GUI
- `cursor-studio-cli` - CLI for cursor-studio

Apply the overlay in your flake outputs:

```nix
nixpkgs.overlays = [
  inputs.nixos-cursor.overlays.default
  # ... other overlays
];
```

### 3. System Packages (NixOS module)

Add cursor-studio to your system packages or user packages:

**Option A - System-wide (configuration.nix or module):**
```nix
environment.systemPackages = with pkgs; [
  cursor           # Cursor IDE
  cursor-studio    # Modern egui manager (replaces cursor-manager)
];
```

**Option B - Per-user (home-manager):**
```nix
home.packages = with pkgs; [
  cursor
  cursor-studio
];
```

### 4. DEPRECATED: cursor-manager and cursor-chat-library

These packages are **DEPRECATED** and will show a warning redirecting to `cursor-studio`:
- `cursor-manager` → Use `cursor-studio` instead
- `cursor-chat-library` → Use `cursor-studio` instead

If you have these in your config, replace them:
```nix
# OLD (deprecated):
environment.systemPackages = [ pkgs.cursor-manager ];

# NEW:
environment.systemPackages = [ pkgs.cursor-studio ];
```

### 5. Test the Build

After making changes, test the build:

```bash
# Dry-build to check for errors
sudo nixos-rebuild dry-build --flake .#YourHostname

# If successful, switch
sudo nixos-rebuild switch --flake .#YourHostname

# Verify packages installed
which cursor cursor-studio cursor-studio-cli
```

### 6. Using cursor-studio

After installation:

```bash
# Launch GUI manager
cursor-studio

# Or use CLI
cursor-studio-cli list              # List versions
cursor-studio-cli list --available  # Show downloadable versions
cursor-studio-cli download 2.1.34   # Download specific version
```

---

## Example: Complete Flake Change

**Before:**
```nix
inputs = {
  nixos-cursor = {
    url = "github:Distracted-E421/nixos-cursor/pre-release";
  };
  cursor-studio = {
    url = "github:Distracted-E421/nixos-cursor/pre-release?dir=cursor-studio-egui";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

**After:**
```nix
inputs = {
  # Cursor IDE with cursor-studio included (v0.2.0-rc2)
  nixos-cursor = {
    url = "github:Distracted-E421/nixos-cursor/pre-release";
  };
  # REMOVED: cursor-studio (now part of nixos-cursor)
};
```

---

## Troubleshooting

### "cursor-studio: command not found"
Ensure the overlay is applied and the package is in your packages list:
```nix
nixpkgs.overlays = [ inputs.nixos-cursor.overlays.default ];
environment.systemPackages = [ pkgs.cursor-studio ];
```

### "deprecated cursor-manager" warning
This is expected - cursor-manager has been replaced by cursor-studio. Update your configuration to use cursor-studio instead.

### Build fails with hash mismatch
Run `nix flake update nixos-cursor` to get the latest hashes.

---

## What's New in v0.2.0-rc2

- **cursor-studio**: Modern Rust/egui GUI for managing Cursor versions
- **cursor-studio-cli**: Terminal interface for automation
- **Security scanning**: Detect API keys/secrets in chat history
- **VS Code theme support**: Import themes from VS Code
- **Unified package**: cursor-manager and cursor-chat-library merged into cursor-studio
- **Bash→Nushell migration**: All scripts now use Nushell

---

**Questions?** See [MIGRATION.md](MIGRATION.md) for detailed migration guide.
