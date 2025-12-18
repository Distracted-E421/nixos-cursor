#!/usr/bin/env python3
"""
Deep decoder for PotentiallyGenerateMemory payload.

This is the crown jewel - contains full conversation context!
"""

import sys
import json
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from dataclasses import dataclass, field

@dataclass
class DecodedField:
    number: int
    wire_type: int
    value: Any
    raw_length: int
    children: List['DecodedField'] = field(default_factory=list)

def read_varint(data: bytes, offset: int) -> Tuple[int, int]:
    """Read varint, return (value, new_offset)."""
    value = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        value |= (byte & 0x7F) << shift
        offset += 1
        if not (byte & 0x80):
            break
        shift += 7
    return value, offset

def decode_field(data: bytes, offset: int, depth: int = 0) -> Tuple[Optional[DecodedField], int]:
    """Decode a single protobuf field."""
    if offset >= len(data):
        return None, offset
    
    start_offset = offset
    tag, offset = read_varint(data, offset)
    wire_type = tag & 0x07
    field_num = tag >> 3
    
    if field_num == 0 or field_num > 536870911:  # Invalid field number
        return None, start_offset
    
    if wire_type == 0:  # Varint
        value, offset = read_varint(data, offset)
        return DecodedField(field_num, wire_type, value, offset - start_offset), offset
    
    elif wire_type == 1:  # 64-bit
        if offset + 8 > len(data):
            return None, start_offset
        value = int.from_bytes(data[offset:offset+8], 'little')
        return DecodedField(field_num, wire_type, value, 8), offset + 8
    
    elif wire_type == 2:  # Length-delimited
        length, offset = read_varint(data, offset)
        if offset + length > len(data):
            return None, start_offset
        content = data[offset:offset+length]
        offset += length
        
        # Try to decode as UTF-8 string
        try:
            decoded = content.decode('utf-8')
            # Check if it's printable
            if all(c.isprintable() or c in '\n\r\t ' for c in decoded):
                return DecodedField(field_num, wire_type, decoded, len(content)), offset
        except:
            pass
        
        # Try to decode as nested message
        children = decode_message(content, depth + 1)
        if children:
            return DecodedField(field_num, wire_type, f"<message:{len(children)} fields>", len(content), children), offset
        
        # Return as hex if small, truncated otherwise
        if len(content) <= 100:
            return DecodedField(field_num, wire_type, content.hex(), len(content)), offset
        else:
            return DecodedField(field_num, wire_type, f"<bytes:{len(content)}>", len(content)), offset
    
    elif wire_type == 5:  # 32-bit
        if offset + 4 > len(data):
            return None, start_offset
        value = int.from_bytes(data[offset:offset+4], 'little')
        return DecodedField(field_num, wire_type, value, 4), offset + 4
    
    return None, start_offset

def decode_message(data: bytes, depth: int = 0, max_depth: int = 15) -> List[DecodedField]:
    """Decode a protobuf message into fields."""
    if depth > max_depth:
        return []
    
    fields = []
    offset = 0
    
    while offset < len(data):
        field, new_offset = decode_field(data, offset, depth)
        if field is None or new_offset == offset:
            break
        fields.append(field)
        offset = new_offset
        
        if len(fields) > 500:  # Safety limit
            break
    
    return fields

def extract_conversation_structure(fields: List[DecodedField], depth: int = 0) -> Dict:
    """Extract meaningful structure from decoded fields."""
    result = {}
    
    for f in fields:
        key = f"field_{f.number}"
        
        if isinstance(f.value, str):
            if f.value.startswith("<message:"):
                # Recurse into nested message
                result[key] = extract_conversation_structure(f.children, depth + 1)
            else:
                # Check for meaningful content
                val = f.value
                if len(val) > 200:
                    val = val[:200] + f"... ({len(f.value)} chars)"
                result[key] = val
        else:
            result[key] = f.value
    
    return result

def analyze_memory_payload(filepath: Path):
    """Analyze a PotentiallyGenerateMemory payload."""
    data = filepath.read_bytes()
    print(f"Analyzing: {filepath}")
    print(f"Size: {len(data):,} bytes ({len(data)/1024/1024:.2f} MB)")
    print("=" * 70)
    
    fields = decode_message(data)
    
    print(f"\nTop-level fields: {len(fields)}")
    print("-" * 70)
    
    # Analyze top-level structure
    for f in fields:
        wire_names = {0: "varint", 1: "fixed64", 2: "len_del", 5: "fixed32"}
        wt = wire_names.get(f.wire_type, "?")
        
        if isinstance(f.value, str) and not f.value.startswith("<"):
            preview = f.value[:80] + "..." if len(f.value) > 80 else f.value
            print(f"#{f.number} ({wt}): \"{preview}\"")
        elif f.children:
            print(f"#{f.number} ({wt}): <nested message with {len(f.children)} fields>")
            # Show first few children
            for child in f.children[:5]:
                if isinstance(child.value, str) and not child.value.startswith("<"):
                    preview = child.value[:60] + "..." if len(child.value) > 60 else child.value
                    print(f"    #{child.number}: \"{preview}\"")
                elif child.children:
                    print(f"    #{child.number}: <nested: {len(child.children)} fields>")
                else:
                    print(f"    #{child.number}: {child.value}")
            if len(f.children) > 5:
                print(f"    ... and {len(f.children) - 5} more fields")
        else:
            print(f"#{f.number} ({wt}): {f.value}")
    
    # Deep dive into field 2 (the conversation data)
    print("\n" + "=" * 70)
    print("DEEP DIVE: Conversation Structure (Field 2)")
    print("=" * 70)
    
    for f in fields:
        if f.number == 2 and f.children:
            analyze_conversation_field(f.children)
            break

