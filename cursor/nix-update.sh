#!/usr/bin/env bash
# Cursor Nix Update - Convenience wrapper for updating Cursor via Nix
# Usage: cursor --nix-update

set -euo pipefail

echo "🚀 Cursor Nix Updater"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Find flake directory
FLAKE_DIR="${NIXOS_CURSOR_FLAKE_DIR:-}"

if [[ -z "$FLAKE_DIR" ]]; then
    # Try to find it in common locations
    POSSIBLE_DIRS=(
        "$HOME/.config/home-manager"
        "$HOME/.config/nixos"
        "$HOME/nixos"
        "$HOME/.nixos"
    )
    
    for dir in "${POSSIBLE_DIRS[@]}"; do
        if [[ -f "$dir/flake.nix" ]] && grep -q "nixos-cursor" "$dir/flake.nix" 2>/dev/null; then
            FLAKE_DIR="$dir"
            break
        fi
    done
fi

if [[ -z "$FLAKE_DIR" ]]; then
    echo "❌ Could not find your flake directory!"
    echo
    echo "Please set the environment variable:"
    echo "  export NIXOS_CURSOR_FLAKE_DIR=/path/to/your/flake"
    echo
    echo "Or run manually:"
    echo "  cd /path/to/your/flake"
    echo "  nix flake update nixos-cursor"
    echo "  home-manager switch"
    exit 1
fi

echo "📁 Flake directory: $FLAKE_DIR"
echo

# Check current version
CURRENT_VERSION="@version@"
echo "📦 Current version: $CURRENT_VERSION"

# Update the flake input
echo
echo "🔄 Updating nixos-cursor flake input..."
cd "$FLAKE_DIR"
if nix flake update nixos-cursor; then
    echo "✅ Flake input updated"
else
    echo "❌ Failed to update flake input"
    exit 1
fi

# Check if we're using Home Manager or NixOS system
if command -v home-manager >/dev/null 2>&1; then
    echo
    echo "🏠 Rebuilding Home Manager configuration..."
    if home-manager switch --flake "$FLAKE_DIR"; then
        echo "✅ Home Manager rebuilt successfully"
    else
        echo "❌ Home Manager rebuild failed"
        exit 1
    fi
elif [[ -f /etc/nixos/configuration.nix ]]; then
    echo
    echo "🖥️  Rebuilding NixOS configuration..."
    echo "⚠️  This requires sudo privileges"
    if sudo nixos-rebuild switch --flake "$FLAKE_DIR"; then
        echo "✅ NixOS rebuilt successfully"
    else
        echo "❌ NixOS rebuild failed"
        exit 1
    fi
else
    echo
    echo "⚠️  Could not determine how to rebuild"
    echo "Please run manually:"
    echo "  home-manager switch --flake $FLAKE_DIR"
    echo "  OR"
    echo "  sudo nixos-rebuild switch --flake $FLAKE_DIR"
    exit 1
fi

# Check new version
NEW_VERSION=$(nix eval "$FLAKE_DIR#nixos-cursor.packages.x86_64-linux.cursor.version" --raw 2>/dev/null || echo "unknown")

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Update complete!"
echo "   $CURRENT_VERSION → $NEW_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
