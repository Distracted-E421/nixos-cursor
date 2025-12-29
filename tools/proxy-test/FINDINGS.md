# Cursor AI Streaming Interception - Research Findings

## Project Goal
Intercept Cursor IDE's AI streaming responses to enable mid-stream context injection, custom modes, and enhanced AI control.

---

## 📅 Research Timeline

### 2025-12-17: Initial Investigation

#### Discovery 1: Cursor's Architecture
**Finding:** Cursor is an Electron app with **two separate network stacks**:

| Process | Type | Network Behavior |
|---------|------|------------------|
| `network.mojom.NetworkService` | Chromium | Respects `--proxy-server` flag |
| `node.mojom.NodeService` | Node.js | **Ignores** proxy flags |

**Implication:** AI chat runs in Node.js service, which bypasses Chromium proxy settings.

#### Discovery 2: Environment Variables Ignored
**Test:** Set all standard proxy environment variables:
```bash
HTTP_PROXY=http://127.0.0.1:8080
HTTPS_PROXY=http://127.0.0.1:8080
ALL_PROXY=http://127.0.0.1:8080
NODE_TLS_REJECT_UNAUTHORIZED=0
NODE_EXTRA_CA_CERTS=/path/to/ca.pem
```

**Result:** ❌ Node.js service still makes direct connections to external IPs.

**Conclusion:** Cursor's HTTP client **deliberately ignores** proxy environment variables.

#### Discovery 3: Selective Certificate Pinning
**Finding:** Cursor uses selective cert pinning:
- ✅ Telemetry/analytics endpoints: No pinning (easily intercepted)
- ✅ Auth endpoints: No pinning
- ⚠️ AI streaming endpoints: Uses custom HTTP client that ignores proxy

#### Discovery 4: Transparent Proxy Works!
**Test:** iptables NAT redirect at kernel level:
```bash
sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner $(id -u) -j REDIRECT --to-port 8080
```

**Result:** ✅ Successfully intercepted AI-related traffic including:
- `aiserver.v1.AiService/PotentiallyGenerateMemory`
- `aiserver.v1.AiService/CheckQueuePosition`
- `aiserver.v1.AnalyticsService/Batch`
- `aiserver.v1.ToolCallEventService/SubmitToolCallEvents`

**Problem:** File descriptor exhaustion ("Too many open files") when redirecting all :443 traffic.

---

## 🔬 Technical Details

### Cursor API Endpoints Discovered

#### Services Overview

| Service | Purpose |
|---------|---------|
| `aiserver.v1.AiService` | AI models, queue management, configuration |
| `aiserver.v1.ChatService` | Real-time streaming (autocomplete, conversations) |
| `aiserver.v1.ToolCallEventService` | Tool execution reporting |
| `aiserver.v1.AnalyticsService` | Telemetry and logging |
| `aiserver.v1.DashboardService` | Usage, billing, team management |
| `aiserver.v1.ServerConfigService` | Server configuration |

#### Detailed Endpoints

| Endpoint | Purpose | Protocol | Traffic Volume |
|----------|---------|----------|----------------|
| `ChatService/StreamSpeculativeSummaries` | Real-time autocomplete | gRPC streaming | **HIGH** |
| `AiService/CheckQueuePosition` | AI queue polling | gRPC | HIGH (1/sec during requests) |
| `ToolCallEventService/SubmitToolCallEvents` | Tool call submissions | gRPC | **VERY HIGH** |
| `AnalyticsService/Batch` | Analytics batching | gRPC | HIGH |
| `AnalyticsService/SubmitLogs` | Log submission | gRPC | Medium |
| `AiService/AvailableModels` | List AI models | gRPC | Low (startup) |
| `AiService/GetDefaultModel` | Get default model | gRPC | Low |
| `AiService/AvailableDocs` | Available documentation | gRPC | Low |
| `DashboardService/GetTeams` | Team info | gRPC | Low |
| `DashboardService/GetCurrentPeriodUsage` | Usage stats | gRPC | Low |
| `DashboardService/GetHardLimit` | Usage limits | gRPC | Low |
| `ServerConfigService/GetServerConfig` | Config | gRPC | Low (startup) |
| `api3.cursor.sh/tev1/v1/rgstr` | Telemetry registration | HTTP | Medium |
| `metrics.cursor.sh/api/.../envelope` | Sentry metrics | HTTP | Medium |

#### 🎯 FOUND: AI Conversation Streaming Endpoint

**`aiserver.v1.ChatService/StreamUnifiedChatWithTools`**

