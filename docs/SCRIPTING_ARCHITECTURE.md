# Scripting Architecture: Multi-Language Strategy

> **Core Tenet**: Language is infrastructure. Choose the language that makes the problem domain clearest, not the one with the shortest syntax.

## 🎯 Language Philosophy

 We prioritize:

1. **Expressiveness** over brevity
2. **Type safety** over convenience
3. **Reproducibility** with flexibility
4. **Functional patterns** over imperative ones
5. **Immutability** by default

## 📚 Language Stack

### Tier 1: Primary Languages (Use First)

| Language | Use Case | Runner |
|----------|----------|--------|
| **Nix** | Configuration, packaging, system orchestration | `nix build`, `nix eval` |
| **Nushell** | Data pipelines, automation, quick scripts | `nu script.nu` |
| **Python (uv)** | AI/ML, data analysis, HTTP operations | `uv run script.py` |
| **Rust** | Performance-critical CLI tools, system utilities | `cargo run` |
| **Elixir** | Long-running services, fault-tolerant daemons | `elixir script.exs` |

### Tier 2: Secondary Languages (When Required)

| Language | When to Use |
|----------|-------------|
| **Zig** | Low-level systems, C interop, embedded |
| **Go** | Kubernetes tools, simple network services |
| **TypeScript** | Web frontends, Node.js tooling |

### Tier 3: Avoid (Legacy Compatibility Only)

| Language | Why Avoid | Migration Target |
|----------|-----------|------------------|
| **Bash** | Unstructured, error-prone, no types | → Nushell |
| **Shell scripts** | Hard to maintain, debugging nightmare | → Nushell |
| **Perl** | Readability issues, maintenance burden | → Python |

## 🔧 Language Selection Guide

```
Is it NixOS configuration?
  └─ YES → Nix

Quick data manipulation or automation?
  └─ YES → Nushell

Long-running daemon with fault tolerance?
  └─ YES → Elixir

AI/ML or heavy data science?
  └─ YES → Python (uv)

Performance-critical CLI tool?
  └─ YES → Rust

Low-level systems programming?
  └─ YES → Zig

Simple network service?
  └─ YES → Go or Elixir
```

## 📁 Repository Structure

```
scripts/
├── nu/                      # Nushell scripts (Tier 1)
│   ├── disk-usage.nu        # Nix store analysis
│   ├── gc-helper.nu         # Garbage collection
│   ├── validate-urls.nu     # URL validation
│   └── test-versions.nu     # Version testing
│
├── python/                  # Python scripts (Tier 1)
│   └── compute_hashes.py    # Hash computation with async HTTP
│
├── elixir/                  # Elixir services (future)
│   └── cursor_tracker/      # Long-running data tracker
│
├── rust/                    # Rust tools (future)
│   └── cursor-manager/      # Compiled version manager
│
├── lib/                     # Shared utilities
│   └── colors.nu            # Nushell color helpers
│
└── legacy/                  # Deprecated bash (migration targets)
    ├── gc-helper.sh         # → scripts/nu/gc-helper.nu
    ├── validate-urls.sh     # → scripts/nu/validate-urls.nu
    └── disk-usage.sh        # → scripts/nu/disk-usage.nu (DONE)
```

## ⚡ Migration Priority

### Phase 1: Nushell ✅ COMPLETE

| Script | Status | Notes |
|--------|--------|-------|
| `disk-usage.sh` | ✅ Done | `scripts/nu/disk-usage.nu` |
| `gc-helper.sh` | ✅ Done | `scripts/nu/gc-helper.nu` |
| `validate-urls.sh` | ✅ Done | `scripts/nu/validate-urls.nu` |
| `all-versions-test.sh` | ✅ Done | `scripts/nu/test-versions.nu` |

Legacy bash scripts moved to `scripts/legacy/` for reference.

### Phase 2: Python (uv)

| Script | Status | Notes |
|--------|--------|-------|
| `compute-hashes.sh` | ✅ Done | `scripts/python/compute_hashes.py` |
| Complex HTTP operations | 📋 Planned | async, progress bars |

### Phase 3: Elixir (Future)

