# Feasibility: Headless Cursor & TUI Interface

**Status**: Active Development (See `../designs/CURSOR_TUI_ARCHITECTURE.md`)
**Objective**: Decouple the Agent logic from the Electron UI to enable high-performance automated testing and Agent-Swarm capabilities.

## The Premise

We have reverse-engineered the transport layer:

* **Protocol**: Connect (gRPC-Web variant)
* **Transport**: HTTP/2 over TLS
* **Serialization**: Protobuf
* **Auth**: `x-cursor-checksum` + Session Tokens

If we can construct a valid request packet manually, we can bypass the Cursor Application entirely.

## Architecture: `cursor-tui` (Previously `cursor-cli`)

A Rust workspace with:
* `cursor-core`: Shared library for Protocol, Auth, and Transport.
* `cursor-tui`: Ratatui-based interface.
* `cursor-bot`: Headless automation agent.

```
[cursor-tui]
    │
    ├── Authenticator
    │   ├── Loads tokens from ~/.config/Cursor/User/state.vscdb
    │   └── Generates machine-id and checksums
    │
    ├── ProtoBuilder
    │   ├── Constructs StreamUnifiedChatRequest
    │   └── Encodes to Protobuf -> Length-Prefixed -> Gzip
    │
    └── NetworkClient (tonic)
        ├── Connects to api2.cursor.sh:443
        ├── Sends Headers + Frames
        └── Decodes Response Stream to Stdout
```

## Status Update (Jan 2026)

We have successfully implemented:
1.  **Transport**: TLS + gRPC via `tonic` works.
2.  **Auth**: Token extraction from `state.vscdb` works.
3.  **Connection**: We can hit `api2.cursor.sh`.

**The Blocker**: 
The server returns `PermissionDenied` with message "Outdated Client Error" if `x-cursor-checksum` is missing or invalid. This confirms that checksum validation is enforced and critical.

## Technical Challenges

1. **Checksum Reversal**: We currently rely on *forwarding* the checksum from a real client. To run headless, we must either:
    * Reverse-engineer the checksum generation algorithm (Hard JS obfuscation).
    * **Or** Capture a valid checksum/token pair from a real session and "replay" it (The "Harvester" Strategy).
2. **Auth Refresh**: Handling 401s and token refresh flows without the Electron IPC.

## Roadmap

1. **The Harvester (REQUIRED)**:
    * Run `tools/cursor-proxy` to intercept local Cursor traffic.
    * Capture `x-cursor-checksum` and `x-cursor-client-version` from a valid request.
    * Store for replay.
2. **Replay Attack**:
    * Use harvested headers in `cursor-tui`.
    * Verify if checksum is bound to body content (if so, we are strictly limited to replay).
    * *Note:* Our injection tests suggest checksum IS NOT strictly bound to full body content (as we injected context successfully). This suggests a window of opportunity.

## Potential Use Cases

### 1. Automated Regression Testing (The "Swarm")

Run 50 parallel instances of `cursor-bot` against your local proxy to test injection strategies.

### 2. The "Agent's Agent"

An autonomous agent that uses `cursor-bot` as a tool.
