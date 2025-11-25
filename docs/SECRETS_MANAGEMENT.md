# Secrets Management for nixos-cursor

> **Status**: Planning for v0.2.0  
> **Problem**: MCP servers need API tokens, but `~/.cursor/mcp.json` is read-only on NixOS

## The Challenge

On NixOS with Home Manager:
```
~/.cursor/mcp.json → /nix/store/xxxxx-home-manager-files/.cursor/mcp.json (read-only)
```

We **cannot** simply edit this file. Secrets must be injected at runtime, not build time.

---

## NixOS Secrets Ecosystem Overview

| Tool | Encryption | Best For | Complexity | Home Manager |
|------|------------|----------|------------|--------------|
| **agenix** | age (SSH keys) | Simple setups, single machine | Low | ✅ Via activation |
| **sops-nix** | age/GPG/cloud KMS | Teams, multi-backend | Medium | ✅ Native support |
| **ragenix** | age (Rust) | agenix + better UX | Low | ✅ Via activation |
| **vault-secrets** | HashiCorp Vault | Enterprise, existing Vault | High | ⚠️ Systemd only |
| **pass** | GPG | Unix philosophy fans | Medium | ⚠️ Manual |
| **Plain files** | None (permissions) | Simple, trusted machines | Lowest | ✅ Easy |

### Recommendation Matrix

| Use Case | Recommended Tool |
|----------|------------------|
| Single machine, personal use | agenix or plain files |
| Multi-machine homelab | sops-nix with age |
| Team/organization | sops-nix with cloud KMS |
| Existing Vault infrastructure | vault-secrets |
| Maximum simplicity | Plain files + good permissions |

---

## Approach 1: Plain Files (Simplest)

**Best for**: Personal machines, trusted environments

### Setup

```bash
# Create secrets directory
mkdir -p ~/.config/cursor-secrets
chmod 700 ~/.config/cursor-secrets

# Store token
echo "github_pat_YOUR_TOKEN" > ~/.config/cursor-secrets/github-token
chmod 600 ~/.config/cursor-secrets/github-token
```

### Home Manager Configuration

```nix
# home.nix
programs.cursor = {
  enable = true;
  mcp.servers = {
    github = {
      command = "bash";
      args = [
        "-c"
        ''
          export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ~/.config/cursor-secrets/github-token)"
          exec npx -y @modelcontextprotocol/server-github
        ''
      ];
    };
  };
};
```

### Pros/Cons
- ✅ No additional tools needed
- ✅ Works immediately
- ❌ Token in plaintext on disk
- ❌ Must manually sync between machines

---

## Approach 2: agenix (Recommended for Personal Use)

**Best for**: Personal homelab, SSH-based encryption

### Prerequisites

```nix
# flake.nix inputs
inputs.agenix.url = "github:ryantm/agenix";

# Add to system modules
agenix.nixosModules.default
```

### Setup

```bash
# Create secrets.nix to define who can decrypt
cat > secrets/secrets.nix << 'EOF'
let
  # Your SSH public keys
  user = "ssh-ed25519 AAAA...";
  # Machine host keys
  obsidian = "ssh-ed25519 AAAA...";
in {
  "github-token.age".publicKeys = [ user obsidian ];
}
EOF

# Encrypt the secret
cd secrets
agenix -e github-token.age
# (Editor opens, paste your token, save)
```

### NixOS Configuration

```nix
# configuration.nix
age.secrets.github-mcp-token = {
  file = ./secrets/github-token.age;
  owner = "e421";
  group = "users";
  mode = "0400";
  # Decrypted to /run/agenix/github-mcp-token
};
```

### Home Manager Configuration

```nix
# home.nix
programs.cursor = {
  enable = true;
  mcp.servers = {
    github = {
      command = "bash";
      args = [
        "-c"
        ''
          export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat /run/agenix/github-mcp-token)"
          exec npx -y @modelcontextprotocol/server-github
        ''
      ];
    };
  };
};
```

