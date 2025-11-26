# Scripting Architecture: Beyond Bash

## The Problem with Bash

While bash is ubiquitous and we know it well, it has fundamental limitations:

| Issue | Example | Impact |
|-------|---------|--------|
| **Whitespace sensitivity** | `[ $var = "test" ]` vs `[$var="test"]` | Silent failures |
| **Quoting hell** | `"$(echo "$var")"` | Hard to read/maintain |
| **No structured data** | JSON requires `jq` | External dependency |
| **Weak typing** | Everything is a string | Runtime errors |
| **Poor error handling** | `set -e` is fragile | Unexpected behavior |
| **Array syntax** | `"${array[@]}"` | Easy to forget quotes |
| **Arithmetic** | `$((a + b))` or `bc` | Inconsistent |

## Language Selection Matrix

| Task Type | Recommended | Alternatives | Avoid |
|-----------|-------------|--------------|-------|
| **Data manipulation** | Nushell | Python, Nim | Bash |
| **HTTP/API** | Python, Nushell | Rust | Bash+curl |
| **System commands** | Nushell | Bash | - |
| **Performance-critical** | Nim, Zig, Rust | Go | Python, Bash |
| **Complex logic** | Python, Nim | Rust | Bash |
| **Interactive CLI** | Nushell | Python (rich) | Bash |
| **Quick one-liners** | Nushell | Bash | - |
| **Build automation** | Nushell, Just | Make | Bash scripts |

## Recommended Stack

### 1. Nushell (Primary Shell Language)

**Best for**: Data manipulation, system commands, interactive CLI

```nu
# Example: disk-usage.nu
def analyze_store [] {
    let store_entries = (ls /nix/store | where name =~ "cursor")
    let total_size = ($store_entries | get size | math sum)
    
    {
        entries: ($store_entries | length)
        total_size: $total_size
        breakdown: ($store_entries | group-by type | each { |g| 
            { type: $g.name, count: ($g.items | length) }
        })
    }
}
```

**Advantages**:
- Native structured data (tables, records, lists)
- Built-in JSON/YAML/TOML parsing
- Type inference
- Pipeline-oriented (like bash, but typed)
- Beautiful output formatting
- Cross-platform

**Available in Nix**: `pkgs.nushell`

### 2. Python (Complex Logic / Data Processing)

**Best for**: Complex algorithms, HTTP APIs, data transformation

```python
# Example: compute_hashes.py
import httpx
import hashlib
from pathlib import Path

def compute_hash(url: str) -> str:
    """Download and compute SHA256 hash."""
    with httpx.stream("GET", url) as response:
        hasher = hashlib.sha256()
        for chunk in response.iter_bytes():
            hasher.update(chunk)
    return f"sha256-{base64.b64encode(hasher.digest()).decode()}"
```

**Advantages**:
- Rich ecosystem (httpx, rich, typer)
- Excellent for data transformation
- Good error handling
- Type hints available

**Available in Nix**: `pkgs.python3`

### 3. Nim (Performance + Readability)

**Best for**: Performance-critical tools, compiled CLI apps

```nim
# Example: fast_validator.nim
import std/[httpclient, asyncdispatch, json]

proc validateUrl(url: string): Future[bool] {.async.} =
  let client = newAsyncHttpClient()
  try:
    let response = await client.head(url)
    return response.code == Http200
  except:
    return false
```

**Advantages**:
- Python-like syntax
- Compiles to C (very fast)
- Small binaries
- No runtime dependencies
- Great for tools that need speed

**Available in Nix**: `pkgs.nim`

### 4. Zig (Systems / Maximum Performance)

**Best for**: Low-level operations, maximum performance

```zig
// Example: hash_compute.zig
const std = @import("std");

pub fn computeHash(data: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(data);
    return hasher.finalResult();
}
```

**Advantages**:
- No hidden allocations
- Compile-time computation
- Excellent for performance-critical paths
- Great interop with C

**Available in Nix**: `pkgs.zig`

### 5. Rust (Reliability / Long-term Tools)

**Best for**: Tools that need maximum reliability, will be maintained long-term

```rust
// Example: cursor_manager.rs
use clap::Parser;
use anyhow::Result;

#[derive(Parser)]
struct Args {
    #[arg(short, long)]
    version: Option<String>,
}

fn main() -> Result<()> {
    let args = Args::parse();
    // ...
}
```

**Advantages**:
- Memory safety without GC
- Excellent error handling
- Rich ecosystem (clap, serde, tokio)
- Great for long-lived projects

**Available in Nix**: `pkgs.rustc`, `pkgs.cargo`

## Script Migration Plan

### Phase 1: Quick Wins (Nushell)

