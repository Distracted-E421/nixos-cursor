# Legacy Bash Scripts

⚠️ **DEPRECATED**: These scripts have been replaced by Nushell equivalents.

## Migration Status

| Legacy Script | Replacement | Status |
|---------------|-------------|--------|
| `disk-usage.sh` | `../nu/disk-usage.nu` | ✅ Migrated |
| `gc-helper.sh` | `../nu/gc-helper.nu` | ✅ Migrated |
| `validate-urls.sh` | `../nu/validate-urls.nu` | ✅ Migrated |
| `all-versions-test.sh` | `../nu/test-versions.nu` | ✅ Migrated |

## Why Nushell?

| Issue | Bash | Nushell |
|-------|------|---------|
| JSON handling | Requires `jq` | Native |
| Arithmetic | `$((a+b))` or `bc` | Native operators |
| Data types | Strings only | Tables, records, lists |
| Error handling | `set -e` (fragile) | Result types |

## Usage

**Use the Nushell versions instead:**

```bash
# Instead of: ./legacy/disk-usage.sh
nix develop --command nu scripts/nu/disk-usage.nu

# Instead of: ./legacy/gc-helper.sh
nix develop --command nu scripts/nu/gc-helper.nu

# Instead of: ./legacy/validate-urls.sh
nix develop --command nu scripts/nu/validate-urls.nu

# Instead of: ./legacy/all-versions-test.sh
nix develop --command nu scripts/nu/test-versions.nu
```

## Preservation

These scripts are kept for:
- Reference during migration
- Fallback if Nushell is unavailable
- Historical documentation

**Do not update these scripts** - they will be removed in a future release.
