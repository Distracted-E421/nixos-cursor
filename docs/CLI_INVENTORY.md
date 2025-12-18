# CLI & Scripts Inventory

Complete inventory of all CLI tools, scripts, and commands exposed by nixos-cursor.

## 📦 Flake Packages (`nix run .#<package>`)

### Primary Tools

| Package | Binary | Description | Status |
|---------|--------|-------------|--------|
| `cursor` | `cursor` | Latest stable Cursor IDE (2.2.27) | ✅ Active |
| `cursor-studio` | `cursor-studio` | GUI dashboard (Rust/egui) | ✅ Active |
| `cursor-studio-cli` | `cursor-studio-cli` | CLI for version management | ✅ Active |
| `cursor-test` | `cursor-test` | Isolated testing instance | ✅ Active |

### Deprecated Tools

| Package | Binary | Replacement | Status |
|---------|--------|-------------|--------|
| `cursor-manager` | `cursor-manager` | `cursor-studio` | ⚠️ Deprecated |
| `cursor-chat-library` | `cursor-chat-library` | `cursor-studio` | ⚠️ Deprecated |

### Version-Specific Packages (68 total)

All versions follow the pattern: `cursor-X_Y_Z` → binary `cursor-X.Y.Z`

**2.2.x Era (11 versions):**
`cursor-2_2_27`, `cursor-2_2_23`, `cursor-2_2_20`, `cursor-2_2_17`, `cursor-2_2_14`, `cursor-2_2_12`, `cursor-2_2_9`, `cursor-2_2_8`, `cursor-2_2_7`, `cursor-2_2_6`, `cursor-2_2_3`

**2.1.x Era (21 versions):**
`cursor-2_1_50`, `cursor-2_1_49`, `cursor-2_1_48`, `cursor-2_1_47`, `cursor-2_1_46`, `cursor-2_1_44`, `cursor-2_1_42`, `cursor-2_1_41`, `cursor-2_1_39`, `cursor-2_1_36`, `cursor-2_1_34`, `cursor-2_1_32`, `cursor-2_1_26`, `cursor-2_1_25`, `cursor-2_1_24`, `cursor-2_1_20`, `cursor-2_1_19`, `cursor-2_1_17`, `cursor-2_1_15`, `cursor-2_1_7`, `cursor-2_1_6`

**2.0.x Custom Modes Era (17 versions):**
`cursor-2_0_77`, `cursor-2_0_75`, `cursor-2_0_74`, `cursor-2_0_73`, `cursor-2_0_69`, `cursor-2_0_64`, `cursor-2_0_63`, `cursor-2_0_60`, `cursor-2_0_57`, `cursor-2_0_54`, `cursor-2_0_52`, `cursor-2_0_43`, `cursor-2_0_40`, `cursor-2_0_38`, `cursor-2_0_34`, `cursor-2_0_32`, `cursor-2_0_11`

**1.7.x Classic Era (19 versions):**
`cursor-1_7_54`, `cursor-1_7_53`, `cursor-1_7_52`, `cursor-1_7_46`, `cursor-1_7_44`, `cursor-1_7_43`, `cursor-1_7_40`, `cursor-1_7_39`, `cursor-1_7_38`, `cursor-1_7_36`, `cursor-1_7_33`, `cursor-1_7_28`, `cursor-1_7_25`, `cursor-1_7_23`, `cursor-1_7_22`, `cursor-1_7_17`, `cursor-1_7_16`, `cursor-1_7_12`, `cursor-1_7_11`

---

## 🖥️ Binary Commands (After Installation)

### From `cursor` Package

```bash
cursor                 # Launch Cursor IDE
cursor-update          # Update flake and rebuild
cursor-check-update    # Check for available updates
```

### From `cursor-studio` Package

```bash
cursor-studio          # Launch GUI dashboard
cursor-studio-cli      # CLI version management
sync-cli              # Chat sync client (experimental)
sync-server           # Chat sync server (experimental)
p2p-sync              # P2P chat sync (experimental)
```

### cursor-studio-cli Commands

```bash
cursor-studio-cli list                    # List installed versions
cursor-studio-cli list --available        # Show downloadable versions
cursor-studio-cli list --all              # Show all versions
cursor-studio-cli download 2.1.34         # Download a version
cursor-studio-cli install 2.1.34          # Download + install
cursor-studio-cli info 2.0.77             # Version details
cursor-studio-cli clean --older-than 30   # Cleanup old versions
cursor-studio-cli clean --dry-run         # Preview cleanup
cursor-studio-cli launch                  # Launch current version
cursor-studio-cli launch 2.0.77           # Launch specific version
cursor-studio-cli cache                   # Show cache/storage info
cursor-studio-cli hash 2.1.34             # Compute/verify hash
cursor-studio-cli verify-hashes           # Verify all hashes
cursor-studio-cli import /path/file       # Import manual download
cursor-studio-cli urls 2.1.34             # Show download URLs
cursor-studio-cli export-registry         # Export hash registry
cursor-studio-cli import-registry file    # Import hash registry
```

