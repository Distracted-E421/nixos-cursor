# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-05

> 🎉 **First stable release of Cursor Studio** - A complete rewrite from Python/Tkinter to Rust/egui

### Highlights

- **Native Rust Application** - Fast, single binary, no runtime dependencies
- **VS Code-like Interface** - Familiar layout with activity bar, sidebars, tabs
- **Security Features** - Sensitive data detection, NPM malicious package scanning
- **Full Bookmark System** - Persistent bookmarks that survive reimports
- **48 Cursor Versions** - Multi-version management with isolated configs
- **Modular Build System** - Fast iteration with `--lite` builds (~2 min)

### Added

- **Security Panel**:
  - Dynamic audit log showing actual scan results and import status
  - Feature checklist showing implemented vs planned features
  - NPM package security scanner with embedded blocklist
  - Sensitive data detection (API keys, passwords, secrets)

- **Sync Infrastructure** (Experimental):
  - P2P sync via libp2p (mDNS discovery, Noise encryption)
  - Server sync mode with REST API (axum)
  - SurrealDB integration for sync-capable storage
  - Device ID persistence and management

- **Build System**:
  - Modular feature flags (full, p2p-sync, server-sync, minimal)
  - Fast `--lite` builds without sync features (~2 min)
  - Aggressive parallelization (16 cores, mold linker)
  - `rebuild.nu` script for optimized local builds

- **CI/CD**:
  - Full GitHub Actions pipeline with Nix builds
  - Home Manager module validation
  - NPM security scanning workflow
  - Linux-only restriction for egui (Wayland/X11)

### Fixed

- libclang path for surrealdb-librocksdb-sys bindgen
- Home Manager module evaluation (functions are lambdas)
- NPM artifact naming with scoped packages
- ajv date-time format validation
- Multiple clippy warnings for clean CI

### Notes

- P2P/Server sync features are implemented but marked experimental
- macOS builds require manual cargo build (Nix packaging Linux-only)
- See cursor-studio-egui/ROADMAP.md for planned features

---

## [0.2.0-rc2] - 2025-11-29

### Added

- **Jump-to-Message Functionality**:
  - Click bookmark "→" button to scroll to message
  - Click security finding "→" to jump to sensitive data
  - Highlight animation for jumped-to messages
  - Works across conversation tabs

- **NPM Package Security Scanner**:
  - Embedded blocklist of known malicious packages
  - Shai-Hulud 2025 attack patterns
  - Historical compromised packages (event-stream, flatmap-stream, etc.)
  - Typosquatting package detection
  - CVE tracking for blocked packages
  - Directory scanning for package.json files
  - Category breakdown (historical, typosquatting, etc.)

- **Security Panel Enhancements**:
  - Sensitive data scan results with jump-to buttons
  - NPM Package Security section
  - Blocklist database stats (version, last updated, totals)
  - Scan path input for npm scanning
  - Results display with file paths and package details

- **Export to Markdown**:
  - 📤 button in conversation toolbar
  - Includes tool calls with JSON formatting
  - Thinking blocks in collapsible `<details>` tags
  - Auto-creates `~/Documents/cursor-studio-exports/`
  - Filename sanitization

- **In-Conversation Search**:
  - 🔍 search box in conversation toolbar
  - Searches content, thinking blocks, and tool calls
  - Live search (triggers after 2 characters)
  - ◀/▶ navigation between results
  - Result counter (X/Y matches)
  - Jump to matching messages

## [0.2.0-rc1] - 2025-11-28

### Added

- **Cursor Studio (egui)**: New VS Code-like unified application
  - Activity bar with sidebar toggles
  - Dual sidebars (Version Manager left, Chat Library right)
  - Tabbed interface for conversations
  - VS Code theme parser and converter
  - Modern toggle switches and dropdowns
  - Animated import spinner
  
- **Chat Message Improvements**:
  - Tool call rendering with status icons (✓/⏳/✗)
  - Thinking blocks (custom collapsible, theme-aware)
  - Code block syntax highlighting
  - Markdown rendering (headings, bold, inline code, bullets)
  - **Right-aligned user messages** (bubble style with accent background)
  - Left-aligned AI responses
  - Bookmark buttons on every message
  
- **Bookmark System** (Fully functional):
  - Persistent bookmarks that survive cache clears
  - Per-message bookmarks with labels, notes, colors (🔖 gold default)
  - Bookmark panel toggle in conversation header
  - Jump to bookmarked messages
  - Auto-reattach bookmarks after reimport by sequence number
  
- **Display Preferences UI**:
  - Configurable alignment per content type (◀ left / ▶ right / ◆ center)
  - Live preview in Settings → Display section
  - Supports: User Messages, AI Responses, Thinking Blocks, Tool Calls
  - Persisted to database
  
