# Python Scripts

Data-heavy and HTTP-intensive scripts using Python with modern async.

## Why Python?

| Task | Best Tool |
|------|-----------|
| HTTP requests | `httpx` with async |
| Progress bars | `rich` library |
| Complex logic | Type hints, dataclasses |
| Parallel I/O | `asyncio` |
| JSON handling | Native |

## Requirements

```bash
# Via nix-shell (recommended)
nix-shell -p 'python3.withPackages (ps: with ps; [httpx rich])'

# Or in flake devShell
nix develop

# Or system-wide
# Add to your environment.systemPackages or home.packages
```

## Scripts

### `compute_hashes.py`

Compute SHA256 hashes for Cursor downloads with parallel HTTP requests.

```bash
# Single URL
python compute_hashes.py https://downloads.cursor.com/.../Cursor-2.1.34-x86_64.AppImage

# From file
python compute_hashes.py -f ../validation/urls.txt

# Parallel downloads (3 concurrent by default)
python compute_hashes.py -f urls.txt -p 5

# Output as Nix attribute set
python compute_hashes.py -f urls.txt --nix -o hashes.nix

# JSON output
python compute_hashes.py -f urls.txt --json
```

**Features:**
- Async HTTP with streaming (efficient memory usage)
- Rich progress bars
- Parallel downloads
- Nix-compatible SRI hash output
- Beautiful terminal output

## Comparison with Bash

### Bash (old)

```bash
# Single-threaded, no progress, fragile error handling
for url in "${urls[@]}"; do
    hash=$(curl -sL "$url" | sha256sum | cut -d' ' -f1)
    # Converting to base64 is complex...
    nix_hash=$(echo "$hash" | xxd -r -p | base64)
    echo "sha256-$nix_hash"
done
```

### Python (new)

```python
async def compute_hash(url: str) -> HashResult:
    async with client.stream("GET", url) as response:
        hasher = hashlib.sha256()
        async for chunk in response.aiter_bytes():
            hasher.update(chunk)
    return HashResult(hash=to_nix_hash(hasher.digest()))

# Parallel execution
results = await asyncio.gather(*[compute_hash(url) for url in urls])
```

## Adding New Scripts

Use this template:

```python
#!/usr/bin/env python3
"""
Script Description
"""

import asyncio
from dataclasses import dataclass
from pathlib import Path

try:
    from rich.console import Console
    # ... other imports
except ImportError:
    print("Missing dependencies. Install with:")
    print("  nix-shell -p 'python3.withPackages (ps: with ps; [...])'")
    sys.exit(1)

console = Console()

@dataclass
class Result:
    """Strongly typed result."""
    success: bool
    data: str

async def main():
    # Your async code here
    pass

if __name__ == "__main__":
    asyncio.run(main())
```
