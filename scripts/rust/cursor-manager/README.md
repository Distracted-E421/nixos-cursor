# Cursor Manager (Rust)

Fast, reliable Cursor IDE version manager written in Rust.

## Features

- ⚡ **Fast** - Native compiled binary, instant startup
- 🔒 **Reliable** - Type-safe, memory-safe, no runtime errors
- 📦 **Version Management** - Install, switch, uninstall versions
- 🧹 **Cleanup** - Automatic disk space management
- 🔄 **Progress** - Beautiful download progress bars

## Installation

```bash
# Build from source
cargo build --release

# Install to PATH
cargo install --path .
```

## Usage

```bash
# List installed versions
cursor-manager list

# List all available versions
cursor-manager list --all

# Install a version
cursor-manager install 2.1.34
cursor-manager install latest

# Switch to a version
cursor-manager use 2.1.34

# Show current version
cursor-manager current

# Show version info
cursor-manager info 2.1.34

# Uninstall a version
cursor-manager uninstall 2.0.77
cursor-manager uninstall 2.0.77 --keep-data

# Clean old versions
cursor-manager clean
cursor-manager clean --older-than 30
cursor-manager clean --dry-run

# Configuration
cursor-manager config
cursor-manager config install_dir
cursor-manager config keep_versions 5
```

## Architecture

```
src/
├── main.rs       # Entry point
├── cli.rs        # CLI commands (clap)
├── config.rs     # Configuration management
├── version.rs    # Version resolution and management
├── instance.rs   # Isolated instance management
└── download.rs   # HTTP downloads with progress
```

## Why Rust?

| Requirement | Why Rust Fits |
|-------------|---------------|
| Fast startup | Native compiled, no runtime |
| Reliable | Memory safety, type safety |
| CLI UX | Excellent ecosystem (clap, indicatif) |
| Downloads | Async with tokio/reqwest |
| Cross-platform | Single binary, easy distribution |

## Development

```bash
# Run in development
cargo run -- list

# Run tests
cargo test

# Build release
cargo build --release

# Check formatting
cargo fmt --check

# Run clippy
cargo clippy
```

## Integration

The cursor-manager can be called from other tools:

```bash
# JSON output (future)
cursor-manager list --json

# Exit codes
# 0 = success
# 1 = error
```

## License

MIT
