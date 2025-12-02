# cursor-chat-library - DEPRECATED
#
# ⚠️  WARNING: This package is deprecated and will be removed in v1.0.0
#
# The Python/tkinter chat library has been superseded by cursor-studio,
# a modern Rust/egui application with superior chat viewing capabilities:
#   - Fast message rendering
#   - Full-text search with highlighting
#   - Bookmark persistence across reimports
#   - Security scanning for sensitive data
#   - Export to Markdown
#   - VS Code theme support
#
# MIGRATION:
#   # In your flake.nix or configuration:
#   # OLD: inputs.nixos-cursor.packages.${system}.cursor-chat-library
#   # NEW: inputs.nixos-cursor.packages.${system}.cursor-studio
#
# The legacy implementation is preserved in ./legacy/chat-library.nix for reference.
#
{pkgs, ...}:

pkgs.writeShellScriptBin "cursor-chat-library" ''
  echo ""
  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║  ⚠️  cursor-chat-library is DEPRECATED                            ║"
  echo "╠═══════════════════════════════════════════════════════════════════╣"
  echo "║                                                                   ║"
  echo "║  This package has been replaced by cursor-studio, which offers:  ║"
  echo "║                                                                   ║"
  echo "║    ✓ Fast native message rendering                               ║"
  echo "║    ✓ Full-text search with navigation                            ║"
  echo "║    ✓ Persistent bookmarks                                        ║"
  echo "║    ✓ Security scanning for API keys                              ║"
  echo "║    ✓ Markdown export                                             ║"
  echo "║    ✓ VS Code theme support                                       ║"
  echo "║                                                                   ║"
  echo "║  To install cursor-studio:                                       ║"
  echo "║                                                                   ║"
  echo "║    nix run github:Distracted-E421/nixos-cursor#cursor-studio     ║"
  echo "║                                                                   ║"
  echo "║  Or add to your flake:                                           ║"
  echo "║                                                                   ║"
  echo "║    inputs.nixos-cursor.packages.\$\{system\}.cursor-studio       ║"
  echo "║                                                                   ║"
  echo "╚═══════════════════════════════════════════════════════════════════╝"
  echo ""
  
  # Check if cursor-studio is available and offer to launch it
  if command -v cursor-studio &> /dev/null; then
    echo "cursor-studio is installed. Launching..."
    exec cursor-studio "$@"
  else
    echo "To install cursor-studio, run:"
    echo "  nix run github:Distracted-E421/nixos-cursor#cursor-studio"
    exit 1
  fi
''
