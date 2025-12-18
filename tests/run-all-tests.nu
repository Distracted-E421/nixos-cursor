#!/usr/bin/env nu

# Script: run-all-tests.nu
# Purpose: Comprehensive test harness for all languages and components
# Usage: nu run-all-tests.nu [options]
#
# Tests: Nushell scripts, Python scripts, Elixir compilation, Rust compilation, Nix flake

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

const VERSION = "1.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def header [title: string] {
    print ""
    print $"(ansi blue)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi blue)║     (ansi white_bold)($title)(ansi reset)(ansi blue)                              ║(ansi reset)"
    print $"(ansi blue)╚═══════════════════════════════════════════════════════════════════╝(ansi reset)"
    print ""
}

def section [title: string] {
    print ""
    print $"(ansi cyan)━━━ ($title) ━━━(ansi reset)"
    print ""
}

def pass [test: string] { print $"  (ansi green)✓(ansi reset) ($test)" }
def fail [test: string] { print $"  (ansi red)✗(ansi reset) ($test)" }
def skip-test [test: string] { print $"  (ansi yellow)○(ansi reset) ($test) \(skipped\)" }
def info [msg: string] { print $"  (ansi cyan)ℹ(ansi reset) ($msg)" }

# Check if a command exists
def has-command [cmd: string]: nothing -> bool {
    (which $cmd | length) > 0
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST SUITES
# ─────────────────────────────────────────────────────────────────────────────

# Test Nix flake
def test-nix [repo_root: string]: nothing -> list {
    section "Nix Flake Tests"
    
    mut results = []
    
    # Check flake
    let r1 = (do { cd $repo_root; nix flake check --no-build } | complete)
    if $r1.exit_code == 0 {
        pass "Flake check"
        $results = ($results | append { test: "Flake check", status: "pass" })
    } else {
        fail $"Flake check: ($r1.stderr | str trim | str substring 0..100)"
        $results = ($results | append { test: "Flake check", status: "fail", error: $r1.stderr })
    }
    
    # Evaluate main package
    let r2 = (do { nix eval $"($repo_root)#cursor.name" --impure } | complete)
    if $r2.exit_code == 0 {
        pass "Evaluate cursor package"
        $results = ($results | append { test: "Evaluate cursor package", status: "pass" })
    } else {
        fail "Evaluate cursor package"
        $results = ($results | append { test: "Evaluate cursor package", status: "fail" })
    }
    
    # Evaluate cursor-manager
    let r3 = (do { nix eval $"($repo_root)#cursor-manager.name" --impure } | complete)
    if $r3.exit_code == 0 {
        pass "Evaluate cursor-manager"
        $results = ($results | append { test: "Evaluate cursor-manager", status: "pass" })
    } else {
        fail "Evaluate cursor-manager"
        $results = ($results | append { test: "Evaluate cursor-manager", status: "fail" })
    }
    
    # Check devShell
    let r4 = (do { nix eval $"($repo_root)#devShells.x86_64-linux.default.name" --impure } | complete)
    if $r4.exit_code == 0 {
        pass "Evaluate devShell"
        $results = ($results | append { test: "Evaluate devShell", status: "pass" })
    } else {
        fail "Evaluate devShell"
        $results = ($results | append { test: "Evaluate devShell", status: "fail" })
    }
    
    $results
}

# Test Nushell scripts
def test-nushell [repo_root: string]: nothing -> list {
    section "Nushell Script Tests"
    
    mut results = []
    let scripts_dir = $"($repo_root)/scripts/nu"
    
    # Test script syntax
    for script in (glob $"($scripts_dir)/*.nu") {
        let name = ($script | path basename)
        let r = (do { nu --commands $"source ($script)" } | complete)
        if $r.exit_code == 0 {
            pass $"Syntax: ($name)"
            $results = ($results | append { test: $"Syntax: ($name)", status: "pass" })
        } else {
            fail $"Syntax: ($name)"
            $results = ($results | append { test: $"Syntax: ($name)", status: "fail" })
        }
    }
    
    # Test disk-usage.nu --help
    let r1 = (do { nu $"($scripts_dir)/disk-usage.nu" --help } | complete)
    if $r1.exit_code == 0 {
        pass "disk-usage.nu --help"
        $results = ($results | append { test: "disk-usage.nu --help", status: "pass" })
    } else {
        fail "disk-usage.nu --help"
        $results = ($results | append { test: "disk-usage.nu --help", status: "fail" })
    }
    
    # Test gc-helper.nu --help
    let r2 = (do { nu $"($scripts_dir)/gc-helper.nu" --help } | complete)
    if $r2.exit_code == 0 {
        pass "gc-helper.nu --help"
        $results = ($results | append { test: "gc-helper.nu --help", status: "pass" })
    } else {
        fail "gc-helper.nu --help"
        $results = ($results | append { test: "gc-helper.nu --help", status: "fail" })
    }
    
    # Test validate-urls.nu --help
    let r3 = (do { nu $"($scripts_dir)/validate-urls.nu" --help } | complete)
    if $r3.exit_code == 0 {
        pass "validate-urls.nu --help"
        $results = ($results | append { test: "validate-urls.nu --help", status: "pass" })
    } else {
        fail "validate-urls.nu --help"
        $results = ($results | append { test: "validate-urls.nu --help", status: "fail" })
    }
    
    # Test test-versions.nu --help
    let r4 = (do { nu $"($scripts_dir)/test-versions.nu" --help } | complete)
    if $r4.exit_code == 0 {
        pass "test-versions.nu --help"
        $results = ($results | append { test: "test-versions.nu --help", status: "pass" })
    } else {
        fail "test-versions.nu --help"
        $results = ($results | append { test: "test-versions.nu --help", status: "fail" })
    }
    
    $results
}

# Test Python scripts
def test-python [repo_root: string]: nothing -> list {
    section "Python Script Tests"
    
    mut results = []
    let scripts_dir = $"($repo_root)/scripts/python"
    
    if not (has-command "python3") {
        skip-test "Python not available"
        return [{ test: "Python", status: "skip" }]
    }
    
    # Check syntax for all Python scripts
    let py_scripts = [
        "compute_hashes.py"
        "cursor_context_inject.py"
        "cursor_docs_mcp.py"
        "cursor_sync_poc.py"
    ]
    
    for script in $py_scripts {
        let script_path = $"($scripts_dir)/($script)"
        if ($script_path | path exists) {
            let r = (do { python3 -m py_compile $script_path } | complete)
            if $r.exit_code == 0 {
                pass $"($script) syntax"
                $results = ($results | append { test: $"($script) syntax", status: "pass" })
            } else {
                fail $"($script) syntax"
                $results = ($results | append { test: $"($script) syntax", status: "fail" })
            }
        }
    }
    
    # Check if pytest tests exist and can be discovered
    let tests_dir = $"($scripts_dir)/tests"
    if ($tests_dir | path exists) {
        let test_files = (ls $"($tests_dir)/test_*.py" | length)
        if $test_files > 0 {
            pass $"Found ($test_files) pytest test files"
            $results = ($results | append { test: "Pytest tests discovered", status: "pass" })
            
            # Try running pytest if available
            if (has-command "pytest") {
                info "Running pytest..."
                let r = (do { cd $scripts_dir; pytest tests/ -v --tb=short 2>&1 } | complete)
                if $r.exit_code == 0 {
                    pass "Pytest tests passed"
                    $results = ($results | append { test: "Pytest", status: "pass" })
                } else {
                    fail "Pytest tests failed"
                    $results = ($results | append { test: "Pytest", status: "fail", error: $r.stderr })
                }
            } else {
                skip-test "pytest not installed - run with: pip install pytest pytest-asyncio"
                $results = ($results | append { test: "Pytest", status: "skip" })
            }
        }
    }
    
    # Check imports (requires deps)
    let r2 = (do { python3 -c "import httpx, rich, typer" } | complete)
    if $r2.exit_code == 0 {
        pass "Python dependencies available"
        $results = ($results | append { test: "Python dependencies", status: "pass" })
    } else {
        skip-test "Python dependencies not installed"
        $results = ($results | append { test: "Python dependencies", status: "skip" })
    }
    
    $results
}

# Test Elixir project
def test-elixir [repo_root: string]: nothing -> list {
    section "Elixir Project Tests"
    
    mut results = []
    let elixir_dir = $"($repo_root)/scripts/elixir/cursor_tracker"
    
    if not (has-command "elixir") {
        skip-test "Elixir not available"
        return [{ test: "Elixir", status: "skip" }]
    }
    
    # Check mix.exs exists
    if ($"($elixir_dir)/mix.exs" | path exists) {
        pass "mix.exs exists"
        $results = ($results | append { test: "mix.exs exists", status: "pass" })
    } else {
        fail "mix.exs not found"
        $results = ($results | append { test: "mix.exs exists", status: "fail" })
        return $results
    }
    
    # Check module files exist
    let modules = [
        "lib/cursor_tracker.ex"
        "lib/cursor_tracker/application.ex"
        "lib/cursor_tracker/config.ex"
        "lib/cursor_tracker/git_backend.ex"
        "lib/cursor_tracker/data_watcher.ex"
        "lib/cursor_tracker/snapshot.ex"
        "lib/cursor_tracker/cli.ex"
    ]
    
    for module in $modules {
        let path = $"($elixir_dir)/($module)"
        if ($path | path exists) {
            pass $"Module: ($module)"
            $results = ($results | append { test: $"Module: ($module)", status: "pass" })
        } else {
            fail $"Module missing: ($module)"
            $results = ($results | append { test: $"Module: ($module)", status: "fail" })
        }
    }
    
    $results
}

# Test Rust project
def test-rust [repo_root: string]: nothing -> list {
    section "Rust Project Tests"
    
    mut results = []
    let rust_dir = $"($repo_root)/scripts/rust/cursor-manager"
    
    if not (has-command "cargo") {
        skip-test "Cargo not available"
        return [{ test: "Rust", status: "skip" }]
    }
    
    # Check Cargo.toml exists
    if ($"($rust_dir)/Cargo.toml" | path exists) {
        pass "Cargo.toml exists"
        $results = ($results | append { test: "Cargo.toml exists", status: "pass" })
    } else {
        fail "Cargo.toml not found"
        $results = ($results | append { test: "Cargo.toml exists", status: "fail" })
        return $results
    }
    
    # Check source files
    let sources = [
        "src/main.rs"
        "src/cli.rs"
        "src/config.rs"
        "src/version.rs"
        "src/instance.rs"
        "src/download.rs"
    ]
    
    for src in $sources {
        let path = $"($rust_dir)/($src)"
        if ($path | path exists) {
            pass $"Source: ($src)"
            $results = ($results | append { test: $"Source: ($src)", status: "pass" })
        } else {
            fail $"Source missing: ($src)"
            $results = ($results | append { test: $"Source: ($src)", status: "fail" })
        }
    }
    
    # Try cargo check (syntax validation)
    info "Running cargo check (this may take a moment)..."
    let cargo_result = (do { cd $rust_dir; cargo check 2>&1 } | complete)
    if $cargo_result.exit_code == 0 {
        pass "cargo check passed"
        $results = ($results | append { test: "cargo check", status: "pass" })
    } else {
        fail "cargo check failed"
        $results = ($results | append { test: "cargo check", status: "fail", error: $cargo_result.stderr })
    }
    
    # Run unit tests
    info "Running cargo test..."
    let test_result = (do { cd $rust_dir; cargo test 2>&1 } | complete)
    if $test_result.exit_code == 0 {
        # Count test results
        let output = $test_result.stdout
        pass "cargo test passed"
        $results = ($results | append { test: "cargo test", status: "pass" })
        
        # Extract test count if possible
        let test_line = ($output | lines | where { |l| $l =~ "test result:" } | first | default "")
        if ($test_line | str length) > 0 {
            info $test_line
        }
    } else {
        fail "cargo test failed"
        $results = ($results | append { test: "cargo test", status: "fail", error: $test_result.stderr })
    }
    
    $results
}

# Test version packages (quick mode)
def test-versions [repo_root: string]: nothing -> list {
    section "Cursor Version Package Tests"
    
    mut results = []
    
    # Test a sample of versions
    let sample_versions = ["cursor" "cursor-2_1_34" "cursor-2_0_77" "cursor-1_7_54"]
    
    for pkg in $sample_versions {
        let result = (do { nix eval $"($repo_root)#($pkg).name" --impure } | complete)
        if $result.exit_code == 0 {
            pass $"Package: ($pkg)"
            $results = ($results | append { test: $"Package: ($pkg)", status: "pass" })
        } else {
            fail $"Package: ($pkg)"
            $results = ($results | append { test: $"Package: ($pkg)", status: "fail" })
        }
    }
    
    $results
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

def print-summary [results: list] {
    header "Test Summary"
    
    let total = ($results | length)
    let passed = ($results | where status == "pass" | length)
    let failed = ($results | where status == "fail" | length)
    let skipped = ($results | where status == "skip" | length)
    
    print $"  Total:   (ansi white_bold)($total)(ansi reset)"
    print $"  Passed:  (ansi green)($passed)(ansi reset)"
    print $"  Failed:  (ansi red)($failed)(ansi reset)"
    print $"  Skipped: (ansi yellow)($skipped)(ansi reset)"
    print ""
    
    if $failed > 0 {
        print $"(ansi red)Failed tests:(ansi reset)"
        $results | where status == "fail" | each { |r|
            print $"  ✗ ($r.test)"
            if ($r.error? | is-not-empty) {
                print $"    ($r.error | str trim | str substring 0..100)"
            }
        }
        print ""
        false
    } else {
        print $"(ansi green)All tests passed!(ansi reset)"
        true
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

def main [
    --nix                        # Run only Nix tests
    --nushell                    # Run only Nushell tests
    --python                     # Run only Python tests
    --elixir                     # Run only Elixir tests
    --rust                       # Run only Rust tests
    --versions                   # Run only version package tests
    --json (-j)                  # Output results as JSON
    --help (-h)                  # Show help
] {
    if $help {
        print "
Usage: nu run-all-tests.nu [OPTIONS]

Comprehensive test harness for all languages and components

Options:
    -h, --help      Show this help
    -j, --json      Output results as JSON
    --nix           Run only Nix flake tests
    --nushell       Run only Nushell script tests
    --python        Run only Python script tests
    --elixir        Run only Elixir project tests
    --rust          Run only Rust project tests
    --versions      Run only version package tests

Examples:
    nu run-all-tests.nu                 # Run all tests
    nu run-all-tests.nu --nushell       # Run only Nushell tests
    nu run-all-tests.nu --json          # JSON output
"
        return
    }
    
    header "nixos-cursor Test Suite"
    
    # Determine repo root
    let script_dir = ($env.FILE_PWD? | default ".")
    let repo_root = if ($script_dir | str ends-with "tests") {
        $"($script_dir)/.."
    } else {
        $script_dir
    }
    
    info $"Repository root: ($repo_root)"
    
    # Determine which tests to run
    let run_all = not ($nix or $nushell or $python or $elixir or $rust or $versions)
    
    mut all_results = []
    
    # Run selected tests
    if $run_all or $nix {
        let nix_results = (test-nix $repo_root)
        $all_results = ($all_results | append $nix_results)
    }
    
    if $run_all or $nushell {
        let nu_results = (test-nushell $repo_root)
        $all_results = ($all_results | append $nu_results)
    }
    
    if $run_all or $python {
        let py_results = (test-python $repo_root)
        $all_results = ($all_results | append $py_results)
    }
    
    if $run_all or $elixir {
        let ex_results = (test-elixir $repo_root)
        $all_results = ($all_results | append $ex_results)
    }
    
    if $run_all or $rust {
        let rs_results = (test-rust $repo_root)
        $all_results = ($all_results | append $rs_results)
    }
    
    if $run_all or $versions {
        let ver_results = (test-versions $repo_root)
        $all_results = ($all_results | append $ver_results)
    }
    
    # Output
    if $json {
        $all_results | to json
    } else {
        let success = (print-summary $all_results)
        if not $success {
            exit 1
        }
    }
}
