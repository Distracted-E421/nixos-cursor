# Cursor Protobuf Schema Analysis

## Discovery Method

We reverse-engineered the Cursor API protobuf schema by analyzing the `cursor-always-local` extension's bundled JavaScript code at:

```
/nix/store/1vmz7y8i5wza9hz5xl1mck00b0n0xa1k-cursor-2.0.77/share/cursor/resources/app/extensions/cursor-always-local/dist/main.js
```

The protobuf definitions are embedded using protobuf-es (Connect protocol) with clear type names like `typeName="aiserver.v1.StreamUnifiedChatRequestWithTools"`.

## Key Findings

### 1. Total Types Found: 2,129

All types are under the `aiserver.v1` namespace.

### 2. Services Identified

| Service | Purpose |
|---------|---------|
| `ChatService` | Main chat/completion API |
| `AiService` | General AI operations |
| `BackgroundComposerService` | Background agent operations |
| `BidiService` | Bidirectional streaming |
| `CmdKService` | Command-K inline editing |
| `UploadService` | File upload operations |
| `RepositoryService` | Git/repo operations |
| `MetricsService` | Telemetry |

### 3. Chat Endpoints

| Method | Request Type | Response Type | Kind |
|--------|--------------|---------------|------|
| `StreamUnifiedChat` | `StreamUnifiedChatRequest` | `StreamUnifiedChatResponse` | Server Streaming |
| `StreamUnifiedChatWithTools` | `StreamUnifiedChatRequestWithTools` | `StreamUnifiedChatResponseWithTools` | BiDi Streaming |
| `StreamUnifiedChatWithToolsSSE` | `StreamUnifiedChatRequestWithTools` | `StreamUnifiedChatResponseWithTools` | Server Streaming |
| `StreamUnifiedChatWithToolsIdempotent` | `StreamUnifiedChatRequestWithToolsIdempotent` | `StreamUnifiedChatResponseWithToolsIdempotent` | BiDi Streaming |

### 4. Request Message Structure

**StreamUnifiedChatRequestWithTools:**
- `stream_unified_chat_request` (field 1): The main chat request
- `client_side_tool_v2_result` (field 2): Results from tool execution

**StreamUnifiedChatRequest (partial):**
- `conversation` (field 1): List of ConversationMessage, repeated
- `full_conversation_headers_only` (field 30): Lightweight headers
- `allow_long_file_scan` (field 2): bool
- `explicit_context` (field 3): ExplicitContext
- `model_details` (field 5): ModelDetails
- `linter_errors` (field 6): LinterErrors
- `current_file` (field 15): CurrentFileInfo
- `is_chat` (field 22): bool
- `conversation_id` (field 23): string

### 5. Response Message Structure

**StreamUnifiedChatResponseWithTools:**
- `client_side_tool_v2_call` (field 1): Tool call from server
- `stream_unified_chat_response` (field 2): Actual response text
- `conversation_summary` (field 3): Summary
- `user_rules` (field 4): Applied user rules
- `stream_start` (field 5): Stream start marker
- `tracing_context` (field 6): SpanContext for tracing
- `event_id` (field 7): Event identifier

### 6. ConversationMessage Structure

- `text` (field 1): Message content
- `type` (field 2): Enum (USER=1, ASSISTANT=2, SYSTEM=3, TOOL=4)
- `attached_code_chunks` (field 3): Code selections
- `codebase_context_chunks` (field 4): Context from codebase
- `bubble_id` (field 13): Unique message ID
- Plus many more context fields...

### 7. Tool Call/Result Types

**ClientSideToolV2Call:**
- `tool_name`: Name of the tool to call
- `tool_id`: Unique identifier for this call
- `arguments_json`: JSON-encoded arguments

**ClientSideToolV2Result:**
- `tool_id`: Matching the call
- `result_json`: JSON-encoded result
- `success`: Boolean
- `error_message`: If failed

### 8. Known Tool Types

From the extracted definitions:
- `edit_file` / `EditFileParams`
- `create_file` / `CreateFileParams`  
- `delete_file` / `DeleteFileParams`
- `read_file` / `ReadFileParams`
- `run_terminal` / `RunTerminalCommandV2Params`
- `search_files` / `SearchParams`
- `list_dir` / `ListDirParams`
- `codebase_search` / `SemanticSearchParams`
- `grep_search` / `RipgrepSearchParams`
- `file_search` / `FileSearchParams`
- `fetch_rules` / `FetchRulesParams`
- `web_search` / `WebSearchParams`
- `mcp` / `CallMcpToolParams`

## Protocol Details

### Content-Type
- Request: `application/connect+proto` or `application/grpc-web+proto`
- Accept: Same

### Headers Required
- `Authorization: Bearer <token>`
- `Content-Type: application/connect+proto`
- `Connect-Protocol-Version: 1`
- `X-Cursor-Client-Version: 2.0.77`

### Binary Framing (gRPC-web)
```
[1 byte: flags] [4 bytes: length BE] [payload]
```
- flags = 0x00 for data frame
- flags = 0x80 for trailer frame

## Files Generated

- `proto/aiserver.proto` - Main protobuf schema
- `capture/proto-types.txt` - All 2,129 type names
- `capture/stream_req_with_tools.txt` - Request field extraction
- `capture/stream_resp_with_tools.txt` - Response field extraction
- `capture/conversation_message.txt` - Message structure

## Next Steps

1. **Generate Rust code** from the .proto file using `prost-build`
2. **Implement encoding/decoding** for the key message types
3. **Test against live API** with captured token
4. **Add streaming support** for SSE responses

## Why SSL Key Logging Didn't Work

The SSL key logging (`SSLKEYLOGFILE`) only captured traffic from Chromium/Electron's standard networking layer. The `api2.cursor.sh` traffic uses a different TLS implementation (likely a native module) that doesn't respect the environment variable. The keys logged were only for:
- `metrics.cursor.sh` (Cursor telemetry)
- `search.nixos.org` (MCP server requests)
- Other non-API traffic

This is likely intentional to protect the API communication.

