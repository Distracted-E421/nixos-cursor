# cursor-docs Installation Guide

## Version: 0.3.0-pre (Pre-release)

This document covers installation methods for cursor-docs.

## Quick Start (Development Shell)

```bash
# Enter the development shell
cd services/cursor-docs
nix develop

# Or directly from GitHub (once pushed)
nix develop github:Distracted-E421/nixos-cursor?dir=services/cursor-docs

# Install dependencies and setup
mix deps.get
mix cursor_docs.setup

# Start using
mix cursor_docs.sync    # Sync from Cursor's @docs
mix cursor_docs.status  # Check status
mix cursor_docs.search "authentication"
```

## Installation Methods

### Method 1: Development Shell (Recommended for Development)

```bash
# Clone and enter shell
git clone https://github.com/Distracted-E421/nixos-cursor
cd nixos-cursor/services/cursor-docs
nix develop
```

### Method 2: NixOS Module (System-wide)

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    # cursor-docs from pre-release branch
    cursor-docs = {
      url = "github:Distracted-E421/nixos-cursor?dir=services/cursor-docs&ref=cursor-docs-0.3.0-pre";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, cursor-docs, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        cursor-docs.nixosModules.default
        {
          services.cursor-docs = {
            enable = true;
            
            # Optional: Enable SurrealDB for Tier 3 features
            surrealdb = {
              enable = true;
              graceful = true;  # Low priority, doesn't slow boot
            };
          };
        }
      ];
    };
  };
}
```

### Method 3: Home Manager Module (User-level)

Add to your Home Manager configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    
    cursor-docs = {
      url = "github:Distracted-E421/nixos-cursor?dir=services/cursor-docs&ref=cursor-docs-0.3.0-pre";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, cursor-docs, ... }: {
    homeConfigurations."user@host" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        cursor-docs.homeManagerModules.default
        {
          programs.cursor-docs = {
            enable = true;
            enableOllama = true;     # For AI embeddings
            enableSurrealdb = true;  # For Tier 3 storage
          };
        }
      ];
    };
  };
}
```

### Method 4: Direct with mix (Any System with Elixir)

```bash
# Ensure you have Elixir 1.15+ and Erlang/OTP 26+
git clone https://github.com/Distracted-E421/nixos-cursor
cd nixos-cursor/services/cursor-docs

mix deps.get
mix cursor_docs.setup
```

## Storage Tier Configuration

### Tier 1: Disabled (Default - Zero Setup)

No configuration needed. Uses FTS5 keyword search.

```elixir
# Works out of the box!
```

### Tier 2: sqlite-vss (Embedded Vectors)

```elixir
# config/config.exs
config :cursor_docs, CursorDocs.Storage.Vector.SQLiteVss,
  db_path: "~/.local/share/cursor-docs/vectors.db",
  dimensions: 768  # Must match your embedding model
```

### Tier 3: SurrealDB (Full Features)

```elixir
# config/config.exs
config :cursor_docs, CursorDocs.Storage.Vector.SurrealDB,
  endpoint: "http://localhost:8000",
  namespace: "cursor",
  database: "docs",
  username: "root",
  password: "root",
  lazy_connect: true  # Don't block if SurrealDB not ready
```

## AI Provider Configuration

### Ollama (Recommended)

```bash
# Pull an embedding model
ollama pull nomic-embed-text    # Best quality
# or
ollama pull all-minilm          # Faster, smaller
```

```elixir
# config/config.exs
config :cursor_docs, CursorDocs.AI.Ollama,
  base_url: "http://localhost:11434",
  model: "nomic-embed-text"
```

### Multi-GPU Setup (Like Obsidian)

```elixir
# config/config.exs
config :cursor_docs, CursorDocs.AI.Ollama,
  instances: [
    %{url: "http://localhost:11434", gpu: "RTX 2080"},
    %{url: "http://localhost:11435", gpu: "Arc A770"}
  ],
  strategy: :round_robin
```

## Verification

After installation, verify everything is working:

```bash
# Check system status
mix cursor_docs.status

# Test hardware detection
mix run -e "IO.puts(CursorDocs.AI.Hardware.summary())"

# Test provider detection
mix run -e "IO.inspect(CursorDocs.AI.Provider.status())"

# Test search modes
mix run -e "IO.inspect(CursorDocs.Search.available_modes())"
```

## Troubleshooting

### "SurrealDB not available"

This is normal if SurrealDB isn't running. cursor-docs gracefully falls back to sqlite-vss or FTS5.

To start SurrealDB:

```bash
surreal start --user root --pass root file:~/.local/share/cursor-docs/surreal.db
```

### "Ollama not available"

Ensure Ollama is running and has an embedding model:

```bash
ollama serve  # In another terminal
ollama pull nomic-embed-text
```

### "Only keyword search available"

This means neither AI provider nor vector storage is available. Check:

1. Is Ollama running? `curl http://localhost:11434/api/version`
2. Is SurrealDB running? `curl http://localhost:8000/health`
3. Do you have models? `ollama list`

## Pre-release Branch

To use the pre-release version:

```nix
# In your flake inputs:
cursor-docs = {
  url = "github:Distracted-E421/nixos-cursor?dir=services/cursor-docs&ref=cursor-docs-0.3.0-pre";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

To use the main branch (stable):

```nix
cursor-docs = {
  url = "github:Distracted-E421/nixos-cursor?dir=services/cursor-docs";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

