# Cursor API Schema Reconstruction

**Cursor Version**: 2.0.77  
**Protocol**: Connect Protocol v1 (https://connectrpc.com/)  
**Transport**: HTTP/2 over TLS  
**Serialization**: Protocol Buffers  
**Base URL**: `https://api2.cursor.sh`

## Service Map

### High Priority (AI Operations)

| Service | Endpoint | Priority | Samples | Description |
|---------|----------|----------|---------|-------------|
| `ChatService` | `StreamUnifiedChatWithTools` | 🔴 CRITICAL | 0* | Main AI conversation (streaming) |
| `AiService` | `CheckQueuePosition` | 🟡 HIGH | 570 | Queue position for AI requests |
| `AiService` | `PotentiallyGenerateMemory` | 🟡 HIGH | 323 | Conversation context (HUGE!) |
| `AiService` | `NameTab` | 🟡 HIGH | 576 | AI-powered tab naming |
| `AiService` | `AvailableModels` | 🟢 MEDIUM | 53 | List available AI models |
| `FastApplyService` | `ReportEditFate` | 🟢 MEDIUM | 193 | Report edit outcomes |
| `BackgroundComposerService` | `ListBackgroundComposers` | 🟢 MEDIUM | 200 | Background AI tasks |

*ChatService streaming was not captured due to mitmproxy streaming limitations

### Low Priority (Noise)

| Service | Endpoint | Samples | Description |
|---------|----------|---------|-------------|
| `AnalyticsService` | `SubmitLogs` | 11,530 | Telemetry logs |
| `AnalyticsService` | `Batch` | 3,994 | Batched analytics |
| `tev1` (Sentry) | `v1` | 3,822 | Error reporting |
| `ToolCallEventService` | `SubmitToolCallEvents` | 2,246 | Tool usage telemetry |
| `AuthService` | `MarkPrivacy` | 1,203 | Privacy settings |

---

## Reconstructed Schemas

### AiService/AvailableModels

```protobuf
// Request: 2 bytes
message AvailableModelsRequest {
  bool include_all = 3;  // Always 1 (true)
}

// Response: Unknown (not captured)
message AvailableModelsResponse {
  repeated Model models = ?;
}
```

### AiService/CheckQueuePosition

```protobuf
// Request: 56 bytes
message CheckQueuePositionRequest {
  string request_id = 1;  // UUID: "21e2e063-13fa-48d8-be5d-e11517b8e427"
  ModelInfo model = 2;
}

message ModelInfo {
  string model_name = 1;  // "gemini-3-pro", "claude-3.5-sonnet", etc.
  string reserved = 4;    // Empty string
}
```

### AiService/NameTab

```protobuf
// Request: ~1240 bytes
message NameTabRequest {
  string context = 1;  // Conversation snippet for naming
  // Additional fields TBD
}
```

### AiService/PotentiallyGenerateMemory

**CRITICAL**: This is the largest payload (1.7MB+) containing full conversation history!

```protobuf
// Request: 1,732,442 bytes (!!)
message PotentiallyGenerateMemoryRequest {
  string conversation_id = 1;  // UUID: "aa750-c36a-430f-aca6-779f47905fcd"
  
  // The payload contains the ENTIRE conversation context including:
  // - All messages (user and assistant)
  // - Tool calls and their results
  // - File contents being edited
  // - Terminal output with ANSI codes
  // - Timestamps (ISO 8601)
  // - Message UUIDs for correlation
  
  repeated ConversationFile files = 3;  // Files in context
  repeated ConversationTurn turns = ?;  // Message history
}

message ConversationFile {
  string path = 1;   // "tools/proxy-test/collect_payloads.sh"
  int32 status = 2;  // 1 = active
  string content = 3;  // Full file content
  int32 type = 6;    // File type enum
  bool tracked = 10; // Git tracked status
}

message ConversationTurn {
  string text = 1;          // Message content
  int32 role = 2;           // 2 = assistant
  string message_id = 13;   // UUID
  ToolCall tool_call = 18;  // Tool invocation details
  string timestamp = 78;    // ISO 8601
  // Many more fields...
}

message ToolCall {
  string tool_id = 1;       // "toolu_01JMh5inMWS9AgUbRejeoE6Q"
  string tool_name = 2;     // "run_terminal_cmd"
  bool completed = 3;       // 1 = done
  string arguments = 5;     // JSON: {"command": "...", "explanation": "..."}
  ToolResult result = 8;    // Result details
  ToolInvocation invocation = 11;  // Invocation metadata
}
```

### FastApplyService/ReportEditFate

```protobuf
// Request: 40 bytes
message ReportEditFateRequest {
  string edit_id = 1;  // UUID: "091c2331-a5b8-4b18-ae30-67ac1e38abdf"
  int32 fate = 2;      // 1 = accepted, 2 = rejected, etc.
}
```

### BackgroundComposerService/ListBackgroundComposers

```protobuf
// Request: 86 bytes
message ListBackgroundComposersRequest {
  int32 limit = 1;       // 32 (pagination)
  string repo_url = 4;   // "github.com/Distracted-E421/nixos-cursor"
  string repo_path = 5;  // "github.com/Distracted-E421/nixos-cursor"
  bool active_only = 6;  // 1 = true
}
```

### BackgroundComposerService/GetGithubAccessTokenForRepos

```protobuf
// Request: 41 bytes
message GetGithubAccessTokenForReposRequest {
  string repo_url = 1;  // "github.com/Distracted-E421/nixos-cursor"
}
```

---

## Header Analysis

### Required Headers

```http
POST /aiserver.v1.AiService/CheckQueuePosition HTTP/2
Host: api2.cursor.sh
Content-Type: application/proto
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Connect-Protocol-Version: 1
User-Agent: connect-es/1.6.1
X-Cursor-Client-Version: 2.0.77
X-Cursor-Client-Type: ide
X-Cursor-Streaming: true
X-Cursor-Timezone: America/Chicago
X-Ghost-Mode: true
X-Session-Id: d7f3052b-67c9-45da-acb8-6ae03b5ba94b
X-Request-Id: fd098603-4f71-4382-b28b-c88d7961aa1f
X-Client-Key: 31ec948fe449fd3708aa5c39fea5d71fbf59b2ca40bb5e9d23ccb73a13b4ccc9
X-Cursor-Checksum: Vy4wLeOe46ecf06b92ae6b5fa9848f3d614d6436213bb9ca90f690a919a9cf3c131780a4/...
```

### Header Meanings

| Header | Value | Purpose |
|--------|-------|---------|
| `Authorization` | `Bearer <JWT>` | User authentication |
| `Connect-Protocol-Version` | `1` | Connect RPC version |
| `X-Cursor-Client-Version` | `2.0.77` | IDE version |
| `X-Cursor-Streaming` | `true` | Enable streaming responses |
| `X-Ghost-Mode` | `true` | Privacy mode active |
| `X-Session-Id` | UUID | Session tracking |
| `X-Request-Id` | UUID | Request correlation |
| `X-Client-Key` | 64-char hex | Client identity |
| `X-Cursor-Checksum` | Complex hash | Request integrity |

---

## Data Statistics

### Payload Sizes

| Endpoint | Size | Notes |
|----------|------|-------|
| `AvailableModels` | 2 bytes | Smallest request |
| `ReportEditFate` | 40 bytes | UUID + enum |
| `CheckQueuePosition` | 56 bytes | UUID + model name |
| `ListBackgroundComposers` | 86 bytes | Pagination + repo |
| `NameTab` | ~1,240 bytes | Context snippet |
| `PotentiallyGenerateMemory` | ~1.7 MB | Full conversation! |

### Payload Distribution (29,864 total)

```
AnalyticsService/SubmitLogs:    11,530 (38.6%) - NOISE
AnalyticsService/Batch:          3,994 (13.4%) - NOISE
tev1/v1:                         3,822 (12.8%) - NOISE
ToolCallEventService:            2,246 (7.5%)  - NOISE
AiService/AvailableDocs:         1,578 (5.3%)
AuthService/MarkPrivacy:         1,203 (4.0%)
BackgroundComposerService:       1,140 (3.8%)
api (Sentry):                      824 (2.8%)  - NOISE
DashboardService:                  727 (2.4%)
AiService (high-priority):       1,608 (5.4%)  ← TARGET
```

**Noise Ratio**: ~69% of traffic is telemetry/analytics

---

## Field Number Conventions

Observing patterns across endpoints:

| Field | Common Usage |
|-------|-------------|
| 1 | Primary identifier (UUID, path, text) |
| 2 | Secondary data (role enum, nested message) |
| 3 | Content/body (file content, config) |
| 4, 5 | Repeated URLs/paths |
| 6, 7 | Type enums |
| 10 | Boolean flags |
| 13 | Message ID (UUID) |
| 18 | Tool call details |
| 47 | Role indicator (2 = assistant) |
| 50 | Parent reference ID |
| 63 | Status flags |
| 78 | Timestamp (ISO 8601) |
| 80 | Completion status |

---

## Next Steps

1. **Capture ChatService/StreamUnifiedChatWithTools** - Requires fixing streaming proxy
2. **Build Rust filter** - Fast payload filtering by service/endpoint
3. **Decode responses** - Need bidirectional capture
4. **Generate .proto files** - Full schema definitions
5. **Build injection layer** - Context insertion for AI conversations

---

## Files

- `decode_protobuf.py` - Protobuf wire format decoder
- `analyze_payloads.py` - Payload analysis tool
- `search_payloads.py` - Database search tool
- `payload_collector.py` - mitmproxy addon for capture

