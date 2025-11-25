# Basic Flake Example

Minimal Cursor installation with no MCP servers.

## What This Does

- Installs Cursor IDE (latest stable: 2.0.77)
- No MCP servers
- No extra configuration

**Use case**: Just want Cursor, don't need AI tools

## Usage

```bash
# Clone and activate
git clone https://github.com/Distracted-E421/nixos-cursor
cd nixos-cursor/examples/basic-flake

# Edit username in flake.nix
vim flake.nix  # Change "myuser" to your username

# Activate
nix run .#homeConfigurations.myuser.activationPackage
```

## What You Get

- Cursor IDE installed
- Desktop launcher
- Command: `cursor`

## Want Multiple Versions?

You can also install specific versions:

```nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Latest (2.0.77)
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # Classic
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-manager  # GUI picker
];
```

See the main [README](../../README.md) for all 37 available versions.

## Next Steps

Want MCP servers? See [../with-mcp/](../with-mcp/)
