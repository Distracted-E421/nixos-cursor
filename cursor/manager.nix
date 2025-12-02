# cursor-manager - DEPRECATED
#
# ⚠️  WARNING: This package is deprecated and will be removed in v1.0.0
#
# The Python/tkinter cursor-manager has been superseded by cursor-studio,
# a modern Rust/egui application with:
#   - Better performance (native Rust vs Python)
#   - Security scanning features
#   - VS Code theme support
#   - CLI interface (cursor-studio-cli)
#   - Planned TUI interface
#
# MIGRATION:
#   # In your flake.nix or configuration:
#   # OLD: inputs.nixos-cursor.packages.${system}.cursor-manager
#   # NEW: inputs.nixos-cursor.packages.${system}.cursor-studio
#
# The legacy implementation is preserved in ./legacy/manager.nix for reference.
#
# Known Issues with Legacy Manager:
#   - AttributeError: '_tkinter.tkapp' object has no attribute 'on_close'
#   - Slow startup time
#   - Limited theme support
#
{pkgs, ...}:
pkgs.writeShellScriptBin "cursor-manager" ''
  echo ""
  echo "╔═══════════════════════════════════════════════════════════════════╗"
  echo "║  ⚠️  cursor-manager is DEPRECATED                                 ║"
  echo "╠═══════════════════════════════════════════════════════════════════╣"
  echo "║                                                                   ║"
  echo "║  This package has been replaced by cursor-studio, which offers:  ║"
  echo "║                                                                   ║"
  echo "║    ✓ Modern Rust/egui GUI (fast, native)                         ║"
  echo "║    ✓ Security scanning for API keys/secrets                      ║"
  echo "║    ✓ VS Code theme support                                       ║"
  echo "║    ✓ CLI interface (cursor-studio-cli)                           ║"
  echo "║    ✓ Planned TUI interface                                       ║"
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
