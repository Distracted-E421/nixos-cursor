# Cursor with agenix Secrets

This example demonstrates secure GitHub MCP token management using [agenix](https://github.com/ryantm/agenix).

## Prerequisites

- NixOS with flakes enabled
- SSH key pair for encryption

## Setup

### 1. Create secrets directory structure

```bash
mkdir -p secrets
```

### 2. Create secrets.nix

Define which keys can decrypt your secrets:

```nix
# secrets/secrets.nix
let
  # Your user's SSH public key
  user = "ssh-ed25519 AAAA... user@host";
  
  # Your machine's host key (get with: ssh-keyscan localhost)
  host = "ssh-ed25519 AAAA... root@myhost";
in {
  "github-token.age".publicKeys = [ user host ];
}
```

### 3. Encrypt your GitHub token

```bash
cd secrets

# Create and encrypt the token
agenix -e github-token.age
# (Editor opens - paste your GitHub PAT, save and exit)
```

### 4. Update your configuration

Copy `flake.nix` to your config and adjust:
- Username (`myuser` → your username)
- Hostname (`myhost` → your hostname)
- Home directory path

### 5. Rebuild

```bash
sudo nixos-rebuild switch --flake .#myhost
home-manager switch --flake .#myuser
```

## How It Works

1. **At NixOS activation**: agenix decrypts `github-token.age` to `/run/agenix/github-mcp-token`
2. **When Cursor starts**: The MCP wrapper reads the token from that file
3. **Security**: Token never appears in Nix store or mcp.json

## File Structure

```
your-config/
├── flake.nix
├── secrets/
│   ├── secrets.nix      # Key definitions
│   └── github-token.age # Encrypted token (safe to commit!)
└── ...
```

## Troubleshooting

### Token file not found

```
ERROR: Token file not found: /run/agenix/github-mcp-token
```

- Ensure NixOS configuration includes the `age.secrets` definition
- Run `sudo nixos-rebuild switch`
- Check: `ls -la /run/agenix/`

### Permission denied

```
ERROR: Cannot read token file: /run/agenix/github-mcp-token
```

- Ensure `owner` in `age.secrets` matches your username
- Check: `ls -la /run/agenix/github-mcp-token`
- Should be owned by your user with mode `0400`

## Security Notes

- The `.age` file is safe to commit to git (it's encrypted)
- Keep your SSH private key secure
- Rotate your GitHub token periodically

## See Also

- [agenix documentation](https://github.com/ryantm/agenix)
- [SECRETS_MANAGEMENT.md](/docs/SECRETS_MANAGEMENT.md)
