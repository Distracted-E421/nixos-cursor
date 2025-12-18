#!/usr/bin/env python3
"""
Cursor API Payload Analyzer

Deep analysis of captured payloads for Protobuf reverse engineering.
Focuses on identifying unique message structures and field patterns.

Usage:
    python analyze_payloads.py                    # Full analysis
    python analyze_payloads.py --service AiService    # Analyze specific service
    python analyze_payloads.py --dedupe           # Show unique payloads only
    python analyze_payloads.py --fields           # Analyze field patterns
    python analyze_payloads.py --export-proto     # Generate proto hints
"""

import argparse
import json
import os
import struct
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Any, Optional, Set, Tuple
import hashlib

SCRIPT_DIR = Path(__file__).parent
PAYLOAD_DB = SCRIPT_DIR / "payload-db"

# Services we care about for AI streaming
HIGH_PRIORITY_SERVICES = {
    "aiserver.v1.AiService",
    "aiserver.v1.ChatService", 
    "aiserver.v1.BackgroundComposerService",
    "aiserver.v1.FastApplyService",
}

# Endpoints we care about
HIGH_PRIORITY_ENDPOINTS = {
    "StreamUnifiedChatWithTools",
    "StreamSpeculativeSummaries",
    "CheckQueuePosition",
    "PotentiallyGenerateMemory",
    "AvailableModels",
    "GetDefaultModelNudgeData",
    "NameTab",
    "ReportEditFate",
    "ListBackgroundComposers",
}

# Noise services to filter out
NOISE_SERVICES = {
    "aiserver.v1.AnalyticsService",
    "tev1",
    "api",
}


def load_all_metadata(version: str = None) -> List[Dict]:
    """Load all metadata files."""
    metadata = []
    
    if version:
        versions = [f"v{version}"] if not version.startswith("v") else [version]
    else:
        versions = sorted([d.name for d in PAYLOAD_DB.iterdir() if d.is_dir() and d.name.startswith("v")])
    
    for v in versions:
        metadata_dir = PAYLOAD_DB / v / "metadata"
        if not metadata_dir.exists():
            continue
        
        for f in sorted(metadata_dir.glob("*.json")):
            if f.name.startswith("session_"):
                continue
            try:
                with open(f) as fh:
                    data = json.load(fh)
                    data["_file"] = str(f)
                    data["_version"] = v
                    metadata.append(data)
            except Exception as e:
                pass
    
    return metadata


def get_unique_by_hash(metadata: List[Dict]) -> Dict[str, Dict]:
    """Deduplicate payloads by content hash."""
    unique = {}
    for m in metadata:
        h = m.get("content_hash_sha256", "")
        if h and h not in unique:
            unique[h] = m
    return unique


def analyze_field_patterns(metadata: List[Dict]) -> Dict[str, Dict]:
    """
    Analyze Protobuf field patterns across payloads.
    Groups by service/endpoint and identifies common field structures.
    """
    patterns = defaultdict(lambda: {
        "field_numbers": defaultdict(int),
        "wire_types": defaultdict(int),
        "string_fields": defaultdict(set),
        "sample_count": 0,
        "unique_structures": set(),
    })
    
    for m in metadata:
        service = m.get("service", "unknown")
        endpoint = m.get("endpoint", "unknown")
        key = f"{service}/{endpoint}"
        
        patterns[key]["sample_count"] += 1
        
        # Analyze gRPC messages
        for msg in m.get("grpc_messages", []):
            if msg.get("type") != "message":
                continue
            
            # Track field structure
            fields = msg.get("field_hints", [])
            field_sig = tuple(
                (f.get("field_number"), f.get("wire_type"))
                for f in fields[:20]  # First 20 fields as signature
            )
            patterns[key]["unique_structures"].add(field_sig)
            
            for field in fields:
                fn = field.get("field_number")
                wt = field.get("wire_type_name", "unknown")
                
                if fn is not None:
                    patterns[key]["field_numbers"][fn] += 1
                    patterns[key]["wire_types"][f"{fn}:{wt}"] += 1
                
                # Track string values
                if "value_string" in field and fn is not None:
                    val = field["value_string"]
                    if len(val) < 100:  # Only short strings
                        patterns[key]["string_fields"][fn].add(val[:50])
    
    # Convert sets to lists for JSON serialization
    result = {}
    for key, data in patterns.items():
        result[key] = {
            "sample_count": data["sample_count"],
            "unique_structures": len(data["unique_structures"]),
            "field_numbers": dict(data["field_numbers"]),
            "wire_types": dict(data["wire_types"]),
            "string_samples": {
                k: list(v)[:5]  # Top 5 samples per field
                for k, v in data["string_fields"].items()
            },
        }
    
    return result


