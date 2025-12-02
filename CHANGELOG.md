# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-12-02

### Added

#### Cursor Studio 🎉
- **Chat Library**: Import, search, and bookmark conversations from Cursor IDE
- **Security Scanning**: Detect API keys, secrets, and passwords in chat history
- **VS Code Themes**: Full theme support with live preview and custom themes
- **Multi-Version Management**: Launch any available Cursor version
- **Selective Version Cleanup**: Remove specific versions (checkbox selection, not all-or-nothing)
- **Background Threading**: Security scans run off main thread, UI stays responsive
- **Settings Scrollbar**: Better UX on small screens with scrollable settings panel

#### CLI (cursor-studio-cli)
- Command-line interface for automation
- Version listing and management
- Chat export functionality

### Changed
- **Nushell Migration**: All scripts converted from bash (except 3 Nix-required)
- **Examples Updated**: Now show real homelab patterns with direct package installation
- **Download URLs**: Using S3 URLs with verified SRI hashes

### Deprecated
- `cursor-manager` (tkinter) - now redirects to `cursor-studio`
- `cursor-chat-library` (tkinter) - now redirects to `cursor-studio`
- `downloader.cursor.sh` fallback removed (requires explicit `srcUrl`)

### Fixed
- Security scan no longer crashes app (moved to background thread)
- NPM scan no longer freezes UI

## [0.1.2] - 2025-11-30

### Added
- Initial secrets support (agenix, sops-nix examples)
- 37+ Cursor versions available

## [0.1.1] - 2025-11-15

### Added
- Multi-version support
- MCP server integration

## [0.1.0] - 2025-11-01

### Added
- Initial release
- Cursor IDE packaging for NixOS
- Home Manager module
- Basic version management
