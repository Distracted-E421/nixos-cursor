# nixos-cursor Proxy Injection Integration Plan

**Created:** 2025-12-30
**Last Updated:** 2025-12-30
**Status:** Phase 2 Ready - Testing & Validation 🧪

## Executive Summary

We have **two proxy implementations** and need to consolidate them to get a working proxy with injection capabilities:

| Component | Status | Has Injection | Builds? |
|-----------|--------|---------------|---------|
| `tools/cursor-proxy/` (Full) | **Incomplete** | ✅ Yes | ❌ No |
| `tools/proxy-test/cursor-proxy/` (Test) | **✅ Working with Injection** | ✅ Yes | ✅ Yes |

**Goal:** Get a working proxy with injection capabilities for NixOS module integration.

---

## ✅ Phase 1 Complete: Injection Added to Test Proxy

### What Was Done

1. **Created `injection.rs` module** with:
   - `InjectionConfig` struct for configuration
   - `InjectionEngine` for runtime state
   - Protobuf manipulation (encode/decode conversation messages)
   - Varint encoding/decoding
   - Connect protocol framing handling
   - gzip compression/decompression support

2. **Updated `Cargo.toml`** with new dependencies:
   - `toml = "0.8"` for config file parsing
   - `flate2 = "1"` for gzip compression

3. **Updated `main.rs`** with:
   - `mod injection;` declaration
   - New CLI flags: `--inject`, `--inject-prompt`, `--inject-config`, `--inject-context`
   - Injection engine integration into `ProxyState`
   - Modified `handle_stream()` to apply injection to first chunk of chat requests

4. **Created `injection-rules.toml`** example configuration

5. **Created `test-injection.sh`** helper script for Phase 2 testing

---

## 🧪 Phase 2: Testing & Validation (CURRENT)

### Prerequisites ✅

All prerequisites are met:

- ✅ **Proxy binary**: `target/release/cursor-proxy` (4.6MB)
- ✅ **CA certificates**: `~/.cursor-proxy/ca-cert.pem`, `ca-key.pem`
- ✅ **Namespace script**: `setup-network-namespace.sh`
- ✅ **Test script**: `test-injection.sh`
- ✅ **Injection config**: `injection-rules.toml`
- ✅ **Injection flags**: `--inject`, `--inject-prompt`, `--inject-config`, `--inject-context`

### Testing Instructions

#### Option 1: Using Test Script (Recommended)

```bash
# Terminal 1: Start the proxy with injection
cd /home/e421/nixos-cursor/tools/proxy-test
./test-injection.sh start

# Terminal 2: Launch Cursor in the namespace
cd /home/e421/nixos-cursor/tools/proxy-test
./test-injection.sh cursor

# In Cursor: Ask any question
# Expected: AI response starts with "🔹 INJECTION CONFIRMED 🔹"

# Terminal 1: Press Ctrl+C to stop, then cleanup
./test-injection.sh stop
```

#### Option 2: Manual Testing

```bash
# Terminal 1: Setup namespace and start proxy
sudo /home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh setup

cd /home/e421/nixos-cursor/tools/proxy-test/cursor-proxy
./target/release/cursor-proxy start \
  --port 8443 \
  --ca-cert ~/.cursor-proxy/ca-cert.pem \
  --ca-key ~/.cursor-proxy/ca-key.pem \
  --inject \
  --inject-prompt "TEST: If you see this, respond with INJECTION_CONFIRMED first." \
  --verbose

# Terminal 2: Launch Cursor in namespace
sudo ip netns exec cursor-proxy-ns sudo -u e421 \
  HOME=/home/e421 \
  DISPLAY=:0 \
  XDG_RUNTIME_DIR=/run/user/1000 \
  NODE_EXTRA_CA_CERTS=/home/e421/.cursor-proxy/ca-cert.pem \
  WAYLAND_DISPLAY="" \
  cursor --ozone-platform=x11

# Cleanup
sudo /home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh teardown
```

#### Option 3: With Config File

```bash
# Uses injection-rules.toml for NixOS-specific context
cd /home/e421/nixos-cursor/tools/proxy-test/cursor-proxy
./target/release/cursor-proxy start \
  --port 8443 \
  --ca-cert ~/.cursor-proxy/ca-cert.pem \
  --ca-key ~/.cursor-proxy/ca-key.pem \
  --inject-config ./injection-rules.toml \
  --verbose
```

### What to Look For

#### In Proxy Logs (Terminal 1)
```
✨ Injected context: X → Y bytes
INFO  Connection from 10.200.1.2:xxxxx
INFO  Proxying request to api2.cursor.sh
DEBUG Request path: /aiserver.v1.ChatService/StreamUnifiedChatWithTools
```

#### In Cursor (Terminal 2)
- AI response should acknowledge the injection
- With test script: Look for "🔹 INJECTION CONFIRMED 🔹"
- With config file: AI should reference NixOS context

### Validation Checklist

