# Changelog

All notable changes to Cursor Studio will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-12-01

### 🌐 Multi-Platform Version Registry

#### Robust Hash System
- **External registry file** - `~/.config/cursor-studio/version-registry.json`
- **No recompile needed** - Update hashes without rebuilding the binary
- **48 versions tracked** - From 1.6.45 to 2.1.34
- **5 platforms per version**:
  - Linux x64 (AppImage)
  - Linux ARM64 (AppImage)
  - macOS Intel (DMG)
  - macOS Apple Silicon (DMG)
  - macOS Universal (DMG)

#### Manual Download Fallback
When automated download fails or hashes are outdated:
```bash
# 1. Get URLs for manual download
cursor-cli urls 2.0.77 --all

# 2. Download in browser from the displayed URL

# 3. Import the file and compute hash
cursor-cli import ~/Downloads/Cursor-2.0.77-x86_64.AppImage --version 2.0.77

# 4. Optionally update local registry with new hash
cursor-cli import ~/Downloads/file.AppImage --version 2.0.77 --update-registry
```

#### New CLI Commands
| Command | Description |
|---------|-------------|
| `urls <version> [--all]` | Show download URLs for manual download |
| `import <file> --version <ver>` | Import manually downloaded file |
| `export-registry [--output <file>]` | Export registry to JSON |
| `import-registry <file> [--merge]` | Import/update registry from JSON |

#### Technical Details
- New `version_registry.rs` module with:
  - `Platform` enum with auto-detection
  - `CursorVersion` struct with per-platform hashes
  - `VersionRegistry` with JSON serialization
  - `ManualImport` helper for fallback workflow
- GUI hash verification after download completion
- Graceful handling when no hash available

### 🔧 Hash Verification Fix
- Fixed incorrect hashes for 2.1.32, 2.1.26, 2.1.25, 2.1.24, 2.1.20
- Hashes verified against actual downloads on 2025-12-01
- CLI now provides hash computation: `cursor-cli hash <version>`

### ⚡ Build Time Optimizations
- **Feature flags** for heavy dependencies:
  - `p2p-sync` - libp2p (~3 min)
  - `server-sync` - axum/tower (~30s)
  - `surrealdb-store` - surrealdb (~2 min)
- **Minimal build**: `cargo build --no-default-features --features minimal`
  - Builds in ~3 min vs ~13 min full build
- **Incremental builds**: ~0.5s after initial compile

### 🏠 Home Manager Module
- New `nix/home-manager-module.nix` for declarative configuration
- Configure theme, font scale, default version, hash registry via Nix
- Example:
  ```nix
  programs.cursor-studio = {
    enable = true;
    defaultVersion = "2.0.77";
    settings.theme = "nord";
    hashRegistry."2.0.77".linux-x64 = "sha256-...";
  };
  ```

### 🔒 Stability Confirmation
- **cursor-studio does NOT affect Cursor IDE stability**
- Cursor's database opened read-only (`SQLITE_OPEN_READ_ONLY`)
- No file locking on Cursor files
- Separate database for cursor-studio data

### 🎨 GUI Improvements (Post-Release)
- **Enhanced version list display**:
  - `★` Yellow star = Default version
  - `●` Green dot = Installed
  - `⬇` Blue arrow = Downloadable (with hash)
  - `○` Gray circle = No hash verification
- **Legend** at top of version list explaining icons
- **Download status indicators**: `✓` = hash verified, `?` = no hash
- **Background highlight** for downloadable versions with verified hashes
- **Failed download recovery panel** showing:
  - Download URL with copy-to-clipboard button
  - CLI import command
  - Retry and dismiss buttons
- **Approval Mode selector** in Settings:
  - Double-click (GUI default)
  - Terminal prompt
  - Auto-approve (for power users)
- **Default to showing all versions** (installed + downloadable)

---

## [0.2.1] - 2025-12-01

### 🔧 Bug Fixes