| Tool | Status | Notes |
|------|--------|-------|
| `cursor-data-tracker` | 📋 Planned | Long-running, fault-tolerant |
| Service monitoring | 📋 Planned | OTP supervision trees |

### Phase 4: Rust (Future)

| Tool | Status | Notes |
|------|--------|-------|
| `cursor-manager` | 📋 Planned | Compiled, fast startup |
| Version resolver | 📋 Planned | Performance-critical |

## 🔄 Bash vs Nushell Comparison

### Example: Summing File Sizes

**Bash** (error-prone):
```bash
# Word splitting issues, needs awk, quoting hell
total=$(du -sb "$DIR"/*.txt 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
percentage=$(awk "BEGIN {printf \"%.1f\", $total * 100 / $store_size}")
echo -e "${BOLD}Total: ${YELLOW}$(numfmt --to=iec $total)${NC}"
```

**Nushell** (clean, typed):
```nu
# Native structured data, no external tools
let total = (ls $dir/*.txt | get size | math sum)
let percentage = ($total / $store_size * 100 | math round --precision 1)
print $"(ansi bold)Total: (ansi yellow)($total)(ansi reset)"
```

### Example: HTTP Validation

**Bash** (fragile):
```bash
http_code=$(curl -sL -o /dev/null -w '%{http_code}' --connect-timeout 10 "$url" 2>/dev/null || echo "000")
case "$http_code" in
    200) echo "OK" ;;
    *) echo "FAIL" ;;
esac
```

**Nushell** (structured):
```nu
let response = (http head $url --max-time 10sec | complete)
if $response.exit_code == 0 {
    { url: $url, status: "OK" }
} else {
    { url: $url, status: "FAIL", error: $response.stderr }
}
```

## 🛠️ Development Shell

```bash
# Enter development environment with all tools
nix develop

# Available:
#   nu        - Nushell (primary shell)
#   python    - Python 3 with httpx, rich, typer
#   statix    - Nix linter
#   jq        - JSON fallback (prefer nu for JSON)

# Full shell with compiled languages
nix develop .#full
#   Also includes: nim, zig, cargo, rustc
```

## 📋 Script Template: Nushell

```nu
#!/usr/bin/env nu

# Script: my-script.nu
# Purpose: Brief description
# Usage: nu my-script.nu [args]

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

const VERSION = "1.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def log [level: string, message: string] {
    let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S")
    let icon = match $level {
        "info" => "ℹ"
        "success" => "✓"
        "warn" => "⚠"
        "error" => "✗"
        _ => "•"
    }
    print $"[($timestamp)] ($icon) ($message)"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN LOGIC
# ─────────────────────────────────────────────────────────────────────────────

def main [
    --verbose (-v)  # Enable verbose output
    --dry-run (-n)  # Don't make changes
] {
    log "info" "Starting script..."
    
    # Stage 1
    log "info" "Stage 1: Processing..."
    # ... work ...
    log "success" "Stage 1 complete"
    
    # Done
    log "success" "Script complete!"
}
```

## 📋 Script Template: Python (uv)

```python
#!/usr/bin/env -S uv run
# /// script
# dependencies = ["httpx", "rich", "typer"]
# ///
"""
Script description.

Usage: uv run script.py [OPTIONS]
"""

import asyncio
from dataclasses import dataclass
from typing import Optional

from rich.console import Console
import typer

console = Console()
app = typer.Typer()

@dataclass
class Result:
    success: bool
    data: Optional[str] = None
    error: Optional[str] = None

@app.command()
def main(
    verbose: bool = typer.Option(False, "--verbose", "-v"),
    dry_run: bool = typer.Option(False, "--dry-run", "-n"),
):
    """Main command."""
    console.print("🚀 Starting script...")
    # ... work ...
    console.print("✅ Complete!")

if __name__ == "__main__":
    app()
```

## 🔗 References

- [Nushell Book](https://www.nushell.sh/book/)
- [Python uv Guide](https://docs.astral.sh/uv/)
- [Elixir Getting Started](https://elixir-lang.org/getting-started/)
- [Rust Book](https://doc.rust-lang.org/book/)
- [Zig Documentation](https://ziglang.org/documentation/)
