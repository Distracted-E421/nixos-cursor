# Cursor TUI Progress Report (2026-01-03)

## Status: BLOCKED

We have successfully implemented the transport and authentication layer for a headless Cursor client in Rust, but are currently blocked by server-side integrity checks (`x-cursor-checksum` and `x-cursor-client-version`).

## Achievements

1.  **Architecture Setup**: 
    - Created `cursor-tui` workspace with `cursor-core`, `cursor-tui`, and `cursor-bot` crates.
    - Defined project structure for separation of concerns (Core logic vs TUI vs Bot).

2.  **Proto Compilation**:
    - Successfully compiled `aiserver.v1.proto` using `tonic-build` and `prost`.
    - Integrated generated Rust types into `cursor-core`.

3.  **Authentication**:
    - Implemented logic to extract authentication tokens (`access_token`, `refresh_token`) from Cursor's local SQLite database (`state.vscdb`).
    - Verified successful extraction of live tokens.

4.  **Transport Layer**:
    - Implemented a gRPC client using `tonic` and `rustls`.
    - Successfully established a TLS connection to `api2.cursor.sh`.
    - Successfully initiated a gRPC stream to `StreamUnifiedChatWithTools`.

## The Wall (Failure Condition)

We successfully connected to the endpoint, but the server closed the stream immediately with a **PermissionDenied** error.

**Error Details:**
```
status: PermissionDenied
message: "Error"
details: [
    ...
    "Outdated Client Error",
    "Your version of Cursor no longer supports this action. Please update to the latest version to continue."
]
```

### Analysis
This error persists even when spoofing the `x-cursor-client-version` header (tried `2.2.36` and `99.99.99`). This strongly indicates that the server performs a composite validation checking:
1.  `x-cursor-client-version` (Header)
2.  `x-cursor-checksum` (Header) - **MISSING/INVALID**

The "Outdated Client" message is likely a generic fallback for "Integrity Check Failed" or "Checksum Mismatch".

## Path Forward (Harvester Strategy)

To proceed, we MUST generate a valid `x-cursor-checksum`. This checksum is likely a hash of the request body + machine ID + timestamp + salt. Reversing it is difficult.

**Required Next Step:**
Implement a "Header Harvester" using `cursor-proxy`.
1.  Run `cursor-proxy` locally.
2.  Route the actual Electron Cursor app through the proxy.
3.  Trigger a chat request.
4.  Capture the valid `x-cursor-checksum` and `x-cursor-client-version` pair.
5.  Replay these headers in `cursor-tui`.

Since this requires active user intervention (running the proxy and configuring Cursor to use it), we are pausing development here.

## Code Location
- `tools/cursor-tui/`: Rust source code.
- `tools/cursor-tui/cursor-core/src/client.rs`: gRPC client implementation.
- `tools/cursor-tui/cursor-core/src/auth.rs`: Auth extraction logic.

