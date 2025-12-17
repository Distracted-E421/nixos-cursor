# Streaming Proxy Architecture

> **Goal**: Intercept AI responses mid-stream to inject context, detect needs, and enhance capabilities across all projects.

## 🔬 Testing Status (Dec 17, 2025)

### Proxy Interception Results

| Endpoint | Interception | Status |
|----------|--------------|--------|
| `metrics.cursor.sh` | ✅ Works | Sentry telemetry |
| `api3.cursor.sh` | ✅ Works | Analytics |
| `marketplace.cursorapi.com` | ✅ Works | Extensions |
| `api2.cursor.sh/auth/*` | ✅ Works | Auth/profile |
| `api2.cursor.sh/updates/*` | ✅ Works | Update checks |
| `api2.cursor.sh` (streaming) | ❌ Cert-pinned | AI chat - TLS handshake fails |
| `app.posthog.com` | ❌ Cert-pinned | Analytics |

### Next Steps

1. **System-wide CA Trust**: Add mitmproxy CA to NixOS PKI trust store
2. **Test if system CA bypasses app-level pinning**
3. **If still blocked**: Investigate Electron app modification or Frida

### Key Finding

Cursor uses **selective cert pinning** - non-critical endpoints work fine,
but the AI streaming endpoints have additional protection.

## Overview

```
┌─────────────────┐     HTTPS      ┌──────────────────┐     HTTPS      ┌─────────────────┐
│   Cursor IDE    │ ─────────────► │  Streaming Proxy │ ─────────────► │  Cursor API     │
│                 │ ◄───────────── │  (localhost)     │ ◄───────────── │  (api.cursor.com)│
└─────────────────┘    Modified    └──────────────────┘    Original    └─────────────────┘
                       Stream              │
                                           │ Analysis + Injection
                                           ▼
                                   ┌──────────────────┐
                                   │  cursor-studio   │
                                   │  (decision engine)│
                                   │                  │
                                   │  - cursor-docs   │
                                   │  - modes system  │
                                   │  - memory MCP    │
                                   └──────────────────┘
```

## Technical Approach

### Option 1: mitmproxy-based (Recommended for Development)

**Pros**: 
- Well-maintained, Python-based
- Supports custom addons
- Real-time stream modification
- Works with any HTTPS traffic

**Cons**:
- Requires CA certificate trust
- May be blocked by cert pinning
- User sees "insecure" warnings initially

```python
# cursor_proxy.py - mitmproxy addon
from mitmproxy import http, ctx
from mitmproxy.net.http import Headers
import json
import re

class CursorStreamInterceptor:
    def __init__(self):
        self.cursor_hosts = ["api.cursor.com", "api2.cursor.sh"]
        self.injection_queue = []
        
    def request(self, flow: http.HTTPFlow):
        """Capture outgoing requests to detect context"""
        if any(h in flow.request.host for h in self.cursor_hosts):
            # Log what the user is asking
            if flow.request.content:
                self.analyze_user_message(flow.request.content)
    
    def responseheaders(self, flow: http.HTTPFlow):
        """Prepare for streaming response"""
        if any(h in flow.request.host for h in self.cursor_hosts):
            # Mark this flow for streaming interception
            flow.response.stream = self.modify_stream
    
    def modify_stream(self, chunks):
        """Process SSE stream chunk by chunk"""
        buffer = ""
        
        for chunk in chunks:
            buffer += chunk.decode('utf-8', errors='ignore')
            
            # Parse SSE events
            while '\n\n' in buffer:
                event, buffer = buffer.split('\n\n', 1)
                
                # Analyze and potentially inject
                modified = self.process_sse_event(event)
                yield modified.encode('utf-8')
                
                # Check if we should inject context
                if self.should_inject():
                    injection = self.get_injection()
                    yield injection.encode('utf-8')
        
        # Remaining buffer
        if buffer:
            yield buffer.encode('utf-8')
    
    def process_sse_event(self, event: str) -> str:
        """Analyze SSE event, detect if AI needs help"""
        if event.startswith('data: '):
            data = event[6:]
            if data != '[DONE]':
                try:
                    parsed = json.loads(data)
                    content = self.extract_content(parsed)
                    
                    # Detection logic
                    self.detect_needs(content)
                    
                except json.JSONDecodeError:
                    pass
        
        return event + '\n\n'
    
    def detect_needs(self, content: str):
        """Detect if AI needs additional context"""
        # Pattern matching for common needs
        patterns = [
            (r"I don't have information about", "needs_docs"),
            (r"I'm not sure about", "needs_docs"),
            (r"let me search", "can_assist"),
            (r"@docs", "explicit_docs_request"),
            (r"NixOS|Nix|flake", "nix_context"),
        ]
        
        for pattern, action in patterns:
            if re.search(pattern, content, re.IGNORECASE):
                self.queue_injection(action, content)
    
    def queue_injection(self, action: str, context: str):
        """Queue a context injection"""
        # Communicate with cursor-studio to get relevant docs
        # This would use IPC (socket, pipe, or HTTP)
        self.injection_queue.append({
            "action": action,
            "context": context,
            "timestamp": time.time()
        })
    
    def should_inject(self) -> bool:
        return len(self.injection_queue) > 0
    
    def get_injection(self) -> str:
        """Format injection as SSE event"""
        if not self.injection_queue:
            return ""
        
        item = self.injection_queue.pop(0)
        
        # Get relevant docs from cursor-docs
        docs = self.fetch_relevant_docs(item["context"])
        
        if docs:
            # Format as if it's part of the AI response
            injection = f"""

<system_context_injection>
Based on your local documentation index, here's relevant information:

{docs}
</system_context_injection>

"""
            return f"data: {json.dumps({'choices': [{'delta': {'content': injection}}]})}\n\n"
        
        return ""
    
    def fetch_relevant_docs(self, query: str) -> str:
        """Query cursor-docs for relevant content"""
        # HTTP call to cursor-docs API
        try:
            response = requests.post(
                "http://localhost:4000/api/search",
                json={"query": query, "limit": 3}
            )
            if response.ok:
                results = response.json()
                return self.format_docs(results)
        except:
            pass
        return ""

addons = [CursorStreamInterceptor()]
```

