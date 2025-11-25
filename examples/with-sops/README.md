# Cursor with sops-nix Secrets

This example demonstrates secure GitHub MCP token management using [sops-nix](https://github.com/Mic92/sops-nix).

sops-nix is ideal for:
- Multi-machine homelabs (different keys per machine)
- Team environments
- Users who want native Home Manager integration

## Prerequisites

- NixOS or standalone Home Manager with flakes
- `age` and `sops` CLI tools

## Setup

### 1. Generate an age key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# Note the public key (age1...) - you'll need it
cat ~/.config/sops/age/keys.txt | grep "public key"
```

### 2. Create .sops.yaml

In your config root:

```yaml
# .sops.yaml
keys:
  - &user_myuser age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *user_myuser
```

### 3. Create and encrypt secrets

```bash
mkdir -p secrets

# Create the secrets file (sops will encrypt on save)
sops secrets/mcp-tokens.yaml
```

In the editor, add:
```yaml
github_token: github_pat_YOUR_TOKEN_HERE
```

Save and exit. The file is now encrypted!

### 4. Update configuration

Copy `flake.nix` to your config and adjust:
- Username and home directory
- Paths to match your structure

### 5. Build and activate

```bash
home-manager switch --flake .#myuser
```

## How It Works

1. **At activation**: sops-nix decrypts `mcp-tokens.yaml` and writes individual secrets
2. **Secret path**: Each secret gets a path like `~/.config/sops-nix/secrets/github-mcp-token`
3. **Integration**: `config.sops.secrets.github-mcp-token.path` gives you the exact path
4. **Cursor**: The MCP wrapper reads the token from that path at runtime

## File Structure

```
your-config/
├── flake.nix
├── .sops.yaml           # Key configuration
└── secrets/
    └── mcp-tokens.yaml  # Encrypted secrets (safe to commit!)
```

## Example Encrypted File

```yaml
# After encryption, mcp-tokens.yaml looks like:
github_token: ENC[AES256_GCM,data:xxxxx,iv:xxxxx,tag:xxxxx,type:str]
sops:
    kms: []
    age:
        - recipient: age1xxxxxxxxxx
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            xxxxx
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2025-01-01T00:00:00Z"
    ...
```

## Multiple Secrets

Add more secrets to the same file:

```yaml
# secrets/mcp-tokens.yaml
github_token: github_pat_xxx
anthropic_key: sk-ant-xxx
openai_key: sk-xxx
```

Then declare them in your config:

```nix
sops.secrets = {
  github-mcp-token.key = "github_token";
  anthropic-key.key = "anthropic_key";
  openai-key.key = "openai_key";
};
```

## Multi-Machine Setup

Add machine-specific keys to `.sops.yaml`:

```yaml
keys:
  - &user_myuser age1xxx...
  - &host_desktop age1yyy...
  - &host_laptop age1zzz...
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *user_myuser
          - *host_desktop
          - *host_laptop
```

Then re-encrypt:
```bash
sops updatekeys secrets/mcp-tokens.yaml
```

## Troubleshooting

### "Failed to get data key"

- Your age key isn't in the list of recipients
- Run: `sops updatekeys secrets/mcp-tokens.yaml`

### Secret file not found

- Home Manager activation failed or hasn't run
- Check: `ls ~/.config/sops-nix/secrets/`
- Re-run: `home-manager switch`

### Permission denied

- sops-nix sets correct permissions by default
- If issues, check `mode` option in `sops.secrets.<name>`

## Security Notes

- Encrypted files are safe to commit to git
- Keep `~/.config/sops/age/keys.txt` secure (it's your private key!)
- Use different age keys for different trust levels

## See Also

- [sops-nix documentation](https://github.com/Mic92/sops-nix)
- [SECRETS_MANAGEMENT.md](/docs/SECRETS_MANAGEMENT.md)
- [with-agenix example](../with-agenix/) - Alternative using agenix
