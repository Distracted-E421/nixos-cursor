# Cursor Agent TUI - Development Status

## ✅ Completed

1. **Protobuf Schema Reverse-Engineered**
   - Extracted 2,129 types from Cursor's bundled JavaScript
   - Created `proto/aiserver.proto` with key message definitions
   - Generated Rust code using `prost-build`

2. **Authentication Working**
   - Token extraction from Cursor's SQLite database (state.vscdb)
   - Token at: `cursorAuth/accessToken` in `ItemTable`
   - Successfully authenticates with API (AvailableModels returns 58 models)

3. **Protobuf Encoding Correct**
   - `WarmStreamUnifiedChatWithTools` accepts our encoded requests
   - Message structure verified with `protoc --decode_raw`
   - Proper Connect Protocol framing implemented

## ⚠️ Current Blocker: Client Version

**Problem:** Cursor version 2.0.77 is too old for the streaming chat endpoint.

```json
{
  "error": "ERROR_OUTDATED_CLIENT",
  "details": {
    "title": "Outdated Client Error",
    "detail": "Your version of Cursor no longer supports this action."
  }
}
```

### Endpoint Status

| Endpoint | Status | Notes |
|----------|--------|-------|
| `WarmStreamUnifiedChatWithTools` | ✅ Works | Returns `{}` (warm cache) |
| `StreamUnifiedChatWithTools` | ❌ OUTDATED_CLIENT | BiDi streaming |
| `StreamUnifiedChatWithToolsSSE` | ⏳ Hangs | Might need specific format |
| `StreamUnifiedChatWithToolsIdempotent` | ❌ Needs encryption | Too complex |

### Other Working Endpoints

- `AvailableModels` ✅
- `CheckQueuePosition` ✅

## 🔧 Next Steps to Resolve

### Option 1: Update Cursor Version
- Update to latest Cursor in NixOS
- May require nixpkgs update or manual package override

### Option 2: Find Version Bypass
- Test different `X-Cursor-Client-Version` header values
- The server might accept certain version strings

### Option 3: Different Endpoint
- The SSE endpoint might work with different request framing
- Need to capture actual Cursor traffic to see exact format

### Option 4: Use cursor-proxy
- Re-enable the cursor-proxy to intercept real Cursor traffic
- Learn the exact request/response format from actual usage

## 📁 Key Files

- `proto/aiserver.proto` - Protobuf definitions
- `src/generated/aiserver.v1.rs` - Generated Rust types  
- `src/bin/proto_test.rs` - Test binary for encoding
- `capture/PROTO_SCHEMA_ANALYSIS.md` - Schema documentation

## 🏃 Quick Test Commands

```bash
# Auth test
./target/release/cursor-agent auth --test

# Proto encoding test
./target/release/proto_test 2>&1 >/tmp/test.bin && xxd /tmp/test.bin

# Models list (works!)
./target/release/cursor-agent models
```

---
*Last updated: 2025-12-19*
