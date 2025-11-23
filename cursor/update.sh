#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq coreutils nix-prefetch gnused
# shellcheck shell=bash
set -eu -o pipefail

# Cursor Auto-Update Script
# Queries Cursor's API for latest version and updates cursor/default.nix
#
# Usage:
#   ./update.sh
#
# This script:
# 1. Queries https://api2.cursor.sh/updates/api/download/stable for latest version
# 2. Compares with current version in default.nix
# 3. Downloads new AppImages and calculates SRI hashes
# 4. Updates default.nix with new version and hashes
#
# Based on nixpkgs' code-cursor update script:
# https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/co/code-cursor/update.sh

# Cursor API endpoint
# Channels: stable (default), prerelease (early access)
CHANNEL="${CURSOR_CHANNEL:-stable}"  # Override with: CURSOR_CHANNEL=prerelease ./update.sh
CURSOR_API="https://api2.cursor.sh/updates/api/download/$CHANNEL"

# Get current version from default.nix directly (parse the version = "X.Y.Z" line)
echo "🔍 Checking current Cursor version..."
echo "📡 Channel: $CHANNEL"
currentVersion=$(grep -oP 'version = "\K[0-9.]+' "$(dirname "$0")/default.nix" | head -1)
if [[ -z "$currentVersion" ]]; then
  >&2 echo "❌ ERROR: Could not determine current version from default.nix"
  exit 1
fi
echo "📦 Current version: $currentVersion"

# Platform mapping (Cursor API uses different names than Nix)
declare -A platforms=(
  [x86_64-linux]='linux-x64'
  [aarch64-linux]='linux-arm64'
)

declare -A updates=()
first_version=""

echo ""
echo "🌐 Querying Cursor API for updates..."
echo ""

# Check each platform for updates
for platform in "${!platforms[@]}"; do
  api_platform=${platforms[$platform]}
  
  echo "  Checking $platform ($api_platform)..."
  
  # Query Cursor API
  result=$(curl -s "$CURSOR_API/$api_platform/cursor")
  version=$(echo "$result" | jq -r '.version')
  
  echo "    Latest version: $version"
  
  # Check if already up to date
  if [[ "$version" == "$currentVersion" ]]; then
    echo ""
    echo "✅ Already up to date! (version $currentVersion)"
    echo ""
    exit 0
  fi
  
  # Ensure consistent version across platforms
  if [[ -z "$first_version" ]]; then
    first_version=$version
    first_platform=$platform
  elif [[ "$version" != "$first_version" ]]; then
    >&2 echo ""
    >&2 echo "❌ ERROR: Version mismatch across platforms!"
    >&2 echo "   $first_platform: $first_version"
    >&2 echo "   $platform: $version"
    >&2 echo ""
    >&2 echo "This usually means Cursor is still rolling out the update."
    >&2 echo "Wait 24 hours and try again."
    exit 1
  fi
  
  # Get download URL
  url=$(echo "$result" | jq -r '.downloadUrl')
  
  echo "    Download URL: $url"
  
  # Verify URL is accessible
  if ! curl --output /dev/null --silent --head --fail "$url"; then
    >&2 echo ""
    >&2 echo "❌ ERROR: Cannot access download URL"
    >&2 echo "   Platform: $platform"
    >&2 echo "   URL: $url"
    >&2 echo ""
    >&2 echo "This might be a temporary Cursor server issue."
    >&2 echo "Try again later or check https://cursor.com/changelog"
    exit 1
  fi
  
  updates+=( [$platform]="$result" )
  echo "    ✅ Verified download available"
  echo ""
done

# Apply updates to default.nix
echo "================================================"
echo "📥 Downloading and updating cursor package..."
echo "   New version: $first_version"
echo "   Current version: $currentVersion"
echo "================================================"
echo ""

# Collect new URLs and hashes
declare -A new_urls
declare -A new_hashes

for platform in "${!updates[@]}"; do
  result=${updates[$platform]}
  version=$(echo "$result" | jq -r '.version')
  url=$(echo "$result" | jq -r '.downloadUrl')
  
  echo "🔧 Processing $platform..."
  echo "   URL: $url"
  
  # Prefetch the file and calculate SRI hash
  echo "   📥 Downloading and calculating hash..."
  
  # nix-prefetch-url outputs the hash in base32 format
  hash_base32=$(nix-prefetch-url "$url" --name "cursor-$version" 2>/dev/null)
  
  # Convert base32 hash to SRI format (sha256-...)
  # Use nix-hash to convert from base32 to base64
  hash=$(nix hash to-sri --type sha256 "$hash_base32")
  
  echo "   ✅ Hash: $hash"
  echo ""
  
  new_urls[$platform]=$url
  new_hashes[$platform]=$hash
done

# Update default.nix with new URLs and hashes
echo "📝 Updating default.nix..."

default_nix="$(dirname "$0")/default.nix"

# Update version (both occurrences: in let block and mkDerivation)
sed -i "s/version = \"$currentVersion\"/version = \"$first_version\"/g" "$default_nix"

# Update x86_64-linux
if [[ -n "${new_urls[x86_64-linux]:-}" ]]; then
  # Find and replace the x86_64-linux URL
  sed -i "/x86_64-linux = fetchurl {/,/};/ {
    s|url = \"[^\"]*\";|url = \"${new_urls[x86_64-linux]}\";|
    s|hash = \"[^\"]*\";|hash = \"${new_hashes[x86_64-linux]}\";|
  }" "$default_nix"
fi

# Update aarch64-linux
if [[ -n "${new_urls[aarch64-linux]:-}" ]]; then
  # Find and replace the aarch64-linux URL
  sed -i "/aarch64-linux = fetchurl {/,/};/ {
    s|url = \"[^\"]*\";|url = \"${new_urls[aarch64-linux]}\";|
    s|hash = \"[^\"]*\";|hash = \"${new_hashes[aarch64-linux]}\";|
  }" "$default_nix"
fi

echo "✅ Updated default.nix"
echo ""

echo "================================================"
echo "✅ Update complete!"
echo "================================================"
echo ""
echo "📦 New version: $first_version (was $currentVersion)"
echo ""
echo "🚀 Next steps:"
echo "   1. Test the build:"
echo "      $ cd .. && nix build .#cursor"
echo "      $ ./result/bin/cursor --version"
echo ""
echo "   2. Test with MCP servers:"
echo "      $ nix build .#homeConfigurations.test.activationPackage"
echo ""
echo "   3. Update flake.lock:"
echo "      $ nix flake update"
echo ""
echo "   4. Commit changes:"
echo "      $ git add cursor/default.nix"
echo "      $ git commit -m \"chore: Update Cursor to $first_version\""
echo ""
echo "   5. Tag release:"
echo "      $ git tag v$first_version"
echo "      $ git push origin main --tags"
echo ""
