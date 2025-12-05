# nixos-cursor

**v0.2.0 Stable** · **48 Versions** · **NixOS + macOS**  
[![CI](https://github.com/Distracted-E421/nixos-cursor/actions/workflows/cursor-studio.yml/badge.svg)](https://github.com/Distracted-E421/nixos-cursor/actions/workflows/cursor-studio.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

The **definitive Cursor IDE package for NixOS** — featuring multi-version management, MCP server integration, and the new **Cursor Studio** native application.

---

## 🚀 Quick Start

```bash
# Try Cursor Studio (GUI) without installing
nix run github:Distracted-E421/nixos-cursor#cursor-studio

# Or run Cursor directly
nix run github:Distracted-E421/nixos-cursor#cursor
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
    inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Latest stable (2.0.77)
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio   # GUI manager
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio-cli  # CLI (optional)
  ];
}
```

---

## ✨ What's New in v0.2.0

### Cursor Studio — Native Rust Application

A complete rewrite from Python/Tkinter to **Rust/egui**:

| Feature | Description |
|---------|-------------|
| 📊 **Dashboard** | Stats, quick actions, version overview |
| 💬 **Chat Library** | Import, search, bookmark, export conversations |
| 🔐 **Security** | Sensitive data scanning, NPM blocklist |
| 🎨 **Themes** | Full VS Code theme support |
| 🔄 **Sync** | P2P and server sync infrastructure (experimental) |
| 🏠 **Home Manager** | Declarative configuration via Nix |

### Multi-Version Management

- **48 versions** available (2.1.x, 2.0.x, 1.7.x, 1.6.x)
- **Isolated configs** — each version has its own `~/.cursor-VERSION/`
- **Run concurrently** — 2.0.77 and 1.7.54 side-by-side
- **Shared auth** — keep login synced across versions (optional)

---

## 📦 Available Packages

| Package | Description |
|---------|-------------|
| `cursor` | Latest stable Cursor IDE (2.0.77) |
| `cursor-studio` | GUI: Version manager + Chat library |
| `cursor-studio-cli` | CLI interface for automation |
| `cursor-2_0_77` | Specific version |
| `cursor-1_7_54` | Classic version |
| `cursor-1_6_45` | Legacy version |

**All 48 versions**: See [cursor-versions.nix](cursor-versions.nix)

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

### v0.2.x (Current)

- [x] Cursor Studio GUI (Rust/egui)
- [x] 48 version support
- [x] Security scanning
- [x] Chat library with bookmarks
- [x] Home Manager modules
- [ ] Window size persistence
- [ ] Global search across chats

### v0.3.0 (Next)

- [ ] **P2P Sync** — Sync chats across devices via local network
- [ ] **Server Sync** — Central server for cloud sync
- [ ] **CLI/TUI** — Headless interfaces
- [ ] **2.1.x versions** — Add newer releases

### v1.0.0 (Future)

- [ ] Custom modes reimplementation for 2.1.x
- [ ] Plugin system
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

- [VERSION_MANAGER_GUIDE.md](VERSION_MANAGER_GUIDE.md) — Multi-version usage
- [SECURITY.md](SECURITY.md) — Security principles
- [CHANGELOG.md](CHANGELOG.md) — Release history
- [cursor-studio-egui/README.md](cursor-studio-egui/README.md) — Cursor Studio details

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## 📄 License

**Packaging code**: MIT License

**Cursor binary**: Proprietary. Downloaded from official servers, not redistributed.

---

**Maintained by [e421](https://github.com/Distracted-E421)** · **Version tracking by [oslook](https://github.com/oslook)**
