#!/usr/bin/env python3
"""
Protobuf Wire Format Decoder

Decodes raw Protobuf payloads from Cursor API captures.
Handles Connect protocol framing.

Usage:
    python decode_protobuf.py <payload_file.bin>
    python decode_protobuf.py --hex "0a0b68656c6c6f"
    python decode_protobuf.py --endpoint CheckQueuePosition
"""

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from dataclasses import dataclass, field
from collections import defaultdict

@dataclass
class ProtoField:
    """Represents a decoded Protobuf field."""
    number: int
    wire_type: int
    wire_type_name: str
    value: Any
    raw_bytes: bytes
    children: List['ProtoField'] = field(default_factory=list)
    
    def to_dict(self) -> dict:
        d = {
            "field": self.number,
            "type": self.wire_type_name,
            "value": self.value if not isinstance(self.value, bytes) else self.value.hex(),
        }
        if self.children:
            d["children"] = [c.to_dict() for c in self.children]
        return d


def read_varint(data: bytes, offset: int) -> Tuple[int, int]:
    """Read a varint from data at offset. Returns (value, new_offset)."""
    value = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        value |= (byte & 0x7F) << shift
        offset += 1
        if not (byte & 0x80):
            break
        shift += 7
        if shift > 63:
            raise ValueError("Varint too long")
    return value, offset


def decode_protobuf(data: bytes, depth: int = 0, max_depth: int = 10) -> List[ProtoField]:
    """
    Decode raw Protobuf wire format.
    
    Returns list of decoded fields.
    """
    if depth > max_depth:
        return []
    
    fields = []
    offset = 0
    
    while offset < len(data):
        try:
            # Read field tag
            tag, offset = read_varint(data, offset)
            wire_type = tag & 0x07
            field_number = tag >> 3
            
            if field_number == 0:
                # Invalid field number, might be raw data
                break
            
            wire_type_names = {
                0: "varint",
                1: "fixed64",
                2: "length_delimited",
                5: "fixed32",
            }
            wire_name = wire_type_names.get(wire_type, f"unknown({wire_type})")
            
            if wire_type == 0:  # Varint
                value, offset = read_varint(data, offset)
                fields.append(ProtoField(
                    number=field_number,
                    wire_type=wire_type,
                    wire_type_name=wire_name,
                    value=value,
                    raw_bytes=b'',
                ))
                
            elif wire_type == 1:  # 64-bit
                if offset + 8 > len(data):
                    break
                value = data[offset:offset+8]
                offset += 8
                # Try to decode as double
                try:
                    double_val = struct.unpack('<d', value)[0]
                    display_val = f"double:{double_val}" if abs(double_val) < 1e10 else value.hex()
                except:
                    display_val = value.hex()
                fields.append(ProtoField(
                    number=field_number,
                    wire_type=wire_type,
                    wire_type_name=wire_name,
                    value=display_val,
                    raw_bytes=value,
                ))
                
            elif wire_type == 2:  # Length-delimited
                length, offset = read_varint(data, offset)
                if offset + length > len(data):
                    # Incomplete data
                    break
                content = data[offset:offset+length]
                offset += length
                
                # Try to decode as string
                value = None
                children = []
                
                try:
                    decoded = content.decode('utf-8')
                    if all(c.isprintable() or c in '\n\r\t' for c in decoded):
                        value = decoded
                except:
                    pass
                
                if value is None:
                    # Try to decode as nested message
                    try:
                        children = decode_protobuf(content, depth + 1, max_depth)
                        if children:
                            value = f"<nested message with {len(children)} fields>"
                        else:
                            value = content  # Raw bytes
                    except:
                        value = content  # Raw bytes
                
                fields.append(ProtoField(
                    number=field_number,
                    wire_type=wire_type,
                    wire_type_name=wire_name,
                    value=value,
                    raw_bytes=content,
                    children=children,
                ))
                
            elif wire_type == 5:  # 32-bit
                if offset + 4 > len(data):
                    break
                value = data[offset:offset+4]
                offset += 4
                # Try to decode as float
                try:
                    float_val = struct.unpack('<f', value)[0]
                    display_val = f"float:{float_val}" if abs(float_val) < 1e10 else value.hex()
                except:
                    display_val = value.hex()
                fields.append(ProtoField(
                    number=field_number,
                    wire_type=wire_type,
                    wire_type_name=wire_name,
                    value=display_val,
                    raw_bytes=value,
                ))
                
            else:
                # Unknown wire type - might indicate corrupt data or wrong offset
                break
                
        except Exception as e:
            # Stop on any error
            break
    
    return fields