| Script | Current | Migrate To | Reason |
|--------|---------|------------|--------|
| `disk-usage.sh` | Bash | Nushell | Native structured data, beautiful tables |
| `gc-helper.sh` | Bash | Nushell | Better prompts, cleaner logic |
| `all-versions-test.sh` | Bash+jq | Nushell | Native JSON, no jq dependency |

### Phase 2: Data-Heavy Scripts (Python)

| Script | Current | Migrate To | Reason |
|--------|---------|------------|--------|
| `cursor-data-tracker.sh` | Bash+jq | Python | Complex logic, JSON handling |
| `compute-hashes.sh` | Bash+curl | Python | HTTP handling, progress bars |
| `validate-urls.sh` | Bash+curl | Python | Parallel HTTP, better error handling |

### Phase 3: Performance-Critical (Nim/Rust)

| Tool | Current | Migrate To | Reason |
|------|---------|------------|--------|
| `cursor-manager` | Bash GUI | Nim or Rust | Compiled, fast startup |
| Hash validation | Python | Nim | Speed for large downloads |

## File Organization

```
scripts/
├── nu/                      # Nushell scripts
│   ├── disk-usage.nu
│   ├── gc-helper.nu
│   └── test-versions.nu
├── python/                  # Python scripts
│   ├── data_tracker.py
│   ├── compute_hashes.py
│   └── validate_urls.py
├── nim/                     # Nim tools (compiled)
│   └── fast_validator.nim
├── rust/                    # Rust tools (compiled)
│   └── cursor-manager/
├── bash/                    # Legacy/simple bash
│   ├── prepare-public-branch.sh
│   ├── release-to-main.sh
│   └── validate-public-branch.sh
└── lib/                     # Shared utilities
    ├── colors.nu            # Nushell color definitions
    └── common.py            # Python shared code
```

## Nix Integration

### Adding Language Support to Flake

```nix
# flake.nix additions
{
  devShells.default = pkgs.mkShell {
    packages = with pkgs; [
      # Shell
      nushell
      
      # Python
      (python3.withPackages (ps: with ps; [
        httpx
        rich
        typer
      ]))
      
      # Compiled languages
      nim
      zig
      rustc
      cargo
    ];
  };
}
```

### Script Wrapper Pattern

```nix
# Wrap Nushell scripts for PATH
cursor-disk-usage = pkgs.writeShellScriptBin "cursor-disk-usage" ''
  ${pkgs.nushell}/bin/nu ${./scripts/nu/disk-usage.nu} "$@"
'';
```

## Comparison: Bash vs Nushell

### disk-usage.sh in Bash (Current)

```bash
# Pain points highlighted
appimage_bytes=$(du -sb "$STORE_PATH"/*Cursor*AppImage* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
cursor_percentage=$(awk "BEGIN {printf \"%.1f\", $total_cursor_bytes * 100 / $total_store_bytes}")
echo -e "  ${BOLD}Total Cursor usage: ${YELLOW}$(format_size "$total_cursor_bytes")${NC}"
```

### disk-usage.nu in Nushell (Proposed)

```nu
# Clean, typed, no quoting issues
let appimages = (ls /nix/store/*Cursor*AppImage* | get size | math sum)
let percentage = ($total_cursor / $total_store * 100 | math round -p 1)
print $"  (ansi bold)Total Cursor usage: (ansi yellow)($total_cursor | into filesize)(ansi reset)"
```

## Migration Guidelines

### When to Keep Bash

1. Simple wrappers (< 20 lines)
2. One-time scripts
3. System bootstrapping (before other tools installed)
4. POSIX portability required

### When to Use Nushell

1. Data manipulation (JSON, tables, lists)
2. Interactive CLI tools
3. Scripts with complex output formatting
4. Cross-platform shell scripts

### When to Use Python

1. HTTP/API operations
2. Complex business logic
3. Need for rich libraries
4. Data science / transformation

### When to Use Nim/Zig/Rust

1. Performance is critical
2. Tool will be distributed
3. Need compiled binary
4. Long-term maintenance expected

## Getting Started

### Install Nushell

```bash
# NixOS/Home Manager
programs.nushell.enable = true;

# Or via nix-shell
nix-shell -p nushell
```

### First Nushell Script

```nu
#!/usr/bin/env nu

# cursor-info.nu - Example Nushell script
def main [] {
    let versions = (ls ~/.cursor-* | where type == dir | get name | path basename)
    
    print "Cursor Versions Found:"
    $versions | each { |v| print $"  • ($v)" }
    
    print ""
    print $"Total: ($versions | length) versions"
}
```

## References

- [Nushell Book](https://www.nushell.sh/book/)
- [Nim Manual](https://nim-lang.org/docs/manual.html)
- [Zig Documentation](https://ziglang.org/documentation/)
- [Rust Book](https://doc.rust-lang.org/book/)
