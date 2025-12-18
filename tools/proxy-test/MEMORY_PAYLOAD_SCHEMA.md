# PotentiallyGenerateMemory Payload Schema

**This is the most important endpoint for context injection** - it contains the COMPLETE conversation context.

## Top-Level Structure

```protobuf
message PotentiallyGenerateMemoryRequest {
  string conversation_id = 1;        // UUID: "37faa750-c36a-430f-aca6-779f47905fcd"
  repeated ConversationTurn turns = 2;  // All messages in conversation
  string repository_url = 3;         // "https://github.com/Distracted-E421/nixos-cursor"
  string workspace_id = 4;           // UUID
}
```

## ConversationTurn Structure

Based on analysis of 132 turns in sample payload:

```protobuf
message ConversationTurn {
  // Core fields
  string content = 1;              // Message text, file content, or terminal output
  int32 role = 2;                  // 1 = user, 2 = assistant
  
  // File context (field 3)
  repeated FileContext files = 3;
  
  // Identity
  string message_id = 13;          // UUID for this message
  
  // Tool calls
  repeated ToolCall tool_calls = 18;
  
  // Relationships
  int32 unknown_29 = 29;           // Often 1
  string parent_message_id = 32;   // UUID of parent (for threading)
  
  // Response metadata
  ResponseMetadata metadata = 45;
  
  // Additional role info
  int32 role_secondary = 47;       // 2 = assistant, 4 = ?
  string thread_id = 50;           // UUID linking related messages
  
  // Status
  int32 status = 63;               // 0 = complete
  int32 token_count = 65;          // For assistant messages
  string timestamp = 78;           // ISO 8601: "2025-12-17T22:20:14.974Z"
  int32 completion_status = 80;    // 0 = done
}
```

## FileContext Structure

```protobuf
message FileContext {
  string path = 1;                 // File path relative to workspace
  int32 status = 2;                // 1 = active
  string content = 3;              // FULL file contents!
  int32 type = 6;                  // File type enum
  int32 type2 = 7;                 // Secondary type
  bool git_tracked = 10;           // In git?
}
```

## ToolCall Structure

```protobuf
message ToolCall {
  string tool_id = 1;              // "toolu_01JMh5inMWS9AgUbRejeoE6Q"
  string tool_name = 2;            // "run_terminal_cmd", "search_replace", "write", etc.
  bool completed = 3;              // 1 = done
  string arguments_json = 5;       // JSON: {"command": "...", "file_path": "..."}
  ToolResult result = 8;           // Result from tool
  ToolInvocation invocation = 11;  // Invocation metadata
  string invocation_id = 12;       // UUID
}

message ToolResult {
  int32 result_type = 1;           // 15 = terminal, 38 = file edit, etc.
  TerminalResult terminal = 24;    // For terminal commands
  string tool_id = 35;             // Back-reference
  string result_id = 48;           // UUID
  bool success = 49;               // 1 = success
  FileEditResult file_edit = 51;   // For file edits
}

message TerminalResult {
  bytes output = 1;                // Terminal output with ANSI codes!
  int32 exit_code = 3;             // 0 = success
  bool interactive = 6;            // Required user interaction?
  bool truncated = 9;              // Output was truncated?
  bool background = 10;            // Background process?
  CommandInfo command_info = 14;   // Parsed command structure
}

message FileEditResult {
  string before = 1;               // Content before edit
  EditDiff diff = 3;               // Diff information
  bool success = 8;                // Edit succeeded?
  string message = 10;             // Status message
  string after = 12;               // Content after edit
}
```

## ResponseMetadata Structure

```protobuf
message ResponseMetadata {
  string response_text = 1;        // AI's response text
  bytes response_binary = 2;       // Binary blob (encrypted?)
}
```

## Key Insights

### Content in Field 1

Field 1 contains various types based on context:
- **User messages**: Raw text like "ok, lets do option a"
- **Assistant messages**: Markdown formatted responses
- **File references**: "@filename.ext" followed by context
- **Terminal output**: Command results (may include ANSI codes)
- **Diff content**: Shows file changes

### Role Encoding

| Value | Meaning |
|-------|---------|
| 1 | User message |
| 2 | Assistant message |
| 4 | System/tool message? |

### Field 5 (Tool Arguments)

JSON-encoded tool call arguments:
```json
{
  "file_path": "/home/e421/nixos-cursor/tools/proxy-test/payload_collector.py",
  "contents": "#!/usr/bin/env python3\n..."
}
```

Or for terminal:
```json
{
  "command": "cd /home/e421/nixos-cursor && git status",
  "explanation": "Checking repository status"
}
```

### Field 12 (File Content After Edit)

Contains full file content after tool operations like `write` or `search_replace`.

## Sample Payload Statistics

| Metric | Value |
|--------|-------|
| Total size | 1.65 MB |
| Conversation turns | 132 |
| Unique strings >100 chars | 293 |
| Largest string | 99,911 chars (file content) |
| Files in context | Multiple (full contents!) |
| Tool calls | ~50+ |

## Context Injection Opportunities

### 1. Intercept Before Send
Modify the PotentiallyGenerateMemory request to inject custom context:
- Add synthetic file content
- Inject system instructions
- Modify conversation history

### 2. Response Modification
(Requires response capture - not yet implemented)
Modify what Cursor "remembers" about the conversation.

### 3. Custom Modes
Inject mode-specific context into field 3 (files) or field 1 (messages):
```protobuf
// Inject a "virtual file" with mode instructions
FileContext {
  path = ".cursor/custom-mode/rust-expert.md"
  content = "You are an expert Rust developer..."
  status = 1
}
```

## Next Steps

1. **Build Rust proxy** with HTTP/2 streaming support
2. **Implement Protobuf serialization** using prost
3. **Create injection API** for adding context
4. **Handle streaming responses** for ChatService

