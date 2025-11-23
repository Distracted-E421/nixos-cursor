# Basic Flake Example

Minimal Cursor installation with no MCP servers.

## What This Does

- ✅ Installs Cursor IDE
- ❌ No MCP servers
- ❌ No extra configuration

**Use case**: Just want Cursor, don't need tools

## Usage

```bash
# Clone and activate
git clone https://github.com/yourusername/cursor-nixos
cd cursor-nixos/examples/basic-flake

# Edit username in flake.nix
vim flake.nix  # Change "myuser" to your username

# Activate
nix run .#homeConfigurations.myuser.activationPackage
```

## What You Get

- Cursor IDE installed
- Desktop launcher
- Command: `cursor`

## Next Steps

Want MCP servers? See [../with-mcp/](../with-mcp/)
