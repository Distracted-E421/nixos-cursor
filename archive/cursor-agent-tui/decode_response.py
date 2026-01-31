#!/usr/bin/env python3
"""Decode the StreamUnifiedChat response."""

import sqlite3
import struct
import requests
import uuid

def get_token():
    db_path = "/home/e421/.config/Cursor/User/globalStorage/state.vscdb"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'")
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None

def encode_varint(value):
    result = []
    while value > 0x7f:
        result.append((value & 0x7f) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)

def encode_field(field_num, wire_type, value):
    tag = (field_num << 3) | wire_type
    return encode_varint(tag) + value

def encode_string(value):
    encoded = value.encode('utf-8')
    return encode_varint(len(encoded)) + encoded

def build_conversation_message(text, msg_type=1):
    result = b''
    result += encode_field(1, 2, encode_string(text))
    result += encode_field(2, 0, encode_varint(msg_type))
    result += encode_field(13, 2, encode_string(str(uuid.uuid4())))
    return result

def build_model_details(model_name):
    result = b''
    result += encode_field(1, 2, encode_string(model_name))
    return result

def build_stream_unified_chat_request(conversation, model_name):
    result = b''
    for msg in conversation:
        result += encode_field(1, 2, encode_varint(len(msg)) + msg)
    model = build_model_details(model_name)
    result += encode_field(5, 2, encode_varint(len(model)) + model)
    result += encode_field(22, 0, encode_varint(1))
    result += encode_field(23, 2, encode_string(str(uuid.uuid4())))
    return result

def grpc_frame(data):
    return struct.pack('>BI', 0, len(data)) + data

def parse_grpc_response(data):
    """Parse gRPC-web response frames."""
    pos = 0
    frames = []
    while pos < len(data):
        if pos + 5 > len(data):
            break
        flags = data[pos]
        length = struct.unpack('>I', data[pos+1:pos+5])[0]
        pos += 5
        if pos + length > len(data):
            break
        payload = data[pos:pos+length]
        pos += length
        frames.append((flags, payload))
    return frames

def decode_varint(data, pos):
    """Decode a varint from data starting at pos."""
    result = 0
    shift = 0
    while True:
        if pos >= len(data):
            break
        b = data[pos]
        result |= (b & 0x7f) << shift
        pos += 1
        if not (b & 0x80):
            break
        shift += 7
    return result, pos

def decode_field(data, pos):
    """Decode a single protobuf field."""
    if pos >= len(data):
        return None, None, None, pos
    
    tag, pos = decode_varint(data, pos)
    field_num = tag >> 3
    wire_type = tag & 0x7
    
    if wire_type == 0:  # Varint
        value, pos = decode_varint(data, pos)
    elif wire_type == 2:  # Length-delimited
        length, pos = decode_varint(data, pos)
        value = data[pos:pos+length]
        pos += length
    elif wire_type == 5:  # 32-bit
        value = struct.unpack('<I', data[pos:pos+4])[0]
        pos += 4
    elif wire_type == 1:  # 64-bit
        value = struct.unpack('<Q', data[pos:pos+8])[0]
        pos += 8
    else:
        value = None
        
    return field_num, wire_type, value, pos

def decode_proto_message(data, indent=0):
    """Recursively decode a protobuf message."""
    pos = 0
    prefix = "  " * indent
    while pos < len(data):
        field_num, wire_type, value, new_pos = decode_field(data, pos)
        if field_num is None:
            break
        pos = new_pos
        
        type_names = {0: 'varint', 1: '64-bit', 2: 'bytes', 5: '32-bit'}
        type_name = type_names.get(wire_type, f'unknown({wire_type})')
        
        if wire_type == 2 and value:
            # Try to decode as string
            try:
                as_string = value.decode('utf-8')
                if all(c.isprintable() or c in '\n\r\t' for c in as_string):
                    print(f"{prefix}Field {field_num} ({type_name}): \"{as_string[:100]}{'...' if len(as_string) > 100 else ''}\"")
                    continue
            except:
                pass
            # Show nested structure
            print(f"{prefix}Field {field_num} ({type_name}): [{len(value)} bytes]")
            decode_proto_message(value, indent + 1)
        else:
            print(f"{prefix}Field {field_num} ({type_name}): {value}")

def main():
    print("=" * 60)
    print("Testing StreamUnifiedChat and Decoding Response")
    print("=" * 60)
    
    token = get_token()
    print(f"✓ Got token")
    
    msg = build_conversation_message("Hello", msg_type=1)
    chat_req = build_stream_unified_chat_request([msg], "gpt-4o")
    framed = grpc_frame(chat_req)
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/grpc-web+proto',
        'Accept': 'application/grpc-web+proto',
        'Connect-Protocol-Version': '1',
        'x-cursor-client-version': '2.0.77',
    }
    
    print(f"\n>>> Sending request ({len(framed)} bytes)...")
    response = requests.post(
        "https://api2.cursor.sh/aiserver.v1.ChatService/StreamUnifiedChat",
        data=framed,
        headers=headers,
        timeout=15
    )
    
    print(f"Status: {response.status_code}")
    body = response.content
    print(f"Body: {len(body)} bytes\n")
    
    # Parse gRPC frames
    frames = parse_grpc_response(body)
    print(f"Parsed {len(frames)} gRPC frame(s)\n")
    
    for i, (flags, payload) in enumerate(frames):
        print(f"Frame {i}: flags={flags:#04x}, payload={len(payload)} bytes")
        if flags & 0x80:  # Trailer frame
            print("  (Trailer)")
            try:
                trailer = payload.decode('utf-8')
                print(f"  {trailer}")
            except:
                pass
        else:
            print("  Decoding protobuf:")
            decode_proto_message(payload, indent=2)
        print()

if __name__ == "__main__":
    main()
