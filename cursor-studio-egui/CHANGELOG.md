# Changelog

All notable changes to Cursor Studio will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0-rc1] - 2025-11-29

### 🎉 Highlights

This release represents a major overhaul of Cursor Studio, transforming it from a simple chat library viewer into a comprehensive **Open Source Cursor IDE Manager**. Key highlights include:

- **Complete UI Overhaul** - Modern dashboard with stats cards, VS Code-style theming
- **Security Scanning** - Detect sensitive data (API keys, passwords, secrets) in chat history
- **NPM Security Integration** - Embedded blocklist for malicious package detection
- **Home Manager Module** - Declarative NixOS configuration support
- **Nushell Scripts** - Modern shell scripting replacing bash

### Added

#### 🖥️ User Interface
- **Modern Dashboard** with 4-column stats display (Chats, Messages, Favorites, Versions)
- **3-column button layout** for Import, Reimport, Launch actions
- **Message alignment settings** - Left, Center, Right alignment per message type
- **Unified message box rendering** - Consistent 66% width rule across all alignments
- **Auto-refresh on tab switch** - Data always current when navigating
- **Theme refresh button** with visual feedback
- **Scrollable theme picker** for large theme collections
- **Modern conversation header** with inline actions and stats

#### 🔐 Security
- **Sensitive data scanning** - Regex-based detection of:
  - API keys and tokens
  - Passwords and credentials
  - Secrets and private keys
- **Jump-to-message** from security scan results
- **NPM security blocklist** - Embedded list of known malicious packages
- **Security panel** in right sidebar with VS Code-style context switcher

#### 🏠 Home Manager Integration
- **New `programs.cursor-studio` module** for declarative configuration
- Generates `~/.config/cursor-studio/config.json` from Nix options
- Options for:
  - UI settings (font scale, message spacing, status bar font)
  - Display preferences (alignments per message type)
  - Security settings (scan on import, show warnings)
  - Export defaults (format, include bookmarks)
  - Resource limits (CPU, RAM, VRAM, storage) - for future enforcement

#### 📝 Features
- **Bookmark persistence** - Survives clear & reimport operations
- **Favorites persistence** - Saved and restored on reimport
- **In-conversation search** with result navigation
- **Export to Markdown** - Full conversation export
- **Settings persistence** - All settings saved on exit
- **Tab auto-refresh** - Fresh data when switching tabs

#### 🐚 Scripts
- `cursor/launcher.nu` - Nushell version of cursor launcher
- `scripts/release-to-main.nu` - Release automation in nushell

### Changed

#### UI/UX Improvements
- **Branding update** - Subtitle now "Open Source Cursor IDE Manager"
- **Version display** - Shows v0.2.0-rc1 with accent color
- **Font size controls** - Separate sliders for content, spacing, status bar
- **Theme contrast** - Dynamic `selected_bg`/`selected_fg` calculation for visibility
- **Quick Tips** - Condensed to single-line format

#### Technical
- **Message rendering** - Unified box-based approach for all alignments
- **Layout system** - Uses `ui.columns()` for reliable centering
- **Theme parsing** - Enhanced VS Code theme compatibility
- **Lexical text extraction** - Fixed vertical column rendering bug
- **Bold text rendering** - Proper `**bold**` parsing with brighter colors

### Fixed

#### Critical
- **Large conversation rendering** - Fixed vertical column text bug
- **Screen tearing** - Added `request_repaint()` after preference changes
- **Settings persistence** - Now saves on application exit
- **Bold text** - No longer breaks on `**bold**` patterns
- **Unicode support** - Improved font discovery for NixOS

#### UI
- **Theme contrast** - Selected elements now visible on all themes
- **Dashboard spacing** - Removed negative spacing calculations
- **Message alignment** - Each box positions independently
- **Bookmark loading** - Loads immediately after import via `refresh_all()`
- **Tab switching** - Clears stale data, loads fresh content

### CI/CD

- **NixOS-centric pipeline** - Primary builds via Nix
- **Removed `--all-systems`** - Prevents hangs on cross-platform evaluation
- **Deleted `test-feature.yml`** - Obsolete workflow removed
- **Home Manager validation** - Module syntax checking in CI

### Known Issues

- Some VS Code themes (with minimal `colors` sections) may not load fully
- Very long conversations (10k+ messages) may load slowly
- NPM blocklist is embedded, not auto-updated (manual refresh needed)

### Migration Notes

- **From 0.1.x**: Database schema is compatible, no migration needed
- **Settings**: Previous settings in database will be loaded
- **Bookmarks**: Existing bookmarks preserved

---

## [0.1.x] - Previous Releases

See git history for changes prior to v0.2.0.

---

## Roadmap

### v0.2.1 (Patch)
- [ ] NPM blocklist auto-update
- [ ] Window size persistence
- [ ] Bookmark notes
- [ ] Export JSON format

### v0.3.0 (Future)
- [ ] CLI interface
- [ ] TUI interface
- [ ] Shared config schema (GUI/CLI/TUI/Flake)
- [ ] Integrated data editor

---

*For the full commit history, see the [GitHub releases](https://github.com/Distracted-E421/nixos-cursor/releases).*
