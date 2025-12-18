"""
Cursor AI Traffic Interception Addon for mitmproxy

This addon intercepts and logs Cursor IDE's AI-related traffic,
including gRPC/Protobuf payloads.

Usage:
    mitmdump -s test_cursor_proxy.py -p 8080 --ssl-insecure
"""

import json
import time
import os
from datetime import datetime
from mitmproxy import http, ctx
from pathlib import Path

# Output directory for captured data
CAPTURE_DIR = Path("/tmp/cursor_captures")
CAPTURE_DIR.mkdir(exist_ok=True)

# Track statistics
stats = {
    "requests": 0,
    "cursor_requests": 0,
    "ai_endpoints": 0,
    "streaming_responses": 0,
    "grpc_payloads": 0,
    "errors": [],
    "endpoints_seen": set(),
    "start_time": datetime.now().isoformat(),
}

# Domains to track
CURSOR_DOMAINS = [
    "api.cursor.com",
    "api2.cursor.sh",
    "api3.cursor.sh",
    "cursor.sh",
    "cursorapi.com",
    "api.anthropic.com",
    "api.openai.com",
]

# AI-related endpoint patterns
AI_PATTERNS = [
    "AiService",
    "Stream",
    "Chat",
    "Generate",
    "Memory",
    "Conversation",
    "Completion",
]


def is_ai_endpoint(path: str) -> bool:
    """Check if this is an AI-related endpoint"""
    return any(pattern.lower() in path.lower() for pattern in AI_PATTERNS)


def save_payload(flow: http.HTTPFlow, payload_type: str, data: bytes):
    """Save payload to file for later analysis"""
    timestamp = datetime.now().strftime("%H%M%S_%f")
    endpoint = flow.request.path.split("/")[-1][:30]
    filename = f"{timestamp}_{payload_type}_{endpoint}.bin"
    filepath = CAPTURE_DIR / filename
    
    with open(filepath, "wb") as f:
        f.write(data)
    
    return filepath


def decode_grpc_length_prefixed(data: bytes) -> list:
    """
    Attempt to decode gRPC length-prefixed messages.
    gRPC format: [1 byte compressed flag][4 bytes length][message]
    """
    messages = []
    offset = 0
    
    while offset < len(data):
        if offset + 5 > len(data):
            break
            
        compressed = data[offset]
        length = int.from_bytes(data[offset+1:offset+5], byteorder='big')
        
        if offset + 5 + length > len(data):
            break
            
        message = data[offset+5:offset+5+length]
        messages.append({
            "compressed": compressed,
            "length": length,
            "data_preview": message[:100].hex() if message else "",
            "printable": "".join(chr(b) if 32 <= b < 127 else "." for b in message[:200])
        })
        
        offset += 5 + length
    
    return messages