This is THE endpoint for AI chat conversations! Discovered 2025-12-17 16:01.

| Property | Value |
|----------|-------|
| Full URL | `https://api2.cursor.sh/aiserver.v1.ChatService/StreamUnifiedChatWithTools` |
| Protocol | gRPC streaming over HTTP/2 |
| Serialization | Protocol Buffers (binary) |
| Behavior | Multiple requests per conversation (streaming chunks) |

**What this endpoint handles:**
- User messages sent to AI
- AI response streaming (token by token)
- Tool call invocations (file reads, terminal commands, etc.)
- All agent interactions

**Other ChatService endpoints discovered:**
- `ChatService/StreamSpeculativeSummaries` - Autocomplete/code suggestions

### Protocol Analysis
- **Primary protocol:** gRPC over HTTP/2
- **Serialization:** Protocol Buffers (binary)
- **NOT JSON** - attempts to parse as JSON fail with decode errors
- **Content-Type headers:**
  - Requests: `application/grpc` or `application/grpc-web+proto`
  - Responses: `application/grpc` with streaming

### Complete Service/Endpoint Map (as of 2025-12-17)

```
aiserver.v1.AiService/
├── AvailableDocs           # List available documentation sources
├── AvailableModels         # List available AI models (30KB+ response)
├── CheckFeaturesStatus     # Feature flags
├── CheckNumberConfigs      # Numeric configuration values
├── CheckQueuePosition      # Queue polling during AI requests
├── GetDefaultModelNudgeData # Model selection hints
├── NameTab                 # Tab naming suggestions
├── ReportBug               # Error reporting
└── ServerTime              # Server timestamp sync

aiserver.v1.ChatService/
├── StreamUnifiedChatWithTools  # 🎯 MAIN AI CONVERSATION STREAMING
└── StreamSpeculativeSummaries  # Autocomplete/code suggestions

aiserver.v1.ToolCallEventService/
└── SubmitToolCallEvents    # Report tool executions (HIGH volume)

aiserver.v1.AnalyticsService/
├── Batch                   # Analytics batching (HIGH volume)
├── BootstrapStatsig        # Statsig analytics init
└── SubmitLogs              # Log submission

aiserver.v1.DashboardService/
├── GetClientUsageData      # Usage statistics
├── GetCurrentPeriodUsage   # Current billing period
├── GetHardLimit            # Usage limits
├── GetTeams                # Team information
├── GetTokenUsage           # Token consumption
├── GetUsageBasedPremiumRequests # Premium request tracking
├── GetUserPrivacyMode      # Privacy settings
└── IsAllowedFreeTrialUsage # Trial status

aiserver.v1.ServerConfigService/
└── GetServerConfig         # Server configuration

aiserver.v1.NetworkService/
└── IsConnected             # Connectivity check

aiserver.v1.RepositoryService/
└── FastRepoSyncComplete    # Repository sync (repo42.cursor.sh)
```

### IP Addresses (api2.cursor.sh)
Load balanced across multiple AWS IPs:
- 52.200.135.112, 54.89.126.254, 34.196.182.75
- 98.87.129.38, 52.1.227.3, 18.233.190.170
- 3.228.84.246, 34.227.39.107, 3.216.239.46
- And more...

---

## ✅ Successes

1. **Identified all Cursor API domains:**
   - `api2.cursor.sh` (main AI service)
   - `api3.cursor.sh` (telemetry)
   - `metrics.cursor.sh` (Sentry)
   - `marketplace.cursorapi.com`

2. **Confirmed transparent proxy approach works**
   - iptables NAT redirect successfully intercepts Node.js traffic
   - No certificate errors when system CA is trusted

3. **Identified AI service endpoints**
   - Found `PotentiallyGenerateMemory` endpoint
   - Found `CheckQueuePosition` (queue polling)
   - Confirmed gRPC/Protobuf protocol

4. **Environment propagation verified**
   - Child processes DO inherit env vars
   - Cursor just ignores them programmatically

---

## ❌ Failures & Challenges

1. **Standard proxy methods don't work:**
   - `--proxy-server` flag: Only affects Chromium, not Node.js
   - `HTTP_PROXY` env var: Ignored by Cursor's HTTP client
   - System proxy settings: Not respected

2. **Resource exhaustion with blanket redirect:**
   - Redirecting all :443 causes file descriptor storm
   - mitmproxy defaults to 1024 open files limit

3. **Binary protocol complexity:**
   - gRPC/Protobuf requires schema to decode
   - Can't easily read/modify payloads without .proto files

---

## 🔧 Working Configuration

