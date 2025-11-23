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
nix flake update cursor-with-mcp
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

## FAQs

### "I want the latest version NOW!"

Maintainer updates within 1-2 weeks. For bleeding edge:
1. Fork the repo
2. Run `cursor/update.sh`
3. Build your custom version

### "Can I enable Cursor's built-in updater?"

No - it's disabled with `--update=false` to prevent confusion and failed updates.

### "How do I rollback?"

```bash
home-manager switch --rollback
# OR
nixos-rebuild switch --rollback
```

---

**See**: [AUTO_UPDATE_IMPLEMENTATION.md](../AUTO_UPDATE_IMPLEMENTATION.md) for maintainer documentation
