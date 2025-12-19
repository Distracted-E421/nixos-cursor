# Cursor Proxy NixOS Modules

This directory contains NixOS modules for isolated Cursor AI traffic interception and context injection.

## Quick Start

### Add to your flake.nix

```nix
{
  inputs.nixos-cursor.url = "github:e421/nixos-cursor";
  
  outputs = { self, nixpkgs, nixos-cursor, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-cursor.nixosModules.cursor-proxy-isolated
        {
          services.cursor-proxy-isolated = {
            enable = true;
            user = "your-username";  # Who will use cursor-test
          };
        }
      ];
    };
  };
}
```

### Rebuild and use

```bash
# Rebuild NixOS
sudo nixos-rebuild switch

# Run isolated Cursor with proxy
cursor-test ~/your-project

# Check status
cursor-test --status

# View proxy logs
cursor-test --logs
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Main Network (Your System)                       │
│                                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ Main Cursor  │  │  Tailscale   │  │ Mullvad VPN  │              │
│  │  (unaffected)│  │ (unaffected) │  │ (unaffected) │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│         │                 │                 │                       │
│         └─────────────────┴─────────────────┘                       │
│                           │                                         │
│                    ┌──────▼──────┐                                  │
│                    │   Internet  │                                  │
│                    └─────────────┘                                  │
│                           ▲                                         │
│                    veth pair                                        │
│                           │                                         │
├───────────────────────────┼─────────────────────────────────────────┤
│                           │                                         │
│               cursor-test Network Namespace                         │
│                           │                                         │
│    ┌──────────────────────┼──────────────────────────────────┐     │
│    │                      ▼                                   │     │
│    │    ┌────────────────────────────────────────────┐       │     │
│    │    │           cursor-proxy (Rust)               │       │     │
│    │    │    - Intercepts HTTPS port 443              │       │     │
│    │    │    - Decodes gRPC/Protobuf                  │       │     │
│    │    │    - Captures AI conversations              │       │     │
│    │    │    - Injection hooks                        │       │     │
│    │    └──────────────────────────────────────────────────┘       │
│    │                         ▲                                │     │
│    │              iptables REDIRECT                           │     │
│    │                         │                                │     │
│    │    ┌────────────────────┴───────────────────────┐       │     │
│    │    │         Test Cursor Instance               │       │     │
│    │    │    - Separate user data directory          │       │     │
│    │    │    - Auth copied from main Cursor          │       │     │
│    │    │    - All traffic goes through proxy        │       │     │
│    │    └────────────────────────────────────────────┘       │     │
│    │                                                          │     │
│    └──────────────────────────────────────────────────────────┘     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Why Network Namespace?

The key insight: **Cursor's Node.js AI client ignores HTTP_PROXY environment variables.**

Standard approaches fail:
- ❌ `HTTPS_PROXY` - Ignored by Cursor's AI client
- ❌ `http_proxy` - Same issue
- ❌ Chromium `--proxy-server` - Only affects browser, not AI

The solution: **Transparent proxying via iptables REDIRECT**

But iptables rules affect the entire system, which would:
- ❌ Break your VPN (Mullvad, Tailscale)
- ❌ Interfere with other traffic
- ❌ Risk your main Cursor installation

**Network namespace solves this:**
- ✅ Isolated network stack
- ✅ iptables rules only affect the namespace
- ✅ Main system completely unaffected
- ✅ Safe to experiment

## Module: cursor-proxy-isolated

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the isolated proxy environment |
| `user` | string | `"e421"` | User who will run cursor-test |
| `proxyPort` | port | `8443` | Port for proxy (inside namespace) |
| `caDir` | path | `/var/lib/cursor-proxy` | CA certificate storage |
| `captureDir` | path | `/var/lib/cursor-proxy/captures` | Captured traffic storage |

### Commands

The module installs a `cursor-test` command:

```bash
# Run Cursor with transparent proxy
cursor-test [workspace]

# Run in namespace but skip proxy
cursor-test --no-proxy [workspace]

# Show environment status
cursor-test --status

# View live proxy logs
cursor-test --logs

# Manually start proxy service
cursor-test --start-proxy