### Launch Script (cursor-with-full-proxy.sh)
```bash
#!/bin/bash
export HTTP_PROXY=http://127.0.0.1:8080
export HTTPS_PROXY=http://127.0.0.1:8080
export ALL_PROXY=http://127.0.0.1:8080
export NODE_TLS_REJECT_UNAUTHORIZED=0
export NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
export SSL_CERT_FILE=~/.mitmproxy/mitmproxy-ca-cert.pem
export REQUESTS_CA_BUNDLE=~/.mitmproxy/mitmproxy-ca-cert.pem
export ELECTRON_GET_USE_PROXY=1

cursor --proxy-server=http://127.0.0.1:8080 --ignore-certificate-errors "$@"
```

### Transparent Proxy (iptables)
```bash
# Selective redirect (recommended)
for ip in $(dig +short api2.cursor.sh); do
  sudo iptables -t nat -A OUTPUT -p tcp -d $ip --dport 443 -j REDIRECT --to-port 8080
done

# Or blanket redirect (requires ulimit increase)
ulimit -n 65535
sudo iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner $(id -u) -j REDIRECT --to-port 8080
```

### Cleanup
```bash
# Remove all NAT rules for your user
sudo iptables -t nat -F OUTPUT
# Or remove specific rule
sudo iptables -t nat -D OUTPUT -p tcp --dport 443 -m owner --uid-owner $(id -u) -j REDIRECT --to-port 8080
```

---

## 📋 Next Steps

### Phase 1: Robust Testing ✅ COMPLETE
- [x] Create selective iptables rules for just Cursor IPs
- [x] Increase ulimit in test script
- [x] Capture actual AI streaming data
- [x] Identify the actual token streaming endpoint → **`StreamUnifiedChatWithTools`**
- [ ] Decode gRPC/Protobuf payloads (need to capture and analyze binary content)

### Phase 2: Rust Proxy Development (NEXT)
Requirements now clear:
- [ ] Build gRPC-aware transparent proxy in Rust
- [ ] Handle `StreamUnifiedChatWithTools` specifically
- [ ] Implement Protobuf decoding (may need to reverse-engineer .proto schema)
- [ ] Create injection API for mid-stream context insertion
- [ ] Handle HTTP/2 streaming efficiently

**Key technical requirements:**
```
Protocol: gRPC over HTTP/2
Endpoint: /aiserver.v1.ChatService/StreamUnifiedChatWithTools
Transport: Transparent proxy (iptables NAT redirect)
Challenge: Binary Protobuf - need schema or dynamic decoding
```

### Phase 3: Integration
- [ ] Connect to cursor-docs for context retrieval
- [ ] Implement custom modes injection via stream modification
- [ ] Build cursor-studio integration
- [ ] Create NixOS module for automatic setup

---

## 📚 Related Files

- `tools/proxy-test/test_cursor_proxy.py` - mitmproxy addon
- `tools/proxy-test/run_test.sh` - Proxy launcher
- `tools/proxy-test/cursor-with-full-proxy.sh` - Cursor launcher with proxy
- `tools/proxy-test/CERT_PINNING_BYPASS.md` - Cert pinning notes

---

## 🔑 Key Insights

### Finding 1: Transparent Proxy is Required
Cursor deliberately bypasses standard proxy mechanisms in its Node.js service. The ONLY reliable way to intercept AI traffic is **transparent proxying at the kernel level** using iptables NAT redirect.

### Finding 2: The Streaming Endpoint
**`aiserver.v1.ChatService/StreamUnifiedChatWithTools`** is the endpoint that handles:
- All AI chat conversations
- Tool calls (file operations, terminal commands)
- Agent responses

### Finding 3: Protocol Stack
```
┌─────────────────────────────────┐
│  Application: Cursor IDE        │
├─────────────────────────────────┤
│  Serialization: Protocol Buffers│
├─────────────────────────────────┤
│  RPC: gRPC                      │
├─────────────────────────────────┤
│  Transport: HTTP/2 (streaming)  │
├─────────────────────────────────┤
│  Network: TLS over TCP          │
└─────────────────────────────────┘
```

### Implication for Context Injection
To inject context mid-stream, the Rust proxy must:
1. Terminate TLS (using trusted CA)
2. Parse HTTP/2 frames
3. Decode gRPC framing (length-prefixed messages)
4. Decode/encode Protobuf payloads
5. Insert additional content in the response stream
6. Re-encode and forward to client

This is achievable with libraries like `tonic` (gRPC), `h2` (HTTP/2), and `prost` (Protobuf) in Rust.


