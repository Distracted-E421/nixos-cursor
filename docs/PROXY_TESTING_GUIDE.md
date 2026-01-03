# Cursor AI Transparent Proxy - Testing Guide

## Overview

This guide documents the setup and testing of a transparent HTTP/2 proxy for intercepting and modifying Cursor IDE's AI traffic.

**Status**: ✅ Core proxy working, ✅ Injection working

## Architecture

See [PROXY_ARCHITECTURE.md](PROXY_ARCHITECTURE.md) for detailed architecture.

## Prerequisites

- NixOS machine (Obsidian, neon-laptop, framework)
- Rust toolchain (for building)
- Root/Sudo access (for network namespaces)

## Deployment & Testing Steps

### 1. Build the Proxy

```bash
cd ~/nixos-cursor/tools/proxy-test/cursor-proxy
cargo build --release
```

### 2. Generate CA (One-time setup)

```bash
# If ~/.cursor-proxy doesn't exist:
./target/release/cursor-proxy generate-ca --output ~/.cursor-proxy

# Create bundle
cat /etc/ssl/certs/ca-certificates.crt ~/.cursor-proxy/ca-cert.pem > ~/.cursor-proxy/ca-bundle-with-proxy.pem
```

### 3. Setup Network Namespace

Use the provided script to set up the `cursor-proxy-ns` namespace and iptables rules:

```bash
cd ~/nixos-cursor/tools/proxy-test
sudo ./setup-network-namespace.sh setup
```

### 4. Start the Proxy

```bash
cd ~/nixos-cursor/tools/proxy-test/cursor-proxy
# Kill any existing instance
pkill -f 'cursor-proxy start'

# Start in background
nohup cargo run --release -- start --port 8443 --verbose --inject --inject-prompt "System prompt injected." > /tmp/cursor-proxy.log 2>&1 &
```

### 5. Launch Cursor

Use the wrapper script to launch Cursor inside the isolated namespace:

```bash
cd ~/nixos-cursor/tools/proxy-test
./start-proxy-test.sh
```

### 6. Verify

1.  Open Cursor.
2.  Open Chat (Cmd+L / Ctrl+L).
3.  Type a message.
4.  Check logs: `tail -f /tmp/cursor-proxy.log`
5.  Look for `✨ Injected system message` in logs.
6.  Look for "System prompt injected." appearing as context in the chat (if Cursor UI shows it) or implied by the model's response.

## Troubleshooting

### "Network disconnected" / Timeout
- Check `main.rs` framing logic. Ensure "Framing-Aware Buffering" is active.

### "CertificateUnknown"
- Verify `NODE_EXTRA_CA_CERTS` is set in `run-proxy-test.sh`.

### "FRAME_SIZE_ERROR" (Analytics/NetworkService)
- Ignore these. They don't affect Chat.

## Clean Up

```bash
# Kill proxy
pkill -f 'cursor-proxy start'

# Remove namespace
sudo ./setup-network-namespace.sh cleanup
```
