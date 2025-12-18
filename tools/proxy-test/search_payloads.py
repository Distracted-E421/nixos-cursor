#!/usr/bin/env python3
"""
Payload Database Search Tool

Search and analyze collected Cursor API payloads for reverse engineering.

Usage:
    python search_payloads.py --list                    # List all payloads
    python search_payloads.py --service ChatService     # Filter by service
    python search_payloads.py --endpoint StreamUnified  # Filter by endpoint
    python search_payloads.py --string "claude"         # Search for string in payloads
    python search_payloads.py --field 1                 # Show payloads with field number 1
    python search_payloads.py --stats                   # Show statistics
    python search_payloads.py --export                  # Export all metadata as single JSON
"""

import argparse
import json
import os
from pathlib import Path
from typing import List, Dict, Any, Optional
from collections import defaultdict
import sys

SCRIPT_DIR = Path(__file__).parent
PAYLOAD_DB = SCRIPT_DIR / "payload-db"


def get_all_versions() -> List[str]:
    """Get all collected versions."""
    if not PAYLOAD_DB.exists():
        return []
    return sorted([d.name for d in PAYLOAD_DB.iterdir() if d.is_dir() and d.name.startswith("v")])


def load_metadata(version: Optional[str] = None) -> List[Dict[str, Any]]:
    """Load all metadata files."""
    metadata = []
    
    versions = [version] if version else get_all_versions()
    
    for v in versions:
        metadata_dir = PAYLOAD_DB / v / "metadata"
        if not metadata_dir.exists():
            continue
        
        for f in metadata_dir.glob("*.json"):
            if f.name.startswith("session_"):
                continue  # Skip session summaries
            try:
                with open(f) as fh:
                    data = json.load(fh)
                    data["_file"] = str(f)
                    data["_version_dir"] = v
                    metadata.append(data)
            except Exception as e:
                print(f"Error loading {f}: {e}", file=sys.stderr)
    
    return metadata


def search_by_service(metadata: List[Dict], service: str) -> List[Dict]:
    """Filter payloads by service name."""
    return [m for m in metadata if service.lower() in m.get("service", "").lower()]


def search_by_endpoint(metadata: List[Dict], endpoint: str) -> List[Dict]:
    """Filter payloads by endpoint name."""
    return [m for m in metadata if endpoint.lower() in m.get("endpoint", "").lower()]


def search_by_string(metadata: List[Dict], search_string: str) -> List[Dict]:
    """Search for string in payload content."""
    results = []
    search_lower = search_string.lower()
    
    for m in metadata:
        found = False
        for msg in m.get("grpc_messages", []):
            # Check printable strings
            for s in msg.get("printable_strings", []):
                if search_lower in s.lower():
                    found = True
                    break
            # Check field string values
            for field in msg.get("field_hints", []):
                if search_lower in str(field.get("value_string", "")).lower():
                    found = True
                    break
            if found:
                break
        if found:
            results.append(m)
    
    return results


def search_by_field_number(metadata: List[Dict], field_num: int) -> List[Dict]:
    """Find payloads containing a specific field number."""
    results = []
    
    for m in metadata:
        for msg in m.get("grpc_messages", []):
            for field in msg.get("field_hints", []):
                if field.get("field_number") == field_num:
                    results.append(m)
                    break
    
    return results


def show_statistics(metadata: List[Dict]):
    """Show database statistics."""
    by_version = defaultdict(int)
    by_service = defaultdict(int)
    by_endpoint = defaultdict(int)
    by_direction = defaultdict(int)
    total_bytes = 0
    
    for m in metadata:
        by_version[m.get("cursor_version", "unknown")] += 1
        by_service[m.get("service", "unknown")] += 1
        by_endpoint[m.get("endpoint", "unknown")] += 1
        by_direction[m.get("direction", "unknown")] += 1
        total_bytes += m.get("content_length", 0)
    
    print("=" * 60)
    print("📊 PAYLOAD DATABASE STATISTICS")
    print("=" * 60)
    print(f"\nTotal payloads: {len(metadata)}")
    print(f"Total data: {total_bytes / 1024:.1f} KB")
    
    print(f"\nBy Cursor Version:")
    for v, count in sorted(by_version.items()):
        print(f"  {v}: {count}")
    
    print(f"\nBy Service:")
    for s, count in sorted(by_service.items(), key=lambda x: -x[1]):
        print(f"  {s}: {count}")
    
    print(f"\nBy Endpoint:")
    for e, count in sorted(by_endpoint.items(), key=lambda x: -x[1])[:20]:
        print(f"  {e}: {count}")
    if len(by_endpoint) > 20:
        print(f"  ... and {len(by_endpoint) - 20} more")
    
    print(f"\nBy Direction:")
    for d, count in sorted(by_direction.items()):
        print(f"  {d}: {count}")


