# Checkpoint: Headless Cursor & Proxy (2026-01-04)

## 🚨 Status: "The Wall" (Blocked by Checksum)

We have successfully implemented the entire transport and authentication stack for a headless Cursor client (`cursor-tui`), but are blocked by the server-side integrity check (`x-cursor-checksum`).

### ✅ Achievements (The "Green" List)

1. **Architecture**:
    - Built `cursor-tui` workspace with separated concerns (`core` vs `tui` vs `bot`).
    - Compiles `aiserver.v1.proto` using `tonic` (gRPC) and `prost`.

2. **Authentication**:
    - **Solved**: Automatic extraction of `access_token` and `refresh_token` from `~/.config/Cursor/User/globalStorage/state.vscdb`.
    - Code: `cursor-core/src/auth.rs`.

3. **Transport**:
    - **Solved**: TLS-secured gRPC connection to `api2.cursor.sh` using `tonic` + `rustls`.
    - **Verified**: Connection handshake succeeds.

4. **Interception (The Proxy)**:
    - Built `cursor-proxy` (Rust) to perform Man-in-the-Middle (MitM) on local Cursor traffic.
    - Generates CA certs and handles HTTP/2 framing.

### 🛑 The Failure Condition (The "Red" List)

When `cursor-tui` sends a request (even with valid tokens), the server immediately closes the stream with:

```
Status: PermissionDenied
Message: "Outdated Client Error"
Details: "Your version of Cursor no longer supports this action..."
```

**Root Cause**:

- The server validates the `x-cursor-checksum` header.
- This header is a hash of the request body + machine ID + timestamp + salt (obfuscated in JS/binary).
- Sending a request *without* this checksum (or with an invalid one) triggers the "Outdated" error.
- Spoofing `x-cursor-client-version` (e.g., to `99.99.99`) does **not** bypass this.

### 🔄 The Strategy: "Harvester" Replay

Since reversing the checksum algorithm is brittle and risky (ToS violation), we are pivoting to a **Harvester** approach:

1. **Run Proxy**: Start `cursor-proxy` locally on port 8443.
2. **Route Cursor**: Configure the *real* Cursor app to use this proxy.
3. **Harvest**: Capture a valid `{ x-cursor-checksum, x-cursor-client-version }` pair from a legitimate request.
4. **Replay**: Hardcode these headers into `cursor-tui` to verify if the checksum is bound to the *exact* body or just the *session*.
    - *Hypothesis*: If we can inject context in the proxy (which modifies the body) while keeping the original checksum, then the checksum might only validate the *metadata/auth*, not the full body.

## 🛠️ Current Session Goals (Jan 4)

1. **Spin up Proxy**: Ensure `cursor-proxy` is running clean (Fresh CA).
2. **Connect Agent**: User connects a new Cursor window/agent to the proxy.
3. **Capture**: Log the headers.
4. **Test**: Update `cursor-core` with harvested headers and retry.

## 📋 How to Connect (For the User)

To harvest headers, the user must configure their Cursor instance:

- **Settings**: `Ctrl+,` -> Search "Proxy"
- **Proxy**: `http://127.0.0.1:8443`
- **Strict SSL**: `false` (Critical for self-signed CA)
- **Action**: Send a message ("hello") in Chat.
