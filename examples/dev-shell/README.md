# Dev Shell Integration Example

How to use Cursor with `nix develop` for project-specific dependencies.

## Problem This Solves

**Forum Issue**: "Right now I can't use Cursor for development unless I install everything globally"

**Solution**: Use `buildInputs` in dev shell + launch Cursor from within the shell.

---

## What This Does

- - Project-specific dependencies via Nix
- - Cursor inherits shell environment
- - No global package pollution
- - Reproducible development environment

---

## Usage

### Method 1: Launch from Shell

```bash
# Enter development environment
nix develop

# Launch Cursor (inherits environment)
cursor .
```

**Result**: Cursor sees all packages from `buildInputs`

### Method 2: Direct Launch

```bash
# One command
nix develop --command cursor .
```

---

## Key Insight: buildInputs vs nativeBuildInputs

### - Wrong (VSCode style)

```nix
devShells.default = pkgs.mkShell {
  nativeBuildInputs = [ pkgs.nodejs ];  # Build-time only
};
```

**Problem**: Environment not passed to GUI applications

### - Correct (Cursor style)

```nix
devShells.default = pkgs.mkShell {
  buildInputs = [ pkgs.nodejs ];  # Runtime dependencies
};
```

**Why**: `buildInputs` are available in the runtime environment that Cursor inherits.

---

## Real-World Example

### Python Project

```nix
{
  devShells.default = pkgs.mkShell {
    buildInputs = with pkgs; [
      python312
      python312Packages.pip
      python312Packages.venv
      
      # Python dependencies
      python312Packages.requests
      python312Packages.flask
    ];

    shellHook = ''
      # Create venv if it doesn't exist
      if [ ! -d .venv ]; then
        python -m venv .venv
      fi
      source .venv/bin/activate
      
      echo "Python environment ready!"
      echo "Launch: cursor ."
    '';
  };
}
```

### Node.js Project

```nix
{
  devShells.default = pkgs.mkShell {
    buildInputs = with pkgs; [
      nodejs_22
      nodePackages.npm
      nodePackages.typescript
      nodePackages.typescript-language-server
    ];

    shellHook = ''
      export PATH="$PWD/node_modules/.bin:$PATH"
      
      if [ ! -d node_modules ]; then
        npm install
      fi
      
      echo "Node.js environment ready!"
      echo "Launch: cursor ."
    '';
  };
}
```

### Rust Project

```nix
{
  devShells.default = pkgs.mkShell {
    buildInputs = with pkgs; [
      rustc
      cargo
      rust-analyzer
      rustfmt
      clippy
      
      # Native dependencies
      pkg-config
      openssl
    ];

    shellHook = ''
      export RUST_BACKTRACE=1
      
      echo "Rust environment ready!"
      echo "Launch: cursor ."
    '';
  };
}
```

---

## Workflow

### Initial Setup

```bash
# 1. Create flake.nix in your project
cat > flake.nix << 'EOF'
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    devShells.x86_64-linux.default = 
      let pkgs = import nixpkgs { system = "x86_64-linux"; };
      in pkgs.mkShell {
        buildInputs = with pkgs; [
          # Your dependencies here
        ];
      };
  };
}
EOF

# 2. Enter shell
nix develop

# 3. Launch Cursor
cursor .
```

### Daily Usage

```bash
# One command to launch
nix develop --command cursor .

# Or create alias
alias cursor-dev="nix develop --command cursor ."
```

---

## Testing

Verify environment is passed:

```bash
# In Cursor's integrated terminal
which node
echo $PATH

# Should show Nix store paths
```

---

## Troubleshooting

### "Command not found" in Cursor

**Problem**: Using `nativeBuildInputs` instead of `buildInputs`

**Solution**: Move all dependencies to `buildInputs`

### Environment Not Updated

**Problem**: Shell cached

**Solution**:
```bash
nix develop --refresh
cursor .
```

### Language Server Not Found

**Problem**: Missing language server in `buildInputs`

**Solution**: Add explicitly:
```nix
buildInputs = with pkgs; [
  nodejs_22
  nodePackages.typescript-language-server  # Add this
];
```

---

## Comparison

### Before (Global Install)

```bash
# Install globally (pollutes system)
nix-env -iA nixpkgs.nodejs

# All projects use same version
cursor .  # Uses global Node.js
```

**Problems**: Version conflicts, system pollution

### After (Project Shell)

```bash
# Project-specific
nix develop --command cursor .

# Each project has its own dependencies
```

**Benefits**: Isolation, reproducibility, no conflicts

---

## Integration with Home Manager

Can combine with Cursor + MCP from Home Manager:

```nix
# home.nix
programs.cursor = {
  enable = true;
  mcp.enable = true;
};

# project/flake.nix
devShells.default = pkgs.mkShell {
  buildInputs = [ ... ];
};
```

**Usage**:
```bash
nix develop --command cursor .
```

Gets both MCP servers AND project dependencies!

---

## Next Steps

- **Declarative extensions**: See [../declarative-extensions/](../declarative-extensions/)
- **Full MCP**: See [../with-mcp/](../with-mcp/)