### Option 2: Rust Transparent Proxy (Production Quality)

**Pros**:
- High performance
- Native integration with cursor-studio-egui
- More control over TLS handling

**Cons**:
- More development effort
- Need to handle TLS termination

```rust
// cursor-proxy/src/main.rs
use tokio::net::TcpListener;
use tokio_rustls::TlsAcceptor;
use hyper::{Body, Request, Response, Server};
use hyper::service::{make_service_fn, service_fn};
use futures::StreamExt;

struct CursorProxy {
    docs_client: DocsClient,
    injection_tx: mpsc::Sender<InjectionRequest>,
}

impl CursorProxy {
    async fn handle_request(&self, req: Request<Body>) -> Result<Response<Body>, Error> {
        // Forward to real Cursor API
        let response = self.forward_request(req).await?;
        
        // If streaming response, intercept
        if is_streaming_response(&response) {
            Ok(self.intercept_stream(response).await)
        } else {
            Ok(response)
        }
    }
    
    async fn intercept_stream(&self, response: Response<Body>) -> Response<Body> {
        let (parts, body) = response.into_parts();
        
        let stream = body.map(|chunk| {
            match chunk {
                Ok(data) => {
                    let text = String::from_utf8_lossy(&data);
                    let modified = self.process_sse_chunk(&text);
                    Ok(hyper::body::Bytes::from(modified))
                }
                Err(e) => Err(e)
            }
        });
        
        Response::from_parts(parts, Body::wrap_stream(stream))
    }
}
```

### Option 3: Electron IPC Injection (Risky but Powerful)

**Pros**:
- Direct access to Cursor internals
- No certificate issues
- Can modify UI as well

**Cons**:
- Breaks on Cursor updates
- May violate ToS
- Complex to maintain

```javascript
// Inject into Cursor's renderer process
// (Would require modifying Cursor's asar or using electron-inject)

const originalFetch = window.fetch;
window.fetch = async function(...args) {
    const response = await originalFetch.apply(this, args);
    
    if (args[0].includes('api.cursor.com') && response.body) {
        return new Response(
            interceptStream(response.body),
            { headers: response.headers, status: response.status }
        );
    }
    
    return response;
};

function interceptStream(readableStream) {
    const reader = readableStream.getReader();
    
    return new ReadableStream({
        async start(controller) {
            while (true) {
                const {done, value} = await reader.read();
                if (done) break;
                
                // Process and potentially inject
                const modified = await processChunk(value);
                controller.enqueue(modified);
                
                // Check for injection opportunity
                const injection = await checkForInjection();
                if (injection) {
                    controller.enqueue(injection);
                }
            }
            controller.close();
        }
    });
}
```

## Detection Patterns

### When to Inject Context

```python
INJECTION_TRIGGERS = {
    # Explicit needs
    "explicit_request": [
        r"@docs\s+(\w+)",           # User asks for docs
        r"search.*documentation",   # Direct request
    ],
    
    # AI uncertainty
    "ai_uncertain": [
        r"I don't have.*information",
        r"I'm not.*certain",
        r"I cannot.*verify",
        r"my training.*cutoff",
    ],
    
    # Topic detection
    "topic_match": [
        r"NixOS|nixpkgs|home-manager",  # Nix ecosystem
        r"Hyprland|Wayland|Sway",       # Desktop
        r"Elixir|Phoenix|OTP",          # Your stack
        r"cursor-studio|cursor-docs",   # Your projects
    ],
    
    # Error patterns
    "error_help": [
        r"error:.*not found",
        r"undefined.*reference",
        r"compilation.*failed",
    ],
}
```