### Pros/Cons
- ✅ Encrypted at rest
- ✅ Uses existing SSH keys
- ✅ Declarative, reproducible
- ✅ Can sync encrypted files via git
- ❌ Requires NixOS module (not just Home Manager)
- ❌ Host key setup per machine

---

## Approach 3: sops-nix (Recommended for Teams/Multi-Machine)

**Best for**: Homelabs with multiple machines, team environments

### Prerequisites

```nix
# flake.nix inputs
inputs.sops-nix.url = "github:Mic92/sops-nix";

# Add to system and home-manager modules
sops-nix.nixosModules.sops
sops-nix.homeManagerModules.sops
```

### Setup

```bash
# Create age key (or use existing SSH key)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Create .sops.yaml in your flake root
cat > .sops.yaml << 'EOF'
keys:
  - &user_e421 age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  - &host_obsidian age1yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *user_e421
          - *host_obsidian
EOF

# Create and encrypt secrets
mkdir -p secrets
sops secrets/mcp-tokens.yaml
# (Editor opens with YAML structure)
```

### Secrets File Format

```yaml
# secrets/mcp-tokens.yaml (edited via sops)
github_token: github_pat_YOUR_TOKEN
# sops encrypts this automatically on save
```

### Home Manager Configuration

```nix
# home.nix
{ config, ... }:
{
  sops = {
    defaultSopsFile = ./secrets/mcp-tokens.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    
    secrets.github-mcp-token = {
      key = "github_token";
      # Decrypted to ~/.config/sops-nix/secrets/github-mcp-token
    };
  };

  programs.cursor = {
    enable = true;
    mcp.servers = {
      github = {
        command = "bash";
        args = [
          "-c"
          ''
            export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${config.sops.secrets.github-mcp-token.path})"
            exec npx -y @modelcontextprotocol/server-github
          ''
        ];
      };
    };
  };
}
```

### Pros/Cons
- ✅ Native Home Manager support
- ✅ Multiple encryption backends (age, GPG, AWS KMS, GCP KMS, Azure)
- ✅ YAML format for multiple secrets
- ✅ Great for multi-machine setups
- ❌ More complex initial setup
- ❌ Requires sops CLI tool

---

## Approach 4: Environment Variables (Alternative)

**Best for**: When you already have secrets in environment

### Shell Configuration

```bash
# ~/.zshrc or ~/.bashrc (not in git!)
export GITHUB_PERSONAL_ACCESS_TOKEN="github_pat_YOUR_TOKEN"
```

### Home Manager Configuration

```nix
programs.cursor = {
  enable = true;
  mcp.servers = {
    github = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-github" ];
      # Token inherited from shell environment
    };
  };
};
```

### Pros/Cons
- ✅ Very simple
- ✅ Works with any secrets tool that exports env vars
- ❌ Must start Cursor from shell (not desktop launcher)
- ❌ Token visible in process environment

---

## nixos-cursor Module Design (Implemented in v0.1.1)

The Home Manager module now has first-class secrets support via `tokenFile`:

```nix
# home.nix - Using the tokenFile option
programs.cursor = {
  enable = true;
  
  mcp = {
    enable = true;
    
    github = {
      enable = true;
      
      # Option 1: agenix path
      tokenFile = "/run/agenix/github-mcp-token";
      
      # Option 2: sops-nix path
      # tokenFile = config.sops.secrets.github-mcp-token.path;
      
      # Option 3: Plain file (less secure but works)
      # tokenFile = "${config.home.homeDirectory}/.config/cursor-secrets/github-token";
    };
  };
};
```

### How It Works

1. **Build time**: A wrapper script is generated in `/nix/store` that:
   - Checks if the token file exists
   - Reads the token from the file
   - Exports it as `GITHUB_PERSONAL_ACCESS_TOKEN`
   - Executes the actual MCP server

