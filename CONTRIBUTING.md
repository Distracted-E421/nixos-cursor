# Contributing to nixos-cursor

Thank you for your interest in contributing to nixos-cursor! This document provides guidelines and information for contributors.

## 🌿 Branch Strategy

| Branch | Purpose | CI/CD |
|--------|---------|-------|
| `main` | **Stable releases** - Default branch for users | Full CI + releases |
| `dev` | **Development** - Active development work | Full CI |

### Workflow

1. **Development** happens on `dev` branch
2. **Releases** are merged from `dev` → `main` and tagged (e.g., `v0.1.0`)
3. **Hotfixes** can be applied directly to `main` if critical

### For Contributors

```bash
# Fork the repo, then:
git clone https://github.com/YOUR_USERNAME/nixos-cursor
cd nixos-cursor
git checkout dev
git checkout -b feature/your-feature-name

# Make changes, then:
git push origin feature/your-feature-name
# Open PR against `dev` branch
```

## 🧪 Testing

### Before Submitting a PR

1. **Run flake check:**
   ```bash
   nix flake check
   ```

2. **Test your changes build:**
   ```bash
   nix build .#cursor
   nix build .#cursor-manager
   ```

3. **If adding a new version, verify:**
   ```bash
   nix build .#cursor-X_Y_Z
   # Check store paths are version-specific
   ls -la $(nix build .#cursor-X_Y_Z --print-out-paths)/bin/
   ```

### Local Testing

```bash
# Test the manager with local flake
CURSOR_FLAKE_URI=. nix run .#cursor-manager --impure

# Build specific version
nix build .#cursor-1_7_54
```

## 📦 Adding New Cursor Versions

To add a new Cursor version:

1. **Get the download URL:**
   - Find the S3 URL from [oslook's cursor-ai-downloads](https://github.com/oslook/cursor-ai-downloads)
   - Format: `https://downloads.cursor.com/production/<hash>/linux/x64/Cursor-X.Y.Z-x86_64.AppImage`

2. **Calculate the hash:**
   ```bash
   nix-prefetch-url --type sha256 "https://downloads.cursor.com/production/<hash>/linux/x64/Cursor-X.Y.Z-x86_64.AppImage"
   # Convert to SRI format: sha256-XXXX...
   ```

3. **Add to `cursor-versions.nix`:**
   ```nix
   cursor-X_Y_Z = mkCursorVersion {
     version = "X.Y.Z";
     hash = "sha256-CALCULATED_HASH";
     srcUrl = "https://downloads.cursor.com/production/<hash>/linux/x64/Cursor-X.Y.Z-x86_64.AppImage";
   };
   ```

4. **Update `cursor/manager.nix`** to include the new version in the dropdown.

5. **Test the build:**
   ```bash
   nix build .#cursor-X_Y_Z
   ```

## 🎨 Code Style

### Nix

- Use 2-space indentation
- Follow existing patterns in `cursor-versions.nix`
- Document complex logic with comments

### Python (manager.nix)

- Keep the GUI simple and functional
- Use tkinter/ttk for consistency
- Test on both Wayland and X11

## 📝 Commit Messages

Follow conventional commits:

```
feat: Add Cursor version 2.0.78
fix: Resolve icon conflict for multi-version install
docs: Update VERSION_MANAGER_GUIDE.md
ci: Add matrix build for all versions
```

## 🐛 Reporting Issues

When reporting issues, please include:

1. **NixOS version** (e.g., 24.05, 25.11)
2. **Installation method** (Home Manager, direct flake, nix run)
3. **Which Cursor version(s)** you're trying to use
4. **Full error output** from the build/run
5. **Steps to reproduce**

## 📚 Documentation

- Keep README.md concise - quick start focus
- Detailed guides go in separate markdown files
- Update VERSION_MANAGER_GUIDE.md when adding features

## 🙏 Credits

Special thanks to:
- [@oslook](https://github.com/oslook) for maintaining [cursor-ai-downloads](https://github.com/oslook/cursor-ai-downloads)
- The NixOS community for flake best practices

---

Questions? Open an issue or reach out to [@Distracted-E421](https://github.com/Distracted-E421).