def print_fields(fields: List[ProtoField], indent: int = 0):
    """Pretty print decoded fields."""
    prefix = "  " * indent
    for f in fields:
        val_str = str(f.value)
        if len(val_str) > 100:
            val_str = val_str[:100] + "..."
        
        print(f"{prefix}#{f.number} ({f.wire_type_name}): {val_str}")
        
        if f.children:
            print_fields(f.children, indent + 1)


def analyze_endpoint_samples(endpoint: str, limit: int = 5):
    """Analyze samples for a specific endpoint."""
    db_path = Path(__file__).parent / "payload-db"
    
    # Find samples
    samples = []
    for version_dir in db_path.iterdir():
        if not version_dir.is_dir():
            continue
        
        requests_dir = version_dir / "requests"
        metadata_dir = version_dir / "metadata"
        
        if not requests_dir.exists():
            continue
        
        for bin_file in requests_dir.glob(f"*{endpoint}*.bin"):
            json_file = metadata_dir / (bin_file.stem + ".json")
            if json_file.exists():
                samples.append((bin_file, json_file))
    
    if not samples:
        print(f"No samples found for endpoint: {endpoint}")
        return
    
    print(f"Found {len(samples)} samples for {endpoint}")
    print("=" * 60)
    
    # Analyze unique structures
    structures = defaultdict(list)
    
    for bin_file, json_file in samples[:limit * 10]:  # Check more to find unique
        with open(bin_file, 'rb') as f:
            data = f.read()
        
        fields = decode_protobuf(data)
        
        # Create structure signature
        sig = tuple((f.number, f.wire_type) for f in fields[:10])
        structures[sig].append((bin_file, json_file, fields, data))
    
    print(f"Found {len(structures)} unique structures\n")
    
    for i, (sig, samples_list) in enumerate(list(structures.items())[:limit]):
        bin_file, json_file, fields, data = samples_list[0]
        
        print(f"--- Structure {i+1} ({len(samples_list)} samples) ---")
        print(f"Size: {len(data)} bytes")
        print(f"Fields:")
        print_fields(fields)
        print()


def main():
    parser = argparse.ArgumentParser(description="Decode Protobuf payloads")
    parser.add_argument("file", nargs="?", help="Binary payload file to decode")
    parser.add_argument("--hex", type=str, help="Hex string to decode")
    parser.add_argument("--endpoint", "-e", type=str, help="Analyze samples for endpoint")
    parser.add_argument("--json", "-j", action="store_true", help="Output as JSON")
    parser.add_argument("--limit", "-l", type=int, default=5, help="Limit samples to analyze")
    
    args = parser.parse_args()
    
    if args.endpoint:
        analyze_endpoint_samples(args.endpoint, args.limit)
        return
    
    if args.hex:
        data = bytes.fromhex(args.hex)
    elif args.file:
        with open(args.file, 'rb') as f:
            data = f.read()
    else:
        parser.print_help()
        return
    
    print(f"Decoding {len(data)} bytes...")
    print()
    
    fields = decode_protobuf(data)
    
    if args.json:
        print(json.dumps([f.to_dict() for f in fields], indent=2))
    else:
        print_fields(fields)


if __name__ == "__main__":
    main()