class CursorProxyTest:
    def __init__(self):
        ctx.log.info("🔌 Cursor Proxy Test initialized (gRPC-aware)")
        ctx.log.info(f"   Capture directory: {CAPTURE_DIR}")
        ctx.log.info(f"   Watching domains: {CURSOR_DOMAINS}")
        
    def request(self, flow: http.HTTPFlow):
        """Log all requests, highlight Cursor-related ones"""
        stats["requests"] += 1
        host = flow.request.host
        path = flow.request.path
        
        is_cursor = any(d in host for d in CURSOR_DOMAINS)
        
        if not is_cursor:
            return
            
        stats["cursor_requests"] += 1
        stats["endpoints_seen"].add(f"{host}{path.split('?')[0]}")
        
        # Check if AI-related
        if is_ai_endpoint(path):
            stats["ai_endpoints"] += 1
            ctx.log.info(f"🤖 AI ENDPOINT: {flow.request.method} {flow.request.pretty_url}")
            
            # Log and save request body
            if flow.request.content:
                content_type = flow.request.headers.get("content-type", "")
                
                if "grpc" in content_type or "protobuf" in content_type or not flow.request.content.startswith(b'{'):
                    stats["grpc_payloads"] += 1
                    ctx.log.info(f"   📦 gRPC/Protobuf request ({len(flow.request.content)} bytes)")
                    
                    # Try to decode gRPC structure
                    messages = decode_grpc_length_prefixed(flow.request.content)
                    if messages:
                        ctx.log.info(f"   📝 {len(messages)} gRPC message(s) in request")
                        for i, msg in enumerate(messages[:3]):  # Log first 3
                            ctx.log.info(f"      [{i}] len={msg['length']}, preview: {msg['printable'][:80]}...")
                    
                    # Save for analysis
                    filepath = save_payload(flow, "request", flow.request.content)
                    ctx.log.info(f"   💾 Saved to: {filepath}")
                else:
                    try:
                        body = json.loads(flow.request.content)
                        if "messages" in body:
                            ctx.log.info(f"   📝 JSON with {len(body['messages'])} messages")
                        ctx.log.info(f"   📋 Keys: {list(body.keys())[:10]}")
                    except:
                        ctx.log.info(f"   📦 Binary payload ({len(flow.request.content)} bytes)")
        else:
            ctx.log.info(f"🎯 CURSOR: {flow.request.method} {flow.request.pretty_url}")
    
    def response(self, flow: http.HTTPFlow):
        """Check responses, especially streaming ones"""
        host = flow.request.host
        path = flow.request.path
        is_cursor = any(d in host for d in CURSOR_DOMAINS)
        
        if not is_cursor:
            return
            
        content_type = flow.response.headers.get("content-type", "")
        status = flow.response.status_code
        
        # Check for streaming response
        is_streaming = (
            "text/event-stream" in content_type or
            "application/grpc" in content_type or
            "stream" in path.lower()
        )
        
        if is_streaming or is_ai_endpoint(path):
            stats["streaming_responses"] += 1
            
            ctx.log.info(f"🌊 AI RESPONSE: {status} from {host}")
            ctx.log.info(f"   📍 Path: {path}")
            ctx.log.info(f"   📄 Content-Type: {content_type}")
            ctx.log.info(f"   📊 Size: {len(flow.response.content) if flow.response.content else 0} bytes")
            
            if flow.response.content:
                if "grpc" in content_type or not flow.response.content.startswith(b'{'):
                    # gRPC response
                    messages = decode_grpc_length_prefixed(flow.response.content)
                    if messages:
                        ctx.log.info(f"   📝 {len(messages)} gRPC message(s) in response")
                        for i, msg in enumerate(messages[:5]):  # Log first 5
                            ctx.log.info(f"      [{i}] len={msg['length']}")
                            # Look for text content
                            printable = msg['printable']
                            if len(printable) > 10:
                                ctx.log.info(f"          Text: {printable[:100]}...")
                    
                    # Save for analysis
                    filepath = save_payload(flow, "response", flow.response.content)
                    ctx.log.info(f"   💾 Saved to: {filepath}")
                    
                elif "text/event-stream" in content_type:
                    # SSE response
                    events = flow.response.content.count(b"data: ")
                    ctx.log.info(f"   🎫 SSE with {events} events")
                    preview = flow.response.content[:500].decode('utf-8', errors='ignore')
                    ctx.log.info(f"   Preview: {preview[:200]}...")
                    
                else:
                    try:
                        body = json.loads(flow.response.content)
                        ctx.log.info(f"   📋 JSON keys: {list(body.keys())[:10]}")
                    except:
                        ctx.log.info(f"   📦 Binary response ({len(flow.response.content)} bytes)")
        else:
            ctx.log.info(f"📥 Response: {status} from {host} ({len(flow.response.content) if flow.response.content else 0}b)")
    
    def error(self, flow: http.HTTPFlow):
        """Log any errors"""
        error_msg = str(flow.error) if flow.error else "Unknown error"
        
        stats["errors"].append({
            "url": flow.request.pretty_url,
            "error": error_msg,
            "time": datetime.now().isoformat()
        })
        
        ctx.log.error(f"❌ Error: {flow.request.pretty_url}")
        ctx.log.error(f"   {error_msg}")
        
        # Check for certificate errors
        if "certificate" in error_msg.lower() or "ssl" in error_msg.lower() or "tls" in error_msg.lower():
            ctx.log.error("⚠️  Certificate/TLS error - check CA trust")
    
    def done(self):
        """Print summary when proxy stops"""
        duration = datetime.now() - datetime.fromisoformat(stats["start_time"])
        
        ctx.log.info("\n" + "="*70)
        ctx.log.info("📊 SESSION SUMMARY")
        ctx.log.info("="*70)
        ctx.log.info(f"   Duration:            {duration}")
        ctx.log.info(f"   Total requests:      {stats['requests']}")
        ctx.log.info(f"   Cursor requests:     {stats['cursor_requests']}")
        ctx.log.info(f"   AI endpoints:        {stats['ai_endpoints']}")
        ctx.log.info(f"   Streaming responses: {stats['streaming_responses']}")
        ctx.log.info(f"   gRPC payloads:       {stats['grpc_payloads']}")
        ctx.log.info(f"   Errors:              {len(stats['errors'])}")
        
        ctx.log.info("\n📍 Unique endpoints seen:")
        for endpoint in sorted(stats["endpoints_seen"]):
            ctx.log.info(f"   - {endpoint}")
        
        ctx.log.info(f"\n💾 Captured payloads in: {CAPTURE_DIR}")
        
        # Save summary to file
        summary_file = CAPTURE_DIR / "session_summary.json"
        with open(summary_file, "w") as f:
            json.dump({
                **stats,
                "endpoints_seen": list(stats["endpoints_seen"]),
                "duration_seconds": duration.total_seconds(),
            }, f, indent=2, default=str)
        ctx.log.info(f"📝 Summary saved to: {summary_file}")
        
        ctx.log.info("="*70)


addons = [CursorProxyTest()]
