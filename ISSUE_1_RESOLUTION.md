# Issue #1 Resolution: DNS Issues - Incomplete S3 URL Migration

## Problem Summary
GitHub Issue: https://github.com/Distracted-E421/nixos-cursor/issues/1

Versioned packages `cursor-2_0_64` and `cursor-1_7_54` were attempting to download from `downloader.cursor.sh`, which fails with DNS resolution errors. Only the main `cursor` package was using S3 URLs.

## Root Cause
The `cursor-2_0_64` definition in `cursor-versions.nix` was missing the `srcUrl` parameter, causing it to fall back to the default `downloader.cursor.sh` URL pattern.

## Fix Applied
**Commit:** `4d85350` - "fix: update 2.0.64 to S3 URL and resolve README conflicts for RC3"

### Changes to `cursor-versions.nix`

```nix
# Before (broken - uses downloader.cursor.sh)
cursor-2_0_64 = mkCursorVersion {
  version = "2.0.64";
  hash = "sha256-FP3tl/BDl9FFR/DujbaTKT80tyCNHTzEqCTQ/6bXaaU=";  # Wrong hash
  binaryName = "cursor-2.0.64";
  dataStrategy = "isolated";
};

# After (fixed - uses S3 URL)
cursor-2_0_64 = mkCursorVersion {
  version = "2.0.64";
  hash = "sha256-zT9GhdwGDWZJQl+WpV2txbmp3/tJRtL6ds1UZQoKNzA=";  # Verified hash
  srcUrl = "https://downloads.cursor.com/production/25412918da7e74b2686b25d62da1f01cfcd27683/linux/x64/Cursor-2.0.64-x86_64.AppImage";
  binaryName = "cursor-2.0.64";
  dataStrategy = "isolated";
};
```

## Verification Process

### Hash Calculation
```bash
# Download and calculate hash
nix-prefetch-url "https://downloads.cursor.com/production/25412918da7e74b2686b25d62da1f01cfcd27683/linux/x64/Cursor-2.0.64-x86_64.AppImage"
# Output: 0c1p1856am6dfvxd4ij9zggskff5mmfsb5jz894nc386vj2lcgyd

# Convert to SRI format
nix hash convert --hash-algo sha256 0c1p1856am6dfvxd4ij9zggskff5mmfsb5jz894nc386vj2lcgyd
# Output: sha256-zT9GhdwGDWZJQl+WpV2txbmp3/tJRtL6ds1UZQoKNzA=
```

### Build Verification
```bash
# Test all versioned packages
nix build .#cursor-2_0_64 --impure  # ✅ Success
nix build .#cursor-1_7_54 --impure  # ✅ Success (already working)
nix build .#cursor-2_0_77 --impure  # ✅ Success (already working)
```

## Status of All Packages

| Package | Version | S3 URL | Hash | Status |
|---------|---------|--------|------|--------|
| `cursor` | 2.0.77 | ✅ | `sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=` | ✅ Working |
| `cursor-2_0_77` | 2.0.77 | ✅ | `sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=` | ✅ Working |
| `cursor-2_0_64` | 2.0.64 | ✅ | `sha256-zT9GhdwGDWZJQl+WpV2txbmp3/tJRtL6ds1UZQoKNzA=` | ✅ **FIXED** |
| `cursor-1_7_54` | 1.7.54 | ✅ | `sha256-BKxFrfKFMWmJhed+lB5MjYHbCR9qZM3yRcs7zWClYJE=` | ✅ Working |
| `cursor-manager` | - | N/A | N/A | ✅ Working |

## Testing Instructions

### For Direct Package Usage
```nix
# In home.nix or configuration.nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor          # ✅ 2.0.77
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-manager  # ✅ GUI
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_0_64   # ✅ Now fixed
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # ✅ Working
];
```

### For Testing from CLI
```bash
# Test the GUI manager
nix run github:Distracted-E421/nixos-cursor/pre-release#cursor-manager

# Test specific versions
nix run github:Distracted-E421/nixos-cursor/pre-release#cursor-2_0_64
nix run github:Distracted-E421/nixos-cursor/pre-release#cursor-1_7_54
```

## Additional Changes

**Commit:** `7a16df2` - "docs: restore RC3 README with multi-version focus"
- Resolved README.md merge conflicts
- Updated documentation to reflect RC3 multi-version focus
- Removed confusing v2.1.20-rc1 references

**Commit:** `ed8127b` - "docs: add integration status and RC3 forum update"
- Added integration status to `.cursor/version-urls.txt`
- Created `FORUM_UPDATE_RC3.md` with talking points

## Outcome
✅ **Issue Resolved:** All versioned packages now use direct S3 URLs with verified SRI hashes. No more DNS errors.

## Next Steps
- [ ] Community testing of all packages
- [ ] Consider creating `v2.0.77-rc3` git tag
- [ ] Monitor for any additional DNS issues
- [ ] Potential promotion to `main` branch

---

**Resolution confirmed:** 2025-11-24  
**Commits:** `4d85350`, `7a16df2`, `ed8127b`  
**Branch:** `pre-release`
