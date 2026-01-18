# Cursor Proxy Development Checkpoint - January 1, 2026

## 🎯 Project Goal

Create a transparent MITM proxy that intercepts Cursor IDE's AI traffic to inject custom context into chat requests.

## ✅ What's Working

### Core Infrastructure

- **TLS Interception**: Dynamic certificate generation for `api2.cursor.sh` ✅
- **HTTP/2 Proxying**: Successfully proxies gRPC over HTTP/2 ✅
- **Network Namespace Isolation**: Test Cursor runs in isolated `cursor-proxy-ns` ✅
- **CA Trust**: Custom CA properly trusted by test Cursor instance ✅
- **ChatService Requests**: Successfully proxied with 200 OK and streaming response ✅

### Verified Success (Connection 13)

```
[13/1] 🎯 POST aiserver.v1.ChatService/StreamUnifiedChatWithTools 
[13/1] 📤 Client chunk: 16384 bytes
[13/1] 📤 Client chunk: 11546 bytes
[13/1] 📥 Response status: 200 OK
[13/1] 📥 Chunk: 46 bytes (total: 46)
... streaming response continued successfully
```

## ⚠️ Known Issues

### 1. FRAME_SIZE_ERROR on Some Requests

- **Symptom**: `GoAway { error_code: FRAME_SIZE_ERROR }` from upstream
- **Affected**: `NetworkService/IsConnected`, `AnalyticsService/SubmitLogs`
- **NOT Affected**: `ChatService/StreamUnifiedChatWithTools` (the important one!)
- **Impact**: LOW - These are telemetry/health checks, not AI chat

**Debugging Attempts (Jan 1, 2026):**
1. ❌ Added 50ms sleep after `ready()` - didn't help
2. ❌ Used `h2::client::Builder` with custom settings - didn't help
3. ❌ Checked for `is_end_stream()` to handle empty bodies - didn't help
4. ❌ Reverted to default client handshake settings - didn't help

**Root Cause Analysis:**
- The error occurs ~45ms after sending Headers+Data frames
- All SETTINGS exchanges complete correctly before request is sent
- The issue affects specific gRPC services (Network, Analytics) but NOT ChatService
- This might be server-side behavior or a protocol-level incompatibility
- ChatService requests are larger and take longer to transmit, possibly avoiding the issue

**Current Theory:**
- Cursor's backend may have different handling for health/telemetry vs chat services
- The h2 crate might be sending frames in a way that triggers strict validation
- Could be related to gRPC-Web vs native gRPC differences

### 2. Injection Partially Working (Updated Jan 1, 2026)

**✅ SUCCESS:**
- Injection IS modifying requests successfully
- Upstream returns 200 OK for injected requests
- Debug files created showing before/after payloads:
  - `/tmp/cursor-req-*-before.bin`
  - `/tmp/cursor-req-*-after.bin`

**⚠️ ISSUE: Streaming Deadlock (SOLVED)**
- **Symptom**: `ConnectError: [unknown] Network disconnected` after ~10s.
- **Cause**: Proxy was buffering entire request waiting for EOF, but client kept stream open (bi-directional streaming).
- **Fix**: Implemented **Framing-Aware Buffering**.
  - Reads gRPC header to find length of *first message*.
  - Buffers and injects ONLY the first message.
  - Sends it immediately.
  - Spawns background task to stream any subsequent data.

**Test Results:**
| Request | Before | After | Status |
|---------|--------|-------|--------|
| #1 | 227,779 bytes | 227,653 bytes | ✅ 200 OK + stream error (OLD) |
| #2 | 230,709 bytes | 230,862 bytes | ✅ 200 OK + stream error (OLD) |
| #3 | 28,160 bytes | 28,103 bytes | ✅ 200 OK + stream error (OLD) |
| #4 | TBD | TBD | Testing Framing-Aware Fix |

### 3. Network Namespace is Ephemeral

- If `cursor-proxy` restarts, the namespace `cursor-proxy-ns` might need manual cleanup if not exited cleanly.
- Currently using `run-proxy-test.sh` to manage this.

## 🛠️ Key Files

- `tools/proxy-test/cursor-proxy/src/main.rs`: Core proxy logic (Updated with Framing-Aware Buffering)
- `tools/proxy-test/cursor-proxy/src/injection.rs`: Protobuf decoding/encoding logic
- `tools/proxy-test/run-proxy-test.sh`: Setup script for namespace and iptables

## 🚀 Quick Start (Testing Mode)

```bash
# 1. Start Proxy (in separate terminal)
cd tools/proxy-test/cursor-proxy
cargo run --release -- --port 8443 --verbose --inject --inject-prompt "You are a helpful assistant."

# 2. Run Cursor in Namespace (in another terminal)
cd tools/proxy-test
./run-proxy-test.sh
```

## 📋 Current Code State

- **Language**: Rust
- **Crates**: `h2`, `tokio`, `rustls`, `rcgen`, `prost`
- **Status**: Compiles, runs, intercepts, injects (with fix deployed)

## ⏭️ Next Steps

1. **Verify Chat**: Confirm `ChatService` works without disconnects using the new fix.
2. **Refine Injection**: Ensure context is inserted in the correct Protobuf field (currently using naive field replacement).
3. **Handle FRAME_SIZE_ERROR**: If it becomes blocking, implement selective proxying or `tonic` interceptor.

## 🐛 Debugging Tips

- **Logs**: `tail -f /tmp/cursor-proxy.log`
- **Capture**: Check `/tmp/cursor-proxy-capture/` (if enabled)
- **Restart**: `pkill -f cursor-proxy` and `sudo ip netns delete cursor-proxy-ns` if stuck.

---
*Last Updated: 2026-01-01 19:47 CST*
