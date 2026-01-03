# Network Namespace Isolation for Cursor Proxy Testing

## Overview

This guide explains how to run a **completely isolated** Cursor instance for proxy testing using Linux network namespaces. This ensures your main Cursor instance (and all other network traffic) is **completely unaffected** by the proxy.

## Why Network Namespaces?

| Approach | Pros | Cons |
|----------|------|------|
| **iptables by destination IP** | Simple | Affects ALL processes connecting to those IPs |
| **iptables by UID** | Per-user isolation | Requires running as different user, permission issues |
| **cgroups + iptables** | Process-level | Complex setup, cgroup v2 compatibility issues |
| **Network Namespaces** | Complete isolation, clean | Requires root for setup, slightly more complex |

Network namespaces win because:
- **Zero impact** on main system - proxied Cursor is in its own network "bubble"
- **No permission issues** - same user, just different network stack
- **Easy cleanup** - delete namespace and everything is gone
- **Reproducible** - same setup works across machines

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Host System                                 │
│                                                                      │
│  ┌──────────────────┐           ┌─────────────────────────────────┐ │
│  │   Main Cursor    │           │    cursor-proxy-ns namespace    │ │
│  │   (unaffected)   │           │                                 │ │
│  │        │         │           │  ┌─────────────────┐            │ │
│  │        ▼         │           │  │ Proxied Cursor  │            │ │
│  │  api2.cursor.sh  │           │  │                 │            │ │
│  │    (direct)      │           │  └────────┬────────┘            │ │
│  └──────────────────┘           │           │                     │ │
│                                 │           ▼                     │ │
│                                 │     veth-proxy (10.200.1.2)     │ │
│                                 └───────────┬─────────────────────┘ │
│                                             │                       │
│  ┌──────────────────────────────────────────┼─────────────────────┐ │
│  │               veth-host (10.200.1.1)     │                     │ │
│  │                         ▲                │                     │ │
│  │                         │                │                     │ │
│  │              iptables NAT PREROUTING     │                     │ │
│  │              (redirect :443 → :8443)     │                     │ │
│  │                         │                │                     │ │
│  │                         ▼                │                     │ │
│  │              ┌─────────────────┐         │                     │ │
│  │              │  Cursor Proxy   │─────────┘                     │ │
│  │              │  (port 8443)    │                               │ │
│  │              └────────┬────────┘                               │ │
│  │                       │                                        │ │
│  │                       ▼                                        │ │
│  │              api2.cursor.sh (real)                             │ │
│  │                                                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# One-command setup (recommended)
./cursor-proxy-launcher --isolated

# Or manual setup (for learning/debugging)
./setup-network-namespace.sh setup
./cursor-proxy-launcher --test  # Start proxy only
sudo ip netns exec cursor-proxy-ns sudo -u $USER cursor
./setup-network-namespace.sh teardown
```

## Manual Setup Guide

### Prerequisites

```bash
# Required: iproute2 (usually pre-installed)
which ip  # Should return /usr/bin/ip or similar

# On NixOS, ensure these are available:
nix-shell -p iproute2 iptables
```

### Step 1: Create Network Namespace

```bash
# Create the namespace
sudo ip netns add cursor-proxy-ns

# Verify it exists
ip netns list
# Should show: cursor-proxy-ns
```

### Step 2: Create Virtual Ethernet (veth) Pair

```bash
# Create veth pair: veth-host <-> veth-proxy
sudo ip link add veth-host type veth peer name veth-proxy

# Move one end into the namespace
sudo ip link set veth-proxy netns cursor-proxy-ns

# Assign IP addresses
sudo ip addr add 10.200.1.1/24 dev veth-host
sudo ip netns exec cursor-proxy-ns ip addr add 10.200.1.2/24 dev veth-proxy

# Bring interfaces up
sudo ip link set veth-host up
sudo ip netns exec cursor-proxy-ns ip link set veth-proxy up
sudo ip netns exec cursor-proxy-ns ip link set lo up
```

### Step 3: Set Up Routing

```bash
# Set default route in namespace (via veth-host)
sudo ip netns exec cursor-proxy-ns ip route add default via 10.200.1.1

# Enable IP forwarding on host
sudo sysctl -w net.ipv4.ip_forward=1

# NAT for outgoing traffic from namespace
sudo iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -o $(ip route | grep default | awk '{print $5}') -j MASQUERADE

# Allow forwarding
sudo iptables -A FORWARD -i veth-host -o $(ip route | grep default | awk '{print $5}') -j ACCEPT
sudo iptables -A FORWARD -i $(ip route | grep default | awk '{print $5}') -o veth-host -m state --state RELATED,ESTABLISHED -j ACCEPT
```

### Step 4: Set Up DNS in Namespace

```bash
# Create resolv.conf for namespace
sudo mkdir -p /etc/netns/cursor-proxy-ns
echo "nameserver 8.8.8.8" | sudo tee /etc/netns/cursor-proxy-ns/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/netns/cursor-proxy-ns/resolv.conf
```

### Step 5: Redirect Traffic to Proxy

```bash
# ONLY traffic coming from the namespace gets redirected
# This is the key - it ONLY affects the veth-host interface

