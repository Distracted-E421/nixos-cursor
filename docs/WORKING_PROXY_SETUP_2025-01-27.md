# Working Proxy Setup - January 27, 2025

## Summary

Successfully established a MITM proxy to intercept Cursor 2.4.21 API traffic for custom mode injection.

## Key Components

### 1. Network Namespace Setup

```bash
# Create namespace
sudo ip netns add cursor-proxy-ns

# Create veth pair
sudo ip link add veth-proxy type veth peer name veth-proxy-ns
sudo ip link set veth-proxy-ns netns cursor-proxy-ns

# Configure host side
sudo ip addr add 10.200.1.1/24 dev veth-proxy
sudo ip link set veth-proxy up

# Configure namespace side
sudo ip netns exec cursor-proxy-ns ip addr add 10.200.1.2/24 dev veth-proxy-ns
sudo ip netns exec cursor-proxy-ns ip link set veth-proxy-ns up
sudo ip netns exec cursor-proxy-ns ip link set lo up
sudo ip netns exec cursor-proxy-ns ip route add default via 10.200.1.1

# Enable forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
sudo iptables -A FORWARD -i veth-proxy -o veth-proxy -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 ! -o veth-proxy -j MASQUERADE
```

### 2. iptables Rules (DNAT to host proxy)

```bash
# Create chain
sudo iptables -t nat -N CURSOR_NS_PROXY 2>/dev/null || true

# Add to PREROUTING from namespace
sudo iptables -t nat -A PREROUTING -i veth-proxy -j CURSOR_NS_PROXY

# DNAT all 443 traffic to proxy on host
sudo iptables -t nat -A CURSOR_NS_PROXY -p tcp --dport 443 -j DNAT --to-destination 10.200.1.1:8443
```

### 3. Proxy Launch

```bash
cd /home/e421/nixos-cursor/tools/proxy-test/cursor-proxy
sudo nohup ./target/release/cursor-proxy start \
  --port 8443 \
  --ca-cert /home/e421/.cursor-proxy/ca-cert.pem \
  --ca-key /home/e421/.cursor-proxy/ca-key.pem \
  --inject-config /home/e421/.cursor-proxy/active-mode.toml \
  > /tmp/cursor-proxy-sudo.log 2>&1 &
```

### 4. Cursor Launch (CRITICAL: NODE_TLS_REJECT_UNAUTHORIZED=0)

```bash
DBUS=$(sudo cat /proc/$(pgrep -f plasmashell | head -1)/environ | tr '\0' '\n' | grep DBUS_SESSION_BUS_ADDRESS | cut -d= -f2-)

sudo nsenter --net=/run/netns/cursor-proxy-ns \
  sudo -u e421 \
  env DISPLAY=:0 \
      WAYLAND_DISPLAY=wayland-0 \
      XDG_RUNTIME_DIR=/run/user/1000 \
      XAUTHORITY=/run/user/1000/xauth_WNXomA \
      HOME=/home/e421 \
      DBUS_SESSION_BUS_ADDRESS="$DBUS" \
      NODE_TLS_REJECT_UNAUTHORIZED=0 \
      CURSOR_SESSION_TYPE=test \
  /nix/store/gaw69vli4p6llh98v5rq8ddz8dfkw2fm-cursor-2.4.21/bin/cursor-2.4.21 \
    --ignore-certificate-errors \
    --disable-gpu
```

## Critical Environment Variables

| Variable | Value | Purpose |
|---|----|----|
| `NODE_TLS_REJECT_UNAUTHORIZED` | `0` | **CRITICAL** - Makes Node.js accept our proxy CA |
| `DISPLAY` | `:0` | X11 display |
| `WAYLAND_DISPLAY` | `wayland-0` | Wayland display |
| `XAUTHORITY` | `/run/user/1000/xauth_*` | Must get from running KDE session |
| `DBUS_SESSION_BUS_ADDRESS` | `unix:path=/run/user/1000/bus` | D-Bus for dialogs etc. |
| `CURSOR_SESSION_TYPE` | `test` | Marks as test instance for safe-kill |

## Why --ignore-certificate-errors Alone Doesn't Work

Electron's `--ignore-certificate-errors` flag primarily affects:
- Web content/renderer processes
- Some Chromium network operations

It does NOT affect:
- Node.js native HTTPS module
- Extension host connections
- Background service workers using Node APIs

The `NODE_TLS_REJECT_UNAUTHORIZED=0` environment variable is needed because Cursor's backend services use Node.js networking.

## OAuth Flow

For sign-in to work, you need port forwarding from the namespace to the host:

```bash
# oauth-forward.sh monitors for new listening ports and forwards them
./oauth-forward.sh
```

## Proxy Behavior

The proxy:
1. Intercepts all port 443 traffic from the namespace
2. Uses `is_api2_ip()` to identify Cursor API IPs (AWS ranges)
3. For API2 traffic: TLS intercept + HTTP/2 parsing + injection
4. For other traffic: TCP passthrough (no interception)

## Injection Configuration

Located at `~/.cursor-proxy/active-mode.toml`:

```toml
enabled = true

system_prompt = """
# 🖥️ Maxim: Obsidian Development Agent
...
"""

[tool_access]
enabled = true
allow_all = true

[model]
primary = "claude-3-5-sonnet-20241022"
temperature = 0.5
```

## Troubleshooting

### TLS handshake eof
- **Cause**: Certificate not trusted
- **Fix**: Add `NODE_TLS_REJECT_UNAUTHORIZED=0` to environment

### Frame with invalid size
- **Cause**: HTTP/2 framing issues, often from connection reuse
- **Status**: Normal background noise, doesn't affect functionality

### Authorization required (X display)
- **Cause**: Missing X auth cookie
- **Fix**: Get `XAUTHORITY` path from running KDE session

### GSettings errors
- **Cause**: Missing schema directories
- **Fix**: Set `XDG_DATA_DIRS` and `GSETTINGS_SCHEMA_DIR` (non-fatal, just warnings)

