#!/usr/bin/env python3
"""Test Cursor API endpoints with correct protobuf encoding."""

import sqlite3
import struct
import requests
import uuid

def get_token():
    """Get auth token from Cursor's SQLite database."""
    db_path = "/home/e421/.config/Cursor/User/globalStorage/state.vscdb"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'")
    row = cursor.fetchone()
    conn.close()
    if row:
        return row[0]
    raise Exception("Token not found")

def encode_varint(value):
    """Encode an integer as a varint."""
    result = []
    while value > 0x7f:
        result.append((value & 0x7f) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)

def encode_field(field_num, wire_type, value):
    """Encode a protobuf field."""
    tag = (field_num << 3) | wire_type
    return encode_varint(tag) + value

def encode_string(value):
    """Encode a string as length-delimited bytes."""
    encoded = value.encode('utf-8')
    return encode_varint(len(encoded)) + encoded

def build_conversation_message(text, msg_type=1):
    """Build a ConversationMessage proto.
    
    type: 1=USER, 2=ASSISTANT, 3=SYSTEM
    """
    result = b''
    # Field 1: text (string)
    result += encode_field(1, 2, encode_string(text))
    # Field 2: type (enum as int32)
    result += encode_field(2, 0, encode_varint(msg_type))
    # Field 13: bubble_id (string)
    result += encode_field(13, 2, encode_string(str(uuid.uuid4())))
    return result

def build_model_details(model_name):
    """Build a ModelDetails proto."""
    result = b''
    # Field 1: model_name (string)
    result += encode_field(1, 2, encode_string(model_name))
    # Field 2: supports_tools (bool as varint) - actually might be field 10?
    return result

def build_stream_unified_chat_request(conversation, model_name):
    """Build StreamUnifiedChatRequest."""
    result = b''
    # Field 1: conversation (repeated ConversationMessage)
    for msg in conversation:
        result += encode_field(1, 2, encode_varint(len(msg)) + msg)
    # Field 5: model_details (ModelDetails)
    model = build_model_details(model_name)
    result += encode_field(5, 2, encode_varint(len(model)) + model)
    # Field 22: is_chat (bool)
    result += encode_field(22, 0, encode_varint(1))
    # Field 23: conversation_id (string)
    result += encode_field(23, 2, encode_string(str(uuid.uuid4())))
    return result

def build_request_with_tools(chat_request):
    """Build StreamUnifiedChatRequestWithTools."""
    result = b''
    # Field 1: stream_unified_chat_request
    result += encode_field(1, 2, encode_varint(len(chat_request)) + chat_request)
    return result

def grpc_frame(data):
    """Add gRPC-web framing."""
    # [flags (1 byte)][length (4 bytes BE)][payload]
    return struct.pack('>BI', 0, len(data)) + data

def test_endpoint(name, url, payload, token):
    """Test an endpoint and show results."""
    print(f"\n>>> Testing {name}...")
    print(f"    Payload: {len(payload)} bytes")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/grpc-web+proto',
        'Accept': 'application/grpc-web+proto',
        'Connect-Protocol-Version': '1',
        'x-cursor-client-version': '2.0.77',
        'x-cursor-client-type': 'ide',
        'x-cursor-streaming': 'true',
        'x-session-id': str(uuid.uuid4()),
        'x-request-id': str(uuid.uuid4()),
    }
    
    try:
        response = requests.post(url, data=payload, headers=headers, timeout=10)
        print(f"    Status: {response.status_code}")
        
        # Show relevant headers
        for h in ['grpc-status', 'grpc-message', 'content-type']:
            if h in response.headers:
                print(f"    {h}: {response.headers[h]}")
        
        body = response.content
        print(f"    Body: {len(body)} bytes")
        
        # Try to decode
        if body:
            if len(body) < 200:
                # Try as text
                try:
                    text = body.decode('utf-8')
                    print(f"    Text: {text}")
                except:
                    pass
            # Show hex
            print(f"    Hex: {body[:64].hex()}")
        
        return response
    except Exception as e:
        print(f"    Error: {e}")
        return None

def main():
    print("=" * 60)
    print("Cursor API Endpoint Tests")
    print("=" * 60)
    
    token = get_token()
    print(f"✓ Got token ({len(token)} chars)")
    
    # Build a simple chat request
    msg = build_conversation_message("Say hello in 3 words.", msg_type=1)
    print(f"✓ Built message ({len(msg)} bytes)")
    
    chat_req = build_stream_unified_chat_request([msg], "gpt-4o")
    print(f"✓ Built chat request ({len(chat_req)} bytes)")
    
    request_with_tools = build_request_with_tools(chat_req)
    print(f"✓ Built request with tools ({len(request_with_tools)} bytes)")
    
    framed = grpc_frame(request_with_tools)
    print(f"✓ Framed ({len(framed)} bytes)")
    
    BASE = "https://api2.cursor.sh/aiserver.v1.ChatService"
    
    # Test warm endpoint first
    test_endpoint("WarmStreamUnifiedChatWithTools", 
                  f"{BASE}/WarmStreamUnifiedChatWithTools", framed, token)
    
    # Test BiDi endpoint
    test_endpoint("StreamUnifiedChatWithTools (BiDi)", 
                  f"{BASE}/StreamUnifiedChatWithTools", framed, token)
    
    # Test SSE endpoint
    test_endpoint("StreamUnifiedChatWithToolsSSE", 
                  f"{BASE}/StreamUnifiedChatWithToolsSSE", framed, token)
    
    # Test without tools (simpler)
    BASE2 = "https://api2.cursor.sh/aiserver.v1.ChatService"
    test_endpoint("StreamUnifiedChat (no tools)", 
                  f"{BASE2}/StreamUnifiedChat", grpc_frame(chat_req), token)

if __name__ == "__main__":
    main()