def generate_proto_hints(patterns: Dict[str, Dict]) -> str:
    """Generate .proto file hints based on observed patterns."""
    output = []
    output.append("// Auto-generated Protobuf hints from captured traffic")
    output.append("// Cursor version: 2.0.77")
    output.append("// This is NOT a complete schema - just observed fields")
    output.append("")
    output.append('syntax = "proto3";')
    output.append("")
    output.append("package aiserver.v1;")
    output.append("")
    
    wire_type_map = {
        "varint": "int64",  # Could be int32, int64, uint32, uint64, bool, enum
        "64-bit": "fixed64",  # Could be fixed64, sfixed64, double
        "length-delimited": "bytes",  # Could be string, bytes, embedded message
        "32-bit": "fixed32",  # Could be fixed32, sfixed32, float
    }
    
    for endpoint, data in sorted(patterns.items()):
        if data["sample_count"] < 5:
            continue
        
        service, method = endpoint.split("/") if "/" in endpoint else ("Unknown", endpoint)
        
        # Create message name from method
        msg_name = f"{method}Request"
        
        output.append(f"// Service: {service}")
        output.append(f"// Method: {method}")
        output.append(f"// Samples: {data['sample_count']}, Unique structures: {data['unique_structures']}")
        output.append(f"message {msg_name} {{")
        
        # Group by field number
        fields_seen = set()
        for wt_key, count in sorted(data["wire_types"].items(), key=lambda x: -x[1]):
            parts = wt_key.split(":")
            if len(parts) != 2:
                continue
            fn, wt = int(parts[0]), parts[1]
            
            if fn in fields_seen:
                continue
            fields_seen.add(fn)
            
            proto_type = wire_type_map.get(wt, "bytes")
            
            # Add string samples as comments
            samples = data.get("string_samples", {}).get(fn, [])
            sample_comment = ""
            if samples:
                sample_comment = f"  // samples: {samples[:3]}"
            
            output.append(f"  {proto_type} field_{fn} = {fn};{sample_comment}")
        
        output.append("}")
        output.append("")
    
    return "\n".join(output)


def analyze_endpoint_detail(metadata: List[Dict], endpoint: str) -> Dict:
    """Deep analysis of a specific endpoint."""
    filtered = [m for m in metadata if m.get("endpoint") == endpoint]
    
    if not filtered:
        return {"error": f"No payloads found for endpoint: {endpoint}"}
    
    unique = get_unique_by_hash(filtered)
    
    # Analyze all unique payloads
    analysis = {
        "endpoint": endpoint,
        "total_samples": len(filtered),
        "unique_payloads": len(unique),
        "size_range": {
            "min": min(m.get("content_length", 0) for m in filtered),
            "max": max(m.get("content_length", 0) for m in filtered),
            "avg": sum(m.get("content_length", 0) for m in filtered) / len(filtered),
        },
        "unique_samples": [],
    }
    
    # Get details of unique samples
    for h, m in list(unique.items())[:10]:  # Top 10 unique
        sample = {
            "hash": h[:16],
            "size": m.get("content_length", 0),
            "printable_strings": [],
            "field_structure": [],
        }
        
        for msg in m.get("grpc_messages", []):
            sample["printable_strings"].extend(msg.get("printable_strings", [])[:10])
            for field in msg.get("field_hints", [])[:15]:
                sample["field_structure"].append({
                    "num": field.get("field_number"),
                    "type": field.get("wire_type_name"),
                    "value": field.get("value_string", field.get("value", ""))[:50] if field.get("value_string") or field.get("value") else None,
                })
        
        analysis["unique_samples"].append(sample)
    
    return analysis


def print_priority_analysis(metadata: List[Dict]):
    """Print analysis focused on high-priority endpoints."""
    print("=" * 70)
    print("🎯 HIGH-PRIORITY ENDPOINT ANALYSIS")
    print("=" * 70)
    
    # Group by service
    by_service = defaultdict(list)
    for m in metadata:
        service = m.get("service", "unknown")
        by_service[service].append(m)
    
    # Analyze high-priority services
    for service in HIGH_PRIORITY_SERVICES:
        if service not in by_service:
            print(f"\n⚠️  {service}: NO DATA CAPTURED")
            continue
        
        payloads = by_service[service]
        unique = get_unique_by_hash(payloads)
        
        print(f"\n🟢 {service}")
        print(f"   Total: {len(payloads)}, Unique: {len(unique)}")
        
        # Group by endpoint
        by_endpoint = defaultdict(list)
        for m in payloads:
            by_endpoint[m.get("endpoint", "unknown")].append(m)
        
        for ep, ep_payloads in sorted(by_endpoint.items(), key=lambda x: -len(x[1])):
            ep_unique = len(get_unique_by_hash(ep_payloads))
            priority = "🎯" if ep in HIGH_PRIORITY_ENDPOINTS else "  "
            print(f"   {priority} {ep}: {len(ep_payloads)} ({ep_unique} unique)")
    
    # Show noise stats
    noise_count = sum(len(by_service.get(s, [])) for s in NOISE_SERVICES)
    print(f"\n🔴 NOISE (filtered out): {noise_count} payloads ({noise_count*100//len(metadata)}%)")


