# Legacy Components - DEPRECATED

> ⚠️ **These files are deprecated and will be removed in v1.0.0**

The Python/tkinter-based components in this directory have been superseded by **Cursor Studio**, a modern Rust/egui application with superior performance, features, and maintainability.

## Deprecated Files

| File | Description | Replacement |
|------|-------------|-------------|
| `manager.nix` | Tkinter version manager GUI | `cursor-studio` (egui GUI) |
| `manager-legacy.nix` | Older tkinter manager | `cursor-studio` (egui GUI) |
| `chat-library.nix` | Tkinter chat viewer | `cursor-studio` (egui GUI) |
| `chat-library-v1.nix` | Older tkinter chat viewer | `cursor-studio` (egui GUI) |
| `chat_db.py` | Python database module | `cursor-studio` (Rust SQLite) |
| `chat_manager_gui.py` | Standalone Python GUI | `cursor-studio` (egui GUI) |

## Why Deprecated?

1. **Fatal Bugs**: `cursor-manager` has an `on_close` attribute error that crashes the app
2. **Performance**: Python/tkinter is slow compared to native Rust/egui
3. **Maintainability**: 1000+ lines of Python embedded in Nix files
4. **Features**: Cursor Studio has more features (security scanning, themes, CLI, etc.)
5. **Future**: TUI support planned for Cursor Studio (Python would require complete rewrite)

## Migration Path

### For Users

```nix
# OLD (deprecated):
home.packages = [ inputs.nixos-cursor.packages.${system}.cursor-manager ];

# NEW (recommended):
home.packages = [ inputs.nixos-cursor.packages.${system}.cursor-studio ];

# Or use the Home Manager module:
programs.cursor-studio.enable = true;
```

### For Developers

The cursor-studio source is in `/cursor-studio-egui/`:

```bash
cd cursor-studio-egui
cargo run                    # GUI
cargo run --bin cursor-studio-cli -- --help  # CLI
```

## Timeline

- **v0.2.0**: Legacy files moved to `/cursor/legacy/`, deprecation warnings added
- **v0.3.0**: Legacy packages removed from flake outputs
- **v1.0.0**: Legacy directory removed entirely

## Preserved for Reference

These files are preserved for historical reference and to support any users who may need to understand the original implementation. They should **NOT** be used for new installations.
