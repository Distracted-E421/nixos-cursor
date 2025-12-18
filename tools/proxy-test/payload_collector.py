"""
Cursor API Payload Collector for Protobuf Reverse Engineering

This mitmproxy addon collects and catalogs all Cursor API payloads with metadata
for building a searchable database to reverse-engineer the Protobuf schema.

Usage:
    mitmdump -s payload_collector.py -p 8080 --ssl-insecure

Payloads are saved to: payload-db/v{VERSION}/
"""

import json
import os
import hashlib
import struct
import re
from datetime import datetime
from pathlib import Path
from mitmproxy import http, ctx
from typing import Optional, Dict, List, Any

# Configuration
CURSOR_VERSION = os.environ.get("CURSOR_VERSION", "2.0.77")
BASE_DIR = Path(__file__).parent / "payload-db" / f"v{CURSOR_VERSION}"
CURSOR_DOMAINS = ["cursor.sh", "cursor.com", "cursorapi.com"]

# Ensure directories exist
(BASE_DIR / "requests").mkdir(parents=True, exist_ok=True)
(BASE_DIR / "responses").mkdir(parents=True, exist_ok=True)
(BASE_DIR / "metadata").mkdir(parents=True, exist_ok=True)

# Statistics
stats = {
    "total_captured": 0,
    "by_service": {},
    "by_endpoint": {},
    "errors": [],
}


def is_cursor_domain(host: str) -> bool:
    """Check if host is a Cursor domain."""
    return any(d in host for d in CURSOR_DOMAINS)


def extract_service_endpoint(path: str) -> tuple[str, str]:
    """Extract service and endpoint from gRPC path like /aiserver.v1.ChatService/StreamUnifiedChatWithTools"""
    match = re.match(r'/([^/]+)/([^/?]+)', path)
    if match:
        return match.group(1), match.group(2)
    return "unknown", path


def decode_grpc_messages(data: bytes) -> List[Dict[str, Any]]:
    """
    Decode gRPC length-prefixed messages.
    
    gRPC format: [1 byte compressed flag][4 bytes big-endian length][payload]
    """
    messages = []
    offset = 0
    
    while offset < len(data):
        if offset + 5 > len(data):
            # Incomplete header, save remaining as raw
            messages.append({
                "type": "incomplete",
                "offset": offset,
                "raw_hex": data[offset:].hex(),
            })
            break
        
        compressed = data[offset]
        length = struct.unpack(">I", data[offset+1:offset+5])[0]
        offset += 5
        
        if offset + length > len(data):
            messages.append({
                "type": "truncated",
                "compressed": compressed,
                "expected_length": length,
                "actual_length": len(data) - offset,
                "raw_hex": data[offset:].hex(),
            })
            break
        
        payload = data[offset:offset+length]
        offset += length
        
        # Try to extract readable strings from the protobuf
        printable_strings = extract_printable_strings(payload)
        
        messages.append({
            "type": "message",
            "compressed": compressed,
            "length": length,
            "raw_hex": payload.hex(),
            "printable_strings": printable_strings,
            "field_hints": analyze_protobuf_fields(payload),
        })
    
    return messages


def extract_printable_strings(data: bytes, min_length: int = 4) -> List[str]:
    """Extract printable ASCII strings from binary data."""
    strings = []
    current = []
    
    for byte in data:
        if 32 <= byte <= 126:  # Printable ASCII
            current.append(chr(byte))
        else:
            if len(current) >= min_length:
                strings.append("".join(current))
            current = []
    
    if len(current) >= min_length:
        strings.append("".join(current))
    
    return strings


def analyze_protobuf_fields(data: bytes) -> List[Dict[str, Any]]:
    """
    Attempt to parse protobuf wire format to identify field numbers and types.
    
    Wire types:
    0 = Varint (int32, int64, uint32, uint64, sint32, sint64, bool, enum)
    1 = 64-bit (fixed64, sfixed64, double)
    2 = Length-delimited (string, bytes, embedded messages, packed repeated)
    5 = 32-bit (fixed32, sfixed32, float)
    """
    fields = []
    offset = 0
    
    try:
        while offset < len(data):
            if offset >= len(data):
                break
                
            # Read varint for field tag
            tag_byte = data[offset]
            wire_type = tag_byte & 0x07
            field_number = tag_byte >> 3
            offset += 1
            
            # Handle multi-byte varints for field number
            if tag_byte & 0x80:
                # Multi-byte varint, simplified handling
                while offset < len(data) and data[offset-1] & 0x80:
                    offset += 1
            
            field_info = {
                "field_number": field_number,
                "wire_type": wire_type,
                "wire_type_name": {0: "varint", 1: "64-bit", 2: "length-delimited", 5: "32-bit"}.get(wire_type, "unknown"),
                "offset": offset - 1,
            }
            
            # Try to read the value based on wire type
            if wire_type == 0:  # Varint
                value = 0
                shift = 0
                while offset < len(data):
                    byte = data[offset]
                    value |= (byte & 0x7F) << shift
                    offset += 1
                    if not (byte & 0x80):
                        break
                    shift += 7
                field_info["value"] = value
                
            elif wire_type == 1:  # 64-bit
                if offset + 8 <= len(data):
                    field_info["value_hex"] = data[offset:offset+8].hex()
                    offset += 8
                else:
                    break
                    
            elif wire_type == 2:  # Length-delimited
                # Read length as varint
                length = 0
                shift = 0
                while offset < len(data):
                    byte = data[offset]
                    length |= (byte & 0x7F) << shift
                    offset += 1
                    if not (byte & 0x80):
                        break
                    shift += 7
                
                if offset + length <= len(data):
                    content = data[offset:offset+length]
                    field_info["length"] = length
                    
                    # Try to decode as string
                    try:
                        decoded = content.decode('utf-8')
                        if all(32 <= ord(c) <= 126 or c in '\n\r\t' for c in decoded):
                            field_info["value_string"] = decoded[:200]  # Truncate long strings
                        else:
                            field_info["value_hex"] = content[:50].hex() + ("..." if length > 50 else "")
                    except:
                        field_info["value_hex"] = content[:50].hex() + ("..." if length > 50 else "")
                    
                    offset += length
                else:
                    break
                    
            elif wire_type == 5:  # 32-bit
                if offset + 4 <= len(data):
                    field_info["value_hex"] = data[offset:offset+4].hex()
                    offset += 4
                else:
                    break
            else:
                break  # Unknown wire type
            
            fields.append(field_info)
            
            # Safety limit
            if len(fields) > 100:
                fields.append({"note": "truncated at 100 fields"})
                break
                
    except Exception as e:
        fields.append({"error": str(e)})
    
    return fields