def print_schema_reconstruction(metadata: List[Dict]):
    """Attempt to reconstruct Protobuf schemas from captured data."""
    print("=" * 70)
    print("📋 PROTOBUF SCHEMA RECONSTRUCTION")
    print("=" * 70)
    
    # Filter to high-priority only
    filtered = [
        m for m in metadata 
        if m.get("service") in HIGH_PRIORITY_SERVICES
    ]
    
    patterns = analyze_field_patterns(filtered)
    
    for endpoint, data in sorted(patterns.items(), key=lambda x: -x[1]["sample_count"]):
        if data["sample_count"] < 10:
            continue
        
        print(f"\n📦 {endpoint}")
        print(f"   Samples: {data['sample_count']}, Structures: {data['unique_structures']}")
        
        # Show field patterns
        print("   Fields:")
        for wt_key, count in sorted(data["wire_types"].items(), key=lambda x: -x[1])[:10]:
            parts = wt_key.split(":")
            if len(parts) != 2:
                continue
            fn, wt = parts
            
            samples = data.get("string_samples", {}).get(int(fn), [])
            sample_str = f" → {samples[:2]}" if samples else ""
            print(f"      #{fn} ({wt}): seen {count}x{sample_str}")


def main():
    parser = argparse.ArgumentParser(description="Analyze Cursor API payloads")
    parser.add_argument("--version", "-v", type=str, default="2.0.77", help="Cursor version to analyze")
    parser.add_argument("--service", "-s", type=str, help="Filter by service")
    parser.add_argument("--endpoint", "-e", type=str, help="Deep analyze specific endpoint")
    parser.add_argument("--dedupe", "-d", action="store_true", help="Show deduplicated stats")
    parser.add_argument("--fields", "-f", action="store_true", help="Analyze field patterns")
    parser.add_argument("--priority", "-p", action="store_true", help="Focus on high-priority endpoints")
    parser.add_argument("--schema", action="store_true", help="Reconstruct proto schemas")
    parser.add_argument("--export-proto", type=str, metavar="FILE", help="Export proto hints to file")
    parser.add_argument("--json", "-j", action="store_true", help="Output as JSON")
    
    args = parser.parse_args()
    
    print(f"Loading payloads for v{args.version}...")
    metadata = load_all_metadata(args.version)
    print(f"Loaded {len(metadata)} payloads")
    
    if args.service:
        metadata = [m for m in metadata if args.service.lower() in m.get("service", "").lower()]
        print(f"Filtered to {len(metadata)} for service '{args.service}'")
    
    if args.endpoint:
        analysis = analyze_endpoint_detail(metadata, args.endpoint)
        if args.json:
            print(json.dumps(analysis, indent=2, default=str))
        else:
            print(json.dumps(analysis, indent=2, default=str))
        return
    
    if args.dedupe:
        unique = get_unique_by_hash(metadata)
        print(f"\nUnique payloads: {len(unique)} (from {len(metadata)} total)")
        
        # Show unique by service
        by_service = defaultdict(set)
        for h, m in unique.items():
            by_service[m.get("service", "unknown")].add(h)
        
        print("\nUnique by service:")
        for service, hashes in sorted(by_service.items(), key=lambda x: -len(x[1])):
            print(f"  {service}: {len(hashes)}")
        return
    
    if args.fields:
        patterns = analyze_field_patterns(metadata)
        if args.json:
            print(json.dumps(patterns, indent=2, default=str))
        else:
            for ep, data in sorted(patterns.items(), key=lambda x: -x[1]["sample_count"])[:20]:
                print(f"\n{ep}: {data['sample_count']} samples, {data['unique_structures']} structures")
        return
    
    if args.priority:
        print_priority_analysis(metadata)
        return
    
    if args.schema:
        print_schema_reconstruction(metadata)
        return
    
    if args.export_proto:
        # Filter to important services only
        filtered = [m for m in metadata if m.get("service") not in NOISE_SERVICES]
        patterns = analyze_field_patterns(filtered)
        proto = generate_proto_hints(patterns)
        
        with open(args.export_proto, "w") as f:
            f.write(proto)
        print(f"Exported proto hints to {args.export_proto}")
        return
    
    # Default: priority analysis
    print_priority_analysis(metadata)


if __name__ == "__main__":
    main()

