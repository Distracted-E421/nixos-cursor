# Nix Build Optimization for Cursor Studio

## Problem

Building Cursor Studio and cursor-docs can be slow due to:
1. **Rust compilation** - cargo builds from source
2. **SurrealDB** - Large Rust project with many dependencies
3. **Elixir/Mix** - Compiling BEAM bytecode
4. **No binary cache hits** - Building locally instead of fetching

## Current Setup

We have a Cachix cache configured but it's not being trusted:
```
warning: ignoring untrusted flake configuration setting 'extra-substituters'
```

## Solutions

### 1. Trust the Cachix Cache (Recommended First Step)

Add to your NixOS configuration:

```nix
# In nixos/hosts/Obsidian/configuration.nix
nix.settings = {
  trusted-substituters = [
    "https://nixos-cursor.cachix.org"
    "https://cache.nixos.org"
  ];
  trusted-public-keys = [
    "nixos-cursor.cachix.org-1:8YAZIsMXbzdSJh6YF71XIVR2OgnRXXZ+7e82dL5yCqI="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
};
```

Or run once:
```bash
echo "extra-substituters = https://nixos-cursor.cachix.org" | sudo tee -a /etc/nix/nix.conf
echo "extra-trusted-public-keys = nixos-cursor.cachix.org-1:8YAZIsMXbzdSJh6YF71XIVR2OgnRXXZ+7e82dL5yCqI=" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
```

### 2. Push Builds to Cachix

After building locally, push to cache for future use:

```bash
# Install cachix
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Authenticate (one-time)
cachix authtoken <your-token>

# Push after building
nix build .#cursor-studio
cachix push nixos-cursor ./result
```

### 3. Pre-built Binary Approach

For cursor-studio-egui (Rust), skip Nix entirely for dev:

```bash
# Build with cargo directly (faster incremental builds)
cd cursor-studio-egui
cargo build --release

# Run with library path fix
cursor-studio-dev  # Uses our LD_LIBRARY_PATH alias
```

### 4. Split Heavy Dependencies

Create separate flakes for heavy packages:

```nix
# services/cursor-docs/flake.nix
{
  inputs.surrealdb-bin = {
    # Use pre-built SurrealDB from official release
    url = "github:surrealdb/surrealdb/v2.0.0";
    flake = false;
  };
}
```

### 5. Use nix-fast-build

For parallel builds across multiple derivations:

```bash
nix-fast-build --flake .#cursor-studio --max-jobs 8
```

### 6. Remote Builders

Use other machines in your homelab to distribute builds:

```nix
# In nix.conf or configuration.nix
nix.distributedBuilds = true;
nix.buildMachines = [
  {
    hostName = "neon-laptop";
    system = "x86_64-linux";
    maxJobs = 4;
    speedFactor = 1;
    supportedFeatures = [ "big-parallel" ];
  }
];
```

### 7. Incremental Rust Builds with sccache

```nix
# In your devShell
buildInputs = [
  sccache
];
RUSTC_WRAPPER = "sccache";
```

## Development Workflow Optimization

### Fast Iteration (No Nix)

```bash
# For cursor-studio GUI changes:
build-cursor-studio    # cargo build --release
cursor-studio-dev      # Run with libs

# For cursor-docs changes:
cd services/cursor-docs
mix compile
mix cursor_docs.<command>
```

### NixOS Rebuild with Local Override

```bash
# Test local changes without updating flake.lock
rebuild-cursor-dev     # Uses --override-input
```

### Check What Would Build

```bash
# See what needs to be built
nix build .#cursor-studio --dry-run 2>&1 | grep "will be built"
```

## SurrealDB Specific Options

### Option A: Use Pre-built Binary

Download from SurrealDB releases and wrap:

```nix
surrealdb-bin = pkgs.stdenv.mkDerivation {
  name = "surrealdb-bin";
  src = pkgs.fetchurl {
    url = "https://github.com/surrealdb/surrealdb/releases/download/v2.0.0/surreal-v2.0.0.linux-amd64.tgz";
    sha256 = "...";
  };
  # ... installation steps
};
```

### Option B: Disable SurrealDB for Dev

In cursor-docs config, use SQLite-only mode:

```elixir
# config/dev.exs
config :cursor_docs, :vector_backend, :sqlite_vss
```

### Option C: Run SurrealDB as External Service

Instead of building, run SurrealDB via Docker:

```bash
docker run --name surrealdb -d -p 8000:8000 surrealdb/surrealdb:latest start
```

## Benchmarking Build Times

```bash
# Time a clean build
time nix build .#cursor-studio --rebuild

# Check cache effectiveness
nix path-info --json .#cursor-studio | jq '.[] | {path, narSize}'
```

## Recommended Setup

1. **Enable Cachix trust** (one-time system config)
2. **Use cargo for rapid iteration** (cursor-studio-dev alias)
3. **Use mix directly for Elixir** (cd services/cursor-docs && mix ...)
4. **Only use Nix for final testing** and releases
5. **Push successful builds to Cachix** to speed up future rebuilds