---

## 📊 Payload Database Analysis (2025-12-17 22:30)

### Database Statistics

| Metric | Value |
|--------|-------|
| **Total payloads** | 29,864 |
| **Unique payloads** | 140 |
| **Total data size** | 620 MB |
| **Cursor version** | 2.0.77 |

### Traffic Distribution

```
🔴 NOISE (69.2%):
   AnalyticsService/SubmitLogs:        11,530 (38.6%)
   AnalyticsService/Batch:              3,994 (13.4%)
   tev1 (Sentry):                       3,822 (12.8%)
   api (Sentry metrics):                  824 (2.8%)

⚪ MEDIUM PRIORITY (14.8%):
   ToolCallEventService:                2,246 (7.5%)
   AuthService:                         1,203 (4.0%)
   DashboardService:                      727 (2.4%)
   RepositoryService:                     235 (0.8%)
   ServerConfigService:                    27 (0.1%)

🟢 HIGH PRIORITY (16.0%):
   AiService:                           3,433 (11.5%)
   BackgroundComposerService:           1,140 (3.8%)
   FastApplyService:                      193 (0.6%)
```

### High-Priority Endpoint Analysis

| Endpoint | Samples | Unique | Size Range | Schema Status |
|----------|---------|--------|------------|---------------|
| `AiService/AvailableDocs` | 1,578 | 1 | 5,655 B | ✅ Decoded |
| `AiService/NameTab` | 576 | 3 | 548-1,240 B | ✅ Decoded |
| `AiService/CheckQueuePosition` | 570 | 3 | 56-75 B | ✅ Decoded |
| `AiService/PotentiallyGenerateMemory` | 323 | 1 | **1.7 MB** | ✅ Decoded |
| `BackgroundComposerService/GetGithubAccessTokenForRepos` | 940 | 1 | 41 B | ✅ Decoded |
| `BackgroundComposerService/ListBackgroundComposers` | 200 | 1 | 86 B | ✅ Decoded |
| `FastApplyService/ReportEditFate` | 193 | 1 | 40 B | ✅ Decoded |
| `AiService/AvailableModels` | 53 | 1 | 2 B | ✅ Decoded |
| **ChatService/StreamUnifiedChatWithTools** | **0** | - | - | ⚠️ Not captured |

### Key Finding: PotentiallyGenerateMemory

This endpoint contains the **ENTIRE conversation context** in a single 1.7MB payload:

- Full file contents being edited
- Complete message history (user + assistant)
- Tool call invocations with terminal output
- Timestamps and UUIDs for correlation
- Model names and session IDs

**Schema snippet:**
```protobuf
message PotentiallyGenerateMemoryRequest {
  string conversation_id = 1;  // UUID
  repeated ConversationFile files = 3;
  repeated ConversationTurn turns = ?;
}

message ConversationTurn {
  string text = 1;
  int32 role = 2;  // 2 = assistant
  string message_id = 13;
  ToolCall tool_call = 18;
  string timestamp = 78;  // ISO 8601
}
```

### Tooling Created

1. **`payload-filter` (Rust)** - Lightning-fast filtering
   - Loads 29,864 files in 583ms
   - Full analysis in 22ms
   - Commands: `stats`, `filter`, `unique`, `decode`, `fields`

2. **`decode_protobuf.py`** - Protobuf wire decoder
   - Handles Connect protocol
   - Recursive nested message decoding
   - String/bytes discrimination

3. **`analyze_payloads.py`** - Schema reconstruction
   - Field pattern analysis
   - Proto hint generation
   - Priority filtering

4. **`SCHEMA_RECONSTRUCTION.md`** - Complete schema documentation

---

## 🎯 Next Steps

### Immediate (Required for context injection)

1. **Capture ChatService streaming** - Need to handle HTTP/2 streaming properly
2. **Bidirectional interception** - Currently only capturing requests, need responses
3. **Proto schema generation** - Generate .proto files from observed patterns

### Short-term (Rust proxy development)

1. Build gRPC-aware transparent proxy
2. Handle `StreamUnifiedChatWithTools` specifically
3. Implement context injection layer
4. Create NixOS module for automatic setup

### Long-term (Integration)

1. Connect to cursor-docs for context retrieval
2. Build cursor-studio integration
3. Implement custom modes via stream modification


---

## 2025-12-17 ~18:00 - Rust Proxy CA Trust Progress

### What Works ✅