- **Data Model Enhancements**:
  - Content type detection (text, code, terminal, markdown, mixed)
  - Request segments for grouping user turns
  - Files edited tracking
  
- **Unicode Font Support**:
  - Automatic font loading from system and Nix paths
  - JetBrains Mono, DejaVu, Noto fonts
  - NIX_PROFILES environment variable support
  - Fonts bundled in Nix flake (dejavu, noto, jetbrains-mono)

- **Live Display Preferences**:
  - Message alignment updates immediately when changed in Settings
  - Center alignment option with styled frame
  - Each alignment type has distinct visual style

- **Import Progress Warning**:
  - Two-click import (first click shows warning)
  - Clear warning about UI freeze for large histories
  - Status bar feedback during import

- **Analytics Dashboard** (Status Bar):
  - Real-time message type breakdown
  - Shows: chats, user messages, AI responses, tool calls, thinking blocks, code blocks, bookmarks
  - Updates automatically after import

- **Async Background Import**:
  - Import runs in separate thread (doesn't freeze UI)
  - Progress bar in status bar (X/Y databases, percentage)
  - Spinner animation during import
  - Two-click confirmation (warning then proceed)

- **UI Appearance Customization**:
  - Font scale slider (80%-150%)
  - Message spacing slider (4px-32px)
  - Status bar font size slider (8px-16px)
  - All settings in Settings → Appearance

- **Feature Roadmap** (`ROADMAP.md`):
  - Comprehensive tracking of completed/planned features
  - Known issues documented
  - Future goals outlined

- **Clear & Reimport**:
  - New "🔄 Clear & Reimport" button in Dashboard
  - Clears all cached conversations
  - Preserves bookmarks (stored by message sequence)
  - Reattaches bookmarks to reimported messages
  - Shows success/failure count for bookmark reattachment

- **Resource Allocation Settings** (Settings → Resources):
  - CPU Threads slider (1 to max available cores)
  - RAM Limit slider (512MB - 16GB)
  - VRAM Limit slider (256MB - 32GB for future GPU features)
  - Storage Limit slider (1GB - 100GB)
  - Note: Limits are stored for future AI/caching features

- **Tool Call Preview Enhancement**:
  - Increased args preview from 3 to 5 fields
  - Increased character limit from 50 to 100 chars
  - Shows more useful context for tool calls

### Fixed

- Unicode character handling - safe truncation at character boundaries
- Thinking block styling (replaced default egui CollapsingHeader with custom toggle)
- Tab selection in editor area
- Build performance with mold linker
- Borrow checker issues in UI rendering (action queuing pattern)
- Bookmark buttons now visible (⭐ instead of ☆, larger size, hover cursor)

## [0.1.2] - 2025-11-27

### Fixed

- **cursor-manager**: Fixed PEP8 linting errors (E303, E501) that caused build failures
  - Removed extra blank line before `analyze_disk` method
  - Split long line in `clean_orphans` messagebox call
  - The `writePython3Bin` builder enforces PEP8, so these style issues were causing Home Manager activation failures

## [0.1.1] - 2025-11-26

### Added

- **Disk Management UI**: Added disk usage analysis and cleanup to Cursor Manager GUI
  - Cache cleaning (removes Cache, CachedData, GPUCache, etc.)
  - Orphan directory cleanup (removes unused `~/.cursor-VERSION/` directories)
  - Real-time disk usage display
- **Garbage Collection Module**: New `gc.nix` module for Cursor-specific cleanup
- **Nushell GC Helper**: `gc-helper.nu` script for automated disk space management

### Changed

- Home Manager module now supports `overwriteBackup` option to prevent backup conflicts

## [0.1.0] - 2025-11-25

### Added

- Initial release with 48 Cursor versions available
- **Multi-Version Manager GUI** (`cursor-manager`)
  - Era-based version selection (2.0.x, 1.7.x, 1.6.x)
  - Settings sync between versions
  - Optional globalStorage sharing for auth/docs
- **Home Manager Module** with MCP server integration
  - Filesystem MCP server
  - Memory MCP server
  - NixOS MCP server (package/option search)
  - GitHub MCP server (with secrets support)
  - Playwright MCP server (browser automation)
- **Automated Updates**
  - Daily update checks with desktop notifications
  - `cursor-update` command for one-click updates
  - `cursor-check-update` for manual checks
- **Version Packages**
  - 17 versions from 2.0.x Custom Modes Era
  - 19 versions from 1.7.x Classic Era
  - 1 version from 1.6.x Legacy Era
  - Isolated user data directories per version
- **Documentation**
  - Comprehensive README with quick start guide
  - User data persistence guide
  - Secrets management documentation
  - Example configurations (basic, with-sops, with-agenix, with-mcp)

[0.1.2]: https://github.com/Distracted-E421/nixos-cursor/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Distracted-E421/nixos-cursor/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Distracted-E421/nixos-cursor/releases/tag/v0.1.0
