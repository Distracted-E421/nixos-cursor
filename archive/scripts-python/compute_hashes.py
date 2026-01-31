#!/usr/bin/env python3
"""
Cursor Hash Computation Script
Computes SHA256 hashes for Cursor AppImages/DMGs

Python version - demonstrates:
- Proper HTTP streaming with progress
- Async parallel downloads
- Clean error handling
- Rich terminal output

Compare to scripts/validation/compute-hashes.sh for bash version
"""

import asyncio
import base64
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

try:
    import httpx
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, BarColumn, DownloadColumn, TransferSpeedColumn, TimeRemainingColumn
    from rich.table import Table
    from rich import print as rprint
except ImportError:
    print("Missing dependencies. Install with:")
    print("  nix-shell -p 'python3.withPackages (ps: with ps; [httpx rich])'")
    sys.exit(1)

console = Console()


@dataclass
class HashResult:
    """Result of computing a hash."""
    url: str
    version: str
    hash: str
    size: int
    success: bool
    error: Optional[str] = None


def extract_version(url: str) -> str:
    """Extract version number from URL."""
    # Match patterns like Cursor-2.1.34-x86_64.AppImage
    match = re.search(r'Cursor-(\d+\.\d+\.\d+)', url)
    if match:
        return match.group(1)
    return "unknown"


def to_nix_hash(sha256_bytes: bytes) -> str:
    """Convert SHA256 bytes to Nix SRI format."""
    return f"sha256-{base64.b64encode(sha256_bytes).decode()}"


async def compute_hash_for_url(
    client: httpx.AsyncClient,
    url: str,
    progress: Progress,
    task_id: int
) -> HashResult:
    """Download a file and compute its SHA256 hash."""
    version = extract_version(url)
    
    try:
        async with client.stream("GET", url) as response:
            if response.status_code != 200:
                return HashResult(
                    url=url,
                    version=version,
                    hash="",
                    size=0,
                    success=False,
                    error=f"HTTP {response.status_code}"
                )
            
            total_size = int(response.headers.get("content-length", 0))
            progress.update(task_id, total=total_size, description=f"[cyan]{version}")
            
            hasher = hashlib.sha256()
            downloaded = 0
            
            async for chunk in response.aiter_bytes(chunk_size=8192):
                hasher.update(chunk)
                downloaded += len(chunk)
                progress.update(task_id, completed=downloaded)
            
            return HashResult(
                url=url,
                version=version,
                hash=to_nix_hash(hasher.digest()),
                size=downloaded,
                success=True
            )
    
    except httpx.TimeoutException:
        return HashResult(url=url, version=version, hash="", size=0, success=False, error="Timeout")
    except httpx.RequestError as e:
        return HashResult(url=url, version=version, hash="", size=0, success=False, error=str(e))


async def compute_hashes(urls: list[str], parallel: int = 3) -> list[HashResult]:
    """Compute hashes for multiple URLs."""
    results = []
    
    async with httpx.AsyncClient(timeout=300.0, follow_redirects=True) as client:
        with Progress(
            SpinnerColumn(),
            "[progress.description]{task.description}",
            BarColumn(),
            DownloadColumn(),
            TransferSpeedColumn(),
            TimeRemainingColumn(),
            console=console
        ) as progress:
            # Create tasks for all URLs
            tasks = []
            task_ids = []
            
            for url in urls:
                task_id = progress.add_task(f"[cyan]{extract_version(url)}", total=None)
                task_ids.append(task_id)
            
            # Process in batches
            for i in range(0, len(urls), parallel):
                batch_urls = urls[i:i + parallel]
                batch_task_ids = task_ids[i:i + parallel]
                
                batch_tasks = [
                    compute_hash_for_url(client, url, progress, tid)
                    for url, tid in zip(batch_urls, batch_task_ids)
                ]
                
                batch_results = await asyncio.gather(*batch_tasks)
                results.extend(batch_results)
    
    return results


def format_nix_output(results: list[HashResult]) -> str:
    """Format results as Nix attribute set."""
    lines = ["# Auto-generated Cursor version hashes", "{"]
    
    for r in sorted(results, key=lambda x: x.version, reverse=True):
        if r.success:
            lines.append(f'  "cursor-{r.version}" = {{')
            lines.append(f'    version = "{r.version}";')
            lines.append(f'    hash = "{r.hash}";')
            lines.append(f'    # Size: {r.size:,} bytes')
            lines.append('  };')
            lines.append('')
    
    lines.append("}")
    return "\n".join(lines)


def print_results_table(results: list[HashResult]):
    """Print results as a nice table."""
    table = Table(title="Hash Computation Results")
    table.add_column("Version", style="cyan")
    table.add_column("Status", style="green")
    table.add_column("Size")
    table.add_column("Hash", style="dim")
    
    for r in sorted(results, key=lambda x: x.version, reverse=True):
        if r.success:
            table.add_row(
                r.version,
                "✓",
                f"{r.size / 1024 / 1024:.1f} MB",
                r.hash[:30] + "..."
            )
        else:
            table.add_row(
                r.version,
                f"[red]✗ {r.error}[/red]",
                "-",
                "-"
            )
    
    console.print(table)


def read_urls_from_file(path: Path) -> list[str]:
    """Read URLs from a file, one per line."""
    urls = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and line.startswith("http"):
                urls.append(line)
    return urls


def parse_args():
    """Parse command line arguments."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Compute SHA256 hashes for Cursor downloads"
    )
    parser.add_argument(
        "urls",
        nargs="*",
        help="URLs to compute hashes for"
    )
    parser.add_argument(
        "-f", "--file",
        type=Path,
        help="File containing URLs (one per line)"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        help="Output file for Nix format"
    )
    parser.add_argument(
        "-p", "--parallel",
        type=int,
        default=3,
        help="Number of parallel downloads (default: 3)"
    )
    parser.add_argument(
        "--nix",
        action="store_true",
        help="Output in Nix format"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output in JSON format"
    )
    
    return parser.parse_args()


async def main():
    args = parse_args()
    
    # Collect URLs
    urls = list(args.urls)
    if args.file:
        urls.extend(read_urls_from_file(args.file))
    
    if not urls:
        console.print("[red]No URLs provided. Use --help for usage.[/red]")
        sys.exit(1)
    
    console.print(f"[bold]Computing hashes for {len(urls)} URLs...[/bold]")
    console.print()
    
    # Compute hashes
    results = await compute_hashes(urls, parallel=args.parallel)
    
    console.print()
    
    # Output results
    if args.json:
        import json
        output = [
            {
                "version": r.version,
                "hash": r.hash,
                "size": r.size,
                "url": r.url,
                "success": r.success,
                "error": r.error
            }
            for r in results
        ]
        print(json.dumps(output, indent=2))
    
    elif args.nix:
        nix_output = format_nix_output(results)
        if args.output:
            args.output.write_text(nix_output)
            console.print(f"[green]✓[/green] Wrote Nix output to {args.output}")
        else:
            print(nix_output)
    
    else:
        print_results_table(results)
        
        # Summary
        success_count = sum(1 for r in results if r.success)
        total_size = sum(r.size for r in results if r.success)
        console.print()
        console.print(f"[bold]Summary:[/bold] {success_count}/{len(results)} successful, {total_size / 1024 / 1024 / 1024:.2f} GB total")
        
        if args.output:
            nix_output = format_nix_output(results)
            args.output.write_text(nix_output)
            console.print(f"[green]✓[/green] Wrote Nix output to {args.output}")


if __name__ == "__main__":
    asyncio.run(main())
