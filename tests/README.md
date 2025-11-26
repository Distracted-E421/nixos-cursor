# Test Suite

Comprehensive test harness for all languages and components.

## Quick Start

```bash
# Run all tests
nix develop --command nu tests/run-all-tests.nu

# Or if nu is already available
nu tests/run-all-tests.nu
```

## Test Suites

### Nix Flake Tests (`--nix`)

- Flake syntax check
- Package evaluation
- DevShell evaluation

### Nushell Script Tests (`--nushell`)

- Script syntax validation
- `--help` flag tests
- All scripts in `scripts/nu/`

### Python Script Tests (`--python`)

- Syntax validation
- Dependency checks

### Elixir Project Tests (`--elixir`)

- Project structure
- Module existence
- mix.exs validation

### Rust Project Tests (`--rust`)

- Cargo.toml validation
- Source file existence
- `cargo check` (syntax + types)

### Version Package Tests (`--versions`)

- Sample version package evaluation

## Usage

```bash
# Run all tests
nu run-all-tests.nu

# Run specific test suite
nu run-all-tests.nu --nushell
nu run-all-tests.nu --rust
nu run-all-tests.nu --elixir

# Multiple suites
nu run-all-tests.nu --nushell --python

# JSON output (for CI)
nu run-all-tests.nu --json

# Help
nu run-all-tests.nu --help
```

## CI Integration

The test harness is designed for CI:

```yaml
- name: Run tests
  run: |
    nix develop --command nu tests/run-all-tests.nu --json > results.json
```

Exit codes:
- `0`: All tests passed
- `1`: One or more tests failed

## Adding Tests

Edit `tests/run-all-tests.nu`:

```nu
# Add a new test
def test-my-feature [repo_root: string]: nothing -> list {
    section "My Feature Tests"
    mut results = []
    
    let r1 = (test-cmd "Test description" "command to run")
    $results = ($results | append $r1)
    
    $results
}
```

## Why Nushell for Tests?

| Requirement | Why Nushell |
|-------------|-------------|
| Cross-language | Can run any script/binary |
| Structured output | Native JSON/tables |
| Progress reporting | Beautiful console output |
| CI-friendly | JSON output mode |
| Self-testing | Tests the Nushell scripts too |
