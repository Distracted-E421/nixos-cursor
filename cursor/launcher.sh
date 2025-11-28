#!/usr/bin/env bash
# Cursor Unified Launcher
# Reads configuration from cursor-manager and launches appropriate version
#
# Priority order for version selection:
# 1. Command-line argument: cursor --version 2.0.77
# 2. Environment variable: CURSOR_VERSION=2.0.77 cursor
# 3. Config file: ~/.config/cursor-manager/config.json
# 4. System default: @version@ (flake-specified)
#
# This script also applies data sync settings before launch if configured.

set -euo pipefail

# Configuration paths
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cursor-manager"
CONFIG_FILE="$CONFIG_DIR/config.json"
CURSOR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor"

# System default version (substituted by Nix)
SYSTEM_DEFAULT_VERSION="@version@"
SYSTEM_CURSOR_BIN="@out@/share/@shareDirName@/cursor"

# Parse arguments
VERSION=""
PASS_THROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --cursor-version=*)
            VERSION="${1#*=}"
            shift
            ;;
        *)
            PASS_THROUGH_ARGS+=("$1")
            shift
            ;;
    esac
done

# Function to read JSON value (using jq if available, otherwise fallback)
read_config() {
    local key="$1"
    local default="$2"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi
    
    if command -v jq &>/dev/null; then
        local value
        value=$(jq -r "$key // \"$default\"" "$CONFIG_FILE" 2>/dev/null || echo "$default")
        echo "$value"
    else
        # Fallback: simple grep (works for simple keys)
        grep -o "\"${key#.}\": *\"[^\"]*\"" "$CONFIG_FILE" 2>/dev/null | 
            sed 's/.*: *"\([^"]*\)"/\1/' || echo "$default"
    fi
}

# Function to sync settings between version directories
sync_settings() {
    local target_version="$1"
    local sync_settings sync_snippets sync_global
    
    sync_settings=$(read_config ".settings.syncSettingsOnLaunch" "true")
    sync_snippets=$(read_config ".dataControl.syncSnippets" "true")
    sync_global=$(read_config ".settings.syncGlobalStorage" "false")
    
    if [[ "$target_version" == "$SYSTEM_DEFAULT_VERSION" ]] || [[ "$target_version" == "default" ]]; then
        # Using system default, no sync needed
        return
    fi
    
    local target_dir="$HOME/.cursor-$target_version/User"
    local source_dir="$CURSOR_CONFIG_DIR/User"
    
    if [[ ! -d "$source_dir" ]]; then
        return
    fi
    
    mkdir -p "$target_dir"
    
    # Sync settings.json and keybindings.json
    if [[ "$sync_settings" == "true" ]]; then
        for file in settings.json keybindings.json; do
            if [[ -f "$source_dir/$file" ]] && [[ ! -f "$target_dir/$file" ]]; then
                cp "$source_dir/$file" "$target_dir/$file"
            fi
        done
    fi
    
    # Sync snippets
    if [[ "$sync_snippets" == "true" ]]; then
        if [[ -d "$source_dir/snippets" ]] && [[ ! -d "$target_dir/snippets" ]]; then
            cp -r "$source_dir/snippets" "$target_dir/"
        fi
    fi
    
    # Sync globalStorage (symlink)
    if [[ "$sync_global" == "true" ]]; then
        if [[ -d "$source_dir/globalStorage" ]] && [[ ! -e "$target_dir/globalStorage" ]]; then
            ln -s "$source_dir/globalStorage" "$target_dir/globalStorage"
        fi
    fi
}

# Determine which version to use
get_target_version() {
    # Priority 1: Explicit argument
    if [[ -n "$VERSION" ]]; then
        echo "$VERSION"
        return
    fi
    
    # Priority 2: Environment variable
    if [[ -n "${CURSOR_VERSION:-}" ]]; then
        echo "$CURSOR_VERSION"
        return
    fi
    
    # Priority 3: Config file
    local config_version
    config_version=$(read_config ".defaultVersion" "")
    if [[ -n "$config_version" ]] && [[ "$config_version" != "null" ]] && [[ "$config_version" != "system" ]]; then
        echo "$config_version"
        return
    fi
    
    # Priority 4: System default
    echo "$SYSTEM_DEFAULT_VERSION"
}

# Get the binary path for a version
get_cursor_binary() {
    local version="$1"
    
    if [[ "$version" == "$SYSTEM_DEFAULT_VERSION" ]]; then
        # Use system-installed binary
        echo "$SYSTEM_CURSOR_BIN"
        return
    fi
    
    # Check if versioned binary exists in PATH
    local versioned_bin="cursor-$version"
    if command -v "$versioned_bin" &>/dev/null; then
        command -v "$versioned_bin"
        return
    fi
    
    # Try nix run as fallback
    echo "nix-run:$version"
}

# Main execution
main() {
    local target_version
    target_version=$(get_target_version)
    
    # Apply data sync if configured
    local do_sync
    do_sync=$(read_config ".settings.syncSettingsOnLaunch" "true")
    if [[ "$do_sync" == "true" ]]; then
        sync_settings "$target_version"
    fi
    
    # Get binary path
    local cursor_bin
    cursor_bin=$(get_cursor_binary "$target_version")
    
    if [[ "$cursor_bin" == nix-run:* ]]; then
        # Use nix run for non-installed version
        local nix_version="${cursor_bin#nix-run:}"
        local pkg_name="cursor-${nix_version//./_}"
        local flake_uri="${CURSOR_FLAKE_URI:-github:Distracted-E421/nixos-cursor}"
        
        exec nix run "$flake_uri#$pkg_name" --impure -- "${PASS_THROUGH_ARGS[@]}"
    else
        # Direct execution
        exec "$cursor_bin" --update=false "${PASS_THROUGH_ARGS[@]}"
    fi
}

main
