# Storage Management Scripts

Scripts for managing Nix store disk usage, particularly for systems with multiple Cursor versions.

## Scripts

### `disk-usage.sh`

Analyzes Cursor-specific disk usage in the Nix store.

```bash
# Quick summary
./disk-usage.sh

# Detailed breakdown by version era
./disk-usage.sh --detailed

# Show GC roots keeping Cursor versions alive
./disk-usage.sh --gc-roots
```

### `gc-helper.sh`

Safe, interactive garbage collection with dry-run by default.

```bash
# Analyze what would be collected (default)
./gc-helper.sh

# Run garbage collection
./gc-helper.sh collect --no-dry-run

# Manage generations
./gc-helper.sh generations --keep-generations 3

# Full cleanup (generations + gc + optimize)
./gc-helper.sh full --no-dry-run -y
```

## Safety Features

1. **Dry-run by default** - Use `--no-dry-run` to actually perform operations
2. **Confirmation prompts** - Use `-y` to skip
3. **Generation preservation** - Keeps recent generations for rollback
4. **Clear output** - Shows exactly what will be done

## Quick Commands

```bash
# See what's using space
./disk-usage.sh

# See what can be reclaimed
./gc-helper.sh

# Actually clean up (with confirmation)
./gc-helper.sh full --no-dry-run
```

## Documentation

See [docs/GARBAGE_COLLECTION.md](../../docs/GARBAGE_COLLECTION.md) for full documentation.