| Test | Expected | Status |
|------|----------|--------|
| Proxy starts without errors | Clean startup logs | ⬜ |
| Cursor connects via proxy | Connection logs visible | ⬜ |
| Chat request intercepted | Request path logged | ⬜ |
| Injection applied | "Injected context" message | ⬜ |
| AI acknowledges injection | Response contains marker | ⬜ |
| gzip roundtrip works | No corruption errors | ⬜ |
| Large prompts work | > 1KB injection content | ⬜ |

### Troubleshooting

#### Proxy won't start
```bash
# Check if port is in use
ss -tlnp | grep 8443

# Kill any existing process
sudo pkill -f cursor-proxy
```

#### Namespace issues
```bash
# Check namespace status
sudo ip netns list

# Force cleanup
sudo ip netns delete cursor-proxy-ns 2>/dev/null || true
sudo ip link delete veth-cursor 2>/dev/null || true
```

#### Cursor won't connect
```bash
# Verify CA is trusted
NODE_EXTRA_CA_CERTS=/home/e421/.cursor-proxy/ca-cert.pem \
  curl -v https://api2.cursor.sh/health

# Check iptables rules in namespace
sudo ip netns exec cursor-proxy-ns iptables -t nat -L -n
```

#### Injection not working
```bash
# Check verbose logs for injection messages
# Look for: "Checking injection for path:" messages

# Verify injection is enabled
./target/release/cursor-proxy start --help | grep inject
```

---

## Phase 3: NixOS Module Integration (Next)

Once Phase 2 testing confirms injection works:

### Update `cursor-proxy-isolated.nix`

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.cursor-proxy-isolated;
  
  # Build the proxy package
  cursor-proxy = pkgs.rustPlatform.buildRustPackage rec {
    pname = "cursor-proxy";
    version = "0.2.0";
    
    src = ../../tools/proxy-test/cursor-proxy;
    
    cargoLock = {
      lockFile = ../../tools/proxy-test/cursor-proxy/Cargo.lock;
    };
    
    # ... build config
  };
in {
  options.services.cursor-proxy-isolated = {
    enable = lib.mkEnableOption "Cursor proxy in isolated namespace";
    
    injection = {
      enable = lib.mkEnableOption "Context injection";
      
      systemPrompt = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "System prompt to inject into conversations";
      };
      
      contextFiles = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        description = "Context files to inject";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ... service configuration with injection support
  };
}
```

---

## Architecture Reference

### Injection Flow

```
Cursor IDE sends request
         │
         ▼
┌─────────────────────────────────────────────────────┐
│                 PROXY (handle_stream)                │
│                                                      │
│  1. Receive first chunk from client                  │
│  2. Check if ChatService endpoint                    │
│  3. If injection enabled:                            │
│     a. Parse Connect frame (5-byte header)           │
│     b. Decompress gzip if compressed                 │
│     c. Build system message protobuf                 │
│     d. Prepend to conversation array                 │
│     e. Re-compress if was compressed                 │
│     f. Re-frame with Connect header                  │
│  4. Forward modified request to upstream             │
│                                                      │
└─────────────────────────────────────────────────────┘
         │
         ▼
    api2.cursor.sh (sees modified request with injected context)
```

### Protobuf Structure

```protobuf
StreamUnifiedChatRequestWithTools {
  StreamUnifiedChatRequest stream_unified_chat_request = 1 {
    repeated ConversationMessage conversation = 1 {
      string text = 1              // The message content
      MessageType type = 2         // SYSTEM = 3
      string bubble_id = 13        // Unique ID
    }
    // ... other fields
  }
  // ... tools, workspace info
}
```

---

## Known Issues

1. **Full proxy (`tools/cursor-proxy/`) still incomplete**
   - Missing 7 module files
   - No `Cargo.toml`
   - NixOS module `cursor-proxy.nix` can't build it

2. **Test proxy architecture**
   - Injection only on first chunk (works for unary chat requests)
   - Streaming request injection not implemented (not needed for current use case)

---

## Files Reference

### Test Proxy (Working with Injection)
```
tools/proxy-test/cursor-proxy/
├── Cargo.toml           # ✅ Updated with toml, flate2
├── Cargo.lock           # ✅ Dependency lock
├── injection-rules.toml # ✅ NEW - Example config
└── src/
    ├── injection.rs     # ✅ NEW - Injection module
    └── main.rs          # ✅ Updated with injection
```

### Test Infrastructure
```
tools/proxy-test/
├── test-injection.sh         # ✅ NEW - Phase 2 test helper
├── setup-network-namespace.sh # ✅ Namespace management
├── INJECTION_INTEGRATION_PLAN.md # This file
└── cursor-proxy/              # Working proxy with injection
```

### Full Proxy (Incomplete - Future Work)
```
tools/cursor-proxy/
├── Cargo.lock           # Exists but no Cargo.toml
└── src/
    ├── injection.rs     # Reference implementation
    ├── config.rs        # Has configuration
    ├── main.rs          # Complex CLI (references missing modules)
    ├── lib.rs           # References missing modules
    └── ... (missing: cert.rs, dns.rs, error.rs, events.rs, ipc.rs, iptables.rs, dashboard_egui.rs)
```
