# gRPC Frame Size Error Research

## Problem Statement

The cursor-proxy encounters `FRAME_SIZE_ERROR` from Cursor's backend (`api2.cursor.sh`) for:
- `NetworkService/IsConnected` 
- `AnalyticsService/SubmitLogs`

But **NOT** for:
- `ChatService/StreamUnifiedChatWithTools` ✅

## Current Implementation

- **Library**: `h2` crate (pure Rust HTTP/2)
- **Approach**: Transparent proxy with TLS interception
- **Frame handling**: Direct forwarding via h2's stream API

## Research Areas

### 1. gRPC-Web vs Native gRPC

#### Native gRPC (what we're doing)
- Uses HTTP/2 directly
- Binary protobuf over HTTP/2 frames
- Requires full HTTP/2 support including:
  - SETTINGS negotiation
  - Flow control (WINDOW_UPDATE)
  - Stream multiplexing
  - Header compression (HPACK)

#### gRPC-Web
- Designed for browsers (can't do HTTP/2 directly)
- Uses HTTP/1.1 or HTTP/2 with special encoding
- Two modes:
  - `application/grpc-web` - binary, base64 for text mode
  - `application/grpc-web-text` - always base64
- Simpler framing, no HTTP/2 specific features required
- **Envoy proxy** typically used to translate gRPC-Web ↔ native gRPC

**Question**: Is Cursor using gRPC-Web for some services?
- ChatService might use native gRPC (streaming works)
- NetworkService might expect gRPC-Web framing?

### 2. Alternative HTTP/2 Libraries

#### hyper (via h2)
- Higher-level than raw h2
- Handles more protocol details automatically
- Could simplify our implementation

#### reqwest with HTTP/2
- Even higher level
- Not suitable for proxying (designed for client use)

#### tonic
- gRPC-native library for Rust
- Could intercept at gRPC level instead of HTTP/2 level
- More semantic understanding of requests/responses
- **Potential approach**: Use tonic's channel/interceptor pattern

### 3. Connect Protocol

Cursor might be using [Connect](https://connectrpc.com/) instead of raw gRPC:
- Supports HTTP/1.1, HTTP/2, and gRPC
- More flexible framing
- Could explain different behavior for different services

**Test**: Check `content-type` headers:
- `application/grpc` = native gRPC
- `application/grpc-web` = gRPC-Web
- `application/connect+proto` = Connect protocol

### 4. Potential Solutions

#### Solution A: Use tonic for gRPC-level interception
```rust
// Instead of proxying HTTP/2 frames, intercept at gRPC level
use tonic::transport::Channel;
use tonic::codegen::InterceptedService;

// Create interceptor that modifies requests
fn intercept(req: Request<()>) -> Result<Request<()>, Status> {
    // Inject context here
}
```

**Pros**: Works at semantic level, handles protocol details
**Cons**: More complex, need to define service types

#### Solution B: Use Envoy or similar proxy
- Deploy Envoy as the actual proxy
- Configure Envoy for gRPC transcoding
- Our code just modifies payloads before/after Envoy

**Pros**: Battle-tested, handles edge cases
**Cons**: Extra dependency, more moving parts

#### Solution C: Capture and replay approach
- Don't proxy in real-time
- Capture requests, modify offline, replay
- Use for analysis rather than live injection

**Pros**: Simpler, no real-time constraints
**Cons**: Not useful for live injection

#### Solution D: HTTP CONNECT tunnel with selective interception
- Only intercept ChatService streams
- Let other services pass through unmodified
- Requires SNI-based routing or stream inspection

**Pros**: Avoids FRAME_SIZE_ERROR for non-chat services
**Cons**: Still need to solve chat injection

#### Solution E: Different h2 configuration per service
- Detect service from path
- Use different h2 settings for NetworkService vs ChatService
- Maybe NetworkService needs stricter settings?

### 5. Debugging Ideas

#### Capture raw bytes
```rust
// Before sending to upstream, dump the exact bytes
let raw = frame.to_bytes();
std::fs::write(format!("/tmp/frame-{}.bin", frame_id), &raw);
```

#### Compare with working client
- Use `grpcurl` or `grpc_cli` to send same requests
- Capture with tcpdump/wireshark
- Compare frame-by-frame with our proxy

#### Test with different backends
- Set up local gRPC server
- Test if FRAME_SIZE_ERROR is Cursor-specific or general

### 6. References

- [gRPC-Web Protocol](https://github.com/grpc/grpc/blob/master/doc/PROTOCOL-WEB.md)
- [Connect Protocol Spec](https://connectrpc.com/docs/protocol/)
- [h2 crate docs](https://docs.rs/h2/latest/h2/)
- [tonic interceptors](https://docs.rs/tonic/latest/tonic/service/interceptor/index.html)
- [Envoy gRPC transcoding](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/grpc_json_transcoder_filter)

### 7. Unexpected Frame Type Fix (Jan 1, 2026)

**Issue**: `Stream error: user error: unexpected frame type` after receiving 200 OK headers from upstream.

**Analysis**:
- Occurred when using a background task to stream injected body to upstream.
- Race condition: `response_future` (headers) might be ready before `upstream_task` completes sending body.
- When `handle_stream` starts processing response body, `h2` state machine might be confused if request body is still "in flight" or not properly closed.
- Also, `Content-Length` header was mismatching (original vs injected size).

**First Attempt (Failed)**:
- **Synchronous Buffering**: Buffer entire request body, inject, update content-length, send.
- **Result**: `ConnectError: [unknown] Network disconnected`.
- **Cause**: **Streaming Deadlock**. `ChatService` uses bi-directional streaming. The client keeps the request stream OPEN to send more data (e.g. abort signals, user typing). Our synchronous buffering logic waited for `None` (EOF) from client, but client was waiting for response. Deadlock → Timeout → Disconnect.

**Final Fix Implemented**:
- **Framing-Aware Buffering**:
  1. Read first 5 bytes to get gRPC message length.
  2. Buffer ONLY the first message.
  3. Inject into first message.
  4. Send headers + injected message immediately.
  5. Spawn background task to stream ANY REMAINING data from client.
- **Result**: Allows injection while maintaining streaming capabilities. Prevents deadlock.

## Next Steps

1. **Verify Injection Fix**: Confirm chat messages work with context injection.
2. **Investigate FRAME_SIZE_ERROR**: Use `tonic` or solution D if `h2` continues to struggle with non-chat services.
3. **Selective Proxying**: Implement SNI filtering to bypass non-Cursor traffic if needed.

---
*Created: 2026-01-01*
*Status: Researching & Fixing*
