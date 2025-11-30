# Darwin (macOS) Support Plan

> **Status**: Planned for v0.2.0  
> **Priority**: High  
> **Maintainer**: Looking for Mac testers!

## Overview

This document outlines the plan to add macOS support to `nixos-cursor`, enabling nix-darwin users to install and manage Cursor versions.

## Current State

| Platform | Architecture | Status | Notes |
|----------|--------------|--------|-------|
| Linux | x86_64 | ✅ Stable | 37 versions packaged |
| Linux | aarch64 | ⚠️ Untested | URLs exist, needs testing |
| macOS | x86_64 (Intel) | ❌ Not implemented | Planned v0.2.0 |
| macOS | aarch64 (Apple Silicon) | ❌ Not implemented | Planned v0.2.0 |

## URL Pattern Analysis

Based on the Linux URL structure:
```
https://downloads.cursor.com/production/{commit-hash}/linux/x64/Cursor-{version}-x86_64.AppImage
```

Expected macOS URLs:
```
# Intel Mac
https://downloads.cursor.com/production/{commit-hash}/darwin/x64/Cursor-{version}.dmg

# Apple Silicon
https://downloads.cursor.com/production/{commit-hash}/darwin/arm64/Cursor-{version}.dmg
```

### Example (2.0.77)
```
# Linux (known working)
https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage

# macOS Intel (needs verification)
https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/x64/Cursor-2.0.77.dmg

# macOS Apple Silicon (needs verification)
https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/arm64/Cursor-2.0.77.dmg
```

## Implementation Plan

### Phase 1: URL Discovery & Verification
- [ ] Verify macOS download URLs exist
- [ ] Document URL patterns for Intel and Apple Silicon
- [ ] Get SRI hashes for at least 3 representative versions

### Phase 2: Darwin Derivation
- [ ] Create `cursor/darwin.nix` for `.dmg` extraction
- [ ] Handle `.app` bundle installation
- [ ] Create appropriate wrappers for macOS

### Phase 3: CI/CD Integration
- [ ] Add `macos-latest` job to GitHub Actions
- [ ] Test build on GitHub's macOS runners (free!)
- [ ] Add darwin packages to Cachix

### Phase 4: nix-darwin Module
- [ ] Create darwin-specific home-manager module
- [ ] Handle macOS-specific paths (`~/Applications`, etc.)
- [ ] Test with nix-darwin users

## Technical Differences: Linux vs Darwin

| Aspect | Linux | Darwin |
|--------|-------|--------|
| Package format | `.AppImage` | `.dmg` |
| App location | `/nix/store/.../bin/` | `/nix/store/.../Applications/` |
| Config location | `~/.cursor/` | `~/Library/Application Support/Cursor/` |
| Binary patching | `patchelf`, `autoPatchelfHook` | `install_name_tool`, `fixupPhase` |
| Desktop entry | `.desktop` files | macOS handles `.app` bundles |

## Darwin Derivation Skeleton

```nix
# cursor/darwin.nix (DRAFT - not implemented)
{ lib, stdenv, fetchurl, undmg, makeWrapper }:

stdenv.mkDerivation rec {
  pname = "cursor";
  version = "2.0.77";

  src = fetchurl {
    url = "https://downloads.cursor.com/production/${commitHash}/darwin/${arch}/Cursor-${version}.dmg";
    hash = "sha256-XXXXXXXXXX";  # To be determined
  };

  nativeBuildInputs = [ undmg makeWrapper ];

  sourceRoot = "Cursor.app";

  installPhase = ''
    mkdir -p $out/Applications
    cp -r . $out/Applications/Cursor.app
    
    # Create bin wrapper
    mkdir -p $out/bin
    makeWrapper $out/Applications/Cursor.app/Contents/MacOS/Cursor $out/bin/cursor \
      --set CURSOR_CHECK_UPDATE "false"
  '';

  meta = with lib; {
    description = "AI-first code editor";
    homepage = "https://cursor.com";
    platforms = platforms.darwin;
    license = licenses.unfree;
  };
}
```

## Testing Strategy

### Without Mac Hardware

1. **GitHub Actions** (Primary):
   ```yaml
   jobs:
     build-darwin:
       runs-on: macos-latest
       steps:
         - uses: cachix/install-nix-action@v27
         - run: nix build .#cursor-darwin --print-build-logs
   ```

2. **Nix Evaluation** (Local):
   ```bash
   # Can check derivation evaluates without building
   nix eval .#packages.aarch64-darwin.cursor --json
   ```

3. **Community Testing**:
   - Post on r/NixOS, NixOS Discourse
   - Ask for Mac users to test pre-release branch

### With Mac Hardware (Contributors)

```bash
# Full test
nix build github:Distracted-E421/nixos-cursor#cursor-darwin
./result/bin/cursor --version

# Multi-version test
nix run .#cursor-darwin-2_0_77
nix run .#cursor-darwin-1_7_54
```

## Open Questions

1. **URL Verification**: Do the darwin URLs follow the same pattern as Linux?
2. **Code Signing**: Does the `.dmg` include proper signatures, or do we need to handle Gatekeeper?
3. **Config Migration**: Should we support migrating Linux config to Darwin format?
4. **Multi-version paths**: macOS uses `~/Library/Application Support/` - how to isolate versions?

## How to Help

If you have a Mac and want to help:

1. **Verify URLs exist**:
   ```bash
   curl -I "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/arm64/Cursor-2.0.77.dmg"
   ```

2. **Get hash**:
   ```bash
   nix-prefetch-url "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/darwin/arm64/Cursor-2.0.77.dmg"
   ```

3. **Test builds**:
   ```bash
   git clone https://github.com/Distracted-E421/nixos-cursor
   cd nixos-cursor
   git checkout dev
   nix build .#cursor-darwin
   ```

4. **Report results**: Open an issue or PR!

## Timeline

| Milestone | Target | Status |
|-----------|--------|--------|
| URL verification | v0.2.0-alpha | Not started |
| Darwin derivation | v0.2.0-alpha | Not started |
| CI integration | v0.2.0-beta | Not started |
| Community testing | v0.2.0-rc | Not started |
| Stable release | v0.2.0 | Not started |

## References

- [undmg - Nix DMG extractor](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/undmg/default.nix)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [VS Code darwin packaging](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/vscode/vscode.nix)

---

*Last updated: 2025-11-25*
