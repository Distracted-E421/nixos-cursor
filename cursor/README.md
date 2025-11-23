# Cursor - Enhanced NixOS Package

**License**: MIT (this packaging) | Proprietary (Cursor itself)  
**Platforms**: x86_64-linux, aarch64-linux

Production-ready Cursor IDE package with NixOS-specific fixes.

---

## Features

### NixOS Fixes Included

- - **libxkbfile** - Fixes keyboard mapping errors
- - **libGL** - GPU acceleration support
- - **Wayland** - Native Wayland window decorations
- - **Proper wrapping** - All dependencies in LD_LIBRARY_PATH

### What This Solves

**Before** (stock AppImage):
- - Keyboard mapping errors
- - GPU acceleration disabled
- - Poor Wayland support
- - Missing system libraries

**After** (this package):
- - Full keyboard support
- - Hardware-accelerated graphics
- - Native Wayland experience
- - All dependencies bundled

---

## Usage

### Basic

```nix
{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.callPackage ./cursor { })
  ];
}
```

### With Custom Version

```nix
{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.callPackage ./cursor {
      version = "0.43.0";
      src = pkgs.fetchurl {
        url = "https://downloader.cursor.sh/linux/appImage/x64";
        hash = "sha256-...";  # Get with: nix-prefetch-url
      };
    })
  ];
}
```

### In flake.nix

```nix
{
  inputs = {
    cursor-nixos.url = "github:yourusername/cursor-nixos";
  };

  outputs = { nixpkgs, cursor-nixos, ... }: {
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      modules = [
        {
          nixpkgs.overlays = [
            (final: prev: {
              cursor = cursor-nixos.packages.${prev.system}.cursor;
            })
          ];
          
          environment.systemPackages = [ pkgs.cursor ];
        }
      ];
    };
  };
}
```

---

## Updating

### Finding New Versions

```bash
# Check Cursor's official website
curl -I https://downloader.cursor.sh/linux/appImage/x64

# Get SHA256 hash
nix-prefetch-url https://downloader.cursor.sh/linux/appImage/x64
```

### Updating Package

Edit `default.nix`:

```nix
officialVersions = {
  "0.43.0" = {  # New version
    x86_64-linux = {
      url = "https://downloader.cursor.sh/linux/appImage/x64";
      hash = "sha256-NEWHASHHERE";
    };
  };
};
```

---

## Technical Details

### Dependencies

**Build-time**:
- `makeWrapper` - Script wrapping
- `wrapGAppsHook3` - GTK integration
- `autoPatchelfHook` - ELF binary patching

**Runtime**:
- `libxkbfile` - Keyboard mapping
- `libglvnd` - OpenGL acceleration
- `gtk3`, `glib` - UI framework
- `mesa` - Graphics drivers
- And ~20 more standard libraries

### Electron Flags

Optimized for NixOS:

```
--ozone-platform-hint=auto        # Wayland/X11 detection
--enable-features=UseOzonePlatform,WaylandWindowDecorations
--enable-gpu-rasterization        # Hardware acceleration
--enable-zero-copy                # Performance
--num-raster-threads=4            # Multi-threading
```

### File Layout

```
$out/
├── bin/
│   └── cursor                     # Main executable
├── share/
│   ├── cursor/                    # Extracted AppImage
│   ├── applications/
│   │   └── cursor.desktop         # Desktop entry
│   ├── icons/                     # Application icons
│   └── pixmaps/                   # Legacy icons
```

---

## Comparison with nixpkgs

### vs `pkgs.code-cursor`

| Feature | nixpkgs | This Package |
|---------|---------|--------------|
| libxkbfile fix | - | - |
| GPU acceleration | WARNING: | - |
| Wayland flags | WARNING: | - |
| Version flexibility | - | - |
| ARM64 support | WARNING: | - |
| Update speed | Slow | Fast |

### Why Not Contribute to nixpkgs?

**We should!** This is a prototype to:
1. Test enhancements quickly
2. Gather community feedback
3. Refine the approach

**Goal**: Eventually upstream these improvements.

---

## Known Issues

### AppImage Hash Changes

Cursor's AppImage URL doesn't include version numbers, so the hash changes with each release.

**Workaround**: Provide custom `src` parameter.

### ARM64 Support

ARM64 builds exist but aren't always released simultaneously with x86_64.

**Status**: Framework ready, needs hash updates when available.

---

## Contributing

### Adding New Versions

1. Download AppImage: `wget https://downloader.cursor.sh/linux/appImage/x64`
2. Get hash: `nix-prefetch-url file://$(pwd)/cursor.AppImage`
3. Add to `officialVersions` in `default.nix`
4. Test: `nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix { version = "X.Y.Z"; }'`

### Testing Changes

```bash
# Build only
nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'

# Build and run
nix-shell -p '(callPackage ./default.nix {})' --run cursor

# Test in VM
nixos-rebuild build-vm --flake '.#test'
```

---

## License

**This packaging**: MIT License  
**Cursor IDE**: Proprietary (Anysphere, Inc.)

See [../LICENSING_AND_FOSS.md](../LICENSING_AND_FOSS.md) for details.

---

## References

- [Cursor Official](https://www.cursor.com/)
- [nixpkgs code-cursor](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/code-cursor/default.nix)
- [AppImage specification](https://github.com/AppImage/AppImageSpec)

---

**Maintained by**: e421 (distracted.e421@gmail.com)  
**Status**: Production-ready
