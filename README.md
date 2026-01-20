# nixos-cursor

**v0.3.1** · **69 Versions** · **NixOS + macOS**
[![CI](https://github.com/Distracted-E421/nixos-cursor/actions/workflows/cursor-studio.yml/badge.svg)](https://github.com/Distracted-E421/nixos-cursor/actions/workflows/cursor-studio.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **definitive Cursor IDE package for NixOS** — featuring multi-version management, MCP server integration, isolation tools, and the new **Cursor Studio** native application.

---

## 🚀 Quick Start

```bash
# Try Cursor Studio (GUI) without installing
nix run github:Distracted-E421/nixos-cursor#cursor-studio

# Run the latest stable Cursor
nix run github:Distracted-E421/nixos-cursor#cursor

# Run a specific version
nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77
```

### Add to Your Flake

```nix
# flake.nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
}
```

```nix
# In your Home Manager or NixOS configuration
{ inputs, pkgs, ... }: {
  home.packages = [
    inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Default (2.0.77)
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_3_10   # Latest 2.3.x
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio   # GUI manager
  ];
}
```

---

## ✨ What's New in v0.3.0

### 🎯 Interactive Dialog System

AI agents can now request user feedback **without burning API requests**:

| Feature | Description |
|---------|-------------|
| 📋 **Multiple Choice** | Single or multi-select with descriptions |
| ✏️ **Text Input** | With optional validation and multiline |
| ✅ **Confirmation** | Yes/No with customizable labels |
| 🎚️ **Slider** | Numeric input with min/max/step |
| 🔔 **Toast Notifications** | Non-blocking status updates |
| 💬 **Comment Field** | Add context to any selection |
| ⏸️ **Pause Timer** | Take your time on decisions |

```bash
# Enable the dialog system
cursor-studio dialog enable

# Test it
cursor-studio dialog test

# Check status
cursor-studio dialog status
```

See [docs/designs/INTERACTIVE_DIALOG_SYSTEM.md](docs/designs/INTERACTIVE_DIALOG_SYSTEM.md) for details.

---

## 📦 Available Packages

### Core Packages

| Package | Description |
|---------|-------------|
| `cursor` | Default Cursor IDE (2.0.77 - last with custom modes) |
| `cursor-studio` | GUI version manager + chat library |
| `cursor-studio-cli` / `cs` | CLI interface for automation |
| `cursor-test` | Isolated test instance |
| `cursor-dialog-daemon` | D-Bus daemon for agent dialogs |
| `cursor-dialog-cli` | CLI for dialog system |

### Version Highlights

| Package | Version | Notes |
|---------|---------|-------|
| `cursor-2_3_10` | 2.3.10 | Latest available |
| `cursor-2_2_27` | 2.2.27 | Latest 2.2.x |
| `cursor-2_1_50` | 2.1.50 | Latest 2.1.x |
| `cursor-2_0_77` | 2.0.77 | **Last with custom modes** |
| `cursor-1_7_54` | 1.7.54 | Classic era |

### All 69 Versions

- **2.3.x**: 1 version (2.3.10)
- **2.2.x**: 11 versions (2.2.3 - 2.2.27)
- **2.1.x**: 21 versions (2.1.6 - 2.1.50)
- **2.0.x**: 17 versions (2.0.11 - 2.0.77) — **Custom modes era**
- **1.7.x**: 19 versions (1.7.11 - 1.7.54)
- **1.6.x**: ❌ Dropped (no longer supported by Cursor)

See [cursor-versions.nix](cursor-versions.nix) for the full list.

---

## 🛡️ Cursor Isolation Tools

Suite of scripts to prevent configuration corruption and ensure safe testing:

| Tool | Description |
|------|-------------|
| `cursor-test` | Run Cursor in isolated environments |
| `cursor-backup` | Snapshot configuration before risky operations |
| `cursor-sandbox` | Full environment isolation |
| `cursor-share-data` | Share data between versions |

See [tools/cursor-isolation/README.md](tools/cursor-isolation/README.md) for details.

---

## 🎨 Cursor Studio

A native **Rust/egui** application for managing Cursor:

| Feature | Description |
|---------|-------------|
| 📊 **Dashboard** | Stats, quick actions, version overview |
| 💬 **Chat Library** | Import, search, bookmark, export conversations |
| 🔐 **Security** | Sensitive data scanning, NPM blocklist |
| 🎨 **Themes** | Full VS Code theme support |
| 🔄 **Sync** | P2P and server sync infrastructure (experimental) |
| 🏠 **Home Manager** | Declarative configuration via Nix |
| 📁 **Workspaces** | Track workspaces across versions (NEW!) |
| 🔍 **Vector Search** | Semantic search over chat history (NEW!) |

### CLI with Workspace Support

```bash
# Run the GUI
nix run github:Distracted-E421/nixos-cursor#cursor-studio

# Launch with workspace (NEW!)
nix run github:Distracted-E421/nixos-cursor#cs -- launch 2.1.34 --folder ~/myproject
nix run github:Distracted-E421/nixos-cursor#cs -- launch current -f /path/to/workspace -n

# Version management
nix run github:Distracted-E421/nixos-cursor#cs -- list
nix run github:Distracted-E421/nixos-cursor#cs -- download 2.0.77
```

### Workspace Tracking

Cursor Studio now tracks which workspaces you've opened with which versions:

- 📁 **Workspace Registry** - Remember all your project folders
- 🕐 **Version History** - Track which Cursor versions opened each workspace
- 💬 **Conversation Linking** - Associate chats with projects
- 📊 **Git Stats** - Branch, uncommitted changes, commit history
- 🏷️ **Tags & Colors** - Organize with custom labels

See [WORKSPACE_TRACKING_DESIGN.md](cursor-studio-egui/WORKSPACE_TRACKING_DESIGN.md) for details.

---

## 🏠 Home Manager Module

### Basic Setup

```nix
{ inputs, ... }: {
  imports = [ inputs.nixos-cursor.homeManagerModules.default ];
  
  programs.cursor = {
    enable = true;
    updateCheck.enable = true;
  };
}
```

### With MCP Servers

```nix
programs.cursor = {
  enable = true;
  
  mcp = {
    enable = true;
    
    # File access for AI
    filesystem.enable = true;
    filesystem.paths = [ "~/projects" "~/.config" ];
    
    # Persistent memory
    memory.enable = true;
    
    # NixOS package/option search
    nixos.enable = true;
    
    # GitHub integration (with secrets)
    github.enable = true;
    github.tokenFile = config.sops.secrets.github-token.path;
    
    # Browser automation
    playwright.enable = true;
  };
};
```

### Cursor Studio Module

```nix
{ inputs, ... }: {
  imports = [ inputs.nixos-cursor.homeManagerModules.cursor-studio ];
  
  programs.cursor-studio = {
    enable = true;
    settings = {
      ui.fontScale = 1.0;
      ui.theme = "dark";
      security.scanOnImport = true;
    };
  };
}
```

---

## 🔐 Security

All sensitive data is handled securely:

- ✅ Tokens read at runtime from encrypted files
- ✅ First-class support for [sops-nix](https://github.com/Mic92/sops-nix) and [agenix](https://github.com/ryantm/agenix)
- ✅ Never stored in Nix store or mcp.json
- ✅ NPM blocklist with known malicious packages
- ✅ Sensitive data detection in chat history

```nix
# Secure token pattern
programs.cursor.mcp.github.tokenFile = config.sops.secrets.github-token.path;
```

See [SECURITY.md](SECURITY.md) for details.

---

## 🗺️ Roadmap

### v0.3.x (Current)

- [x] Interactive Dialog System (D-Bus daemon)
- [x] Toast notifications with sidebar
- [x] Comment fields on all dialogs
- [x] 69 version support (2.3.x - 1.7.x)
- [x] 1.6.x EOL cleanup
- [ ] Darwin dialog support (Unix sockets)

### v0.4.0 (Next)

- [ ] **System Prompt Injection** — Restore custom modes via proxy
- [ ] **Context Injection** — Inject documentation/context into AI requests
- [ ] **Proxy Dashboard** — Web UI for monitoring AI traffic

### v0.5.0 (Future)

- [ ] **P2P Sync** — Sync chats across devices via local network
- [ ] **Server Sync** — Central server for cloud sync
- [ ] **Headless Cursor TUI** — Terminal-based Cursor client

### v1.0.0

- [ ] Custom modes fully restored
- [ ] Plugin system for extensions
- [ ] AI integration (summaries, auto-titles)

---

## 🖥️ Platform Support

| Platform | Status | Format |
|----------|--------|--------|
| x86_64-linux | ✅ Full | AppImage |
| aarch64-linux | ✅ Full | AppImage |
| x86_64-darwin | 🧪 Experimental | DMG |
| aarch64-darwin | 🧪 Experimental | DMG |

### macOS Users

Darwin support needs hash verification. Help us test:

```bash
curl -L -o cursor.dmg "https://downloads.cursor.com/production/.../darwin/universal/Cursor-darwin-universal.dmg"
nix hash file cursor.dmg  # Share this in an issue!
```

See [docs/DARWIN_TESTING.md](docs/DARWIN_TESTING.md)

---

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [VERSION_MANAGER_GUIDE.md](VERSION_MANAGER_GUIDE.md) | Multi-version usage |
| [SECURITY.md](SECURITY.md) | Security principles |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [cursor-studio-egui/README.md](cursor-studio-egui/README.md) | Cursor Studio details |
| [docs/designs/INTERACTIVE_DIALOG_SYSTEM.md](docs/designs/INTERACTIVE_DIALOG_SYSTEM.md) | Dialog system architecture |

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
# Development shell
nix develop

# Run tests
nix flake check

# Build specific package
nix build .#cursor-studio
```

---

## 📄 License

**Packaging code**: MIT License

**Cursor binary**: Proprietary. Downloaded from official servers, not redistributed.

---

**Maintained by [e421](https://github.com/Distracted-E421)** · **Version tracking by [oslook](https://github.com/oslook)**
