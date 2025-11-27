# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