def analyze_conversation_field(fields: List[DecodedField], prefix: str = ""):
    """Analyze the conversation structure."""
    
    # Track what we find
    files_found = []
    messages_found = []
    tool_calls_found = []
    
    for f in fields:
        # Field 1 appears to be text/content
        if f.number == 1 and isinstance(f.value, str) and not f.value.startswith("<"):
            if f.value.startswith("@") or "/" in f.value:
                files_found.append(f.value[:100])
            elif len(f.value) > 50:
                messages_found.append(f.value[:100])
        
        # Field 3 often contains nested content
        if f.number == 3 and f.children:
            for child in f.children:
                if child.number == 1 and isinstance(child.value, str):
                    if "/" in child.value or child.value.endswith(('.py', '.sh', '.md', '.nix')):
                        files_found.append(child.value)
                    elif len(child.value) > 100:
                        messages_found.append(child.value[:150])
        
        # Look for tool calls
        if f.number == 18 and f.children:
            tool_calls_found.append(f.children)
    
    # Print findings
    if files_found:
        print(f"\n📁 FILES IN CONTEXT ({len(files_found)}):")
        for i, f in enumerate(files_found[:15]):
            print(f"   {i+1}. {f}")
        if len(files_found) > 15:
            print(f"   ... and {len(files_found) - 15} more")
    
    if messages_found:
        print(f"\n💬 MESSAGE SNIPPETS ({len(messages_found)}):")
        for i, m in enumerate(messages_found[:10]):
            preview = m.replace('\n', ' ')[:80]
            print(f"   {i+1}. {preview}...")
        if len(messages_found) > 10:
            print(f"   ... and {len(messages_found) - 10} more")
    
    if tool_calls_found:
        print(f"\n🔧 TOOL CALLS ({len(tool_calls_found)}):")
        for i, tc in enumerate(tool_calls_found[:5]):
            # Try to find tool name
            for child in tc:
                if child.number == 2 and isinstance(child.value, str):
                    print(f"   {i+1}. {child.value}")
                    break

def find_all_strings(fields: List[DecodedField], strings: List[str] = None, min_len: int = 50):
    """Recursively find all strings in the payload."""
    if strings is None:
        strings = []
    
    for f in fields:
        if isinstance(f.value, str) and not f.value.startswith("<"):
            if len(f.value) >= min_len:
                strings.append((f.number, f.value))
        if f.children:
            find_all_strings(f.children, strings, min_len)
    
    return strings

def main():
    if len(sys.argv) < 2:
        # Find a sample
        db_path = Path(__file__).parent / "payload-db"
        samples = list(db_path.glob("**/requests/*PotentiallyGenerateMemory*.bin"))
        if samples:
            filepath = samples[0]
            print(f"Using sample: {filepath}\n")
        else:
            print("Usage: python decode_memory_payload.py <payload.bin>")
            print("       Or run without args to use first sample from payload-db")
            sys.exit(1)
    else:
        filepath = Path(sys.argv[1])
    
    analyze_memory_payload(filepath)
    
    # Also extract all strings
    print("\n" + "=" * 70)
    print("ALL SIGNIFICANT STRINGS (>100 chars)")
    print("=" * 70)
    
    data = filepath.read_bytes()
    fields = decode_message(data)
    strings = find_all_strings(fields, min_len=100)
    
    # Deduplicate and sort by length
    seen = set()
    unique_strings = []
    for num, s in strings:
        if s not in seen:
            seen.add(s)
            unique_strings.append((num, s))
    
    unique_strings.sort(key=lambda x: -len(x[1]))
    
    print(f"\nFound {len(unique_strings)} unique strings")
    for i, (num, s) in enumerate(unique_strings[:20]):
        preview = s.replace('\n', '\\n')[:120]
        print(f"\n{i+1}. Field #{num} ({len(s)} chars):")
        print(f"   {preview}...")

if __name__ == "__main__":
    main()