---

## 📜 Scripts (Development/Automation)

### Nushell Scripts (`scripts/nu/`)

Run with: `nu scripts/nu/<script>.nu`

| Script | Purpose | Example |
|--------|---------|---------|
| `disk-usage.nu` | Analyze Nix store for Cursor packages | `nu disk-usage.nu --detailed` |
| `gc-helper.nu` | Safe garbage collection | `nu gc-helper.nu collect` |
| `validate-urls.nu` | Check download URLs | `nu validate-urls.nu --linux-only` |
| `test-versions.nu` | Test version builds | `nu test-versions.nu full` |
| `cursor-data-tracker.nu` | Git-based config tracking | `nu cursor-data-tracker.nu status` |
| `cursor-context-monitor.nu` | Monitor AI context | `nu cursor-context-monitor.nu --watch` |

### Python Scripts (`scripts/python/`)

Run with: `python scripts/python/<script>.py` or via dev shell

| Script | Purpose | Example |
|--------|---------|---------|
| `compute_hashes.py` | Compute URL hashes | `python compute_hashes.py --all` |

### Release Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `prepare-public-branch.nu` | Prepare pre-release from dev |
| `release-to-main.nu` | Release to main branch |
| `validate-public-branch.nu` | Validate branch before release |

### Test Scripts (`tests/`)

| Script | Purpose |
|--------|---------|
| `run-all-tests.nu` | Comprehensive test harness |
| `multi-version-test.nu` | Test concurrent version launches |

### Security Scripts (`security/tests/`)

| Script | Purpose |
|--------|---------|
| `run-all-tests.nu` | Security test suite |
| `test-blocklist.nu` | Test package blocklist |
| `test-scanner.nu` | Test security scanner |

---

## 🔧 Home Manager Services

When using the Home Manager module:

### Enabled Services

| Service | Timer | Purpose |
|---------|-------|---------|
| `cursor-update-check` | Configurable | Check for updates |
| `cursor-gc` | Configurable | Garbage collection |

### Commands via Services

```bash
# Manual update check
systemctl --user start cursor-update-check

# Manual GC
systemctl --user start cursor-gc

# Check status
systemctl --user status cursor-update-check
systemctl --user list-timers
```

---

## 🔐 Security CLI (Via Home Manager)

When using security features:

```bash
cursor-security status              # Show security status
cursor-security scan <package>      # Scan NPM package
cursor-security check <package>     # Check blocklist
cursor-security update-blocklist    # Update blocklist
cursor-security generate-lockfile   # Generate lockfile
cursor-security audit               # Run npm audit
```

---

## 🛠️ Development Shell

Enter with: `nix develop`

### Available Tools

- `nushell` (nu) - Modern shell scripting
- `python3` with packages (requests, beautifulsoup4, etc.)
- `rust-analyzer` - Rust IDE support
- `cargo` - Rust build tool
- Git, jq, ripgrep, etc.

### Shell Commands

```bash
# Run nushell scripts
nu scripts/nu/disk-usage.nu

# Run Python scripts
python scripts/python/compute_hashes.py

# Run tests
nu tests/run-all-tests.nu

# Build packages
nix build .#cursor-studio
nix build .#cursor

# Check flake
nix flake check
```

---

## 📊 Quick Reference

### Most Common Commands

```bash
# Daily Use
cursor                              # Launch Cursor
cursor-studio                       # Launch dashboard
cursor-studio-cli list              # Show versions

# Updates
cursor-update                       # Update and rebuild
cursor-check-update                 # Check for updates

# Version Management
nix run .#cursor-2_0_77            # Run specific version
cursor-studio-cli install 2.1.34   # Install version
cursor-studio-cli clean            # Cleanup

# Debugging
cursor-studio-cli cache            # Storage info
nu scripts/nu/disk-usage.nu        # Nix store analysis
```

### Build Commands

```bash
# Build packages
nix build .#cursor
nix build .#cursor-studio
nix build .#cursor-2_0_77

# Dry-run (check if builds)
nix build .#cursor --dry-run

# Development
nix develop
cargo build --release  # in cursor-studio-egui/
```

---

## ⚠️ Known Issues

1. **cursor-manager/cursor-chat-library**: These show deprecation warnings and redirect to cursor-studio

2. **cursor-security**: Only available when Home Manager module is used with security features enabled

3. **sync-cli/sync-server/p2p-sync**: Experimental, may not be fully functional

---

## 📚 Related Documentation

- [VERSION_MANAGER_GUIDE.md](../VERSION_MANAGER_GUIDE.md) - Detailed version management
- [scripts/README.md](../scripts/README.md) - Script documentation
- [scripts/nu/README.md](../scripts/nu/README.md) - Nushell scripts
- [SECURITY.md](../SECURITY.md) - Security features
- [docs/SETUP.md](SETUP.md) - Installation guide

---

**Last Updated**: 2025-12-17