def save_payload(flow: http.HTTPFlow, direction: str, content: bytes, metadata: dict):
    """Save payload with metadata."""
    service, endpoint = extract_service_endpoint(flow.request.path)
    
    # Generate unique ID
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    content_hash = hashlib.sha256(content).hexdigest()[:12]
    filename = f"{timestamp}_{service}_{endpoint}_{content_hash}"
    
    # Save raw binary
    raw_path = BASE_DIR / f"{direction}s" / f"{filename}.bin"
    with open(raw_path, "wb") as f:
        f.write(content)
    
    # Decode and save analyzed version
    messages = decode_grpc_messages(content)
    
    analyzed = {
        "filename": filename,
        "timestamp": datetime.now().isoformat(),
        "cursor_version": CURSOR_VERSION,
        "direction": direction,
        "service": service,
        "endpoint": endpoint,
        "full_path": flow.request.path,
        "host": flow.request.host,
        "method": flow.request.method,
        "content_length": len(content),
        "content_hash_sha256": hashlib.sha256(content).hexdigest(),
        "grpc_messages": messages,
        **metadata,
    }
    
    json_path = BASE_DIR / "metadata" / f"{filename}.json"
    with open(json_path, "w") as f:
        json.dump(analyzed, f, indent=2, default=str)
    
    # Update stats
    stats["total_captured"] += 1
    stats["by_service"][service] = stats["by_service"].get(service, 0) + 1
    stats["by_endpoint"][endpoint] = stats["by_endpoint"].get(endpoint, 0) + 1
    
    return filename


class PayloadCollector:
    """mitmproxy addon for collecting Cursor API payloads."""
    
    def __init__(self):
        ctx.log.info(f"🗄️  Payload Collector initialized")
        ctx.log.info(f"   Version: {CURSOR_VERSION}")
        ctx.log.info(f"   Output: {BASE_DIR}")
    
    def request(self, flow: http.HTTPFlow):
        """Capture request payloads."""
        if not is_cursor_domain(flow.request.host):
            return
        
        service, endpoint = extract_service_endpoint(flow.request.path)
        
        # Log all requests
        ctx.log.info(f"📤 {service}/{endpoint}")
        
        if flow.request.content and len(flow.request.content) > 0:
            content_type = flow.request.headers.get("content-type", "")
            
            metadata = {
                "content_type": content_type,
                "headers": dict(flow.request.headers),
            }
            
            filename = save_payload(flow, "request", flow.request.content, metadata)
            ctx.log.info(f"   💾 Saved request: {filename}")
    
    def response(self, flow: http.HTTPFlow):
        """Capture response payloads."""
        if not is_cursor_domain(flow.request.host):
            return
        
        service, endpoint = extract_service_endpoint(flow.request.path)
        
        if flow.response and flow.response.content and len(flow.response.content) > 0:
            content_type = flow.response.headers.get("content-type", "")
            
            metadata = {
                "status_code": flow.response.status_code,
                "content_type": content_type,
                "response_headers": dict(flow.response.headers),
            }
            
            filename = save_payload(flow, "response", flow.response.content, metadata)
            ctx.log.info(f"   📥 Saved response: {filename} ({len(flow.response.content)} bytes)")
    
    def error(self, flow: http.HTTPFlow):
        """Log errors."""
        if is_cursor_domain(flow.request.host):
            error_msg = str(flow.error) if flow.error else "Unknown"
            stats["errors"].append({
                "url": flow.request.pretty_url,
                "error": error_msg,
                "timestamp": datetime.now().isoformat(),
            })
    
    def done(self):
        """Save session summary."""
        summary = {
            "cursor_version": CURSOR_VERSION,
            "session_end": datetime.now().isoformat(),
            "stats": stats,
        }
        
        summary_path = BASE_DIR / "metadata" / f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(summary_path, "w") as f:
            json.dump(summary, f, indent=2)
        
        ctx.log.info("\n" + "="*60)
        ctx.log.info("🗄️  PAYLOAD COLLECTION SUMMARY")
        ctx.log.info("="*60)
        ctx.log.info(f"   Total payloads: {stats['total_captured']}")
        ctx.log.info(f"   By service: {json.dumps(stats['by_service'], indent=6)}")
        ctx.log.info(f"   Saved to: {BASE_DIR}")
        ctx.log.info("="*60)


addons = [PayloadCollector()]

