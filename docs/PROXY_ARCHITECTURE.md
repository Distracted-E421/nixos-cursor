# Cursor AI Transparent Proxy - Architecture & Lessons Learned

**Date**: 2026-01-02
**Status**: ✅ Pass-through working, ✅ Injection working (Context File Strategy)

## Executive Summary

We built a transparent HTTP/2 proxy that intercepts Cursor IDE's AI traffic for the purpose of context injection. The proxy successfully:
- Intercepts all HTTPS traffic via network namespace + iptables
- Terminates TLS with dynamically generated certificates
- Proxies HTTP/2/gRPC streams bidirectionally
- **Solves Streaming Deadlocks** via Framing-Aware Buffering
- **Injects System Context** via a reverse-engineered Context File strategy

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                Network Namespace: cursor-proxy-ns                    │
│                                                                      │
│  ┌──────────────────┐                                               │
│  │   Test Cursor    │  All outbound :443 traffic                    │
│  │   (Electron)     │────────────────────┐                          │
│  └──────────────────┘                    │                          │
│                                          ▼                          │
│  ┌──────────────────┐    iptables    ┌──────────────────┐          │
│  │    veth-ns       │    DNAT        │  10.200.1.1:8443 │          │
│  │  10.200.1.2/24   │ ─────────────► │   (veth-host)    │          │
│  └──────────────────┘                └────────┬─────────┘          │
└───────────────────────────────────────────────┼─────────────────────┘
                                                │
                    ┌───────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    cursor-proxy (Rust)                               │
│                    Port 8443                                         │
│                                                                      │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐               │
│  │ TLS Accept  │──►│ Framing     │──►│  Injection  │               │
│  │ (rustls)    │   │ Aware Buf   │   │   Engine    │               │
│  └─────────────┘   └─────────────┘   └─────────────┘               │
│         │                  │                │                        │
│         │ Dynamic cert     │ Buffers 1st    │ Inserts              │
│         │ generation       │ message only   │ "system-context.md"  │
│         ▼                  ▼                ▼                        │
│  ┌─────────────────────────────────────────────────────────┐       │
│  │              Upstream Connection Pool                     │       │
│  │              TLS + HTTP/2 to api2.cursor.sh              │       │
│  └─────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────┐
                    │ api2.cursor.sh    │
                    │ Cursor AI Backend │
                    │ (gRPC/Connect)    │
                    └───────────────────┘
```

## Key Technical Solutions

### 1. Framing-Aware Buffering (Solving Streaming Deadlock)

**Problem**: Cursor's chat is a bi-directional gRPC stream. Standard proxies wait for the client to close the stream (EOF) before forwarding. Since Cursor keeps the stream open for the response, a naive buffer deadlocks (Client waits for Server, Proxy waits for Client).

**Solution**:
1. Read the 5-byte gRPC header (`[Flags][Length]`).
2. Buffer *only* the length specified in the header.
3. Perform injection on this isolated message.
4. Immediately forward headers + 1st message to upstream.
5. Spawn a background task to stream the rest of the connection (pass-through).

### 2. Context File Injection (Solving Protobuf Complexity)

**Problem**: Injecting a "System Message" into the chat history is hard because:
- The Protobuf schema for user/bot messages is complex (UUIDs, specific types).
- Modifying the body invalidates checksums, and generating new UUIDs might trigger server-side validation.

**Solution**:
We discovered that `ConversationEntry` (Field 3) is polymorphic. By using a simpler schema matching "Context Files", we can inject system prompts that appear as files to the LLM.

**Schema**:
- Field 1: Filename (String) -> "system-context.md"
- Field 2: Content (String) -> "**System Context**\n\n..."
- Field 5: Type (Int32) -> 0

This avoids the need for valid `bubble_id`s or complex nested message structures.

### 3. Checksum & Header Management

**Critical Findings**:
- **`x-cursor-checksum`**: MUST be forwarded. Stripping it causes `ERROR_OUTDATED_CLIENT`.
- **`content-length`**: MUST be stripped. Since we modify the body size, the original length is invalid. Mismatch causes `FRAME_SIZE_ERROR` or connection drops.

## Key Components

### 1. Network Namespace (`cursor-proxy-ns`)

Provides network isolation so only the test Cursor goes through the proxy.

```bash
# Setup (handled by setup-network-namespace.sh)
sudo ip netns add cursor-proxy-ns
...
```

### 2. TLS Interception

The proxy generates certificates on-the-fly.
**CA Setup**: `~/.cursor-proxy/ca-cert.pem` must be trusted by the Electron app via `NODE_EXTRA_CA_CERTS`.

## Lessons Learned

### 1. HTTP/2 Frame Size Mismatch

**Problem**: Proxy advertised default frame size (16KB), upstream sent larger frames.
**Symptom**: `GoAway { error_code: FRAME_SIZE_ERROR }`
**Solution**: Configure client builder with `max_frame_size(16777215)`

### 2. Protobuf "Blind" Injection

**Problem**: Appending text blindly to the end of a buffer corrupts the Protobuf structure.
**Solution**: Recursive parsing to find the specific repeated field (`ConversationEntry`) and inserting a valid Protobuf message there.

## Current State

### Working ✅
- Transparent interception
- TLS termination
- HTTP/2 bidirectional streaming (No Deadlocks)
- **Context Injection** verified
- All Cursor functionality (chat, agents)

## Files

```
nixos-cursor/tools/proxy-test/
├── cursor-proxy/
│   ├── src/
│   │   ├── main.rs          # Proxy core, Framing-Aware Buffering
│   │   └── injection.rs     # Context File Injection Logic
│   └── target/release/cursor-proxy
├── setup-network-namespace.sh
└── run-proxy-test.sh
```

## Quick Start

```bash
# 1. Start proxy
cd ~/nixos-cursor/tools/proxy-test/cursor-proxy
nohup cargo run --release -- start --port 8443 --verbose --inject --inject-prompt "System prompt injected." &

# 2. Launch Cursor
cd ~/nixos-cursor/tools/proxy-test
./run-proxy-test.sh
```

---

*This proxy enables research into AI assistant customization and context augmentation.*
