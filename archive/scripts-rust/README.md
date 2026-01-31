# Rust Projects

Performance-critical CLI tools and utilities built with Rust.

## Why Rust?

| Requirement | Why Rust Fits |
|-------------|---------------|
| Fast startup | Native compiled, no runtime |
| Reliable | Memory safety, type safety |
| CLI UX | Excellent ecosystem (clap, indicatif, console) |
| Async IO | tokio/reqwest for downloads |
| Cross-platform | Single binary distribution |

## Projects

### `cursor-manager/`

Fast, reliable Cursor IDE version manager.

```bash
cd cursor-manager

# Build
cargo build --release

# Run
./target/release/cursor-manager list
./target/release/cursor-manager install latest
./target/release/cursor-manager use 2.1.34

# Run tests
cargo test
```

**Features:**
- ⚡ Instant startup (native binary)
- 📦 Version management (install, switch, uninstall)
- 🔄 Progress bars for downloads
- 🧹 Automatic cleanup

## Development Environment

```bash
# Full development shell with Rust
nix develop .#full

# Or specific Rust shell
nix-shell -p rustc cargo
```

## Rust Standards

See [rust-scripting.mdc](../../.cursor/rules/languages/rust-scripting.mdc) for coding standards.

Key principles:
- Use `anyhow` for error handling in applications
- Use `thiserror` for library error types
- Prefer `clap` derive macros for CLI
- Use `tokio` for async runtime
- Format with `cargo fmt`, lint with `cargo clippy`