def show_payload_detail(m: Dict):
    """Show detailed payload information."""
    print("-" * 60)
    print(f"📦 {m.get('filename', 'unknown')}")
    print(f"   Version: {m.get('cursor_version')}")
    print(f"   Time: {m.get('timestamp')}")
    print(f"   Direction: {m.get('direction')}")
    print(f"   Service: {m.get('service')}")
    print(f"   Endpoint: {m.get('endpoint')}")
    print(f"   Size: {m.get('content_length', 0)} bytes")
    print(f"   Hash: {m.get('content_hash_sha256', '')[:16]}...")
    
    messages = m.get("grpc_messages", [])
    if messages:
        print(f"   gRPC Messages: {len(messages)}")
        for i, msg in enumerate(messages[:3]):  # Show first 3
            print(f"   [{i}] Type: {msg.get('type')}, Length: {msg.get('length', 'N/A')}")
            
            strings = msg.get("printable_strings", [])
            if strings:
                print(f"       Strings: {strings[:5]}")
            
            fields = msg.get("field_hints", [])[:5]
            if fields:
                print(f"       Fields:")
                for f in fields:
                    val = f.get("value_string") or f.get("value") or f.get("value_hex", "")
                    if isinstance(val, str) and len(val) > 50:
                        val = val[:50] + "..."
                    print(f"         #{f.get('field_number')}: {f.get('wire_type_name')} = {val}")


def export_database(metadata: List[Dict], output_file: str):
    """Export all metadata as a single JSON file."""
    with open(output_file, "w") as f:
        json.dump(metadata, f, indent=2, default=str)
    print(f"Exported {len(metadata)} payloads to {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Search Cursor API payload database")
    parser.add_argument("--list", "-l", action="store_true", help="List all payloads")
    parser.add_argument("--service", "-s", type=str, help="Filter by service name")
    parser.add_argument("--endpoint", "-e", type=str, help="Filter by endpoint name")
    parser.add_argument("--string", "-t", type=str, help="Search for string in payloads")
    parser.add_argument("--field", "-f", type=int, help="Search for field number")
    parser.add_argument("--version", "-v", type=str, help="Filter by Cursor version (e.g., v2.0.77)")
    parser.add_argument("--stats", action="store_true", help="Show statistics")
    parser.add_argument("--export", type=str, metavar="FILE", help="Export all metadata to JSON file")
    parser.add_argument("--detail", "-d", action="store_true", help="Show detailed payload info")
    parser.add_argument("--limit", type=int, default=20, help="Limit results (default: 20)")
    
    args = parser.parse_args()
    
    # Load metadata
    version = args.version if args.version else None
    metadata = load_metadata(version)
    
    if not metadata:
        print("No payloads found. Run collect_payloads.sh to capture some!")
        return
    
    # Apply filters
    results = metadata
    
    if args.service:
        results = search_by_service(results, args.service)
    
    if args.endpoint:
        results = search_by_endpoint(results, args.endpoint)
    
    if args.string:
        results = search_by_string(results, args.string)
    
    if args.field:
        results = search_by_field_number(results, args.field)
    
    # Output
    if args.stats:
        show_statistics(results)
    elif args.export:
        export_database(results, args.export)
    elif args.list or args.detail:
        print(f"Found {len(results)} payloads")
        print()
        for m in results[:args.limit]:
            if args.detail:
                show_payload_detail(m)
            else:
                print(f"  {m.get('direction', '?')[:3]} {m.get('service', '')}/{m.get('endpoint', '')} ({m.get('content_length', 0)}b) - {m.get('cursor_version', '')}")
        if len(results) > args.limit:
            print(f"\n  ... and {len(results) - args.limit} more (use --limit to show more)")
    else:
        # Default: show stats
        show_statistics(results)


if __name__ == "__main__":
    main()

