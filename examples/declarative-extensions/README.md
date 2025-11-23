# Declarative Extension Management Example

**Status**: WARNING: Semi-Declarative (Best Effort)

How to manage Cursor extensions declaratively (with limitations).

---

## WARNING: Important Limitations

### Why Not Fully Declarative?

**Forum Consensus**: "Cursor uses same extension system [as VS Code] but extensions are downloaded/patched at runtime"

**Key Differences from VSCode**:

| Feature | VSCode | Cursor |
|---------|--------|--------|
| Pre-bundled extensions | - `vscode-with-extensions` | - Not possible |
| AppImage structure | N/A | Read-only squashfs |
| Extension location | `/nix/store/...` | `~/.cursor/extensions/` (mutable) |
| Runtime patching | No | Yes |

**Why This Matters**: Extensions live in mutable directories and are downloaded/patched by Cursor at runtime.

---

## What This Example Does

**Semi-declarative approach**:
- - Declares extensions in Nix config
- - Auto-installs on system activation
- WARNING: Cursor can still modify extensions
- WARNING: Not immutable (Cursor owns `~/.cursor/extensions/`)

**Think of it as**: "Declarative defaults with mutable runtime"

---

## Usage

```bash
# Clone and configure
git clone https://github.com/yourusername/cursor-nixos
cd cursor-nixos/examples/declarative-extensions

# Edit extensions list in flake.nix
vim flake.nix

# Activate
nix run .#homeConfigurations.myuser.activationPackage
```

**What happens**:
1. Home Manager activates
2. Activation script runs
3. Extensions install via `cursor --install-extension`
4. Extensions live in `~/.cursor/extensions/`

---

## How It Works

### Activation Script

```nix
home.activation.cursorExtensions = pkgs.lib.hm.dag.entryAfter ["writeBoundary"] ''
  # Install each extension
  cursor --install-extension github.copilot
  cursor --install-extension esbenp.prettier-vscode
  # ...
'';
```

**Runs**: On every `home-manager switch`

**Effect**: Ensures extensions are installed (idempotent)

### Extension List

Edit in `flake.nix`:

```nix
extensions = [
  "github.copilot"                # GitHub Copilot
  "github.copilot-chat"          # Copilot Chat
  "esbenp.prettier-vscode"       # Prettier
  "dbaeumer.vscode-eslint"       # ESLint
  "rust-lang.rust-analyzer"      # Rust Analyzer
  "ms-python.python"             # Python
  "bradlc.vscode-tailwindcss"    # Tailwind CSS
  "naumovs.color-highlight"      # Color Highlight
];
```

