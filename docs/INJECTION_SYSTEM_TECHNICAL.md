# Cursor Proxy Injection System: Technical Overview

## 🎯 Architecture

The injection system is part of `cursor-proxy`, a Rust-based network proxy designed to intercept and modify traffic between the Cursor IDE and its backend servers.

### Core Components

The system resides in `tools/proxy-test/cursor-proxy/src/injection.rs` and consists of:

1.  **InjectionEngine**: The runtime orchestrator.
2.  **Recursive Protobuf Parser**: Traverses `UserRequest` -> `ConversationHistory`.
3.  **Context File Generator**: Creates valid "Context File" entries to insert into the conversation.

## 🔧 Capabilities

### 1. System Context Injection
The proxy injects a system prompt by simulating a context file named `system-context.md`.

- **Mechanism**: Inserts a new `ConversationEntry` at the start of the `conversation` repeated field.
- **Schema Used**:
  - Field 1: `system-context.md` (String)
  - Field 2: `**System Context**\n\n[Content]` (String)
  - Field 5: `0` (Int32)

This strategy is superior to "System Message" injection because it doesn't require spoofing complex UUIDs or message types that trigger server-side validation.

## 📡 Protocol Details

Cursor uses the **Connect** protocol over HTTP/2, wrapping **Protobuf** messages.

**Framing:**
`[Flags (1 byte)] [Length (4 bytes BE)] [Payload (N bytes)]`

**Payload Structure:**
The target message is `StreamUnifiedChatRequestWithTools`.
- **Field 1**: `stream_unified_chat_request` (Message)
  - **Field 3**: `conversation_history` (Message)
    - **Field 3**: `conversation_entry` (Repeated Message)
      - *Polymorphic Content*:
        - **User Message**: Field 1 (Text), Field 2 (Type=1), Field 13 (UUID)
        - **Context File**: Field 1 (Name), Field 2 (Content), Field 5 (Type=0)

## ⚠️ Safety & Risks

- **Breaking Changes**: The protobuf schema is reverse-engineered. If Cursor updates their protocol (field numbers change), injection will fail.
- **Checksums**: The proxy forwards `x-cursor-checksum` to satisfy authentication, but strips `content-length` to avoid frame size errors.

## 🔄 Configuration

Managed via `InjectionConfig` struct:

```rust
pub struct InjectionConfig {
    pub enabled: bool,
    pub system_prompt: Option<String>,
    pub context_files: Vec<PathBuf>,
    pub headers: HashMap<String, String>,
    pub spoof_version: Option<String>,
}
```

## 🛠️ Development Status

- **Location**: `tools/proxy-test/cursor-proxy/src/injection.rs`
- **Status**: ✅ Working & Verified
