# Migration Guide: Legacy Tools → Cursor Studio

This guide helps you migrate from the deprecated Python/tkinter tools (`cursor-manager`, `cursor-chat-library`) to the modern **Cursor Studio** application.

## Overview

| Old Package | New Package | Status |
|-------------|-------------|--------|
| `cursor-manager` (tkinter) | `cursor-studio` (egui GUI) | ⚠️ DEPRECATED |
| `cursor-chat-library` (tkinter) | `cursor-studio` (egui GUI) | ⚠️ DEPRECATED |
| N/A | `cursor-studio-cli` (CLI) | ✨ NEW |
| N/A | TUI (planned) | 🔮 FUTURE |

## Why Migrate?

### Known Issues with Legacy Tools

1. **Fatal Bug in cursor-manager**
   ```
   AttributeError: '_tkinter.tkapp' object has no attribute 'on_close'
   ```
   The app crashes when trying to close the window properly.

2. **Performance Issues**
   - Slow startup (Python + tkinter initialization)
   - Sluggish UI when scrolling large chat histories
   - Memory-intensive for many conversations

3. **Maintenance Burden**
   - 1000+ lines of Python embedded in Nix files
   - Difficult to test and debug
   - No clear separation of concerns

### Benefits of Cursor Studio

| Feature | Legacy (tkinter) | Cursor Studio (egui) |
|---------|------------------|---------------------|
| Startup time | ~2-3 seconds | ~0.3 seconds |
| Memory usage | 200+ MB | ~50 MB |
| UI responsiveness | Sluggish | Instant |
| Theme support | Limited | Full VS Code themes |
| Security scanning | None | API key detection |
| Search | Basic | Full-text with highlighting |
| Bookmarks | None | Persistent across reimports |
| CLI interface | None | Full-featured |
| Export formats | Limited | Markdown, JSON (planned) |

---

## Migration Steps

### Step 1: Update Your Flake

**Before (deprecated):**
```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  
  outputs = { nixos-cursor, ... }: {
    homeConfigurations.user = {
      home.packages = [
        nixos-cursor.packages.x86_64-linux.cursor-manager
        nixos-cursor.packages.x86_64-linux.cursor-chat-library
      ];
    };
  };
}
```

**After (recommended):**
```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor";
  
  outputs = { nixos-cursor, ... }: {
    homeConfigurations.user = {
      home.packages = [
        nixos-cursor.packages.x86_64-linux.cursor-studio
        nixos-cursor.packages.x86_64-linux.cursor-studio-cli  # Optional: CLI interface
      ];
    };
  };
}
```

### Step 2: Try It Out

```bash
# Run without installing (quick test)
nix run github:Distracted-E421/nixos-cursor#cursor-studio

# Or the CLI
nix run github:Distracted-E421/nixos-cursor#cursor-studio-cli -- --help
```

### Step 3: (Optional) Use Home Manager Module

For declarative configuration:

```nix
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

---

## Data Migration

### Chat History

**Good news:** Your chat history doesn't need migration!

Both legacy tools and Cursor Studio read directly from Cursor's SQLite databases:
- `~/.config/Cursor/User/workspaceStorage/*/state.vscdb`
- `~/.cursor-VERSION/User/workspaceStorage/*/state.vscdb`

When you first run Cursor Studio:
1. Click **Import Chats** in the dashboard
2. All conversations are indexed into `~/.config/cursor-studio/chats.db`
3. Future imports are incremental (skips duplicates)

### Configuration

Legacy config location: `~/.config/cursor-manager/config.json`
New config location: `~/.config/cursor-studio/config.json`

The configuration format is different, so you'll start fresh. The new format is:

```json
{
  "ui": {
    "fontScale": 1.0,
    "messageSpacing": 8,
    "statusBarFontSize": 12
  },
  "displayPreferences": {
    "user": { "alignment": "right", "collapsed": false },
    "assistant": { "alignment": "left", "collapsed": false }
  },
  "security": {
    "scanOnImport": false,
    "showSecurityWarnings": true
  }
}
```

---

## Feature Comparison

### Version Management

| Feature | cursor-manager | cursor-studio |
|---------|---------------|---------------|
| Version dropdown | ✅ | ✅ |
| Era grouping | ✅ | ✅ |
| Launch any version | ✅ | ✅ |
| Set default version | ✅ | ✅ |
| Auth sync | ✅ | ✅ |
| Settings sync | ✅ | ✅ |
| Disk usage graph | ✅ | ✅ |
| Clean caches | ✅ | ✅ |

### Chat Library

| Feature | cursor-chat-library | cursor-studio |
|---------|--------------------|--------------| 
| View conversations | ✅ | ✅ |
| Search | Basic | Full-text with highlighting |
| Favorites | ✅ | ✅ |
| Categories | ✅ | ✅ |
| Bookmarks | ❌ | ✅ Persistent! |
| Export Markdown | ✅ | ✅ |
| Export JSON | ❌ | 🔮 Planned |
| Themes | Limited | Full VS Code themes |
| Security scanning | ❌ | ✅ API key detection |
| Message alignment | ❌ | ✅ Configurable |

### New Features in Cursor Studio

- **Security Scanning**: Detect API keys, passwords, and secrets in chat history
- **Jump to Message**: Navigate directly from search results or security findings
- **VS Code Themes**: Use any VS Code theme (loaded from extension dirs)
- **CLI Interface**: Automate tasks with `cursor-studio-cli`
- **Bookmarks**: Mark important messages, persists across reimports

---

## CLI Usage

Cursor Studio includes a full-featured CLI:

```bash
# List available versions
cursor-studio-cli list --available

# Show installed versions
cursor-studio-cli list --installed

# Check cache status
cursor-studio-cli cache

# Download a specific version
cursor-studio-cli download 2.0.77

# Import chat history
cursor-studio-cli import

# Export conversation
cursor-studio-cli export <conversation-id> --format markdown
```

---

## Troubleshooting

### "cursor-studio not found"

Make sure you've added it to your packages:
```nix
home.packages = [ inputs.nixos-cursor.packages.x86_64-linux.cursor-studio ];
```

Then rebuild: `home-manager switch`

### "Download failed"

The old `downloader.cursor.sh` domain is dead. Cursor Studio uses `downloads.cursor.com` URLs. If you see old URLs failing, update to the latest version.

### "Chats not importing"

1. Make sure Cursor IDE has been run at least once
2. Check that database files exist:
   ```bash
   ls ~/.config/Cursor/User/workspaceStorage/*/state.vscdb
   ```
3. Try reimport (clears and re-reads all chats)

### Theme not loading

VS Code themes are loaded from standard extension directories. Make sure:
1. You have VS Code or Cursor installed
2. The theme extension is installed
3. Click "Refresh" in the theme dropdown

---

## Timeline

| Version | Status | Notes |
|---------|--------|-------|
| v0.2.0 | Current | Legacy packages show deprecation warnings |
| v0.3.0 | Planned | Legacy packages removed from flake outputs |
| v1.0.0 | Future | Legacy code removed entirely |

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/Distracted-E421/nixos-cursor/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Distracted-E421/nixos-cursor/discussions)
- **Source**: `cursor-studio-egui/` directory

---

*Last updated: 2025-12-02*
