#!/usr/bin/env bash
# Quick fix to get Cursor working immediately
# Uses the local AppImage you already have downloaded

set -euo pipefail

APPIMAGE="/home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage"
WRAPPER="$HOME/.local/bin/cursor"

echo "🔧 Cursor Quick Fix - Using Local AppImage"
echo "==========================================="
echo

# Check if AppImage exists
if [ ! -f "$APPIMAGE" ]; then
    echo "❌ ERROR: AppImage not found at $APPIMAGE"
    echo "   Please download Cursor 2.0.77 AppImage first"
    exit 1
fi

# Make executable
chmod +x "$APPIMAGE"
echo "✅ Made AppImage executable"

# Create wrapper directory
mkdir -p "$HOME/.local/bin"

# Create wrapper script
cat > "$WRAPPER" << 'WRAPPER'
#!/usr/bin/env bash
# Cursor wrapper - launches local AppImage
# Version: 2.0.77 (has custom modes!)
exec /home/e421/Downloads/Cursor-2.0.77-x86_64.AppImage "$@"
WRAPPER

chmod +x "$WRAPPER"
echo "✅ Created wrapper at $WRAPPER"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
    echo "✅ ~/.local/bin is in PATH"
else
    echo "⚠️  WARNING: ~/.local/bin is NOT in PATH"
    echo "   Add to your shell config:"
    echo '   export PATH="$HOME/.local/bin:$PATH"'
    echo
    echo "   Or run cursor with full path:"
    echo "   ~/.local/bin/cursor"
fi

echo
echo "🚀 SUCCESS! You can now run cursor!"
echo "==========================================="
echo
echo "Try it now:"
echo "  cursor"
echo
echo "This is Cursor 2.0.77 which STILL HAS CUSTOM MODES! ✨"
echo

# Test launch (with --help to avoid full GUI launch)
echo "Testing cursor launch..."
if "$WRAPPER" --version 2>&1 | head -5; then
    echo
    echo "✅ Cursor launches successfully!"
else
    echo "❌ Launch test failed, but wrapper is created"
    echo "   Try manually: $WRAPPER"
fi
