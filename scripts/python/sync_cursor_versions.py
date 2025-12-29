#!/usr/bin/env python3
"""
Cursor Version Sync Automation

Fetches the latest Cursor versions from GitHub, downloads AppImages,
computes SHA256 hashes, and updates Nix derivations.

Usage:
    # Check for new versions (dry run)
    python sync_cursor_versions.py --check

    # Download and hash new versions
    python sync_cursor_versions.py --sync

    # Full automation: sync + update nix + commit + push
    python sync_cursor_versions.py --auto

Requirements:
    pip install httpx rich typer
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

try:
    import httpx
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, DownloadColumn
    from rich.table import Table
    import typer
except ImportError:
    print("Missing dependencies. Install with: pip install httpx rich typer")
    sys.exit(1)

# Initialize
app = typer.Typer(help="Cursor IDE Version Sync Tool")
console = Console()

# Constants
GITHUB_RAW_URL = "https://raw.githubusercontent.com/oslook/cursor-ai-downloads/main/version-history.json"
PROJECT_ROOT = Path(__file__).parent.parent.parent
LOCAL_VERSION_HISTORY = PROJECT_ROOT / "docs" / "cursor-version-history.json"
NIX_VERSIONS_FILE = PROJECT_ROOT / "cursor-versions.nix"
CACHE_DIR = PROJECT_ROOT / ".cache" / "cursor-downloads"


def fetch_github_versions() -> dict:
    """Fetch version history from GitHub."""
    console.print("[cyan]Fetching versions from GitHub...[/cyan]")
    try:
        with httpx.Client(timeout=30) as client:
            response = client.get(GITHUB_RAW_URL)
            response.raise_for_status()
            return response.json()
    except Exception as e:
        console.print(f"[red]Failed to fetch GitHub versions: {e}[/red]")
        raise


def load_local_versions() -> dict:
    """Load local version history."""
    if LOCAL_VERSION_HISTORY.exists():
        with open(LOCAL_VERSION_HISTORY) as f:
            return json.load(f)
    return {"versions": []}


def compare_versions(github: dict, local: dict) -> list[dict]:
    """Find versions in GitHub that aren't in local."""
    local_versions = {v["version"] for v in local.get("versions", [])}
    github_versions = github.get("versions", [])
    
    new_versions = []
    for v in github_versions:
        if v["version"] not in local_versions:
            new_versions.append(v)
    
    return new_versions


