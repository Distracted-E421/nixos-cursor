#!/usr/bin/env nu

# Script: test-versions.nu
# Purpose: Test build capability for all defined Cursor versions
# Usage: nu test-versions.nu [mode]
#
# Replaces: tests/all-versions-test.sh

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

const VERSION = "2.0.0"

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def header [title: string] {
    print $"(ansi blue)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi blue)║     (ansi white_bold)($title)(ansi reset)(ansi blue)                        ║(ansi reset)"
    print $"(ansi blue)╚═══════════════════════════════════════════════════════════════════╝(ansi reset)"
    print ""
}

def success [msg: string] { print $"  (ansi green)✓(ansi reset) ($msg)" }
def fail [msg: string] { print $"  (ansi red)✗(ansi reset) ($msg)" }

# ─────────────────────────────────────────────────────────────────────────────
# DISCOVERY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Get all packages from the flake
def get-flake-packages [flake_dir: string] {
    let result = (^nix flake show $flake_dir --json 2>/dev/null | complete)
    if $result.exit_code != 0 {
        print $"(ansi red)Failed to read flake: ($result.stderr)(ansi reset)"
        return []
    }
    
    $result.stdout 
    | from json 
    | get -o packages."x86_64-linux" 
    | default {} 
    | columns
    | sort
}

