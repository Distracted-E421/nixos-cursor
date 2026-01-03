# Cursor AI Proxy with mitmproxy - Setup Complete

## ✅ Current Status

**Working Components:**
- ✅ mitmproxy transparent proxy on port 8443
- ✅ Network namespace `cursor-proxy-ns` with traffic isolation
- ✅ iptables redirection for all HTTPS traffic
- ✅ Full TLS interception with dynamic certificates
- ✅ HTTP/2 protocol support
- ✅ AI service traffic capture and logging

**Captured Services:**
- `aiserver.v1.MetricsService` - Telemetry
- `aiserver.v1.AnalyticsService` - Analytics (SubmitLogs, Batch)
- `aiserver.v1.UploadService` - Document uploads (GetDoc)
- `aiserver.v1.RepositoryService` - Repo indexing
- `aiserver.v1.AuthService` - Authentication
- `aiserver.v1.HealthService` - Health checks

## 📁 Important Paths

- **Proxy log**: `/tmp/mitmproxy.log`
- **Captured data**: `/home/e421/nixos-cursor/tools/proxy-test/mitmproxy-captures/`
- **AI capture script**: `/tmp/mitmproxy_ai_capture.py`
- **Namespace script**: `/home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh`
- **mitmproxy CA**: `~/.mitmproxy/mitmproxy-ca-cert.pem`

## 🚀 Quick Commands

### Monitor Live Traffic
```bash
tail -f /tmp/mitmproxy.log
```

### Filter for AI Chat Traffic
```bash
tail -f /tmp/mitmproxy.log | grep -E "StreamChat|chat|conversation"
```

### Check Captured Files
```bash
ls -lhS ~/nixos-cursor/tools/proxy-test/mitmproxy-captures/ | head -20
```

### Restart Proxy
```bash
pkill -f mitmdump
nohup mitmdump --mode transparent --listen-port 8443 \
    --set block_global=false --set ssl_insecure=true \
    -s /tmp/mitmproxy_ai_capture.py > /tmp/mitmproxy.log 2>&1 &
```

### Launch Cursor in Namespace
```bash
ssh localhost "sudo ip netns exec cursor-proxy-ns sudo -u e421 bash -c '\
    export DISPLAY=:0; \
    export XDG_RUNTIME_DIR=/run/user/1000; \
    export HOME=/home/e421; \
    export XAUTHORITY=/run/user/1000/xauth_nbdpax; \
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; \
    export NODE_EXTRA_CA_CERTS=/home/e421/.mitmproxy/mitmproxy-ca-cert.pem; \
    cursor
'"
```

### Teardown Everything
```bash
pkill -f mitmdump
ssh localhost "sudo /home/e421/nixos-cursor/tools/proxy-test/setup-network-namespace.sh teardown"
```

## 🎯 Next Steps

1. **Switch to the Cursor window** (check taskbar/activities - "Cursor Settings")
2. **Send an AI chat message** to capture `StreamChat` traffic
3. **Analyze captured traffic** in the mitmproxy-captures folder
4. **Write modification scripts** to inject into AI responses

## 📋 Captured Data Format

Each JSON capture file contains:
```json
{
  "timestamp": "2025-12-29T20:14:08.703275",
  "url": "https://api2.cursor.sh/aiserver.v1.Service/Method",
  "method": "POST",
  "request_headers": {...},
  "request_body": "...",
  "response_status": 200,
  "response_headers": {...},
  "response_body": "..."
}
```

## 🔐 Security Notes

- The mitmproxy CA is stored at `~/.mitmproxy/mitmproxy-ca-cert.pem`
- Only traffic from the namespace is intercepted
- Your main system is NOT affected by the proxy
- Bearer tokens and credentials are visible in captures (keep secure!)