def download_and_hash(url: str, version: str, platform: str) -> Optional[str]:
    """Download file and compute SHA256 hash."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    
    # Determine filename
    filename = url.split("/")[-1]
    cache_path = CACHE_DIR / filename
    
    # Skip if already cached
    if cache_path.exists():
        console.print(f"  [dim]Using cached: {filename}[/dim]")
        with open(cache_path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    
    try:
        with httpx.Client(timeout=300, follow_redirects=True) as client:
            with client.stream("GET", url) as response:
                response.raise_for_status()
                total = int(response.headers.get("content-length", 0))
                
                with Progress(
                    SpinnerColumn(),
                    TextColumn(f"[cyan]{version} {platform}[/cyan]"),
                    BarColumn(),
                    DownloadColumn(),
                    console=console
                ) as progress:
                    task = progress.add_task("Downloading", total=total)
                    
                    sha256 = hashlib.sha256()
                    with open(cache_path, "wb") as f:
                        for chunk in response.iter_bytes(8192):
                            f.write(chunk)
                            sha256.update(chunk)
                            progress.advance(task, len(chunk))
                    
                    return sha256.hexdigest()
    except Exception as e:
        console.print(f"  [red]Failed to download {platform}: {e}[/red]")
        if cache_path.exists():
            cache_path.unlink()
        return None


def update_local_version_history(github_versions: dict):
    """Update local version-history.json with GitHub data."""
    LOCAL_VERSION_HISTORY.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCAL_VERSION_HISTORY, "w") as f:
        json.dump(github_versions, f, indent=2)
    console.print(f"[green]✓ Updated {LOCAL_VERSION_HISTORY}[/green]")


def version_to_nix_name(version: str) -> str:
    """Convert version like 2.3.10 to cursor-2_3_10."""
    return f"cursor-{version.replace('.', '_')}"


def generate_nix_version_entry(version: str, linux_x64_hash: str, url: str) -> str:
    """Generate a Nix attribute set for a version."""
    return f'''
  {version_to_nix_name(version)} = callPackage ./cursor {{
    version = "{version}";
    hash = "sha256-{linux_x64_hash}";
    srcUrl = "{url}";
    binaryName = "cursor-{version}";
    shareDirName = "cursor-{version}";
  }};'''


def update_nix_file(new_versions: list[dict], hashes: dict[str, str]):
    """Update cursor-versions.nix with new versions."""
    if not NIX_VERSIONS_FILE.exists():
        console.print(f"[red]Nix file not found: {NIX_VERSIONS_FILE}[/red]")
        return False
    
    content = NIX_VERSIONS_FILE.read_text()
    
    # Find the insertion point (after the opening brace of the let block)
    # We'll add new versions at the beginning of the version list
    
    new_entries = []
    for v in new_versions:
        version = v["version"]
        url = v["platforms"].get("linux-x64")
        if url and version in hashes:
            entry = generate_nix_version_entry(version, hashes[version], url)
            new_entries.append(entry)
    
    if not new_entries:
        console.print("[yellow]No new entries to add to Nix file[/yellow]")
        return False
    
    # Find where to insert (after "in {" line)
    # Look for the pattern where versions are defined
    # Insert new versions at a logical location
    
    console.print(f"[yellow]⚠ Manual update required for {NIX_VERSIONS_FILE}[/yellow]")
    console.print("[dim]Add these entries to cursor-versions.nix:[/dim]")
    for entry in new_entries:
        console.print(entry)
    
    return True


def run_git_command(args: list[str], cwd: Path = PROJECT_ROOT) -> tuple[int, str]:
    """Run a git command and return exit code and output."""
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        capture_output=True,
        text=True
    )
    return result.returncode, result.stdout + result.stderr


@app.command()
def check():
    """Check for new Cursor versions (dry run)."""
    github = fetch_github_versions()
    local = load_local_versions()
    new_versions = compare_versions(github, local)
    
    if not new_versions:
        console.print("[green]✓ Local versions are up to date![/green]")
        return
    
    table = Table(title=f"[bold]Found {len(new_versions)} New Version(s)[/bold]")
    table.add_column("Version", style="cyan")
    table.add_column("Date", style="yellow")
    table.add_column("Linux x64 URL", style="dim")
    
    for v in new_versions:
        table.add_row(
            v["version"],
            v["date"],
            v["platforms"].get("linux-x64", "N/A")[:60] + "..."
        )
    
    console.print(table)
    console.print("\n[dim]Run with --sync to download and hash these versions[/dim]")


@app.command()
def sync(
    platforms: str = typer.Option(
        "linux-x64",
        help="Comma-separated platforms to hash (linux-x64,linux-arm64)"
    )
):
    """Download new versions and compute hashes."""
    github = fetch_github_versions()
    local = load_local_versions()
    new_versions = compare_versions(github, local)
    
    if not new_versions:
        console.print("[green]✓ Already up to date![/green]")
        return
    
    platform_list = [p.strip() for p in platforms.split(",")]
    hashes = {}
    
    console.print(f"\n[bold]Downloading {len(new_versions)} version(s)...[/bold]\n")
    
    for v in new_versions:
        version = v["version"]
        console.print(f"[cyan]Version {version}[/cyan] ({v['date']})")
        
        for platform in platform_list:
            url = v["platforms"].get(platform)
            if not url:
                console.print(f"  [yellow]No {platform} download available[/yellow]")
                continue
            
            hash_result = download_and_hash(url, version, platform)
            if hash_result:
                hashes[version] = hash_result
                console.print(f"  [green]✓ {platform}:[/green] sha256-{hash_result}")
    
    # Update local version history
    update_local_version_history(github)
    
    # Show Nix update instructions
    if hashes:
        update_nix_file(new_versions, hashes)
    
    return hashes


@app.command()
def auto(
    commit_message: str = typer.Option(
        None,
        help="Custom commit message (default: auto-generated)"
    ),
    push: bool = typer.Option(
        True,
        help="Push changes after committing"
    )
):
    """Full automation: sync, update, commit, and push."""
    # First sync
    github = fetch_github_versions()
    local = load_local_versions()
    new_versions = compare_versions(github, local)
    
    if not new_versions:
        console.print("[green]✓ Already up to date![/green]")
        return
    
    # Download and hash
    hashes = {}
    console.print(f"\n[bold]Syncing {len(new_versions)} new version(s)...[/bold]\n")
    
    for v in new_versions:
        version = v["version"]
        url = v["platforms"].get("linux-x64")
        if url:
            hash_result = download_and_hash(url, version, "linux-x64")
            if hash_result:
                hashes[version] = hash_result
    
    # Update local JSON
    update_local_version_history(github)
    
    # Generate commit message
    version_list = ", ".join([v["version"] for v in new_versions[:5]])
    if len(new_versions) > 5:
        version_list += f" (+{len(new_versions) - 5} more)"
    
    if not commit_message:
        commit_message = f"chore: add Cursor versions {version_list}"
    
    # Show what needs manual update
    if hashes:
        console.print("\n[bold yellow]═══ Manual Nix Updates Required ═══[/bold yellow]\n")
        for v in new_versions:
            version = v["version"]
            if version in hashes:
                url = v["platforms"].get("linux-x64")
                console.print(f"[cyan]{version_to_nix_name(version)}[/cyan] = callPackage ./cursor {{")
                console.print(f'  version = "{version}";')
                console.print(f'  hash = "sha256-{hashes[version]}";')
                console.print(f'  srcUrl = "{url}";')
                console.print(f'  binaryName = "cursor-{version}";')
                console.print(f'  shareDirName = "cursor-{version}";')
                console.print("};")
                console.print("")
    
    # Git operations
    console.print("\n[bold]Git Operations:[/bold]")
    
    # Check for changes
    code, _ = run_git_command(["status", "--porcelain"])
    if code != 0:
        console.print("[red]Git status failed[/red]")
        return
    
    # Stage changes
    code, output = run_git_command(["add", str(LOCAL_VERSION_HISTORY)])
    if code == 0:
        console.print(f"[green]✓ Staged {LOCAL_VERSION_HISTORY.name}[/green]")
    else:
        console.print(f"[red]Failed to stage: {output}[/red]")
        return
    
    # Commit
    code, output = run_git_command(["commit", "-m", commit_message])
    if code == 0:
        console.print(f"[green]✓ Committed: {commit_message}[/green]")
    else:
        console.print(f"[yellow]Commit skipped (no changes or error): {output}[/yellow]")
    
    # Push
    if push:
        code, output = run_git_command(["push"])
        if code == 0:
            console.print("[green]✓ Pushed to remote[/green]")
        else:
            console.print(f"[yellow]Push failed: {output}[/yellow]")
    
    console.print("\n[bold green]✓ Sync complete![/bold green]")


@app.command()
def clean_cache():
    """Remove cached downloads."""
    if CACHE_DIR.exists():
        import shutil
        shutil.rmtree(CACHE_DIR)
        console.print(f"[green]✓ Removed cache directory: {CACHE_DIR}[/green]")
    else:
        console.print("[dim]No cache to clean[/dim]")


@app.command()
def hash_url(url: str = typer.Argument(..., help="URL to download and hash")):
    """Download a single URL and compute its hash."""
    console.print(f"[cyan]Downloading: {url}[/cyan]")
    
    with tempfile.NamedTemporaryFile(delete=True) as tmp:
        try:
            with httpx.Client(timeout=300, follow_redirects=True) as client:
                with client.stream("GET", url) as response:
                    response.raise_for_status()
                    total = int(response.headers.get("content-length", 0))
                    
                    with Progress(
                        SpinnerColumn(),
                        BarColumn(),
                        DownloadColumn(),
                        console=console
                    ) as progress:
                        task = progress.add_task("Downloading", total=total)
                        
                        sha256 = hashlib.sha256()
                        for chunk in response.iter_bytes(8192):
                            tmp.write(chunk)
                            sha256.update(chunk)
                            progress.advance(task, len(chunk))
                        
                        hash_result = sha256.hexdigest()
                        console.print(f"\n[green]SHA256:[/green] {hash_result}")
                        console.print(f"[green]Nix format:[/green] sha256-{hash_result}")
                        
                        # Also compute SRI format
                        import base64
                        sri = base64.b64encode(bytes.fromhex(hash_result)).decode()
                        console.print(f"[green]SRI format:[/green] sha256-{sri}")
        except Exception as e:
            console.print(f"[red]Error: {e}[/red]")


if __name__ == "__main__":
    app()