1. **NixOS System CA Trust** - CA added to `/etc/ssl/certs/ca-bundle.crt`
   ```nix
   security.pki.certificateFiles = [
     ./certs/cursor-proxy-ca.pem
     ./certs/mitmproxy-ca.pem
   ];
   ```

2. **Rust Proxy HTTP/2 Handling** - Full h2 crate integration
   - Dynamic certificate generation per domain
   - TLS termination working
   - HTTP/2 frame handling ready

3. **curl Test** - Successfully verified certificate chain:
   ```
   subject: CN=api2.cursor.sh
   issuer: CN=Cursor Proxy CA; O=Cursor Proxy
   SSL certificate verified via OpenSSL
   ```

### What Doesn't Work Yet ❌

1. **Cursor TLS Handshake** - Gets "tls handshake eof" errors
   - Electron/Node.js apps DON'T use system CA store by default
   - Need `NODE_EXTRA_CA_CERTS` environment variable

### Root Cause

Electron apps bundle their own CA certificates at build time. Even with NixOS system CA trust:
- `curl` and other OpenSSL-based tools work ✅
- Python `requests` with system CA works ✅  
- **Node.js/Electron apps need explicit CA** ❌

### Solution

Launch Cursor with CA explicitly:
```bash
NODE_EXTRA_CA_CERTS=~/.cursor-proxy/ca-cert.pem cursor
```

Or use the new **cursor-proxy-launcher** script that handles everything automatically.

### Key Files

| File | Purpose |
|------|---------|
| `~/.cursor-proxy/ca-cert.pem` | Proxy CA certificate |
| `~/.cursor-proxy/ca-key.pem` | Proxy CA private key |
| `/home/e421/homelab/nixos/hosts/Obsidian/certs/cursor-proxy-ca.pem` | CA in NixOS config |
| `cursor-with-proxy.sh` | Legacy launch script |
| `cursor-proxy-launcher` | **NEW** Painless all-in-one launcher |
| `cursor-proxy/` | Rust HTTP/2 proxy |

---

## 2025-12-29 - Painless Proxy Launcher

### Problem
Users were getting "TLS handshake eof" errors because:
1. Cursor wasn't being launched with `NODE_EXTRA_CA_CERTS`
2. iptables setup was manual and error-prone
3. Cleanup was inconsistent

### Solution: cursor-proxy-launcher

A new all-in-one launcher that handles everything automatically:

```bash
# First-time setup (generates CA, builds proxy)
./cursor-proxy-launcher --setup

# Launch Cursor with full proxy interception
./cursor-proxy-launcher

# Launch specific version
./cursor-proxy-launcher --version 2.3.10

# Launch with CA trust only (no interception)
./cursor-proxy-launcher --no-proxy

# Check status
./cursor-proxy-launcher --status

# Cleanup
./cursor-proxy-launcher --cleanup
```

### What the Launcher Does

1. **Ensures CA certificate exists** - Generates ECDSA CA if missing
2. **Builds Rust proxy** - First run only, cached afterwards  
3. **Starts proxy** - On port 8443, captures to `rust-captures/`
4. **Sets up iptables** - Transparently redirects api2.cursor.sh traffic
5. **Launches Cursor** - With `NODE_EXTRA_CA_CERTS` set correctly
6. **Cleans up on exit** - Removes iptables rules automatically

### Installation

```bash
# Direct usage
./tools/proxy-test/cursor-proxy-launcher

# Or install via flake
nix run .#cursor-proxy-launcher
```

### Expected Log Output (Success)

```
[*] Starting proxy on port 8443...
[✓] Proxy started (PID: 12345)
[*] Setting up iptables rules...
[✓] iptables configured (8 new rules)
[*] Launching Cursor with proxy CA trust...

# In proxy logs:
INFO [1] New connection from 192.168.0.11:55880 -> 100.52.102.154:443
DEBUG [1] Generated certificate for api2.cursor.sh
INFO [1] TLS handshake successful  ← This is the success indicator!
INFO [1] HTTP/2 connection established
INFO [1] gRPC stream: /aiserver.v1.ChatService/StreamUnifiedChatWithTools
```

### Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| "TLS handshake eof" | CA not trusted | Restart Cursor with launcher |
| "sudo: no new privileges" | Running in sandbox | Use external terminal |
| "No rules active" | iptables failed | Run with sudo access |
| "Proxy failed to start" | Port in use | `./cursor-proxy-launcher --cleanup` |

### Next Steps

1. Test Cursor with `NODE_EXTRA_CA_CERTS` explicitly set
2. If that fails, Cursor may have certificate pinning (harder to bypass)
3. Alternative: Modify Cursor's startup script/wrapper