### What to Inject

```python
def generate_injection(trigger_type: str, context: str) -> str:
    if trigger_type == "explicit_request":
        # Full docs response
        return query_docs_full(context)
    
    elif trigger_type == "ai_uncertain":
        # Supplement with local knowledge
        return f"""
<local_knowledge_supplement>
From your indexed documentation:
{query_docs_brief(context)}
</local_knowledge_supplement>
"""
    
    elif trigger_type == "topic_match":
        # Contextual hints
        return f"""
<context_hint>
Relevant local docs available for: {context}
Use @docs to query or refer to: {get_best_match(context)}
</context_hint>
"""
    
    elif trigger_type == "error_help":
        # Error-specific help
        return f"""
<troubleshooting>
Similar issues in your knowledge base:
{query_troubleshooting(context)}
</troubleshooting>
"""
```

## Integration with cursor-studio

### IPC Protocol

```rust
// cursor-studio/src/proxy_integration.rs

#[derive(Serialize, Deserialize)]
pub enum ProxyMessage {
    // From proxy to studio
    StreamChunk { content: String, metadata: ChunkMeta },
    NeedsContext { query: String, trigger: String },
    UserMessage { content: String },
    
    // From studio to proxy
    InjectContext { content: String, priority: u8 },
    OverrideResponse { replacement: String },
    SetMode { mode_name: String },
}

pub struct ProxyBridge {
    socket: UnixStream,
    pending_injections: Vec<String>,
}

impl ProxyBridge {
    pub fn on_needs_context(&self, query: &str) -> Option<String> {
        // Query cursor-docs
        let results = self.docs_client.search(query, 3)?;
        
        // Format for injection
        Some(format_docs_for_injection(results))
    }
    
    pub fn should_inject_mode_context(&self) -> bool {
        // Check if current mode has context to inject
        self.current_mode.context.custom_injection.len() > 0
    }
}
```

## Setup Instructions

### Development Setup (mitmproxy)

```bash
# 1. Install mitmproxy
nix shell nixpkgs#mitmproxy

# 2. Generate CA certificate
mitmproxy --mode regular
# Ctrl+C after startup
# CA cert is at ~/.mitmproxy/mitmproxy-ca-cert.pem

# 3. Trust the CA (NixOS)
# Add to configuration.nix:
security.pki.certificateFiles = [ 
  /home/e421/.mitmproxy/mitmproxy-ca-cert.pem 
];

# 4. Run proxy with our addon
mitmdump -s cursor_proxy.py -p 8080

# 5. Configure Cursor to use proxy
# Set HTTP_PROXY and HTTPS_PROXY environment variables
# Or modify Cursor's launch script
```

### Production Setup (Rust)

```nix
# cursor-proxy NixOS module
{ config, lib, pkgs, ... }:

{
  systemd.user.services.cursor-proxy = {
    description = "Cursor Streaming Proxy";
    after = [ "network.target" ];
    
    serviceConfig = {
      ExecStart = "${cursor-proxy}/bin/cursor-proxy";
      Restart = "always";
      Environment = [
        "CURSOR_DOCS_URL=http://localhost:4000"
        "PROXY_PORT=8443"
      ];
    };
  };
  
  # Auto-configure Cursor to use proxy
  programs.cursor.proxySettings = {
    enable = true;
    proxyUrl = "https://localhost:8443";
    caCertPath = config.age.secrets.proxy-ca.path;
  };
}
```

## Security Considerations

1. **Certificate Trust**: Only trust our CA on the specific machine
2. **Traffic Scope**: Only intercept Cursor API traffic, pass-through everything else
3. **No Logging of Sensitive Data**: Filter out API keys, tokens from logs
4. **User Consent**: Make proxy opt-in, clearly explain what it does

## Limitations

1. **Certificate Pinning**: If Cursor pins certs, proxy won't work
2. **Updates**: Cursor updates may change API format
3. **Performance**: Small latency added (~5-10ms)
4. **Complexity**: Another moving part to maintain

## Alternatives Considered

| Approach | Viability | Effort | Risk |
|----------|-----------|--------|------|
| mitmproxy | High | Low | Medium |
| Rust proxy | High | Medium | Low |
| Electron inject | Medium | High | High |
| Cursor extension | Low | - | - (no API) |
| File watching | Medium | Low | Low |

## Recommendation

**Start with mitmproxy** for rapid prototyping:
1. Prove the concept works
2. Identify what patterns need injection
3. Test with real workflows

**Then build Rust proxy** for production:
1. Integrate with cursor-studio-egui
2. Better performance
3. Single binary deployment

## Next Steps

1. [ ] Create mitmproxy addon for Cursor interception
2. [ ] Test certificate trust on NixOS
3. [ ] Implement basic injection detection
4. [ ] Build IPC bridge to cursor-studio
5. [ ] Create Rust proxy skeleton
6. [ ] Design injection UI in cursor-studio

