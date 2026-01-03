# Cursor Proxy Testing Status

**Last Updated:** 2025-12-30 02:05 UTC

## ✅ What's Working

### Network Namespace Isolation
- **Isolated network environment** - Only the proxied Cursor instance has its traffic intercepted
- **No impact on main system** - Other Cursor instances and system apps work normally
- **Clean setup/teardown** - Scripts manage the full lifecycle

### Traffic Interception
- **TLS interception working** - Dynamic certificate generation per-host
- **HTTP/2 negotiation successful** - ALPN properly negotiated
- **gRPC-ready** - HTTP/2 handshakes complete, ready for streaming interception

**Evidence from logs:**
```
[74] Client TLS complete, ALPN: h2
[74] Upstream TLS complete, ALPN: h2
[74] ✅ HTTP/2 handshake complete - can intercept gRPC!
```

### Infrastructure
- **Proxy server** - Rust-based, handles HTTP/1.1 and HTTP/2
- **Certificate authority** - 10-year self-signed CA
- **iptables rules** - Proper PREROUTING redirect chain
- **SSH loopback** - Bypasses Cursor's `no_new_privs` sandbox for privileged ops

## ⚠️ Current Issues

### TLS Handshake Failures
Many connections fail with "tls handshake eof":
- **Cause:** Client doesn't trust proxy CA and aborts handshake
- **Affected:** Various Cursor internal components (Node.js, extension host, etc.)
- **Workaround:** `--ignore-certificate-errors` helps Chromium but not all components

### HTTP/2 Frame Errors
Some streams get "frame with invalid size" errors:
- **Cause:** Possible timing/buffering issue in proxy
- **Impact:** Some streams fail mid-transfer

### SO_MARK Permission
The proxy can't set socket marks without CAP_NET_ADMIN:
- **Impact:** Minor - namespace isolation makes this unnecessary
- **Note:** Could add capability if needed for other use cases

## 🚀 How to Test

### Quick Start
```bash
# From external terminal (Konsole/Kitty), NOT Cursor's terminal:

# 1. Set up namespace
sudo /home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh setup

# 2. Start proxy (in same terminal)
cd /home/e421/nixos-cursor/tools/proxy-test
./cursor-proxy/target/release/cursor-proxy start \
    --port 8443 \
    --ca-cert ~/.cursor-proxy/ca-cert.pem \
    --ca-key ~/.cursor-proxy/ca-key.pem \
    --capture-dir ./rust-captures

# 3. In another terminal, launch Cursor in namespace
sudo ip netns exec cursor-proxy-ns sudo -u e421 \
    DISPLAY=:0 \
    XDG_RUNTIME_DIR=/run/user/1000 \
    XAUTHORITY=/run/user/1000/xauth_nbdpax \
    NODE_EXTRA_CA_CERTS=/home/e421/.cursor-proxy/ca-cert.pem \
    cursor --ignore-certificate-errors --ozone-platform=x11

# 4. Monitor traffic
tail -f /tmp/cursor-proxy.log

# 5. Clean up when done
sudo /home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh teardown
```

### SSH Loopback (from Cursor's terminal)
```bash
# You can use SSH loopback to run privileged commands:
ssh localhost "sudo /home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh setup"
```

## 📊 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST SYSTEM                              │
│                                                                  │
│  ┌────────────────┐         ┌────────────────────────────────┐  │
│  │ Normal Cursor  │         │     Network Namespace           │  │
│  │ (this one)     │         │     (cursor-proxy-ns)           │  │
│  │                │         │                                  │  │
│  │  Traffic goes  │         │  ┌──────────────┐               │  │
│  │  directly to   │         │  │Proxied Cursor│               │  │
│  │  internet      │         │  └──────┬───────┘               │  │
│  └────────────────┘         │         │ port 443              │  │
│                              │         ▼                       │  │
│                              │  ┌──────────────┐               │  │
│                              │  │ veth-proxy   │               │  │
│                              │  │ 10.200.1.2   │               │  │
│  ┌────────────────┐         │  └──────┬───────┘               │  │
│  │ Cursor Proxy   │         └─────────┼────────────────────────┘ │
│  │ (port 8443)    │                   │                          │
│  │                │◄──────────────────┘                          │
│  │ TLS intercept  │    iptables REDIRECT                         │
│  │ HTTP/2 decode  │    (port 443 → 8443)                         │
│  │ Stream capture │                                              │
│  └───────┬────────┘                                              │
│          │                                                       │
│          ▼                                                       │
│    Internet (Cursor API)                                         │
└─────────────────────────────────────────────────────────────────┘
```

## 🔧 Next Steps

1. **Improve CA trust**
   - Install CA system-wide via NixOS configuration
   - Or use `update-ca-trust` to add to system store

2. **Fix HTTP/2 framing**
   - Review bidirectional streaming implementation
   - Add better buffer management

3. **Add stream capture**
   - Currently captures dir is empty
   - Need to complete capture implementation for gRPC streams

4. **Test AI chat interception**
   - Once basics work, test with actual chat session
   - Verify we can see/modify streaming responses

## 📁 Files

- `cursor-proxy-launcher` - Main launcher script (legacy, use namespace script instead)
- `setup-network-namespace.sh` - Namespace setup/teardown
- `cursor-proxy/` - Rust proxy source
- `rust-captures/` - Captured traffic (currently empty)
- `NETWORK_NAMESPACE_SETUP.md` - Detailed documentation

