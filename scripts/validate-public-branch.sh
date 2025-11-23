#!/usr/bin/env bash
# Validate Public Branch - Checks for leaked private content
# Usage: ./scripts/validate-public-branch.sh [branch]
#
# Example: ./scripts/validate-public-branch.sh pre-release

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

BRANCH="${1:-pre-release}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Validate Public Branch: ${BRANCH}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo -e "${RED}❌ Error: Branch ${BRANCH} doesn't exist${NC}"
    exit 1
fi

# Switch to branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    git checkout "$BRANCH" --quiet
    echo -e "${GREEN}✓ Switched to ${BRANCH}${NC}"
fi

ISSUES=0

# Check 1: Private .cursor/ files
echo -e "${BLUE}🔍 Checking for private .cursor/ files...${NC}"

PRIVATE_CURSOR_FILES=(
    ".cursor/chat-history/"
    ".cursor/maxim.json"
    ".cursor/gorky.json"
    ".cursor/docs/CURSOR_HOOKS_INTEGRATION_COMPLETE.md"
    ".cursor/docs/CURSOR_RULES_INTEGRATION_SUCCESS.md"
)

for file in "${PRIVATE_CURSOR_FILES[@]}"; do
    if [[ -e "$file" ]]; then
        echo -e "${RED}  ❌ Found private file: ${file}${NC}"
        ((ISSUES++))
    fi
done

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}  ✓ No private .cursor/ files found${NC}"
fi

# Check 2: Personal email addresses
echo -e "${BLUE}🔍 Checking for personal email addresses...${NC}"

if git grep -l "distracted\.e421@gmail\.com" -- . \
    ':!LICENSE' \
    ':!BRANCHING_STRATEGY.md' \
    ':!scripts/' \
    ':!.cursor/' 2>/dev/null; then
    echo -e "${RED}  ❌ Found personal email in tracked files${NC}"
    ((ISSUES++))
else
    echo -e "${GREEN}  ✓ No personal email leaks${NC}"
fi

# Check 3: Absolute paths
echo -e "${BLUE}🔍 Checking for absolute paths...${NC}"

if git grep -l "/home/e421/" -- . ':!.git' ':!scripts/' ':!.cursor/' 2>/dev/null; then
    echo -e "${RED}  ❌ Found absolute paths (/home/e421/)${NC}"
    ((ISSUES++))
else
    echo -e "${GREEN}  ✓ No absolute paths found${NC}"
fi

# Check 4: API keys/tokens
echo -e "${BLUE}🔍 Checking for API keys and secrets...${NC}"

if git grep -iE "(api[_-]?key|github[_-]?token|secret|password)\s*=\s*['\"][^'\"]{20,}['\"]" -- . \
    ':!.git' \
    ':!scripts/' \
    ':!.cursor/' \
    ':!BRANCHING_STRATEGY.md' 2>/dev/null; then
    echo -e "${RED}  ❌ Found potential API keys or secrets${NC}"
    ((ISSUES++))
else
    echo -e "${GREEN}  ✓ No API keys or secrets found${NC}"
fi

# Check 5: TODO/FIXME in critical files
echo -e "${BLUE}🔍 Checking for unresolved TODOs in critical files...${NC}"

CRITICAL_TODO_FILES=()
while IFS= read -r -d '' file; do
    CRITICAL_TODO_FILES+=("$file")
done < <(git grep -l -E "(TODO|FIXME|HACK)" -- \
    '*.nix' \
    'flake.nix' \
    'cursor/default.nix' \
    'modules/**/*.nix' 2>/dev/null | tr '\n' '\0')

if [[ ${#CRITICAL_TODO_FILES[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  ⚠️  Found TODOs in critical files:${NC}"
    for file in "${CRITICAL_TODO_FILES[@]}"; do
        echo -e "${YELLOW}    - ${file}${NC}"
    done
    echo -e "${YELLOW}  (Review if these are acceptable for release)${NC}"
fi

# Check 6: Nix flake validation
echo -e "${BLUE}🔍 Running nix flake check...${NC}"

if nix flake check --no-build 2>&1 | grep -i "error"; then
    echo -e "${RED}  ❌ Nix flake check failed${NC}"
    ((ISSUES++))
else
    echo -e "${GREEN}  ✓ Nix flake check passed${NC}"
fi

# Check 7: Documentation completeness
echo -e "${BLUE}🔍 Checking documentation completeness...${NC}"

REQUIRED_DOCS=(
    "README.md"
    "LICENSE"
    "BRANCHING_STRATEGY.md"
    "cursor/README.md"
)

for doc in "${REQUIRED_DOCS[@]}"; do
    if [[ ! -f "$doc" ]]; then
        echo -e "${RED}  ❌ Missing: ${doc}${NC}"
        ((ISSUES++))
    fi
done

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}  ✓ All required documentation present${NC}"
fi

# Check 8: File size check (large files)
echo -e "${BLUE}🔍 Checking for large files (>1MB)...${NC}"

LARGE_FILES=()
while IFS= read -r file; do
    LARGE_FILES+=("$file")
done < <(find . -type f -size +1M \
    ! -path "./.git/*" \
    ! -path "./result/*" \
    ! -path "./.cursor/chat-history/*" 2>/dev/null)

if [[ ${#LARGE_FILES[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  ⚠️  Found large files (>1MB):${NC}"
    for file in "${LARGE_FILES[@]}"; do
        size=$(du -h "$file" | cut -f1)
        echo -e "${YELLOW}    - ${file} (${size})${NC}"
    done
    echo -e "${YELLOW}  (Consider if these should be in the repository)${NC}"
fi

# Summary
echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}✅ Validation Passed${NC}"
    echo -e "${GREEN}Branch ${BRANCH} is ready for public release${NC}"
    EXIT_CODE=0
else
    echo -e "${RED}❌ Validation Failed${NC}"
    echo -e "${RED}Found ${ISSUES} issue(s) that must be fixed${NC}"
    EXIT_CODE=1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Return to original branch
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    git checkout "$CURRENT_BRANCH" --quiet
fi

exit $EXIT_CODE
