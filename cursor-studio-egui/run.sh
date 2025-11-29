#!/usr/bin/env bash
# Quick run script for Cursor Studio development
# Usage: ./run.sh [--release] [--clean]

set -e

cd "$(dirname "$0")"

# Parse arguments
RELEASE=""
CLEAN=""

for arg in "$@"; do
    case $arg in
        --release|-r)
            RELEASE="--release"
            shift
            ;;
        --clean|-c)
            CLEAN="1"
            shift
            ;;
        --help|-h)
            echo "Usage: ./run.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --release, -r    Build in release mode (slower build, faster run)"
            echo "  --clean, -c      Clean build artifacts first"
            echo "  --help, -h       Show this help"
            echo ""
            echo "For fastest iteration, use debug builds (default)."
            echo "For distribution, use: nix build"
            exit 0
            ;;
    esac
done

# Clean if requested
if [ -n "$CLEAN" ]; then
    echo "🧹 Cleaning build artifacts..."
    cargo clean
fi

# Check if we're in a nix shell
if [ -z "$IN_NIX_SHELL" ]; then
    echo "⚡ Entering nix develop shell and building..."
    exec nix develop -c cargo run $RELEASE
else
    echo "⚡ Building and running..."
    cargo run $RELEASE
fi
