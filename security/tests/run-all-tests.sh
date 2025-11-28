#!/usr/bin/env bash
# Master test runner for npm security module
# Run all tests and generate a summary report

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║        NPM Security Module - Complete Test Suite                  ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Date: $(date)"
echo "Directory: $SCRIPT_DIR"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Run blocklist tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Running: Blocklist Tests${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if "$SCRIPT_DIR/test-blocklist.sh"; then
    echo -e "${GREEN}✓ Blocklist tests passed${NC}"
else
    echo -e "${RED}✗ Blocklist tests failed${NC}"
    ((TOTAL_FAILED++)) || true
fi
echo ""

# Run scanner tests (without network by default)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${BLUE}Running: Scanner Tests (offline)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if "$SCRIPT_DIR/test-scanner.sh"; then
    echo -e "${GREEN}✓ Scanner tests passed${NC}"
else
    echo -e "${RED}✗ Scanner tests failed${NC}"
    ((TOTAL_FAILED++)) || true
fi
echo ""

# Run network tests if requested
if [[ "${1:-}" == "--with-network" ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Running: Scanner Tests (with network)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if "$SCRIPT_DIR/test-scanner.sh" --with-network; then
        echo -e "${GREEN}✓ Network tests passed${NC}"
    else
        echo -e "${RED}✗ Network tests failed${NC}"
        ((TOTAL_FAILED++)) || true
    fi
    echo ""
fi

# Final summary
echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                     FINAL TEST SUMMARY                            ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All test suites passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run with --with-network for full validation"
    echo "  2. Manually test cursor-security CLI commands"
    echo "  3. Test in a real Cursor installation"
    exit 0
else
    echo -e "${RED}$TOTAL_FAILED test suite(s) failed${NC}"
    echo ""
    echo "Fix failures before merging to main."
    exit 1
fi
