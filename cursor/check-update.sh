#!/usr/bin/env bash
# Cursor Update Checker
# Checks if a new version of Cursor is available
# Can show desktop notifications and/or return status

set -euo pipefail

# Cursor API endpoint
CURSOR_API="https://api2.cursor.sh/updates/api/download/stable"

# Get current version (passed as argument or from environment)
CURRENT_VERSION="${1:-@version@}"
SHOW_NOTIFICATION="${2:-true}"

# Query Cursor API for latest version
echo "Checking for Cursor updates..." >&2

# Fetch latest version info
RESPONSE=$(curl -s "$CURSOR_API" -w "\n%{http_code}" || echo "000")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Failed to check for updates (HTTP $HTTP_CODE)" >&2
    exit 1
fi

# Parse version from redirect URL
# API returns: {"url": "https://download.cursor.sh/linux/appImage/x64/cursor-X.Y.Z.AppImage"}
LATEST_VERSION=$(echo "$BODY" | grep -oP 'cursor-\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")

if [[ -z "$LATEST_VERSION" ]]; then
    echo "Could not determine latest version" >&2
    exit 1
fi

echo "Current version: $CURRENT_VERSION" >&2
echo "Latest version:  $LATEST_VERSION" >&2

# Compare versions
if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    echo "Up to date!" >&2
    exit 0
fi

# Update available
echo "Update available: $CURRENT_VERSION → $LATEST_VERSION" >&2

# Show desktop notification if requested
if [[ "$SHOW_NOTIFICATION" == "true" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send \
        --app-name="Cursor" \
        --icon=cursor \
        "Cursor Update Available" \
        "New version $LATEST_VERSION is available!\n\nUpdate with: nix flake update nixos-cursor && home-manager switch"
fi

# Exit with status 2 to indicate update available
exit 2
