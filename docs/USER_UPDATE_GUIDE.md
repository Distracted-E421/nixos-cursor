# How to Update Cursor on NixOS

**Quick Answer**: Use `nix flake update`, not Cursor's built-in updater.

---

## Why Cursor's Updater Doesn't Work

When you click **Help → Check for Updates** in Cursor on NixOS:

> ❌ "A newer version is available. Please download from cursor.com"

**This is expected on NixOS!** Cursor is in `/nix/store` (read-only), so the built-in updater can't replace files.

**Solution**: Update via Nix instead.

---

## How to Update

### Step 1: Update the Flake

```bash
cd ~/your-flake-directory
nix flake update nixos-cursor
```

### Step 2: Apply the Update

```bash
home-manager switch  # Home Manager
# OR
nixos-rebuild switch  # System package
```

### Step 3: Verify

```bash
cursor --version
```

---

## Multi-Version Users

If you're using multiple Cursor versions (via `cursor-manager`), each version is pinned to its specific build. The `nix flake update` will update the flake inputs but won't change which versions you have installed.

To switch versions:
1. Use `cursor-manager` GUI
2. Or install different version packages directly

---

## FAQs

### "I want the latest version NOW!"

Maintainer updates versions as they release. For bleeding edge:
1. Fork the repo
2. Add the new version to `cursor-versions.nix`
3. Build your custom version

### "Can I enable Cursor's built-in updater?"

No - it's disabled with `--update=false` to prevent confusion and failed updates.

### "How do I rollback?"

```bash
home-manager switch --rollback
# OR
nixos-rebuild switch --rollback
```

### "How do I use an older version?"

With nixos-cursor v0.1.0+, you have 37 versions available:

```nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54  # Use 1.7.54
];
```

Or via command line:
```bash
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
```

---

**See**: [AUTO_UPDATE_IMPLEMENTATION.md](AUTO_UPDATE_IMPLEMENTATION.md) for maintainer documentation
