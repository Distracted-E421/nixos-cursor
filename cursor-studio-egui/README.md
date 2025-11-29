# Cursor Studio

**Open Source Cursor IDE Manager**

[![CI Status](https://github.com/Distracted-E421/nixos-cursor/actions/workflows/cursor-studio.yml/badge.svg)](https://github.com/Distracted-E421/nixos-cursor/actions/workflows/cursor-studio.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![NixOS](https://img.shields.io/badge/NixOS-5277C3?logo=nixos&logoColor=white)](https://nixos.org/)

A fast, native GUI application for managing your Cursor IDE experience. Built with Rust and egui for performance and cross-platform compatibility.

![Cursor Studio Dashboard](docs/screenshots/dashboard.png)

## ✨ Features

### 📊 Chat Library
- **Import & View** all your Cursor conversations
- **Search** within conversations with result navigation
- **Bookmarks** to mark important messages (persist across reimports)
- **Favorites** for quick access to important conversations
- **Export** conversations to Markdown

### 🎨 Customization
- **VS Code Theme Support** - Use your favorite themes
- **Message Alignment** - Left, Center, Right per message type
- **Font Scaling** - Adjust content size, spacing, and status bar
- **Modern UI** - Clean, responsive design with columns layout

### 🔐 Security
- **Sensitive Data Scanning** - Detect API keys, passwords, secrets
- **Jump-to-Message** - Navigate directly to findings
- **NPM Blocklist** - Embedded list of malicious packages
- **Privacy-First** - All data stays local

### 🚀 Version Management
- **Multi-Version Support** - Launch any of 48 Cursor versions
- **Version Switching** - Easy dropdown selection
- **Isolated Configs** - Each version keeps its own settings

## 📦 Installation

### NixOS / Nix (Recommended)

```nix
# flake.nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  
  outputs = { nixos-cursor, ... }: {
    # In your configuration
    environment.systemPackages = [
      nixos-cursor.packages.x86_64-linux.cursor-studio
    ];
  };
}
```

### Home Manager Module

```nix
# home.nix
{
  imports = [ nixos-cursor.homeManagerModules.cursor-studio ];
  
  programs.cursor-studio = {
    enable = true;
    
    settings = {
      ui = {
        fontScale = 1.0;
        messageSpacing = 8;
        statusBarFontSize = 12;
      };
      
      displayPreferences = {
        user = { alignment = "right"; };
        assistant = { alignment = "left"; };
        toolCalls = { alignment = "left"; collapsed = true; };
      };
      
      security = {
        scanOnImport = true;
        showSecurityWarnings = true;
      };
    };
  };
}
```

### Build from Source

```bash
# Clone and build
git clone https://github.com/Distracted-E421/nixos-cursor
cd nixos-cursor/cursor-studio-egui

# With Nix
nix build
./result/bin/cursor-studio

# With Cargo
cargo build --release
./target/release/cursor-studio
```

## 🖥️ Usage

### Dashboard
The dashboard shows your stats at a glance:
- **Chats** - Total imported conversations
- **Messages** - Total message count
- **Favorites** - Starred conversations
- **Versions** - Installed Cursor versions

### Importing Chats
1. Click **Import Chats** (or **Reimport** to refresh)
2. Cursor Studio reads from `~/.config/Cursor/User/workspaceStorage/`
3. All conversations are imported into a local SQLite database

### Searching
- Use the **Find** box in conversation tabs
- Navigate results with arrow buttons
- Messages scroll into view and highlight

### Bookmarks
- Click the ⭐ icon on any message to bookmark
- View all bookmarks in the left panel
- Click to jump to bookmarked message
- Bookmarks persist even when reimporting

### Security Scanning
1. Open the **Security** panel (shield icon)
2. Click **Scan Chat History**
3. Review detected sensitive data
4. Click findings to jump to the source message

### Themes
1. Open **Settings** (gear icon)
2. Select a theme from the dropdown
3. Click **Refresh** to reload theme list
4. Themes load from VS Code's extension directories

## ⌨️ Configuration

### Config File Location
`~/.config/cursor-studio/config.json`

### Example Configuration
```json
{
  "ui": {
    "fontScale": 1.0,
    "messageSpacing": 8,
    "statusBarFontSize": 12
  },
  "displayPreferences": {
    "user": { "alignment": "right", "collapsed": false },
    "assistant": { "alignment": "left", "collapsed": false },
    "thinking": { "alignment": "left", "collapsed": true },
    "toolCalls": { "alignment": "left", "collapsed": true }
  },
  "security": {
    "scanOnImport": false,
    "showSecurityWarnings": true
  },
  "export": {
    "defaultFormat": "markdown",
    "includeBookmarks": true
  }
}
```

## 🔧 Development

### Prerequisites
- Rust 1.70+
- Nix (for NixOS builds)

### Dev Shell
```bash
cd cursor-studio-egui
nix develop
cargo run
```

### Testing
```bash
cargo test --all-features
cargo clippy
cargo fmt --check
```

### Project Structure
```
cursor-studio-egui/
├── src/
│   ├── main.rs        # Application entry, UI rendering
│   ├── database.rs    # SQLite operations, data models
│   ├── security.rs    # Security scanning logic
│   └── theme.rs       # VS Code theme parsing
├── flake.nix          # Nix build definition
├── Cargo.toml         # Rust dependencies
└── home-manager-module.nix  # HM integration
```

## 📋 Roadmap

### v0.2.0 (Current RC)
- [x] Modern dashboard with stats
- [x] Message alignment options
- [x] Security scanning
- [x] Home Manager module
- [x] Bookmark persistence
- [x] Theme improvements

### v0.2.1 (Planned)
- [ ] Export to JSON
- [ ] Window size persistence
- [ ] Bookmark notes
- [ ] NPM blocklist updates

### v0.3.0 (Future)
- [ ] CLI interface
- [ ] TUI interface
- [ ] Shared config schema
- [ ] Data editor

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](../LICENSE) for details.

## 🙏 Acknowledgments

- [egui](https://github.com/emilk/egui) - Immediate mode GUI library
- [rusqlite](https://github.com/rusqlite/rusqlite) - SQLite bindings
- [Cursor](https://cursor.sh) - The AI-powered code editor

---

**Part of [nixos-cursor](https://github.com/Distracted-E421/nixos-cursor)** - The complete Cursor IDE solution for NixOS.
