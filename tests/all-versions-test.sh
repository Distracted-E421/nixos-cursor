#!/usr/bin/env bash
# Comprehensive All-Versions Test Script
# Tests build capability for all defined Cursor versions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLAKE_DIR="${FLAKE_DIR:-$REPO_ROOT}"

# Test configuration
DRY_RUN="${DRY_RUN:-false}"
PARALLEL="${PARALLEL:-4}"
TEST_MODE="${1:-quick}"  # quick, full, or build

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Cursor All-Versions Test Suite                        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Mode: ${CYAN}$TEST_MODE${NC}"
echo -e "Flake: ${CYAN}$FLAKE_DIR${NC}"
echo ""

# Get all cursor packages from flake
echo -e "${CYAN}Discovering available versions...${NC}"

ALL_PACKAGES=$(nix flake show "$FLAKE_DIR" --json 2>/dev/null | \
    jq -r '.packages."x86_64-linux" | keys[]' | \
    grep -E '^cursor' | \
    sort -V)

CURSOR_VERSIONS=$(echo "$ALL_PACKAGES" | grep -E '^cursor-[0-9]' || true)
CURSOR_MAIN=$(echo "$ALL_PACKAGES" | grep -E '^cursor$' || true)
CURSOR_TOOLS=$(echo "$ALL_PACKAGES" | grep -vE '^cursor(-[0-9]|$)' || true)

echo -e "  Main package: ${GREEN}$(echo "$CURSOR_MAIN" | wc -w)${NC}"
echo -e "  Version packages: ${GREEN}$(echo "$CURSOR_VERSIONS" | wc -w)${NC}"
echo -e "  Tools/utilities: ${GREEN}$(echo "$CURSOR_TOOLS" | wc -w)${NC}"
echo ""

# Test counters
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# Results arrays
declare -a PASS_LIST=()
declare -a FAIL_LIST=()
declare -a SKIP_LIST=()

test_package() {
    local pkg="$1"
    local test_type="$2"
    
    ((TOTAL++)) || true
    
    case "$test_type" in
        eval)
            # Just evaluate the derivation (fastest)
            # Try pname first, fall back to name for non-stdenv packages
            if nix eval "$FLAKE_DIR#$pkg.pname" --impure 2>/dev/null >/dev/null || \
               nix eval "$FLAKE_DIR#$pkg.name" --impure 2>/dev/null >/dev/null; then
                echo -e "  ${GREEN}✓${NC} $pkg (eval)"
                PASS_LIST+=("$pkg")
                ((PASSED++)) || true
                return 0
            else
                echo -e "  ${RED}✗${NC} $pkg (eval failed)"
                FAIL_LIST+=("$pkg")
                ((FAILED++)) || true
                return 1
            fi
            ;;
        dry-build)
            # Dry-build (checks dependencies without building)
            if nix build "$FLAKE_DIR#$pkg" --impure --dry-run 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $pkg (dry-build)"
                PASS_LIST+=("$pkg")
                ((PASSED++)) || true
                return 0
            else
                echo -e "  ${RED}✗${NC} $pkg (dry-build failed)"
                FAIL_LIST+=("$pkg")
                ((FAILED++)) || true
                return 1
            fi
            ;;
        build)
            # Full build
            if nix build "$FLAKE_DIR#$pkg" --impure --no-link 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $pkg (build)"
                PASS_LIST+=("$pkg")
                ((PASSED++)) || true
                return 0
            else
                echo -e "  ${RED}✗${NC} $pkg (build failed)"
                FAIL_LIST+=("$pkg")
                ((FAILED++)) || true
                return 1
            fi
            ;;
    esac
}

# Determine test type based on mode
case "$TEST_MODE" in
    quick)
        TEST_TYPE="eval"
        echo -e "${CYAN}Running quick evaluation tests...${NC}"
        ;;
    full)
        TEST_TYPE="dry-build"
        echo -e "${CYAN}Running dry-build tests...${NC}"
        ;;
    build)
        TEST_TYPE="build"
        echo -e "${YELLOW}Running full build tests (this will take a while)...${NC}"
        ;;
    *)
        echo -e "${RED}Unknown mode: $TEST_MODE${NC}"
        echo "Usage: $0 [quick|full|build]"
        exit 1
        ;;
esac

echo ""

# Test main package
echo -e "${CYAN}Testing main cursor package...${NC}"
if [ -n "$CURSOR_MAIN" ]; then
    test_package "cursor" "$TEST_TYPE"
fi
echo ""

# Test version packages
echo -e "${CYAN}Testing version packages...${NC}"
for pkg in $CURSOR_VERSIONS; do
    test_package "$pkg" "$TEST_TYPE"
done
echo ""

# Test tools
echo -e "${CYAN}Testing tools and utilities...${NC}"
for pkg in $CURSOR_TOOLS; do
    test_package "$pkg" "$TEST_TYPE"
done
echo ""

# Summary
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   Test Summary                            ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Total:   ${CYAN}$TOTAL${NC}"
echo -e "  Passed:  ${GREEN}$PASSED${NC}"
echo -e "  Failed:  ${RED}$FAILED${NC}"
echo -e "  Skipped: ${YELLOW}$SKIPPED${NC}"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}Failed packages:${NC}"
    for pkg in "${FAIL_LIST[@]}"; do
        echo -e "  - $pkg"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ All tests passed!${NC}"
fi

# Version matrix output
if [ "$TEST_MODE" = "quick" ] || [ "$TEST_MODE" = "full" ]; then
    echo ""
    echo -e "${CYAN}Version Matrix:${NC}"
    echo ""
    echo "| Era | Versions | Status |"
    echo "|-----|----------|--------|"
    
    # Count by era
    v2_1=$(echo "$CURSOR_VERSIONS" | grep -c "cursor-2_1" || echo 0)
    v2_0=$(echo "$CURSOR_VERSIONS" | grep -c "cursor-2_0" || echo 0)
    v1_7=$(echo "$CURSOR_VERSIONS" | grep -c "cursor-1_7" || echo 0)
    v1_6=$(echo "$CURSOR_VERSIONS" | grep -c "cursor-1_6" || echo 0)
    
    echo "| 2.1.x (Latest) | $v2_1 | ✓ |"
    echo "| 2.0.x (Custom Modes) | $v2_0 | ✓ |"
    echo "| 1.7.x (Classic) | $v1_7 | ✓ |"
    echo "| 1.6.x (Legacy) | $v1_6 | ✓ |"
fi