2. **Runtime**: When Cursor starts the MCP server:
   - The wrapper reads the **decrypted** secret file
   - Token never touches the Nix store
   - Works with any secrets manager that writes to a file

3. **Security**: 
   - Token is not in `mcp.json` or Nix store
   - Only readable by your user (via secrets manager permissions)
   - Wrapper validates file exists and is readable

### Implementation Strategy

The module will:
1. Generate wrapper scripts that read secrets at runtime
2. Never put actual secrets in the Nix store
3. Support any secrets manager via file paths
4. Provide helpers for common patterns (agenix, sops-nix)

---

## Security Hardening with nix-mineral

If you're using [nix-mineral](https://github.com/cynicsketch/nix-mineral) for system hardening:

### Relevant Hardening Features

| Feature | Impact on Cursor/MCP | Mitigation |
|---------|---------------------|------------|
| hidepid on /proc | None - Cursor runs as your user | N/A |
| AppArmor enforcement | May block MCP servers | Create AppArmor profiles |
| USBGuard | None | N/A |
| Firewall (block incoming) | None - MCP are outbound | N/A |
| Disable core dumps | Good - protects secrets in crashes | N/A |
| /home permissions | Good - protects secret files | N/A |

### AppArmor Considerations

If nix-mineral enforces AppArmor, MCP servers (especially Node.js ones) may need profiles:

```nix
# Example AppArmor profile for MCP servers
security.apparmor.policies.mcp-servers = {
  enable = true;
  profile = ''
    # Allow Node.js MCP servers
    /nix/store/*-nodejs-*/bin/node ix,
    /home/*/.npm/** r,
    /run/agenix/* r,
    # Network access for GitHub API
    network inet stream,
    network inet6 stream,
  '';
};
```

### Secret File Permissions

nix-mineral makes `/home/$USER` only readable by owner. This is **good** for secrets:

```bash
# Verify permissions
ls -la ~/.config/cursor-secrets/
# Should show: drwx------ (700) for directory
# Should show: -r-------- (400) for token files
```

---

## Multi-Machine Sync Strategy

### With Encrypted Secrets (agenix/sops-nix)

```
homelab/
├── secrets/
│   ├── secrets.nix          # Who can decrypt (agenix)
│   ├── .sops.yaml            # Key configuration (sops)
│   ├── github-token.age      # Encrypted (agenix)
│   └── mcp-tokens.yaml       # Encrypted (sops)
├── hosts/
│   ├── obsidian/
│   │   └── configuration.nix  # References secrets
│   └── neon-laptop/
│       └── configuration.nix  # Same secrets, different host key
└── users/
    └── e421/
        └── home.nix           # MCP config with secret paths
```

### Syncing Process

1. **Add new machine's host key** to `secrets.nix` or `.sops.yaml`
2. **Re-encrypt secrets** with new key: `agenix -r` or `sops updatekeys`
3. **Commit and push** encrypted files
4. **Pull on new machine** and rebuild

---

## Quick Start: Your Immediate Setup

Since you have your token on clipboard, here's the fastest path:

### Option A: Plain File (5 minutes)

```bash
# Run these commands:
mkdir -p ~/.config/cursor-secrets
chmod 700 ~/.config/cursor-secrets

# Paste your token when prompted:
read -s -p "Paste GitHub token: " token && echo "$token" > ~/.config/cursor-secrets/github-token
chmod 600 ~/.config/cursor-secrets/github-token
unset token
```

Then update your Home Manager config (I can help with that).

### Option B: Add to Existing agenix Setup (If you have it)

```bash
cd ~/homelab/nixos/secrets
agenix -e github-mcp-token.age
# Paste token, save
```

Then reference in config.

---

## References

- [agenix](https://github.com/ryantm/agenix)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [NixOS Wiki: Comparison of secret managing schemes](https://wiki.nixos.org/wiki/Comparison_of_secret_managing_schemes)
- [nix-mineral](https://github.com/cynicsketch/nix-mineral)

---

*Last updated: 2025-11-25*
