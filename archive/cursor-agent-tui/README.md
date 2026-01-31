# cursor-agent-tui

A lightweight TUI for Cursor AI without Electron bloat.

## Current Status: Alpha

### Working Features ✅

| Feature | Command | Status |
|---------|---------|--------|
| **Authentication** | `cursor-agent auth --test` | ✅ Working |
| **Model Listing** | `cursor-agent models` | ✅ Working |
| **Agent Models** | `cursor-agent models --agent-only` | ✅ Working |
| **Configuration** | `cursor-agent config` | ✅ Working |

### In Progress 🚧

| Feature | Status | Blocker |
|---------|--------|---------|
| **Chat/Query** | 🚧 Proto ready | Schema reverse-engineered, implementing encoding |
| **TUI Interface** | 🚧 Waiting | Depends on chat working |
| **Tool Execution** | 🚧 Waiting | Depends on chat working |

### Protobuf Schema Status 📋

The schema has been **reverse-engineered** from Cursor's bundled code!

- **2,129 types** discovered in `aiserver.v1` namespace
- Full message definitions for `StreamUnifiedChatRequestWithTools`
- Tool call/result structures documented
- See `capture/PROTO_SCHEMA_ANALYSIS.md` for details

## Installation

```bash
cd tools/cursor-agent-tui
cargo build --release

# Add to PATH (optional)
ln -s $(pwd)/target/release/cursor-agent ~/.local/bin/
```

## Usage

### Check Authentication

```bash
# Test if auth token is valid
cursor-agent auth --test

# Show token (careful - sensitive!)
cursor-agent auth --show
```

### List Available Models

```bash
# All models
cursor-agent models

# Agent-capable models only
cursor-agent models --agent-only

# JSON output
cursor-agent models --format json
```

### Configuration

```bash
# Show config
cursor-agent config

# Edit config
cursor-agent config --edit
```

## Technical Details

### API Protocol

The Cursor API uses:
- **Connect Protocol** (v1) - gRPC-web variant from https://connectrpc.com/
- **Protobuf** serialization (binary, not JSON)
- **HTTP/2** over TLS

### Endpoints Reversed

| Endpoint | Schema Status |
|----------|---------------|
| `AiService/AvailableModels` | ✅ Working (accepts JSON) |
| `AiService/CheckQueuePosition` | ✅ Schema known |
| `ChatService/StreamUnifiedChatWithTools` | ✅ **Schema reverse-engineered** |
| `ChatService/StreamUnifiedChatWithToolsSSE` | ✅ **Schema reverse-engineered** |

### Proto Schema Location

The protobuf schema was reverse-engineered from Cursor's bundled JavaScript:

```
proto/aiserver.proto  # Main schema (2,129 types)
capture/PROTO_SCHEMA_ANALYSIS.md  # Discovery documentation
```

### Implementation Status

The chat endpoint requires:
1. ✅ **Binary protobuf encoding** - Schema now known
2. ✅ **Complex message structure** - All nested types documented  
3. ✅ **Proper field tags** - Extracted from bundled code
4. 🚧 **prost code generation** - In progress

## Development

### Run Tests

```bash
cargo test
```

### Build Release

```bash
cargo build --release
```

### Debug Output

```bash
RUST_LOG=debug cursor-agent auth --test
```

## Related Tools

- **[cleanup-cursor-db.sh](../../scripts/cleanup-cursor-db.sh)** - Clean Cursor's bloated SQLite database
- **[cursor-proxy](../cursor-proxy/)** - Transparent proxy for capturing API traffic

## Contributing

To help complete the chat implementation:

1. **Capture protobuf traffic** from Cursor IDE using Wireshark or Charles Proxy
2. **Decode wire format** to reconstruct message structure
3. **Update `src/proto.rs`** with correct field tags and types
4. **Test and iterate** until streaming works

## License

Same as parent repository.

