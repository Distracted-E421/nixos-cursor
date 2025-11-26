# Nix Store Garbage Collection & Disk Management

Managing disk space is crucial for NixOS and nix-darwin systems. The Nix store can grow very large, especially when:
- Building multiple Cursor versions (~200-300MB each)
- Accumulating system generations
- Not running regular garbage collection

## Quick Reference

```bash
# Analyze disk usage
./scripts/storage/disk-usage.sh

# Detailed breakdown
./scripts/storage/disk-usage.sh --detailed

# Analyze what can be collected (dry-run)
./scripts/storage/gc-helper.sh

# Actually run garbage collection
./scripts/storage/gc-helper.sh collect --no-dry-run

# Full cleanup (generations + gc + optimize)
./scripts/storage/gc-helper.sh full --no-dry-run
```

## Understanding Nix Store Growth

### Why Does the Store Grow?

1. **Multiple Cursor Versions**: Each version is ~200-300MB
   - AppImage: ~230MB
   - Extracted: ~350-500MB  
   - Built package: ~200-300MB

2. **System Generations**: Each `nixos-rebuild switch` creates a new generation
   - Kept indefinitely by default
   - Old generations reference old packages

3. **User Profile Generations**: Each `nix-env -i` or Home Manager switch
   - Also kept indefinitely
   - Creates references preventing GC

4. **Build Artifacts**: Intermediate build products
   - Cached for faster rebuilds
   - Can be reclaimed safely

### What's Safe to Delete?

| Type | Safe to Delete | Notes |
|------|----------------|-------|
| Dead paths | ✅ Yes | Not referenced by anything |
| Old generations | ✅ Yes | Keep recent ones for rollback |
| Build caches | ✅ Yes | Can be rebuilt |
| Current generation | ❌ No | System won't boot |
| Active profile refs | ❌ No | Programs stop working |

## Manual Commands

### Basic Garbage Collection

```bash
# Remove unused packages (user only)
nix-collect-garbage

# Also delete old generations (user only)
nix-collect-garbage -d

# System-wide (includes system generations)
sudo nix-collect-garbage -d

# Delete specific old generations
nix-env --delete-generations +5  # Keep last 5
nix-env --delete-generations 30d # Delete older than 30 days
```

### Generation Management

```bash
# List system generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# List user generations
nix-env --list-generations

# List Home Manager generations
home-manager generations

# Delete old system generations (keep last 5)
sudo nix-env --delete-generations +5 --profile /nix/var/nix/profiles/system

# Rollback if something breaks
sudo nixos-rebuild switch --rollback
```

### Store Optimization

```bash
# Deduplicate identical files (SLOW - can take 30+ minutes)
nix store optimise

# Show store size
du -sh /nix/store

# Find large packages
du -sh /nix/store/* | sort -h | tail -20

# Find dead paths (what GC would remove)
nix-store --gc --print-dead | wc -l
```

## Automatic Garbage Collection

### Option 1: Home Manager Module

Add to your Home Manager configuration:

```nix
{ pkgs, ... }:
{
  imports = [
    # Import the GC module from nixos-cursor
    (builtins.fetchurl {
      url = "https://raw.githubusercontent.com/your-repo/nixos-cursor/main/home-manager-module/gc.nix";
    })
  ];

  programs.cursor.gc = {
    enable = true;
    schedule = "weekly";           # or "daily", "monthly", "*-*-* 03:00:00"
    keepGenerations = 5;           # Keep last 5 generations
    deleteOlderThan = {
      enable = true;
      days = 7;                    # Delete older than 7 days
    };
    optimize = false;              # Store optimization (slow, use sparingly)
    cursorVersionsToKeep = [       # Protect specific versions from GC
      "2.0.77"
      "1.7.54"
    ];
  };
}
```

### Option 2: NixOS System Configuration

```nix
# configuration.nix
{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Optional: auto-optimize store
  nix.settings.auto-optimise-store = true;
}
```

### Option 3: Systemd Timer (Manual)

