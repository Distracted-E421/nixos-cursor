# Project Map & Architecture

This document provides a high-level map of the `nixos-cursor` repository, visualizing the relationships between sub-components, services, and tooling.

## 🗺️ System Map

```d2
direction: right

# Styling
classes: {
  nix: {
    style: {
      fill: "#7ebae4"
      stroke: "#205EA6"
    }
  }
  rust: {
    style: {
      fill: "#dea584"
      stroke: "#A72145"
    }
  }
  elixir: {
    style: {
      fill: "#a074c4"
      stroke: "#4e2a84"
    }
  }
  docs: {
    style: {
      fill: "#98c379"
      stroke: "#3d6e1d"
    }
  }
  script: {
    style: {
      fill: "#e5c07b"
      stroke: "#b08833"
    }
  }
}

# Root Configuration
NixOS Config: {
  class: nix
  label: "NixOS Flake\n(flake.nix)"
  
  Modules: {
    label: "Modules"
    System: "nixos/"
    Home: "home-manager/"
  }
  
  Devices: {
    label: "Devices"
    Obsidian: "Obsidian (Workstation)"
    Neon: "neon-laptop (Laptop)"
    Framework: "framework (Mobile)"
  }
}

# Core Tools
Cursor Tools: {
  label: "Cursor Tools"
  
  Cursor Studio: {
    class: rust
    label: "cursor-studio-egui\n(Rust)"
    description: "GUI Companion App"
  }
  
  Cursor Proxy: {
    class: rust
    label: "cursor-proxy\n(Rust)"
    description: "Traffic Injection & Analysis"
  }
  
  Cursor Isolation: {
    class: rust
    label: "cursor-isolation\n(Rust)"
    description: "Sandboxed execution"
  }

  Cursor Docs: {
    class: elixir
    label: "cursor-docs\n(Elixir)"
    description: "Documentation Indexer"
  }
  
  Dialog Daemon: {
    class: rust
    label: "cursor-dialog-daemon\n(Rust)"
    description: "D-Bus Interactive Dialogs"
  }
}

# Support Scripts
Scripts: {
  class: script
  label: "Automation Scripts"
  NuShell: "nu/"
  Python: "python/"
  Rust: "rust/"
}

# Documentation
Docs: {
  class: docs
  label: "Documentation"
  Internal: "internal/"
  Agents: "agents/"
  Architecture: "diagrams/"
}

# Relationships
NixOS Config.Devices.Obsidian -> Cursor Tools.Cursor Studio: "Runs on"
NixOS Config.Devices.Obsidian -> Cursor Tools.Cursor Proxy: "Runs on"

Cursor Tools.Cursor Proxy -> Cursor Tools.Cursor Studio: "Intersects traffic for"
Cursor Tools.Cursor Studio -> Cursor Tools.Cursor Docs: "Queries index"

Scripts.NuShell -> NixOS Config: "Manages builds"
```

## 🏗️ Component Details

### 🟢 NixOS Configuration (`/nixos/`)
The foundation of the homelab.
- **Flake**: Defines the entire system state declaratively.
- **Hosts**: Machine-specific configurations (`Obsidian`, `neon-laptop`, etc.).
- **Modules**: Reusable components (`services`, `desktop`, `development`).

### 🟠 Cursor Proxy (`tools/cursor-proxy/`)
**Language**: Rust
**Status**: Active Development
**Purpose**: Intercepts and modifies Cursor API traffic.
- **Injection System**: Inject system prompts and context into Connect/Protobuf messages.
- **Traffic Analysis**: Capture and decode proprietary protocol messages.
- **Testing**: `tools/proxy-test/` contains replay and validation tools.

### 🟣 Cursor Studio (`cursor-studio-egui/`)
**Language**: Rust (egui)
**Status**: Active
**Purpose**: Power-user companion app for Cursor.
- **Modes**: Manage custom AI personalities and tool access.
- **Security**: Scan for secrets and blocked packages.
- **Sync**: P2P database synchronization (in progress).

### 🟠 Dialog Daemon (`tools/cursor-dialog-daemon/`)
**Language**: Rust (egui + zbus)
**Status**: MVP Complete
**Purpose**: D-Bus service for AI agent interactive dialogs.
- **D-Bus Interface**: `sh.cursor.studio.Dialog1` with typed methods.
- **Dialogs**: Choice, text input, confirmation, slider, file picker.
- **Agent Integration**: Via CLI tool or direct D-Bus calls.
- **Design Doc**: `docs/designs/INTERACTIVE_DIALOG_SYSTEM.md`

### 🔵 Cursor Docs Service (`services/cursor-docs/`)
**Language**: Elixir
**Status**: Stable
**Purpose**: Local documentation indexing and search.
- **Scraper**: Multi-strategy crawler for documentation sites.
- **Search**: FTS5-based full-text search.
- **Ollama**: Integration for AI-powered queries.

### 🟡 Automation Scripts (`scripts/`)
**Languages**: Nushell, Python, Rust
**Purpose**: Glue code and automation.
- **Build Wrappers**: `nom-rebuild`, `rebuild-via-ssh`.
- **Cleanup**: Database maintenance and garbage collection.
- **Analysis**: Log analysis and metrics.

## 📂 Directory Structure

```
.
├── devices/                 # Device-specific notes & configs
├── docs/                    # Knowledge base
│   ├── agents/              # Persona definitions
│   ├── internal/            # Decision logs
│   └── diagrams/            # Architecture visualizations
├── modules/                 # Shared NixOS modules
├── nixos/                   # Core NixOS configuration (Flake)
├── scripts/                 # Automation scripts
├── services/                # Standalone services
│   └── cursor-docs/         # Documentation indexer
└── tools/                   # Custom tooling
    ├── cursor-dialog-daemon/# D-Bus dialog service
    ├── cursor-proxy/        # Traffic interceptor
    ├── cursor-studio-egui/  # GUI companion
    └── proxy-test/          # Proxy validation
```