Find extension IDs:
- Search on [VS Code Marketplace](https://marketplace.visualstudio.com/vscode)
- Extension ID is in URL: `publisher.extension-name`

---

## Workflows

### Approach 1: Baseline + Manual

**Strategy**: Declare essential extensions, manage others manually

```nix
extensions = [
  # Essential (declarative)
  "github.copilot"
  "esbenp.prettier-vscode"
  
  # Add project-specific extensions manually in Cursor UI
];
```

**When**: You want flexibility but guaranteed baseline

### Approach 2: Full Declaration

**Strategy**: Declare everything, reinstall on drift

```nix
extensions = [
  # Every extension you use
  "extension1"
  "extension2"
  # ... (20+ extensions)
];
```

**Sync script**:
```bash
# Reinstall all declared extensions
home-manager switch
```

**When**: You want maximum reproducibility

### Approach 3: Export + Import

**Strategy**: Export current extensions, declare them

```bash
# Export current extensions
cursor --list-extensions > extensions.txt

# Convert to Nix list
cat extensions.txt | sed 's/^/"/' | sed 's/$/"/' | paste -sd ',' -
```

**When**: Migrating from manual setup

---

## Comparison with VSCodium

### VSCodium (Fully Declarative)

```nix
programs.vscode = {
  package = pkgs.vscodium;
  extensions = with pkgs.vscode-extensions; [
    github.copilot
    esbenp.prettier-vscode
  ];
};
```

**Result**: Extensions pre-installed in `/nix/store/`, immutable

### Cursor (Semi-Declarative)

```nix
programs.cursor.enable = true;

home.activation.cursorExtensions = /* install script */;
```

**Result**: Extensions installed in `~/.cursor/extensions/`, mutable

**Why Different**: Cursor's AppImage structure + runtime patching

---

## Advantages & Disadvantages

### - Advantages

- **Reproducible**: Declare extensions in Nix config
- **Portable**: Same config works on multiple machines
- **Recoverable**: Lost extensions? Just `home-manager switch`
- **Versionable**: Extension list in Git

### - Disadvantages

- **Not immutable**: Cursor can modify extensions
- **Slower activation**: Downloads extensions each time (if missing)
- **No pinning**: Can't lock extension versions
- **Not atomic**: Extensions install sequentially

---

## Troubleshooting

### Extensions Not Installing

**Problem**: `cursor` command not in PATH during activation

**Solution**: Ensure Cursor installed before extensions:

```nix
home.activation.cursorExtensions = 
  pkgs.lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Wait for cursor to be available
    if command -v cursor >/dev/null 2>&1; then
      # Install extensions
    fi
  '';
```

### Extension Installation Fails

**Problem**: Network issues, marketplace down

**Solution**: Activation script uses `|| true` to not fail:

```nix
cursor --install-extension ${ext} 2>/dev/null || true
```

### Extensions Keep Disappearing

**Problem**: Cursor's extension updater removing/updating

**Solution**: Disable auto-update in Cursor settings:

```json
{
  "extensions.autoUpdate": false
}
```

---

## Alternative Approaches

### 1. Manual Backup Script

```bash
#!/usr/bin/env bash
# backup-extensions.sh

# Backup extensions list
cursor --list-extensions > ~/.config/cursor/extensions.txt

# Restore
while read ext; do
  cursor --install-extension "$ext"
done < ~/.config/cursor/extensions.txt
```

### 2. Dotfiles Management

Use dotfiles manager (like `chezmoi` or `stow`) to sync `~/.cursor/extensions/`

### 3. Cloud Sync

Use Cursor's built-in settings sync (if available)

---

## Future Possibilities

### If Cursor Adds Support

**What would enable full declarative extensions**:
- Pre-bundling support (like `cursor-with-extensions` wrapper)
- Extension directory in read-only location
- No runtime patching requirement

**Until then**: This semi-declarative approach is best effort

### Community Solutions

Watch for:
- `nix-cursor-extensions` wrapper package
- `home-manager` module enhancements
- Cursor upstream changes

---

## Best Practices

### 1. Keep List Small

```nix
# Only declare essential extensions
extensions = [
  "github.copilot"      # Essential
  "esbenp.prettier-vscode"  # Essential
  # Manage others manually
];
```

### 2. Document Why

```nix
extensions = [
  "github.copilot"              # AI pair programming (essential)
  "rust-lang.rust-analyzer"     # For rust projects
  "ms-python.python"            # For python projects
];
```

### 3. Version in Git

```bash
git add flake.nix
git commit -m "Add extension management"
```

### 4. Test on Fresh System

```bash
# Test in VM
nixos-rebuild build-vm --flake '.#test'
```

---

## Related

- **VSCode extensions**: [NixOS Wiki](https://nixos.wiki/wiki/Visual_Studio_Code)
- **Home Manager activation**: [Manual](https://nix-community.github.io/home-manager/index.html#sec-usage-activation)
- **Forum discussion**: [Original thread](https://forum.cursor.com/t/cursor-is-now-available-on-nixos/16640)

---

## Summary

### What Works

- Declare extension list in Nix  
- Auto-install on activation  
- Reproducible across machines  
- Version-controlled configuration  

### What Doesn't Work

- Immutable extensions  
- Version pinning  
- Pre-bundling in `/nix/store/`  
- Atomic updates  

### Verdict

**Good enough for**: Development environments, personal machines  
**Not suitable for**: Production deployments, strict reproducibility requirements  

**Recommendation**: Use this approach for convenience, but don't expect VSCode-level declarativeness.

---

**Status**: Best effort workaround until Cursor adds better support  
**Maintainers**: Community-driven improvement welcome