# Create chain for our rules
sudo iptables -t nat -N CURSOR_NS_PROXY 2>/dev/null || true

# Redirect HTTPS from namespace to proxy
sudo iptables -t nat -A CURSOR_NS_PROXY -p tcp --dport 443 -j REDIRECT --to-port 8443

# Apply only to traffic from the namespace
sudo iptables -t nat -A PREROUTING -i veth-host -j CURSOR_NS_PROXY
```

### Step 6: Run Cursor in Namespace

```bash
# Start the proxy first (on host, listening on 8443)
./cursor-proxy-launcher --test

# In another terminal, run Cursor inside the namespace
# Note: We use sudo to enter namespace, then sudo -u to run as original user
sudo ip netns exec cursor-proxy-ns sudo -u $USER \
    NODE_EXTRA_CA_CERTS=/home/$USER/.cursor-proxy/ca-cert.pem \
    cursor
```

### Step 7: Teardown

```bash
# Remove iptables rules
sudo iptables -t nat -D PREROUTING -i veth-host -j CURSOR_NS_PROXY 2>/dev/null
sudo iptables -t nat -F CURSOR_NS_PROXY 2>/dev/null
sudo iptables -t nat -X CURSOR_NS_PROXY 2>/dev/null

# Remove NAT/forward rules (be careful not to remove other rules!)
sudo iptables -t nat -D POSTROUTING -s 10.200.1.0/24 -j MASQUERADE 2>/dev/null

# Delete veth (this also removes veth-proxy automatically)
sudo ip link del veth-host 2>/dev/null

# Delete namespace
sudo ip netns del cursor-proxy-ns 2>/dev/null

# Remove DNS config
sudo rm -rf /etc/netns/cursor-proxy-ns 2>/dev/null
```

## Automated Script

See `setup-network-namespace.sh` for a complete automated setup/teardown script.

## Troubleshooting

### "Cannot connect to network" in namespaced Cursor

1. Check veth is up: `sudo ip netns exec cursor-proxy-ns ip link show`
2. Check routing: `sudo ip netns exec cursor-proxy-ns ip route`
3. Test connectivity: `sudo ip netns exec cursor-proxy-ns ping 8.8.8.8`
4. Check DNS: `sudo ip netns exec cursor-proxy-ns nslookup google.com`

### "Permission denied" when running Cursor

Make sure to run as your user inside the namespace:
```bash
sudo ip netns exec cursor-proxy-ns sudo -u YOUR_USERNAME cursor
```

### Proxy not intercepting traffic

1. Check proxy is running: `curl -k https://localhost:8443`
2. Check iptables: `sudo iptables -t nat -L CURSOR_NS_PROXY -n -v`
3. Check PREROUTING: `sudo iptables -t nat -L PREROUTING -n -v`

### Traffic bypassing proxy

Ensure you're running Cursor **inside** the namespace. Check:
```bash
# This should show cursor-proxy-ns
sudo ip netns identify $(pgrep -f "cursor.*proxied")
```

## NixOS-Specific Notes

### Persistent Namespace (Optional)

Add to your NixOS configuration:

```nix
# /etc/nixos/configuration.nix
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

systemd.services.cursor-proxy-ns = {
  description = "Network namespace for Cursor proxy testing";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "/path/to/setup-network-namespace.sh setup";
    ExecStop = "/path/to/setup-network-namespace.sh teardown";
  };
};
```

### Firewall Considerations

If using NixOS firewall, you may need:

```nix
networking.firewall = {
  allowedTCPPorts = [ 8443 ];  # Proxy port
  extraCommands = ''
    iptables -A FORWARD -i veth-host -j ACCEPT
    iptables -A FORWARD -o veth-host -m state --state RELATED,ESTABLISHED -j ACCEPT
  '';
};
```

## Security Considerations

1. **Root required**: Setting up namespaces requires root. The proxy itself runs as `nobody`.
2. **CA certificate**: The proxy CA is only trusted within the proxied Cursor instance.
3. **Isolation**: Traffic from main Cursor is **never** affected.
4. **Cleanup**: Always run teardown to remove iptables rules and namespace.

## References

- [Linux Network Namespaces](https://man7.org/linux/man-pages/man7/network_namespaces.7.html)
- [veth - Virtual Ethernet Devices](https://man7.org/linux/man-pages/man4/veth.4.html)
- [iptables NAT](https://www.netfilter.org/documentation/HOWTO/NAT-HOWTO.html)

