# NixOS Service Configuration for cursor-docs

This document provides NixOS configuration examples for running cursor-docs with various storage backends.

## Tier 1: SQLite Only (Default)

No additional configuration needed. cursor-docs works out of the box with FTS5.

## Tier 2: sqlite-vss (Recommended)

sqlite-vss provides embedded vector search without requiring a daemon.

### NixOS Configuration

```nix
# In your NixOS configuration or home-manager config

{
  # Ensure sqlite-vss extension is available
  environment.systemPackages = with pkgs; [
    sqlite
    # sqlite-vss may need to be built from source or obtained from overlay
  ];

  # cursor-docs will auto-detect the extension
}
```

### Manual Build (if not in nixpkgs)

```bash
# Build sqlite-vss from source
git clone https://github.com/asg017/sqlite-vss
cd sqlite-vss
make loadable

# Copy to a known location
cp dist/vss0.so ~/.local/lib/sqlite-vss/
```

## Tier 3: SurrealDB (Power Users)

SurrealDB provides full vector search with graph capabilities.

### Graceful Startup Configuration

The key principle: **SurrealDB should never slow down your boot or block other applications**.

```nix
{ config, pkgs, ... }:

{
  # SurrealDB service with graceful startup
  systemd.services.surrealdb-cursor-docs = {
    description = "SurrealDB for cursor-docs (graceful startup)";
    
    # Start after basic services, but don't block boot
    after = [ "network.target" "local-fs.target" ];
    
    # Don't make it a hard dependency of anything
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      # ═══════════════════════════════════════════════════════════
      # GRACEFUL STARTUP: Low priority, doesn't impact other apps
      # ═══════════════════════════════════════════════════════════
      
      # CPU: Lowest priority (nice 19)
      Nice = 19;
      
      # IO: Idle class - only use IO when system is idle
      IOSchedulingClass = "idle";
      
      # CPU Weight: Very low (default is 100)
      CPUWeight = 10;
      
      # Memory: Cap at 2GB to prevent system pressure
      MemoryMax = "2G";
      MemoryHigh = "1G";
      
      # Startup: Allow slow startup, don't block boot
      TimeoutStartSec = "120s";
      
      # ═══════════════════════════════════════════════════════════
      # SERVICE CONFIGURATION
      # ═══════════════════════════════════════════════════════════
      
      Type = "simple";
      
      ExecStart = "${pkgs.surrealdb}/bin/surreal start \
        --user root --pass root \
        --log info \
        file:/var/lib/cursor-docs/surreal.db";
      
      # Data directory
      StateDirectory = "cursor-docs";
      
      # Restart policy: gentle, not aggressive
      Restart = "on-failure";
      RestartSec = "30s";
      
      # Security hardening
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
  
  # Ensure surrealdb package is available
  environment.systemPackages = [ pkgs.surrealdb ];
}
```

### Key Graceful Startup Settings Explained

| Setting | Value | Effect |
|---------|-------|--------|
| `Nice` | 19 | Lowest CPU priority |
| `IOSchedulingClass` | idle | Only use disk when system is idle |
| `CPUWeight` | 10 | 10% of default CPU share |
| `MemoryMax` | 2G | Hard memory cap |
| `MemoryHigh` | 1G | Memory pressure threshold |
| `TimeoutStartSec` | 120s | Allow slow startup |
| `RestartSec` | 30s | Don't restart too quickly |

### User-Level Service (Alternative)

For per-user installation without root:

```nix
{ config, pkgs, ... }:

{
  # Home Manager configuration
  systemd.user.services.surrealdb-cursor-docs = {
    Unit = {
      Description = "SurrealDB for cursor-docs (user)";
      After = [ "default.target" ];
    };
    
    Service = {
      ExecStart = "${pkgs.surrealdb}/bin/surreal start \
        --user root --pass root \
        --bind 127.0.0.1:8000 \
        file:%h/.local/share/cursor-docs/surreal.db";
      
      # Graceful settings
      Nice = "19";
      IOSchedulingClass = "idle";
      
      Restart = "on-failure";
      RestartSec = "30s";
    };
    
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
```

### cursor-docs Configuration

Configure cursor-docs to connect to SurrealDB:

```elixir
# config/config.exs or config/runtime.exs

config :cursor_docs, CursorDocs.Storage.Vector.SurrealDB,
  endpoint: "http://localhost:8000",
  namespace: "cursor",
  database: "docs",
  username: "root",
  password: "root",
  lazy_connect: true,      # Don't block startup if SurrealDB isn't ready
  connect_timeout: 5_000   # Quick timeout for health checks
```

## Ollama Configuration (AI Provider)

For AI embeddings, configure Ollama:

### Single GPU Setup

```nix
{ config, pkgs, ... }:

{
  services.ollama = {
    enable = true;
    acceleration = "cuda";  # or "rocm" for AMD
  };
}
```

### Multi-GPU Setup (Like Obsidian)

```nix
{ config, pkgs, ... }:

{
  # RTX 2080 instance (port 11434)
  systemd.services.ollama-rtx2080 = {
    description = "Ollama on RTX 2080";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    environment = {
      CUDA_VISIBLE_DEVICES = "0";
      OLLAMA_HOST = "0.0.0.0:11434";
    };
    
    serviceConfig = {
      ExecStart = "${pkgs.ollama}/bin/ollama serve";
      Restart = "on-failure";
    };
  };
  
  # Arc A770 instance (port 11435)
  systemd.services.ollama-arc-a770 = {
    description = "Ollama on Arc A770";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    environment = {
      # Intel GPU configuration
      OLLAMA_HOST = "0.0.0.0:11435";
      # Add Intel-specific env vars as needed
    };
    
    serviceConfig = {
      ExecStart = "${pkgs.ollama}/bin/ollama serve";
      Restart = "on-failure";
    };
  };
}
```

### cursor-docs Ollama Configuration

```elixir
# For multi-GPU setup
config :cursor_docs, CursorDocs.AI.Ollama,
  instances: [
    %{url: "http://localhost:11434", gpu: "RTX 2080"},
    %{url: "http://localhost:11435", gpu: "Arc A770"}
  ],
  strategy: :round_robin,  # or :fastest
  model: "nomic-embed-text"
```

## Complete Example: Power User Setup

```nix
{ config, pkgs, ... }:

{
  # SurrealDB for vector storage
  systemd.services.surrealdb-cursor-docs = {
    description = "SurrealDB for cursor-docs";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "idle";
      CPUWeight = 10;
      MemoryMax = "2G";
      
      ExecStart = "${pkgs.surrealdb}/bin/surreal start \
        --user root --pass root \
        file:/var/lib/cursor-docs/surreal.db";
      
      StateDirectory = "cursor-docs";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };
  
  # Ollama for embeddings
  services.ollama = {
    enable = true;
    acceleration = "cuda";
  };
  
  # Ensure models are pulled on activation
  systemd.services.ollama-model-pull = {
    description = "Pull Ollama embedding models";
    after = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ollama}/bin/ollama pull nomic-embed-text";
      RemainAfterExit = true;
    };
  };
  
  environment.systemPackages = with pkgs; [
    surrealdb
    ollama
  ];
}
```

## Verification Commands

```bash
# Check SurrealDB status
systemctl status surrealdb-cursor-docs

# Check Ollama status
systemctl status ollama

# Verify cursor-docs sees the backends
cd /path/to/cursor-docs
mix run -e "IO.inspect(CursorDocs.Storage.Vector.status())"
mix run -e "IO.inspect(CursorDocs.AI.Provider.status())"
mix run -e "IO.inspect(CursorDocs.Search.available_modes())"
```

## Troubleshooting

### SurrealDB Not Detected

1. Check if service is running: `systemctl status surrealdb-cursor-docs`
2. Check connectivity: `curl http://localhost:8000/health`
3. Check logs: `journalctl -u surrealdb-cursor-docs -f`

### Ollama Not Detected

1. Check if service is running: `systemctl status ollama`
2. Check API: `curl http://localhost:11434/api/version`
3. Ensure embedding model is pulled: `ollama list`

### High Resource Usage

If SurrealDB is using too many resources:

1. Verify Nice and IOSchedulingClass are set
2. Lower MemoryMax if needed
3. Consider using sqlite-vss instead for lower overhead

