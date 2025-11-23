#!/usr/bin/env bash
# Prepare Public Branch - Automates dev → pre-release transition
# Usage: ./scripts/prepare-public-branch.sh [version-tag]
#
# Example: ./scripts/prepare-public-branch.sh v2.1.20-rc1

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TARGET_BRANCH="pre-release"
SOURCE_BRANCH="dev"
VERSION_TAG="${1:-}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Prepare Public Branch - dev → ${TARGET_BRANCH}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if version tag provided
if [[ -z "$VERSION_TAG" ]]; then
    echo -e "${RED}❌ Error: Version tag required${NC}"
    echo "Usage: $0 <version-tag>"
    echo "Example: $0 v2.1.20-rc1"
    exit 1
fi

# Validate version tag format
if [[ ! "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$ ]]; then
    echo -e "${YELLOW}⚠️  Warning: Version tag doesn't match expected format (vX.Y.Z or vX.Y.Z-rcN)${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${RED}❌ Error: Uncommitted changes detected${NC}"
    echo "Please commit or stash your changes before running this script."
    git status --short
    exit 1
fi

# Ensure we're on dev branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$SOURCE_BRANCH" ]]; then
    echo -e "${YELLOW}⚠️  Not on ${SOURCE_BRANCH} branch. Switching...${NC}"
    git checkout "$SOURCE_BRANCH"
fi

echo -e "${GREEN}✓ On ${SOURCE_BRANCH} branch${NC}"
echo

# Create pre-release branch if it doesn't exist
if ! git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    echo -e "${YELLOW}⚠️  ${TARGET_BRANCH} branch doesn't exist. Creating...${NC}"
    git checkout -b "$TARGET_BRANCH"
else
    echo -e "${GREEN}✓ ${TARGET_BRANCH} branch exists${NC}"
    git checkout "$TARGET_BRANCH"
fi

# Merge dev into pre-release (without committing)
echo -e "${BLUE}📦 Merging ${SOURCE_BRANCH} into ${TARGET_BRANCH}...${NC}"
if ! git merge "$SOURCE_BRANCH" --no-commit --no-ff; then
    echo -e "${RED}❌ Merge conflicts detected${NC}"
    echo "Please resolve conflicts manually and re-run this script."
    git merge --abort
    exit 1
fi

# Use public .gitignore (restrictive - excludes entire .cursor/)
echo -e "${BLUE}🔧 Applying public .gitignore...${NC}"
if [[ -f .gitignore-public ]]; then
    cp .gitignore-public .gitignore
    git add .gitignore
else
    echo -e "${RED}❌ ERROR: .gitignore-public not found${NC}"
    exit 1
fi

# Remove entire .cursor/ directory
echo -e "${BLUE}🧹 Removing entire .cursor/ directory...${NC}"

REMOVED_FILES=()

# Remove entire .cursor/ directory
if [[ -d .cursor ]]; then
    git rm -rf --cached .cursor/ 2>/dev/null || true
    rm -rf .cursor/
    REMOVED_FILES+=(".cursor/ (entire directory)")
    echo -e "${GREEN}  ✓ Removed entire .cursor/ directory${NC}"
else
    echo -e "${YELLOW}  ⚠️  .cursor/ directory already removed${NC}"
fi

# Validate no sensitive content
echo
echo -e "${BLUE}🔍 Validating for sensitive content...${NC}"

ISSUES=()

# Check for personal email addresses
if git grep -l "distracted\.e421@gmail\.com" -- . ':!.git' ':!scripts/' ':!BRANCHING_STRATEGY.md' 2>/dev/null; then
    ISSUES+=("Found personal email address in tracked files")
fi

# Check for absolute paths
if git grep -l "/home/e421/" -- . ':!.git' 2>/dev/null; then
    ISSUES+=("Found absolute paths (/home/e421/) in tracked files")
fi

# Check for API keys/tokens (simple pattern)
if git grep -iE "(api[_-]?key|token|secret|password)\s*=\s*['\"][^'\"]+['\"]" -- . ':!.git' ':!scripts/' 2>/dev/null; then
    ISSUES+=("Found potential API keys or secrets")
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Validation failed:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo -e "${RED}  • $issue${NC}"
    done
    echo
    echo "Please fix these issues before continuing."
    git reset --hard HEAD
    exit 1
fi

echo -e "${GREEN}✓ No sensitive content detected${NC}"
echo

# Commit the merge
echo -e "${BLUE}💾 Committing changes...${NC}"
git add -A
git commit -m "chore: Prepare ${VERSION_TAG} from ${SOURCE_BRANCH}

Removed private artifacts:
$(printf '  - %s\n' "${REMOVED_FILES[@]}")

Ready for public release testing."

echo -e "${GREEN}✓ Committed to ${TARGET_BRANCH}${NC}"

# Tag the release candidate
echo -e "${BLUE}🏷️  Tagging as ${VERSION_TAG}...${NC}"
git tag -a "$VERSION_TAG" -m "Release candidate ${VERSION_TAG}

Changelog:
- $(git log --oneline --no-merges ${TARGET_BRANCH}..${SOURCE_BRANCH} | head -5 | sed 's/^/  /')
- (see full history for details)
"

echo -e "${GREEN}✓ Tagged as ${VERSION_TAG}${NC}"
echo

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Preparation Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review changes:"
echo "     ${BLUE}git diff ${SOURCE_BRANCH}..${TARGET_BRANCH}${NC}"
echo
echo "  2. Test the build:"
echo "     ${BLUE}nix flake check${NC}"
echo "     ${BLUE}nix build .#cursor${NC}"
echo
echo "  3. Push to GitHub (when ready):"
echo "     ${BLUE}git push origin ${TARGET_BRANCH}${NC}"
echo "     ${BLUE}git push origin ${VERSION_TAG}${NC}"
echo
echo -e "${YELLOW}⚠️  Remember: This will make ${TARGET_BRANCH} and ${VERSION_TAG} PUBLIC${NC}"
echo
