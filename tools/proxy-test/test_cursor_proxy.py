"""
Cursor Streaming Proxy Test

This addon tests if we can intercept Cursor's API traffic.
Run with: mitmdump -s test_cursor_proxy.py -p 8080

Then launch Cursor with proxy:
  HTTP_PROXY=http://127.0.0.1:8080 HTTPS_PROXY=http://127.0.0.1:8080 cursor

Or for Electron (recommended):
  cursor --proxy-server=http://127.0.0.1:8080 --ignore-certificate-errors
"""

import json
import time
from mitmproxy import http, ctx
from datetime import datetime

# Track what we've seen
stats = {
    "requests": 0,
    "cursor_requests": 0,
    "streaming_responses": 0,
    "intercepted_tokens": 0,
    "errors": [],
}

# Domains to intercept
CURSOR_DOMAINS = [
    "api.cursor.com",
    "api2.cursor.sh",
    "cursor.sh",
    "api.anthropic.com",  # Claude backend
    "api.openai.com",     # OpenAI backend
]

class CursorProxyTest:
    def __init__(self):
        ctx.log.info("🔌 Cursor Proxy Test initialized")
        ctx.log.info(f"   Watching domains: {CURSOR_DOMAINS}")
        
    def request(self, flow: http.HTTPFlow):
        """Log all requests, highlight Cursor-related ones"""
        stats["requests"] += 1
        host = flow.request.host
        
        is_cursor = any(d in host for d in CURSOR_DOMAINS)
        
        if is_cursor:
            stats["cursor_requests"] += 1
            ctx.log.info(f"🎯 CURSOR REQUEST: {flow.request.method} {flow.request.pretty_url}")
            
            # Log request body for chat completions
            if flow.request.content and b"messages" in flow.request.content:
                try:
                    body = json.loads(flow.request.content)
                    if "messages" in body:
                        ctx.log.info(f"   📝 Messages: {len(body['messages'])} messages")
                        if body["messages"]:
                            last_msg = body["messages"][-1]
                            content = last_msg.get("content", "")[:100]
                            ctx.log.info(f"   📝 Last message: {content}...")
                except json.JSONDecodeError:
                    pass
    
    def response(self, flow: http.HTTPFlow):
        """Check responses, especially streaming ones"""
        host = flow.request.host
        is_cursor = any(d in host for d in CURSOR_DOMAINS)
        
        if not is_cursor:
            return
            
        content_type = flow.response.headers.get("content-type", "")
        
        # Check for streaming response (SSE)
        if "text/event-stream" in content_type or "stream" in flow.request.path:
            stats["streaming_responses"] += 1
            ctx.log.info(f"🌊 STREAMING RESPONSE detected!")
            ctx.log.info(f"   Status: {flow.response.status_code}")
            ctx.log.info(f"   Content-Type: {content_type}")
            
            # Try to peek at the content
            if flow.response.content:
                preview = flow.response.content[:500].decode('utf-8', errors='ignore')
                ctx.log.info(f"   Preview: {preview[:200]}...")
                
                # Count SSE events
                events = flow.response.content.count(b"data: ")
                ctx.log.info(f"   SSE events in response: {events}")
                stats["intercepted_tokens"] += events
        else:
            ctx.log.info(f"📥 Response: {flow.response.status_code} from {host}")
    
    def error(self, flow: http.HTTPFlow):
        """Log any errors"""
        error_msg = f"❌ Error for {flow.request.pretty_url}: {flow.error}"
        ctx.log.error(error_msg)
        stats["errors"].append({
            "url": flow.request.pretty_url,
            "error": str(flow.error),
            "time": datetime.now().isoformat()
        })
        
        # Check for certificate errors (indicates pinning)
        if flow.error and ("certificate" in str(flow.error).lower() or 
                          "ssl" in str(flow.error).lower() or
                          "tls" in str(flow.error).lower()):
            ctx.log.error("⚠️  POSSIBLE CERTIFICATE PINNING DETECTED!")
            ctx.log.error("   Try launching Cursor with: --ignore-certificate-errors")
    
    def done(self):
        """Print summary when proxy stops"""
        ctx.log.info("\n" + "="*60)
        ctx.log.info("📊 SESSION SUMMARY")
        ctx.log.info("="*60)
        ctx.log.info(f"   Total requests:      {stats['requests']}")
        ctx.log.info(f"   Cursor requests:     {stats['cursor_requests']}")
        ctx.log.info(f"   Streaming responses: {stats['streaming_responses']}")
        ctx.log.info(f"   Intercepted tokens:  {stats['intercepted_tokens']}")
        ctx.log.info(f"   Errors:              {len(stats['errors'])}")
        
        if stats['cursor_requests'] > 0 and len(stats['errors']) == 0:
            ctx.log.info("\n✅ SUCCESS! Cursor traffic can be intercepted!")
            ctx.log.info("   Certificate pinning does NOT appear to be enabled.")
        elif len(stats['errors']) > 0:
            ctx.log.info("\n⚠️  ERRORS DETECTED - Check for certificate pinning")
            for err in stats['errors'][:5]:
                ctx.log.info(f"   - {err['error']}")
        else:
            ctx.log.info("\n❓ No Cursor traffic seen. Make sure Cursor is using the proxy.")
        
        ctx.log.info("="*60)

addons = [CursorProxyTest()]