# Remove isolated data directory
cursor-test --cleanup

# Show help
cursor-test --help
```

### Services

Two systemd services are created:

1. **cursor-proxy-ns-setup.service**
   - Creates network namespace
   - Sets up veth pair for connectivity
   - Configures iptables REDIRECT rules
   - One-shot, remains after exit

2. **cursor-proxy-isolated.service**
   - Runs cursor-proxy inside the namespace
   - Intercepts all port 443 traffic
   - Started automatically by `cursor-test`

### Sudo Rules

The module configures passwordless sudo for:
- Entering the network namespace
- Starting/stopping the services

This allows normal users to run `cursor-test` without password prompts.

## How It Works

### Transparent Proxy Chain

1. **Cursor makes HTTPS request** to `api.cursor.sh:443`
2. **iptables REDIRECT** intercepts in namespace: `--dport 443 → localhost:8443`
3. **cursor-proxy** receives connection
4. **SO_ORIGINAL_DST** reveals real destination
5. **Proxy decrypts** using generated CA certificate
6. **Traffic captured** (gRPC/Protobuf decoded)
7. **Context injection** happens here
8. **Re-encrypted** and forwarded to real Cursor API
9. **Response captured** and returned to Cursor

### Why This Works

- `SO_ORIGINAL_DST` socket option only works with `REDIRECT` (not DNAT)
- Running proxy inside the namespace ensures correct socket behavior
- Namespace isolation means no impact on main system networking

## Integration

### With Cursor Studio

The captured traffic can be fed to cursor-studio for analysis:

```bash
# Captures are saved to:
/var/lib/cursor-proxy/captures/

# Format: YYYYMMDD_HHMMSS_mmm_connID.json
# Contains: service, method, headers, request/response data
```

### With MCP Servers

Context injection via the proxy enables:
- Dynamic rule injection
- Project context enhancement
- Cross-session memory

### With Cursor Agents

Agent configurations can be injected transparently:
- No modification to main Cursor
- Test agents in isolation
- Safe experimentation

## Troubleshooting

### Namespace not created

```bash
# Check if service exists
systemctl status cursor-proxy-ns-setup.service

# Manually start
sudo systemctl start cursor-proxy-ns-setup.service

# Check namespace
ip netns list
```

### Proxy not intercepting

```bash
# Check proxy is running in namespace
sudo ip netns exec cursor-test ps aux | grep cursor-proxy

# Check iptables rules in namespace
sudo ip netns exec cursor-test iptables -t nat -L OUTPUT -n

# Test connectivity from namespace
sudo ip netns exec cursor-test curl -v https://api.cursor.sh/
```

### Certificate errors

```bash
# Check CA exists
ls -la /var/lib/cursor-proxy/ca-cert.pem

# Regenerate if needed
sudo rm /var/lib/cursor-proxy/ca-*.pem
sudo systemctl restart cursor-proxy-isolated.service
```

### Can't login to test Cursor

Auth tokens are copied from main Cursor on first run. If this fails:

```bash
# Manually copy auth
cursor-test --cleanup
# Then re-run cursor-test - it will re-copy auth
```

## Security Considerations

1. **CA Certificate**: A custom CA is generated for TLS interception. 
   - Stored in `/var/lib/cursor-proxy/`
   - Only trusted inside the namespace (via `NODE_EXTRA_CA_CERTS`)
   - Does not affect system-wide trust store

2. **Network Isolation**: All proxy activity is contained in the namespace.
   - Main system traffic never touches the proxy
   - VPN/Tailscale continue working normally

3. **Captured Data**: Traffic captures may contain sensitive information.
   - Store in secure location
   - Consider encryption at rest
   - Don't commit to git

## Legacy Module: cursor-proxy

The `cursor-proxy` module is deprecated in favor of `cursor-proxy-isolated`.

Reasons:
- Required system-wide iptables rules
- Interfered with VPN traffic
- Risky for main Cursor installation
- Required manual setup for isolation

## Contributing

When modifying these modules:

1. Test in isolated environment first
2. Verify VPN/Tailscale remain unaffected
3. Check `nix flake check` passes
4. Update this documentation

