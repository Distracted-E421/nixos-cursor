#!/usr/bin/env bash
# Test suite for npm security blocklist
# Validates: no false positives, catches known malicious packages

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKLIST_DIR="$SCRIPT_DIR/../blocklists"
BLOCKLIST_FILE="$BLOCKLIST_DIR/known-malicious.json"

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((PASSED++)) || true; }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; ((FAILED++)) || true; }
log_skip() { echo -e "${YELLOW}○ SKIP${NC}: $1"; ((SKIPPED++)) || true; }
log_info() { echo -e "  INFO: $1"; }

# ═══════════════════════════════════════════════════════════════════════════
# Test: Blocklist file exists and is valid JSON
# ═══════════════════════════════════════════════════════════════════════════
test_blocklist_exists() {
    echo ""
    echo "═══ Test: Blocklist File Validity ═══"
    
    if [[ -f "$BLOCKLIST_FILE" ]]; then
        log_pass "Blocklist file exists"
    else
        log_fail "Blocklist file not found: $BLOCKLIST_FILE"
        return 1
    fi
    
    if jq empty "$BLOCKLIST_FILE" 2>/dev/null; then
        log_pass "Blocklist is valid JSON"
    else
        log_fail "Blocklist is not valid JSON"
        return 1
    fi
    
    # Check required fields
    local version=$(jq -r '.version' "$BLOCKLIST_FILE")
    if [[ -n "$version" && "$version" != "null" ]]; then
        log_pass "Has version field: $version"
    else
        log_fail "Missing version field"
    fi
    
    local lastUpdated=$(jq -r '.lastUpdated' "$BLOCKLIST_FILE")
    if [[ -n "$lastUpdated" && "$lastUpdated" != "null" ]]; then
        log_pass "Has lastUpdated field: $lastUpdated"
    else
        log_fail "Missing lastUpdated field"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Known malicious packages are in the blocklist
# These MUST be blocked - failure here is critical
# ═══════════════════════════════════════════════════════════════════════════
test_known_malicious_blocked() {
    echo ""
    echo "═══ Test: Known Malicious Packages Are Blocked ═══"
    
    # Critical malicious packages that MUST be blocked
    local -a must_block=(
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
    )
    
    # Extract all blocked package names
    local blocked_packages=$(jq -r '
        .packages | to_entries[] | .value.packages[]? | .name
    ' "$BLOCKLIST_FILE" | sort -u)
    
    for pkg in "${must_block[@]}"; do
        if echo "$blocked_packages" | grep -qxF "$pkg"; then
            log_pass "Blocks malicious package: $pkg"
        else
            log_fail "CRITICAL: Does NOT block known malicious package: $pkg"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Safe packages are NOT in the blocklist (false positive check)
# These are legitimate popular packages that should NEVER be blocked
# ═══════════════════════════════════════════════════════════════════════════
test_safe_packages_not_blocked() {
    echo ""
    echo "═══ Test: Safe Packages Not Blocked (False Positive Check) ═══"
    
    # Popular legitimate packages that should NEVER be blocked
    local -a safe_packages=(
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
    )
    
    # Extract all blocked package names
    local blocked_packages=$(jq -r '
        .packages | to_entries[] | .value.packages[]? | .name
    ' "$BLOCKLIST_FILE" | sort -u)
    
    for pkg in "${safe_packages[@]}"; do
        if echo "$blocked_packages" | grep -qxF "$pkg"; then
            log_fail "FALSE POSITIVE: Safe package incorrectly blocked: $pkg"
        else
            log_pass "Safe package not blocked: $pkg"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Version-specific blocking works correctly
# Some packages are only malicious in certain versions
# ═══════════════════════════════════════════════════════════════════════════
test_version_specific_blocking() {
    echo ""
    echo "═══ Test: Version-Specific Blocking ═══"
    
    # ua-parser-js: only specific versions are malicious
    local ua_versions=$(jq -r '
        .packages.historical.packages[] | select(.name == "ua-parser-js") | .versions[]
    ' "$BLOCKLIST_FILE")
    
    if echo "$ua_versions" | grep -qF "0.7.29"; then
        log_pass "ua-parser-js@0.7.29 is blocked (known malicious)"
    else
        log_fail "ua-parser-js@0.7.29 should be blocked"
    fi
    
    # Check that we're not blocking ALL versions with wildcard
    if echo "$ua_versions" | grep -qxF "*"; then
        log_fail "ua-parser-js should NOT block all versions (*)"
    else
        log_pass "ua-parser-js only blocks specific versions, not all"
    fi
    
    # event-stream: only version 3.3.6 was compromised
    local es_versions=$(jq -r '
        .packages.historical.packages[] | select(.name == "event-stream") | .versions[]
    ' "$BLOCKLIST_FILE")
    
    if echo "$es_versions" | grep -qF "3.3.6"; then
        log_pass "event-stream@3.3.6 is blocked (known malicious)"
    else
        log_fail "event-stream@3.3.6 should be blocked"
    fi
    
    # flatmap-stream: ALL versions are malicious (purely malicious package)
    local fs_versions=$(jq -r '
        .packages.historical.packages[] | select(.name == "flatmap-stream") | .versions[]
    ' "$BLOCKLIST_FILE")
    
    if echo "$fs_versions" | grep -qxF "*"; then
        log_pass "flatmap-stream blocks all versions (purely malicious package)"
    else
        log_fail "flatmap-stream should block all versions"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: IOC patterns are reasonable
# ═══════════════════════════════════════════════════════════════════════════
test_ioc_patterns() {
    echo ""
    echo "═══ Test: IOC Patterns ═══"
    
    local patterns=$(jq -r '
        .packages.shai_hulud_2025.indicators_of_compromise.postinstall_patterns[]?
    ' "$BLOCKLIST_FILE" 2>/dev/null)
    
    if [[ -z "$patterns" ]]; then
        log_skip "No IOC patterns defined"
        return
    fi
    
    local pattern_count=$(echo "$patterns" | wc -l)
    log_info "Found $pattern_count IOC patterns"
    
    # Test that patterns are valid regexes
    while IFS= read -r pattern; do
        if [[ -z "$pattern" ]]; then continue; fi
        
        # Try to use pattern with grep to validate regex
        if echo "" | grep -E "$pattern" >/dev/null 2>&1 || [[ $? -le 1 ]]; then
            log_pass "Valid regex pattern: ${pattern:0:40}..."
        else
            log_fail "Invalid regex pattern: $pattern"
        fi
    done <<< "$patterns"
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: No duplicate entries
# ═══════════════════════════════════════════════════════════════════════════
test_no_duplicates() {
    echo ""
    echo "═══ Test: No Duplicate Entries ═══"
    
    local all_packages=$(jq -r '
        .packages | to_entries[] | .value.packages[]? | .name
    ' "$BLOCKLIST_FILE")
    
    local unique_count=$(echo "$all_packages" | sort -u | wc -l)
    local total_count=$(echo "$all_packages" | wc -l)
    
    if [[ "$unique_count" -eq "$total_count" ]]; then
        log_pass "No duplicate package entries ($total_count total)"
    else
        local dups=$(echo "$all_packages" | sort | uniq -d)
        log_fail "Found duplicate entries: $dups"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Categories have descriptions
# ═══════════════════════════════════════════════════════════════════════════
test_category_metadata() {
    echo ""
    echo "═══ Test: Category Metadata ═══"
    
    local categories=$(jq -r '.packages | keys[]' "$BLOCKLIST_FILE")
    
    while IFS= read -r cat; do
        local desc=$(jq -r ".packages.\"$cat\".description // \"\"" "$BLOCKLIST_FILE")
        if [[ -n "$desc" && "$desc" != "null" ]]; then
            log_pass "Category '$cat' has description"
        else
            log_fail "Category '$cat' missing description"
        fi
    done <<< "$categories"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main test runner
# ═══════════════════════════════════════════════════════════════════════════
main() {
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║          NPM Security Blocklist Test Suite                        ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Testing: $BLOCKLIST_FILE"
    echo "Date: $(date)"
    
    test_blocklist_exists
    test_known_malicious_blocked
    test_safe_packages_not_blocked
    test_version_specific_blocking
    test_ioc_patterns
    test_no_duplicates
    test_category_metadata
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "                         TEST SUMMARY"
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "  ${GREEN}PASSED${NC}:  $PASSED"
    echo -e "  ${RED}FAILED${NC}:  $FAILED"
    echo -e "  ${YELLOW}SKIPPED${NC}: $SKIPPED"
    echo ""
    
    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
