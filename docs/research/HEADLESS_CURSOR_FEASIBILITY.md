# Feasibility: Headless Cursor & TUI Interface

**Status**: Experimental Research
**Objective**: Decouple the Agent logic from the Electron UI to enable high-performance automated testing and Agent-Swarm capabilities.

## The Premise

We have reverse-engineered the transport layer:
*   **Protocol**: Connect (gRPC-Web variant)
*   **Transport**: HTTP/2 over TLS
*   **Serialization**: Protobuf
*   **Auth**: `x-cursor-checksum` + Session Tokens

If we can construct a valid request packet manually, we can bypass the Cursor Application entirely.

## Architecture: `cursor-cli`

A Rust binary that acts as a headless client.

```
[cursor-cli]
    │
    ├── Authenticator
    │   ├── Loads tokens from ~/.config/Cursor/User/state.vscdb
    │   └── Generates machine-id and checksums
    │
    ├── ProtoBuilder
    │   ├── Constructs StreamUnifiedChatRequest
    │   └── Encodes to Protobuf -> Length-Prefixed -> Gzip
    │
    └── NetworkClient (h2)
        ├── Connects to api2.cursor.sh:443
        ├── Sends Headers + Frames
        └── Decodes Response Stream to Stdout
```

## Potential Use Cases

### 1. Automated Regression Testing (The "Swarm")
Run 50 parallel instances of `cursor-cli` against your local proxy to test injection strategies.
*   *Input:* `tests/prompts/*.txt`
*   *Output:* `tests/results/*.json`
*   *Verification:* Automated parsing of the response to check if injection worked.

### 2. The "Agent's Agent"
An autonomous agent that uses `cursor-cli` as a tool.
*   "Hey Gorky, check the Cursor API for me."
*   Gorky spawns `cursor-cli`, sends the prompt, and parses the output.

## Technical Challenges

1.  **Checksum Reversal**: We currently rely on *forwarding* the checksum from a real client. To run headless, we must either:
    *   Reverse-engineer the checksum generation algorithm (Hard JS obfuscation).
    *   **Or** Capture a valid checksum/token pair from a real session and "replay" it (Validity window unknown).
2.  **Auth Refresh**: Handling 401s and token refresh flows without the Electron IPC.

## Roadmap

1.  **Replay Attack Proof-of-Concept**:
    *   Capture a raw `.bin` body from the Proxy.
    *   Write a script to POST that exact body to `api2.cursor.sh` with captured headers.
    *   If successful -> Headless is possible via Replay.
2.  **Dynamic Construction**:
    *   Replace the text field in the Protobuf and send.
    *   If `x-cursor-checksum` is bound to the *body content*, this will fail (Red Flag).
    *   *Note:* Our injection tests suggest checksum IS bound to content? No, we successfully injected content while forwarding the original checksum. **This implies the checksum validates the Headers/Auth, NOT the full Body integrity.** This is a massive win for Headless feasibility.

