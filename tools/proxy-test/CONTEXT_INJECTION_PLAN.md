# Cursor AI Context Injection System

## Goal

Build a system that allows real-time interception and modification of Cursor AI requests to:

- Monitor context window data
- Inject domain knowledge on-the-fly
- Guide AI tool usage
- Replace/augment built-in Cursor docs

## Protocol Details

**Protocol**: Connect RPC (gRPC-like over HTTP/2)
**Encoding**: Protocol Buffers + gzip compression
**Main Endpoint**: `aiserver.v1.ChatService/StreamUnifiedChatWithTools`
**Type**: Bidirectional streaming

### Schema Location

```
/home/e421/nixos-cursor/tools/proxy-test/proto/aiserver.proto
```

## Injection Points

### 1. Conversation Messages (`conversation`)

Add system messages with domain knowledge:

```protobuf
message ConversationMessage {
  string text = 1;
  MessageType type = 2;  // USER, ASSISTANT, SYSTEM, TOOL
  // ... code chunks, context, etc.
}
```

**Use case**: Inject a SYSTEM message with NixOS-specific guidance before user queries.

### 2. Explicit Context (`explicit_context`)

```protobuf
message ExplicitContext {
  repeated string file_paths = 1;
  repeated string folder_paths = 2;
  repeated string web_urls = 3;
  repeated string doc_identifiers = 4;
}
```

**Use case**: Force inclusion of specific documentation or files.

### 3. Project Context (`project_context`)

Same structure as conversation, but for project-wide context.

**Use case**: Inject homelab-specific rules and conventions.

### 4. Additional Ranked Context (`additional_ranked_context`)

```protobuf
message AdditionalRankedContext {
  string file_path = 1;
  string content = 2;
  float score = 3;  // Higher = more relevant
}
```

**Use case**: Inject high-priority knowledge snippets that should appear in context.

### 5. Tool Results (`ClientSideToolV2Result`)

```protobuf
message ClientSideToolV2Result {
  string tool_id = 1;
  string result_json = 2;
  bool success = 3;
  string error_message = 4;
}
```

**Use case**: Augment tool results with additional information.

## Implementation Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                     CONTEXT INJECTION PROXY                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌──────────┐    ┌────────────────┐    ┌──────────────────┐       │
│  │  Cursor  │───▶│ Injection      │───▶│ api2.cursor.sh   │       │
│  │   IDE    │◀───│ Proxy          │◀───│ (AI Service)     │       │
│  └──────────┘    └────────────────┘    └──────────────────┘       │
│                         │                                          │
│                         ▼                                          │
│                  ┌─────────────────┐                               │
│                  │ Knowledge Store │                               │
│                  │ ├─ Rules DB     │                               │
│                  │ ├─ Docs Index   │                               │
│                  │ ├─ Context DB   │                               │
│                  │ └─ Trigger Rules│                               │
│                  └─────────────────┘                               │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## Phase 1: Read-Only Monitoring

1. **Network Namespace Setup** (already done)
2. **Custom gRPC Proxy** that:
   - Decodes protobuf requests
   - Logs conversation context
   - Tracks tool calls
   - Passes through to real API

### Implementation

```python
# proxy/cursor_proxy.py
import grpc
from proto import aiserver_pb2

class CursorProxyService:
    def StreamUnifiedChatWithTools(self, request_iterator, context):
        for request in request_iterator:
            # LOG: Inspect the request
            log_request(request)
            
            # FORWARD: To real Cursor API
            response = forward_to_cursor(request)
            
            yield response
```

## Phase 2: Context Injection

1. **Trigger System**: Detect when to inject context
2. **Knowledge Retrieval**: Fetch relevant knowledge
3. **Message Injection**: Add to conversation/context

### Trigger Types

- **Keyword triggers**: Detect NixOS, homelab, etc.
- **File path triggers**: Detect .nix files, flake.nix
- **Tool triggers**: Intercept specific tool calls
- **Manual triggers**: CLI command to inject

### Example Injection

```python
def inject_context(request):
    # Detect NixOS-related query
    if is_nixos_query(request):
        # Add system message with NixOS guidance
        system_msg = ConversationMessage(
            text=load_nixos_rules(),
            type=MessageType.SYSTEM
        )
        request.conversation.insert(0, system_msg)
        
        # Add relevant documentation
        request.additional_ranked_context.append(
            AdditionalRankedContext(
                file_path="virtual://nixos-docs",
                content=load_relevant_docs(request),
                score=0.95  # High priority
            )
        )
    
    return request
```

## Phase 3: Tool Interception

1. **Tool Call Monitor**: See what tools the AI wants to use
2. **Tool Result Augmentation**: Enhance results with knowledge
3. **Tool Redirection**: Replace tool calls with custom implementations

### Use Cases

- **read_file**: Inject additional context about the file
- **web_search**: Override with local documentation
- **codebase_search**: Add homelab-specific results

## Technical Requirements

### Protobuf Handling

```bash
# Generate Python classes from proto
pip install grpcio-tools
python -m grpc_tools.protoc \
    -I./proto \
    --python_out=./src \
    --grpc_python_out=./src \
    aiserver.proto
```

### HTTP/2 Proxy

Options:

1. **mitmproxy** with custom addon (has HTTP/2 issues)
2. **envoy proxy** with gRPC filter
3. **Custom Python** with `h2` library
4. **Go proxy** with `connectrpc` library

### Recommended: Go with ConnectRPC

```go
// Handles Connect protocol natively
import "connectrpc.com/connect"

type InjectionInterceptor struct {}

func (i *InjectionInterceptor) WrapStreamingClient(next connect.StreamingClientFunc) connect.StreamingClientFunc {
    return func(ctx context.Context, spec connect.Spec) connect.StreamingClientConn {
        // Intercept and inject here
    }
}
```

## Files Created

- `/proto/aiserver.proto` - Protocol definition
- `/captures/` - 311MB of captured traffic
- `/CONTEXT_INJECTION_PLAN.md` - This document

## Next Steps

1. [ ] Generate protobuf Python/Go classes
2. [ ] Build simple read-only proxy that decodes messages
3. [ ] Implement conversation logger
4. [ ] Create trigger detection system
5. [ ] Build knowledge store (SQLite + vector DB)
6. [ ] Implement injection logic
7. [ ] Test with NixOS-specific queries
8. [ ] Integrate with nixos-cursor docs system

## Related Resources

- Connect Protocol: <https://connectrpc.com/>
- Protocol Buffers: <https://protobuf.dev/>
- Network Namespaces: `setup-network-namespace.sh`
- Captured Data: `/mitmproxy-captures/`
