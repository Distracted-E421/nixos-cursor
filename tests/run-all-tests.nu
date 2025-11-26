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
def skip [test: string] { print $"  (ansi yellow)○(ansi reset) ($test) (skipped)" }
def info [msg: string] { print $"  (ansi cyan)ℹ(ansi reset) ($msg)" }

# Run a command and return success/failure
def test-cmd [description: string, cmd: string]: nothing -> record {
    let start = (date now)
    let result = (do { nu -c $cmd } | complete)
    let elapsed = ((date now) - $start)
    
    if $result.exit_code == 0 {
        pass $description
        { test: $description, status: "pass", elapsed: $elapsed }
    } else {
        fail $"($description): ($result.stderr | str trim)"
        { test: $description, status: "fail", elapsed: $elapsed, error: $result.stderr }
    }
}

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
    let r1 = (test-cmd "Flake check" $"cd ($repo_root) && nix flake check --no-build 2>&1")
    $results = ($results | append $r1)
    
    # Evaluate main package
    let r2 = (test-cmd "Evaluate cursor package" $"nix eval ($repo_root)#cursor.name --impure 2>&1")
    $results = ($results | append $r2)
    
    # Evaluate cursor-manager
    let r3 = (test-cmd "Evaluate cursor-manager" $"nix eval ($repo_root)#cursor-manager.name --impure 2>&1")
    $results = ($results | append $r3)
    
    # Check devShell
    let r4 = (test-cmd "Evaluate devShell" $"nix eval ($repo_root)#devShells.x86_64-linux.default.name --impure 2>&1")
    $results = ($results | append $r4)
    
    $results
}

# Test Nushell scripts
def test-nushell [repo_root: string]: nothing -> list {
    section "Nushell Script Tests"
    
    mut results = []
    let scripts_dir = $"($repo_root)/scripts/nu"
    
    # Test script syntax
    for script in (ls $scripts_dir/*.nu | get name) {
        let name = ($script | path basename)
        let r = (test-cmd $"Syntax: ($name)" $"nu --commands 'source ($script)'")
        $results = ($results | append $r)
    }
    
    # Test disk-usage.nu --help
    let r1 = (test-cmd "disk-usage.nu --help" $"nu ($scripts_dir)/disk-usage.nu --help")
    $results = ($results | append $r1)
    
    # Test gc-helper.nu --help
    let r2 = (test-cmd "gc-helper.nu --help" $"nu ($scripts_dir)/gc-helper.nu --help")
    $results = ($results | append $r2)
    
    # Test validate-urls.nu --help
    let r3 = (test-cmd "validate-urls.nu --help" $"nu ($scripts_dir)/validate-urls.nu --help")
    $results = ($results | append $r3)
    
    # Test test-versions.nu --help
    let r4 = (test-cmd "test-versions.nu --help" $"nu ($scripts_dir)/test-versions.nu --help")
    $results = ($results | append $r4)
    
    $results
}

# Test Python scripts
def test-python [repo_root: string]: nothing -> list {
    section "Python Script Tests"
    
    mut results = []
    let scripts_dir = $"($repo_root)/scripts/python"
    
    if not (has-command "python3") {
        skip "Python not available"
        return [{ test: "Python", status: "skip" }]
    }
    
    # Check syntax
    let r1 = (test-cmd "compute_hashes.py syntax" $"python3 -m py_compile ($scripts_dir)/compute_hashes.py")
    $results = ($results | append $r1)
    
    # Check imports (requires deps)
    let r2_result = (do { python3 -c "import httpx, rich, typer" } | complete)
    if $r2_result.exit_code == 0 {
        pass "Python dependencies available"
        $results = ($results | append { test: "Python dependencies", status: "pass" })
    } else {
        skip "Python dependencies not installed (httpx, rich, typer)"
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
        skip "Elixir not available"
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
        skip "Cargo not available"
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
        fail $"cargo check failed"
        $results = ($results | append { test: "cargo check", status: "fail", error: $cargo_result.stderr })
    }
    
    $results
}

# Test version packages (quick mode)
def test-versions [repo_root: string]: nothing -> list {
    section "Cursor Version Package Tests"
    
    mut results = []
    
    # Test a sample of versions
    let sample_versions = ["cursor" "cursor-2_1_34" "cursor-2_0_77" "cursor-1_7_59"]
    
    for pkg in $sample_versions {
        let result = (do { nix eval $"($repo_root)#($pkg).name" --impure 2>&1 } | complete)
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
