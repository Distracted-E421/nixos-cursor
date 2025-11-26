# Nushell Scripts

Modern, structured shell scripts using [Nushell](https://www.nushell.sh/).

## Why Nushell?

| Feature | Bash | Nushell |
|---------|------|---------|
| Data types | Strings only | Tables, records, lists |
| JSON handling | Requires `jq` | Native |
| Arithmetic | `$((a+b))` or `bc` | `$a + $b` |
| Error handling | `set -e` (fragile) | Result types |
| Pipelines | Text-based | Structured data |

## Requirements

```bash
# NixOS / Home Manager
programs.nushell.enable = true;

# Or via nix-shell
nix-shell -p nushell

# Or run directly
nix run nixpkgs#nushell -- scripts/nu/disk-usage.nu
```

## Scripts

### `disk-usage.nu`

Analyzes Nix store usage for Cursor packages.

```bash
nu disk-usage.nu                # Basic usage
nu disk-usage.nu --detailed     # Detailed breakdown
nu disk-usage.nu --json         # JSON output
nu disk-usage.nu --gc-roots     # Show GC roots
```

### `gc-helper.nu`

Safe, interactive garbage collection for NixOS/nix-darwin.

```bash
nu gc-helper.nu                 # Analyze (default)
nu gc-helper.nu collect         # Run garbage collection
nu gc-helper.nu generations     # Manage generations
nu gc-helper.nu optimize        # Run store optimization
nu gc-helper.nu full --yes      # Full cleanup, no prompts
```

### `validate-urls.nu`

Validate Cursor download URLs are accessible.

```bash
nu validate-urls.nu             # Validate all URLs
nu validate-urls.nu --linux-only    # Only Linux URLs
nu validate-urls.nu --darwin-only   # Only Darwin URLs
nu validate-urls.nu --json      # JSON output
```

### `test-versions.nu`

Test build capability for all defined Cursor versions.

```bash
nu test-versions.nu             # Quick eval test (default)
nu test-versions.nu full        # Dry-build test
nu test-versions.nu build       # Full build (slow!)
nu test-versions.nu --json      # JSON output
```

**All scripts feature:**
- Native structured data handling
- Beautiful table output
- No `bc`, `awk`, or `jq` required
- Type-safe operations

## Comparison with Bash

### Bash (old)

```bash
# Compute sum of sizes, handle empty results, avoid word splitting
appimage_bytes=$(du -sb "$STORE_PATH"/*Cursor*AppImage* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

# Arithmetic requires external tool or special syntax
cursor_percentage=$(awk "BEGIN {printf \"%.1f\", $total_cursor_bytes * 100 / $total_store_bytes}")

# Quoting hell
echo -e "  ${BOLD}Total Cursor usage: ${YELLOW}$(format_size "$total_cursor_bytes")${NC}"
```

### Nushell (new)

```nu
# Simple, type-safe, no quoting issues
let appimages = (ls /nix/store/*Cursor*AppImage* | get size | math sum)

# Arithmetic is natural
let percentage = ($total_cursor / $total_store * 100 | math round --precision 1)

# String interpolation is clean
print $"  (ansi bold)Total: (ansi yellow)($total_cursor)(ansi reset)"
```

## Library

Shared utilities in `lib/colors.nu`:

```nu
use ../lib/colors.nu *

# Use provided helpers
header "My Script"
success "Operation completed"
warn "This might be slow"
error "Something went wrong"
info "Processing..."
```