```bash
# Create user timer
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/nix-gc.service << 'EOF'
[Unit]
Description=Nix Garbage Collection

[Service]
Type=oneshot
ExecStart=/run/current-system/sw/bin/nix-collect-garbage -d
EOF

cat > ~/.config/systemd/user/nix-gc.timer << 'EOF'
[Unit]
Description=Weekly Nix Garbage Collection

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now nix-gc.timer
```

## Scripts Provided

### `disk-usage.sh`

Analyzes Cursor-specific disk usage:

```bash
./scripts/storage/disk-usage.sh
./scripts/storage/disk-usage.sh --detailed
./scripts/storage/disk-usage.sh --gc-roots
```

Output includes:
- Total store size
- Cursor AppImages count and size
- Built packages count and size
- Extracted packages count and size
- Recommendations

### `gc-helper.sh`

Safe, interactive garbage collection:

```bash
# Analyze (default, dry-run)
./scripts/storage/gc-helper.sh

# Commands
./scripts/storage/gc-helper.sh analyze      # What would be collected
./scripts/storage/gc-helper.sh collect      # Run GC
./scripts/storage/gc-helper.sh generations  # Manage generations
./scripts/storage/gc-helper.sh optimize     # Deduplicate store
./scripts/storage/gc-helper.sh full         # All of the above

# Options
--no-dry-run           # Actually do it (dry-run by default!)
--keep-generations N   # Keep last N generations
--keep-days N          # Keep generations from last N days
--system               # Also clean system generations (needs sudo)
-y, --yes              # Skip confirmations
```

## Best Practices

### Regular Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Garbage collection | Weekly | `nix-collect-garbage -d` |
| System generations | Monthly | `sudo nix-env --delete-generations +5 ...` |
| Store optimization | Monthly | `nix store optimise` |
| Disk check | Weekly | `df -h /nix` |

### Recommended Configuration

For a typical workstation with multiple Cursor versions:

```nix
{
  # Keep 5 system generations
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Don't auto-optimize (too slow for frequent rebuilds)
  nix.settings.auto-optimise-store = false;

  # Run optimize monthly via cron/timer instead
}
```

### Space Estimates

| Item | Approximate Size |
|------|-----------------|
| Single Cursor version | 200-300MB |
| All 48 versions built | 10-15GB |
| Typical NixOS system | 20-40GB |
| 10 system generations | +5-10GB each |
| Store with no GC for 6 months | 50-100GB+ |

### Emergency Cleanup

If you're critically low on disk space:

```bash
# 1. Quick GC (removes obvious garbage)
nix-collect-garbage

# 2. Delete all but last 2 generations
sudo nix-env --delete-generations +2 --profile /nix/var/nix/profiles/system
nix-env --delete-generations +2

# 3. Full GC with system
sudo nix-collect-garbage -d

# 4. Check what's left
df -h /nix
du -sh /nix/store
```

## Troubleshooting

### "No space left on device" During Build

```bash
# 1. Run GC first
nix-collect-garbage -d

# 2. If still failing, check what's using space
df -h
du -sh /nix/store/* | sort -h | tail -20

# 3. Consider removing old generations
sudo nix-env --delete-generations +3 --profile /nix/var/nix/profiles/system
```

### GC Not Freeing Expected Space

Paths are kept alive by:
1. Current system profile
2. User profiles
3. Home Manager generations
4. Build result symlinks (`./result`)
5. Dev shells (`direnv`, `nix-shell`)

Check what's keeping a path alive:
```bash
nix-store --query --roots /nix/store/xxx-package-name
```

### Store Optimization Takes Forever

`nix store optimise` can take 30+ minutes on large stores. Options:
1. Run overnight/weekly via timer
2. Skip if store is already mostly optimized
3. Use `auto-optimise-store = true` for incremental optimization

## Related Documentation

- [Auto Update Implementation](./AUTO_UPDATE_IMPLEMENTATION.md)
- [User Data Persistence](./USER_DATA_PERSISTENCE.md)
- [NixOS Manual: Garbage Collection](https://nixos.org/manual/nix/stable/package-management/garbage-collection.html)