#### Version Download System (MAJOR FIX)
- **Fixed broken version list** - Replaced outdated `AVAILABLE_VERSIONS` constant (0.4x-0.5x) with current versions (1.6.x, 1.7.x, 2.0.x, 2.1.x)
- **Implemented actual download functionality** - Clicking on non-installed versions now downloads them
- **Added download progress indicator** - Shows spinner, percentage, and progress bar during downloads
- **Version sorting** - Versions now sorted newest-first (2.1.34 at top)
- **Proper version detection** - Uses both `~/.cursor-{VERSION}` data dirs and installed AppImages

#### Font Scaling (FIX)
- **Font scale now actually applies** - Setting `font_scale` was being saved but never used
- **Uses `pixels_per_point`** - Proper egui scaling for consistent UI across all elements

### ✨ New Features

#### CLI Tool (`cursor-cli`)
- **New binary: `cursor-cli`** - Full command-line interface for version management
- **Commands**:
  - `list` - Show installed and/or available versions
  - `download <version>` - Download a specific version with progress bar
  - `install <version>` - Download and install a version
  - `info <version>` - Show detailed version information
  - `cache` - Show cache and storage statistics
  - `clean` - Remove cached downloads
  - `launch` - Start Cursor IDE
- **Beautiful terminal output** - Uses `console` and `indicatif` for styled output
- **Hash verification** - Downloads verified against SHA256 hashes
- **Approval prompts** - Confirms before downloads/installs (bypass with `-y`)

#### Terminal Approval System
- **New `approval.rs` module** - Unified approval system for confirming operations
- **Double-click confirmation in GUI** - First click registers intent, second click confirms
- **Terminal prompts** - Beautiful terminal prompts with ASCII box drawing
- **Approval modes**: Terminal-only, GUI-only, Both, or Auto-approve
- **Timeout handling** - Confirmations expire after 3 seconds
- **Destructive operation warnings** - Extra warnings for data-destructive operations

#### Version Management Module
- **New `versions.rs` module** - Centralized version information with:
  - Download URLs (both `downloader.cursor.sh` and `downloads.cursor.com` formats)
  - SHA256 hashes for verification (SRI format: `sha256-BASE64`)
  - Commit hashes for reproducibility
  - Release dates
  - Stable/unstable flags
- **Hash verification** - `verify_hash()` and `verify_hash_detailed()` functions
- **Download with verification** - `download_and_verify()` checks hash after download
- **Background downloads** - Non-blocking downloads with channel-based progress reporting
- **Sync download (for CLI)** - Blocking download with callback-based progress

#### Improved UI Settings
- **Display Size presets** - One-click buttons for Small/Normal/Large/XL
- **Preset bundles** - Each preset adjusts scale, spacing, and status font together
- **Fine-tune controls** - +/- buttons for precise adjustments
- **Compact layout** - Settings take less space with better organization

### 🏗️ Technical Changes
- Added `reqwest` dependency with rustls-tls (no OpenSSL required)
- Added `futures-util` for stream handling
- Added `atty` for terminal detection
- Added `sha2` and `base64` for hash verification
- Added `clap`, `console`, `indicatif` for CLI
- New modules: `versions`, `approval`
- New binary: `cursor-cli` (alongside `cursor-studio`)
- Download state machine: Idle → Downloading → Completed/Failed
- Approval manager tracks pending confirmations with expiry
- Proper `pixels_per_point` scaling for font size

### 🐛 Hash Fix (Post-release)
- **Fixed incorrect SHA256 hashes** - Original hashes were from outdated sources
- **Verified hashes 2025-12-01** - All 2.1.x hashes now verified against actual downloads
- **Removed hashes for stale URLs** - 2.0.71 and 2.0.64 URLs may no longer be valid

### Known Issues
- Installed AppImage detection needs refinement
- Some terminal emulators may not display Unicode box characters correctly
- CLI `launch` command may not find system Cursor installation
- Older versions (2.0.71, 2.0.64) may not be downloadable (URLs expired)

---

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
