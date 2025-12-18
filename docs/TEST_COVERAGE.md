# Test Coverage Summary

> **Last Updated**: December 17, 2025

## Overview

This document tracks test coverage across the nixos-cursor project.

## Test Infrastructure

### Test Runners

| Runner | Location | Purpose |
|--------|----------|---------|
| `run-all-tests.nu` | `tests/` | Comprehensive Nushell test harness |
| `cargo test` | `scripts/rust/cursor-manager/` | Rust unit tests |
| `pytest` | `scripts/python/tests/` | Python MCP server tests |

### Running All Tests

```bash
# Run comprehensive test suite
nu tests/run-all-tests.nu

# Run Rust tests only
cd scripts/rust/cursor-manager && cargo test

# Run Python tests only
cd scripts/python && pytest tests/ -v

# Run proxy tests only
cd tools/proxy-test && pytest tests/ -v
```

## Coverage by Component

### 1. Rust: cursor-manager (45 tests) ✅

| Module | Tests | Status |
|--------|-------|--------|
| `config.rs` | 8 | ✅ All passing |
| `version.rs` | 20 | ✅ All passing |
| `instance.rs` | 9 | ✅ All passing |
| `download.rs` | 8 | ✅ All passing |

**Test Categories:**
- Unit tests for all public functions
- Config serialization/deserialization
- Version management (list, install, uninstall, cleanup)
- Instance lifecycle management
- Download URL generation and hash verification
- Async operations (tokio::test)

### 2. Rust: cursor-studio-egui (24 modules with tests) ✅

Already has comprehensive tests:
- `diagram/` - Parser, layout, graph, syntax, dataflow, theme_mapper
- `sync/` - Config, models, daemon, pipe_client
- `chat/` - Models, CRDT, cursor_parser, p2p, sync_service, conversation_browser
- `docs/` - Client
- Core modules: theme, theme_loader, security, database, approval, versions, version_registry

### 3. Python: MCP Servers (NEW) 🆕

| Module | Test File | Tests |
|--------|-----------|-------|
| `cursor_context_inject.py` | `test_context_inject.py` | ~25 tests |
| `cursor_docs_mcp.py` | `test_docs_mcp.py` | ~20 tests |
| `cursor_sync_poc.py` | `test_sync_poc.py` | ~15 tests |

**Test Categories:**
- ContextStore CRUD operations
- Context expiration handling
- Search functionality
- Document chunking algorithms
- FTS search integration
- Database initialization and schema
- Message/conversation storage
- Foreign key relationships

### 4. Tools: proxy-test (NEW) 🆕

| Module | Test File | Tests |
|--------|-----------|-------|
| `test_cursor_proxy.py` | `test_proxy_addon.py` | ~15 tests |

**Test Categories:**
- Domain matching logic
- SSE parsing
- Statistics tracking
- Error tracking
- Certificate pinning detection
- Streaming response detection

### 5. Nushell Scripts (Syntax Validation) ✅

Covered by `run-all-tests.nu`:
- `disk-usage.nu`
- `gc-helper.nu`
- `validate-urls.nu`
- `test-versions.nu`

### 6. Nix Flake ✅

Covered by `run-all-tests.nu`:
- Flake check
- Package evaluation
- DevShell evaluation
- Version package evaluation

## Test Commands Summary

```bash
# Full test suite
nu tests/run-all-tests.nu

# Individual components
nu tests/run-all-tests.nu --rust      # Rust only
nu tests/run-all-tests.nu --python    # Python only
nu tests/run-all-tests.nu --nushell   # Nushell only
nu tests/run-all-tests.nu --nix       # Nix flake only

# Direct test runners
cargo test -p cursor-manager          # cursor-manager
cargo test -p cursor-studio           # cursor-studio-egui
pytest scripts/python/tests/ -v       # Python MCP servers
pytest tools/proxy-test/tests/ -v     # Proxy addon
```

## Coverage Gaps (TODO)

### High Priority
- [ ] Integration tests for cursor-manager CLI
- [ ] End-to-end tests for MCP server communication
- [ ] Mock tests for actual Cursor database reading

### Medium Priority
- [ ] Performance benchmarks for chunking algorithms
- [ ] Stress tests for sync daemon
- [ ] UI tests for cursor-studio-egui (requires headless egui)

### Low Priority
- [ ] Property-based testing for parsers
- [ ] Fuzzing for input handlers
- [ ] Cross-platform tests (Darwin)

## Adding New Tests

### Rust Tests

Add `#[cfg(test)]` module at the bottom of source files:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_example() {
        assert!(true);
    }

    #[tokio::test]
    async fn test_async_example() {
        assert!(true);
    }
}
```

### Python Tests

Create `test_<module>.py` in `scripts/python/tests/`:

```python
import pytest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))
from module_name import function_to_test

class TestFeature:
    def test_example(self):
        assert function_to_test() == expected_value
```

## CI Integration

Tests are run via GitHub Actions on:
- Push to main
- Pull requests
- Manual workflow dispatch

See `.github/workflows/test.yml` for configuration.

