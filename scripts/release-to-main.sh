#!/usr/bin/env bash
# Release to Main - Automates pre-release → main transition
# Usage: ./scripts/release-to-main.sh <version-tag>
#
# Example: ./scripts/release-to-main.sh v2.1.20

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SOURCE_BRANCH="pre-release"
TARGET_BRANCH="main"
VERSION_TAG="${1:-}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Release to Main - ${SOURCE_BRANCH} → ${TARGET_BRANCH}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check if version tag provided
if [[ -z "$VERSION_TAG" ]]; then
    echo -e "${RED}❌ Error: Version tag required${NC}"
    echo "Usage: $0 <version-tag>"
    echo "Example: $0 v2.1.20"
    exit 1
fi

# Validate version tag format (stable - no -rc suffix)
if [[ ! "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ Error: Stable version should not have -rc suffix${NC}"
    echo "Expected format: vX.Y.Z (e.g., v2.1.20)"
    exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${RED}❌ Error: Uncommitted changes detected${NC}"
    echo "Please commit or stash your changes before running this script."
    git status --short
    exit 1
fi

# Ensure pre-release branch exists
if ! git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH"; then
    echo -e "${RED}❌ Error: ${SOURCE_BRANCH} branch doesn't exist${NC}"
    exit 1
fi

# Switch to main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
    echo -e "${YELLOW}⚠️  Not on ${TARGET_BRANCH} branch. Switching...${NC}"
    git checkout "$TARGET_BRANCH"
fi

echo -e "${GREEN}✓ On ${TARGET_BRANCH} branch${NC}"
echo

# Confirm release
echo -e "${YELLOW}⚠️  This will:${NC}"
echo "  1. Merge ${SOURCE_BRANCH} into ${TARGET_BRANCH}"
echo "  2. Tag as ${VERSION_TAG}"
echo "  3. Push to public GitHub repository"
echo
read -p "Are you sure you want to proceed? (yes/N): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Merge pre-release into main
echo -e "${BLUE}📦 Merging ${SOURCE_BRANCH} into ${TARGET_BRANCH}...${NC}"
if ! git merge "$SOURCE_BRANCH" --no-ff -m "chore: Release ${VERSION_TAG}"; then
    echo -e "${RED}❌ Merge conflicts detected${NC}"
    echo "Please resolve conflicts manually."
    exit 1
fi

echo -e "${GREEN}✓ Merged ${SOURCE_BRANCH} into ${TARGET_BRANCH}${NC}"

# Tag the stable release
echo -e "${BLUE}🏷️  Tagging as ${VERSION_TAG}...${NC}"

# Generate changelog from commits
CHANGELOG=$(git log --oneline --no-merges "$TARGET_BRANCH^..$TARGET_BRANCH" | head -10 | sed 's/^/  - /')

git tag -a "$VERSION_TAG" -m "Release ${VERSION_TAG}

Changelog:
$CHANGELOG

See full release notes at:
https://github.com/Distracted-E421/nixos-cursor/releases/tag/${VERSION_TAG}
"

echo -e "${GREEN}✓ Tagged as ${VERSION_TAG}${NC}"
echo

# Run tests
echo -e "${BLUE}🧪 Running tests...${NC}"

if nix flake check 2>&1 | grep -i "error"; then
    echo -e "${RED}❌ Nix flake check failed${NC}"
    echo "Please fix errors before releasing."
    exit 1
fi

echo -e "${GREEN}✓ Tests passed${NC}"
echo

# Build package
echo -e "${BLUE}🔨 Building package...${NC}"

if ! nix build .#cursor; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful${NC}"
echo

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Release Prepared${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}Final steps:${NC}"
echo "  1. Review the release:"
echo "     ${BLUE}git log --oneline -10${NC}"
echo "     ${BLUE}git show ${VERSION_TAG}${NC}"
echo
echo "  2. Push to GitHub:"
echo "     ${BLUE}git push origin ${TARGET_BRANCH}${NC}"
echo "     ${BLUE}git push origin ${VERSION_TAG}${NC}"
echo
echo "  3. Create GitHub Release:"
echo "     ${BLUE}https://github.com/Distracted-E421/nixos-cursor/releases/new${NC}"
echo "     - Tag: ${VERSION_TAG}"
echo "     - Title: nixos-cursor ${VERSION_TAG}"
echo "     - Description: (Add release notes)"
echo
echo "  4. Sync back to dev:"
echo "     ${BLUE}git checkout dev && git merge ${TARGET_BRANCH}${NC}"
echo
