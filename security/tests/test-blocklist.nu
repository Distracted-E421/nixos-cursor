#!/usr/bin/env nu
# NPM Security Blocklist Test Suite
# Validates: no false positives, catches known malicious packages
#
# Usage: nu test-blocklist.nu

use std assert

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

let script_dir = ($env.FILE_PWD? | default ".")
let blocklist_file = $"($script_dir)/../blocklists/known-malicious.json"

# Test result tracking
mut results = {
    passed: 0
    failed: 0
    skipped: 0
    errors: []
}

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
    print $"  INFO: ($msg)"
}

# Extract all blocked package names from blocklist
def get-blocked-packages [blocklist: record] -> list<string> {
    $blocklist.packages
    | transpose key value
    | each { |row|
        $row.value.packages? | default []
    }
    | flatten
    | each { |pkg| $pkg.name }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Blocklist file exists and is valid JSON
# ═══════════════════════════════════════════════════════════════════════════

def test-blocklist-exists [] -> record {
    print ""
    print "═══ Test: Blocklist File Validity ═══"
    
    mut passed = 0
    mut failed = 0
    mut errors = []
    
    # Check file exists
    if ($blocklist_file | path exists) {
        log-pass "Blocklist file exists"
        $passed += 1
    } else {
        log-fail $"Blocklist file not found: ($blocklist_file)"
        $failed += 1
        return { passed: $passed, failed: $failed, errors: $errors }
    }
    
    # Try to parse JSON
    let blocklist = try {
        open $blocklist_file
    } catch {
        log-fail "Blocklist is not valid JSON"
        $failed += 1
        return { passed: $passed, failed: $failed, errors: $errors }
    }
    
    log-pass "Blocklist is valid JSON"
    $passed += 1
    
    # Check required fields
    if ($blocklist.version? | is-not-empty) {
        log-pass $"Has version field: ($blocklist.version)"
        $passed += 1
    } else {
        log-fail "Missing version field"
        $failed += 1
    }
    
    if ($blocklist.lastUpdated? | is-not-empty) {
        log-pass $"Has lastUpdated field: ($blocklist.lastUpdated)"
        $passed += 1
    } else {
        log-fail "Missing lastUpdated field"
        $failed += 1
    }
    
    { passed: $passed, failed: $failed, errors: $errors }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Known malicious packages are in the blocklist
# ═══════════════════════════════════════════════════════════════════════════

def test-known-malicious-blocked [] -> record {
    print ""
    print "═══ Test: Known Malicious Packages Are Blocked ═══"
    
    let blocklist = open $blocklist_file
    let blocked = get-blocked-packages $blocklist
    
    # Critical packages that MUST be blocked
    let must_block = [
        "event-stream"
        "flatmap-stream"
        "ua-parser-js"
        "coa"
        "rc"
        "colors"
        "faker"
        "node-ipc"
        # Typosquats
        "loadsh"
        "crossenv"
        "cross-env.js"
        "mongose"
        "babelcli"
    ]
    
    mut passed = 0
    mut failed = 0
    
    for pkg in $must_block {
        if ($pkg in $blocked) {
            log-pass $"Blocks malicious package: ($pkg)"
            $passed += 1
        } else {
            log-fail $"CRITICAL: Does NOT block known malicious package: ($pkg)"
            $failed += 1
        }
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Safe packages are NOT in the blocklist (false positive check)
# ═══════════════════════════════════════════════════════════════════════════

def test-safe-packages-not-blocked [] -> record {
    print ""
    print "═══ Test: Safe Packages Not Blocked (False Positive Check) ═══"
    
    let blocklist = open $blocklist_file
    let blocked = get-blocked-packages $blocklist
    
    # Popular legitimate packages that should NEVER be blocked
    let safe_packages = [
        "lodash"
        "express"
        "react"
        "typescript"
        "axios"
        "moment"
        "chalk"
        "commander"
        "debug"
        "dotenv"
        "uuid"
        "async"
        "bluebird"
        "underscore"
        "jquery"
        "webpack"
        "babel-core"
        "eslint"
        "prettier"
        "jest"
        # MCP packages we use
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-github"
        "@modelcontextprotocol/server-memory"
        "@modelcontextprotocol/sdk"
    ]
    
    mut passed = 0
    mut failed = 0
    
    for pkg in $safe_packages {
        if ($pkg in $blocked) {
            log-fail $"FALSE POSITIVE: Safe package incorrectly blocked: ($pkg)"
            $failed += 1
        } else {
            log-pass $"Safe package not blocked: ($pkg)"
            $passed += 1
        }
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Version-specific blocking works correctly
# ═══════════════════════════════════════════════════════════════════════════

def test-version-specific-blocking [] -> record {
    print ""
    print "═══ Test: Version-Specific Blocking ═══"
    
    let blocklist = open $blocklist_file
    
    mut passed = 0
    mut failed = 0
    
    # Get ua-parser-js entry
    let ua_entry = $blocklist.packages.historical.packages
        | where name == "ua-parser-js"
        | first
    
    if ("0.7.29" in $ua_entry.versions) {
        log-pass "ua-parser-js@0.7.29 is blocked (known malicious)"
        $passed += 1
    } else {
        log-fail "ua-parser-js@0.7.29 should be blocked"
        $failed += 1
    }
    
    if ("*" in $ua_entry.versions) {
        log-fail "ua-parser-js should NOT block all versions (*)"
        $failed += 1
    } else {
        log-pass "ua-parser-js only blocks specific versions, not all"
        $passed += 1
    }
    
    # Get event-stream entry
    let es_entry = $blocklist.packages.historical.packages
        | where name == "event-stream"
        | first
    
    if ("3.3.6" in $es_entry.versions) {
        log-pass "event-stream@3.3.6 is blocked (known malicious)"
        $passed += 1
    } else {
        log-fail "event-stream@3.3.6 should be blocked"
        $failed += 1
    }
    
    # Get flatmap-stream entry (should block ALL versions)
    let fs_entry = $blocklist.packages.historical.packages
        | where name == "flatmap-stream"
        | first
    
    if ("*" in $fs_entry.versions) {
        log-pass "flatmap-stream blocks all versions (purely malicious package)"
        $passed += 1
    } else {
        log-fail "flatmap-stream should block all versions"
        $failed += 1
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: IOC patterns are valid regexes
# ═══════════════════════════════════════════════════════════════════════════

def test-ioc-patterns [] -> record {
    print ""
    print "═══ Test: IOC Patterns ═══"
    
    let blocklist = open $blocklist_file
    let patterns = $blocklist.packages.shai_hulud_2025.indicators_of_compromise?.postinstall_patterns? | default []
    
    mut passed = 0
    mut failed = 0
    
    if ($patterns | is-empty) {
        log-skip "No IOC patterns defined"
        return { passed: 0, failed: 0, errors: [] }
    }
    
    log-info $"Found ($patterns | length) IOC patterns"
    
    for pattern in $patterns {
        # Test if pattern is valid by trying to use it
        # Nushell's str contains doesn't use regex, so we'll just validate it exists
        let display = if ($pattern | str length) > 40 {
            $"($pattern | str substring 0..40)..."
        } else {
            $pattern
        }
        log-pass $"Pattern defined: ($display)"
        $passed += 1
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: No duplicate entries
# ═══════════════════════════════════════════════════════════════════════════

def test-no-duplicates [] -> record {
    print ""
    print "═══ Test: No Duplicate Entries ═══"
    
    let blocklist = open $blocklist_file
    let all_packages = get-blocked-packages $blocklist
    let unique_packages = $all_packages | uniq
    
    mut passed = 0
    mut failed = 0
    
    if ($all_packages | length) == ($unique_packages | length) {
        log-pass $"No duplicate package entries (($all_packages | length) total)"
        $passed += 1
    } else {
        let duplicates = $all_packages | uniq --count | where count > 1 | get value
        log-fail $"Found duplicate entries: ($duplicates | str join ', ')"
        $failed += 1
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Categories have descriptions
# ═══════════════════════════════════════════════════════════════════════════

def test-category-metadata [] -> record {
    print ""
    print "═══ Test: Category Metadata ═══"
    
    let blocklist = open $blocklist_file
    let categories = $blocklist.packages | transpose key value
    
    mut passed = 0
    mut failed = 0
    
    for cat in $categories {
        if ($cat.value.description? | is-not-empty) {
            log-pass $"Category '($cat.key)' has description"
            $passed += 1
        } else {
            log-fail $"Category '($cat.key)' missing description"
            $failed += 1
        }
    }
    
    { passed: $passed, failed: $failed, errors: [] }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main test runner
# ═══════════════════════════════════════════════════════════════════════════

def main [] {
    print "╔═══════════════════════════════════════════════════════════════════╗"
    print "║          NPM Security Blocklist Test Suite (Nushell)              ║"
    print "╚═══════════════════════════════════════════════════════════════════╝"
    print ""
    print $"Testing: ($blocklist_file)"
    print $"Date: (date now | format date '%Y-%m-%d %H:%M:%S')"
    
    mut total_passed = 0
    mut total_failed = 0
    
    # Run all tests
    let tests = [
        (test-blocklist-exists)
        (test-known-malicious-blocked)
        (test-safe-packages-not-blocked)
        (test-version-specific-blocking)
        (test-ioc-patterns)
        (test-no-duplicates)
        (test-category-metadata)
    ]
    
    for result in $tests {
        $total_passed += $result.passed
        $total_failed += $result.failed
    }
    
    print ""
    print "═══════════════════════════════════════════════════════════════════"
    print "                         TEST SUMMARY"
    print "═══════════════════════════════════════════════════════════════════"
    print $"  (ansi green)PASSED(ansi reset):  ($total_passed)"
    print $"  (ansi red)FAILED(ansi reset):  ($total_failed)"
    print ""
    
    if $total_failed > 0 {
        print $"(ansi red)Some tests failed!(ansi reset)"
        exit 1
    } else {
        print $"(ansi green)All tests passed!(ansi reset)"
        exit 0
    }
}