# Categorize packages
def categorize-packages [packages: list] {
    let cursor_versions = ($packages | where { |p| $p =~ '^cursor-[0-9]' })
    let cursor_main = ($packages | where { |p| $p == 'cursor' })
    let cursor_tools = ($packages | where { |p| 
        ($p starts-with 'cursor') and ($p != 'cursor') and (not ($p =~ '^cursor-[0-9]'))
    })
    
    {
        versions: $cursor_versions
        main: $cursor_main
        tools: $cursor_tools
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# TEST FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Test a single package
def test-package [flake_dir: string, pkg: string, test_type: string]: nothing -> record {
    match $test_type {
        "eval" => {
            # Try pname first, fall back to name
            let result = (do { ^nix eval $"($flake_dir)#($pkg).pname" --impure 2>/dev/null } | complete)
            if $result.exit_code == 0 {
                { package: $pkg, status: "pass", type: "eval" }
            } else {
                let result2 = (do { ^nix eval $"($flake_dir)#($pkg).name" --impure 2>/dev/null } | complete)
                if $result2.exit_code == 0 {
                    { package: $pkg, status: "pass", type: "eval" }
                } else {
                    { package: $pkg, status: "fail", type: "eval", error: "eval failed" }
                }
            }
        }
        "dry-build" => {
            let result = (do { ^nix build $"($flake_dir)#($pkg)" --impure --dry-run 2>/dev/null } | complete)
            if $result.exit_code == 0 {
                { package: $pkg, status: "pass", type: "dry-build" }
            } else {
                { package: $pkg, status: "fail", type: "dry-build", error: $result.stderr }
            }
        }
        "build" => {
            let result = (do { ^nix build $"($flake_dir)#($pkg)" --impure --no-link 2>/dev/null } | complete)
            if $result.exit_code == 0 {
                { package: $pkg, status: "pass", type: "build" }
            } else {
                { package: $pkg, status: "fail", type: "build", error: $result.stderr }
            }
        }
        _ => {
            { package: $pkg, status: "skip", type: "unknown" }
        }
    }
}

# Run tests on all packages
def run-tests [flake_dir: string, packages: list, test_type: string]: nothing -> list {
    $packages | each { |pkg|
        let result = (test-package $flake_dir $pkg $test_type)
        
        if $result.status == "pass" {
            success $"($pkg) \(($test_type)\)"
        } else {
            fail $"($pkg) \(($test_type) failed\)"
        }
        
        $result
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUT FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Print version matrix
def print-version-matrix [packages: list] {
    print ""
    print $"(ansi cyan)Version Matrix:(ansi reset)"
    print ""
    
    let v2_1 = ($packages | where { |p| $p =~ 'cursor-2_1' } | length)
    let v2_0 = ($packages | where { |p| $p =~ 'cursor-2_0' } | length)
    let v1_7 = ($packages | where { |p| $p =~ 'cursor-1_7' } | length)
    let v1_6 = ($packages | where { |p| $p =~ 'cursor-1_6' } | length)
    
    print "| Era | Versions | Status |"
    print "|-----|----------|--------|"
    print $"| 2.1.x \(Latest\) | ($v2_1) | ✓ |"
    print $"| 2.0.x \(Custom Modes\) | ($v2_0) | ✓ |"
    print $"| 1.7.x \(Classic\) | ($v1_7) | ✓ |"
    print $"| 1.6.x \(Legacy\) | ($v1_6) | ✓ |"
}

# Print summary
def print-summary [results: list] {
    let total = ($results | length)
    let passed = ($results | where status == "pass" | length)
    let failed = ($results | where status == "fail" | length)
    let skipped = ($results | where status == "skip" | length)
    
    print ""
    header "Test Summary"
    
    print $"  Total:   (ansi cyan)($total)(ansi reset)"
    print $"  Passed:  (ansi green)($passed)(ansi reset)"
    print $"  Failed:  (ansi red)($failed)(ansi reset)"
    print $"  Skipped: (ansi yellow)($skipped)(ansi reset)"
    print ""
    
    if $failed > 0 {
        print $"(ansi red)Failed packages:(ansi reset)"
        $results | where status == "fail" | each { |r|
            print $"  - ($r.package)"
        }
        print ""
    }
    
    $failed == 0
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main [
    mode?: string = "quick"             # Test mode: quick, full, or build
    --flake (-f): string                # Flake directory (default: current)
    --help (-h)                         # Show help
    --json (-j)                         # Output results as JSON
] {
    if $help {
        print "
Usage: nu test-versions.nu [MODE] [OPTIONS]

Test build capability for all defined Cursor versions

Modes:
    quick    Evaluate derivations only (fastest, default)
    full     Dry-build all packages
    build    Full build all packages (slow!)

Options:
    -h, --help          Show this help
    -f, --flake DIR     Flake directory (default: repo root)
    -j, --json          Output results as JSON

Examples:
    nu test-versions.nu                    # Quick eval test
    nu test-versions.nu full               # Dry-build test
    nu test-versions.nu build              # Full build (slow)
    nu test-versions.nu --json             # JSON output
"
        return
    }
    
    # Determine flake directory
    let flake_dir = if ($flake | is-empty) {
        # Find repo root
        let script_dir = ($env.FILE_PWD? | default ".")
        $"($script_dir)/../.."
    } else {
        $flake
    }
    
    header "Cursor All-Versions Test Suite"
    
    # Map mode to test type
    let test_type = match $mode {
        "quick" => "eval"
        "full" => "dry-build"
        "build" => "build"
        _ => {
            print $"(ansi red)Unknown mode: ($mode)(ansi reset)"
            print "Use: quick, full, or build"
            return
        }
    }
    
    print $"Mode: (ansi cyan)($mode)(ansi reset)"
    print $"Flake: (ansi cyan)($flake_dir)(ansi reset)"
    print ""
    
    # Discover packages
    print $"(ansi cyan)Discovering available versions...(ansi reset)"
    
    let all_packages = (get-flake-packages $flake_dir)
    let cursor_packages = ($all_packages | where { |p| $p starts-with 'cursor' })
    let categories = (categorize-packages $cursor_packages)
    
    print $"  Main package: (ansi green)($categories.main | length)(ansi reset)"
    print $"  Version packages: (ansi green)($categories.versions | length)(ansi reset)"
    print $"  Tools/utilities: (ansi green)($categories.tools | length)(ansi reset)"
    print ""
    
    # Run tests
    mut all_results = []
    
    # Test main package
    if ($categories.main | length) > 0 {
        print $"(ansi cyan)Testing main cursor package...(ansi reset)"
        let main_results = (run-tests $flake_dir $categories.main $test_type)
        $all_results = ($all_results | append $main_results)
        print ""
    }
    
    # Test version packages
    print $"(ansi cyan)Testing version packages...(ansi reset)"
    let version_results = (run-tests $flake_dir $categories.versions $test_type)
    $all_results = ($all_results | append $version_results)
    print ""
    
    # Test tools
    print $"(ansi cyan)Testing tools and utilities...(ansi reset)"
    let tool_results = (run-tests $flake_dir $categories.tools $test_type)
    $all_results = ($all_results | append $tool_results)
    
    # Output
    if $json {
        $all_results | to json
    } else {
        let success = (print-summary $all_results)
        
        if ($mode == "quick") or ($mode == "full") {
            print-version-matrix $categories.versions
        }
        
        if not $success {
            exit 1
        } else {
            print $"(ansi green)✓ All tests passed!(ansi reset)"
        }
    }
}
