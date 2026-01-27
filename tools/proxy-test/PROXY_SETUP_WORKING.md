# Cursor Proxy Setup - Working Configuration

**Date**: 2026-01-27
**Tested With**: Cursor 2.4.21

## What Made It Work

### 1. Network Namespace Setup
```bash
# Create namespace
sudo ip netns add cursor-proxy-ns

# Create veth pair
sudo ip link add veth-host type veth peer name veth-proxy
sudo ip link set veth-proxy netns cursor-proxy-ns

# Configure host side
sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip link set veth-host up

# Configure namespace side
sudo ip netns exec cursor-proxy-ns ip addr add 10.200.1.2/24 dev veth-proxy
sudo ip netns exec cursor-proxy-ns ip link set veth-proxy up
sudo ip netns exec cursor-proxy-ns ip link set lo up
sudo ip netns exec cursor-proxy-ns ip route add default via 10.200.1.1
```

### 2. NAT and Forwarding
```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Masquerade for namespace traffic
sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -j MASQUERADE

# DNAT port 443 to proxy (CRITICAL: use DNAT, not REDIRECT!)
sudo ip netns exec cursor-proxy-ns iptables -t nat -A OUTPUT -p tcp --dport 443 -j DNAT --to-destination 10.200.1.1:8443
```

### 3. Run Proxy with Sudo
```bash
# Proxy MUST run with sudo for proper permissions
cd ~/nixos-cursor/tools/proxy-test/cursor-proxy
sudo ./target/release/cursor-proxy start --port 8443 \
  --ca-cert ~/.cursor-proxy/ca-cert.pem \
  --ca-key ~/.cursor-proxy/ca-key.pem \
  --inject-config ~/.cursor-proxy/active-mode.toml
```

### 4. Launch Cursor in Namespace
```bash
sudo ip netns exec cursor-proxy-ns sudo -E -u e421 env \
  HOME=/home/e421 \
  DISPLAY=:0 \
  WAYLAND_DISPLAY=wayland-0 \
  XDG_RUNTIME_DIR=/run/user/1000 \
  XAUTHORITY=/run/user/1000/xauth_WNXomA \
  CURSOR_SESSION_TYPE=test \
  /tmp/cursor-2.4.21/share/cursor-2.4.21/cursor \
  --ignore-certificate-errors \
  --disable-gpu \
  --user-data-dir=/home/e421/.cursor-test-envs/proxy-test-2.4.21 \
  --folder /tmp/cursor-test-workspace
```

## Key Insights

### Why DNAT Instead of REDIRECT
- `REDIRECT` changes destination to localhost within the namespace
- But proxy runs on HOST, not in namespace
- `DNAT` to 10.200.1.1:8443 routes to proxy on host correctly

### Loop Detection
The proxy detects when traffic would loop back:
1. Client in namespace connects to api2.cursor.sh:443
2. DNAT redirects to 10.200.1.1:8443 (proxy)
3. Proxy sees original_dst as 10.200.1.1:8443 (itself!)
4. Proxy falls back to DNS resolution for upstream

### TCP Passthrough
Non-API2 traffic (Cloudflare CDN, marketplace, etc.) passes through directly without TLS interception - only api2.cursor.sh gets intercepted.

### OAuth Callback
The OAuth callback works because:
1. Browser runs on host (outside namespace)
2. Cursor's callback server may use different port/mechanism
3. Some traffic passes through via TCP passthrough

## Files Modified

- `tools/proxy-test/cursor-proxy/src/main.rs` - Added TCP passthrough for non-API2 IPs
- `flake.nix` - Added 2.4.x and 2.3.x versions
- `tools/proxy-test/setup-network-namespace.sh` - Updated with DNAT rules

## Next Steps

1. Test custom mode injection
2. Verify system prompt is being injected into chat requests
3. Add CA to system trust to avoid --ignore-certificate-errors
