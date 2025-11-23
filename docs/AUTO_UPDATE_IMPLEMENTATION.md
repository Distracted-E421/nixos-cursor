# Cursor Auto-Update Implementation Guide

**Issue**: Cursor's native update system is broken on NixOS - instead of auto-updating, it redirects to the website.

**Root Cause**: Cursor's built-in updater expects to replace the AppImage file itself. On NixOS, the application is in `/nix/store` (read-only), causing updates to fail.

**Date**: 2025-11-22  
**Status**: Implementation Required  

---

## 🎯 The Solution

Following nixpkgs' `code-cursor` implementation, we need three components:

### 1. Disable Cursor's Built-in Updater
Add `--update=false` flag to prevent Cursor from attempting self-updates.

### 2. Provide `passthru.updateScript`
Automate version checking and hash updating via Cursor's API.

### 3. User Update via Nix
Users update by running `nix flake update` instead of Cursor's internal updater.

---

## 📋 Implementation Steps

### Step 1: Update `cursor/default.nix`

**Changes needed**:

```nix
# Add commandLineArgs parameter
{ lib
, stdenv
, fetchurl
, appimageTools
, makeWrapper
# ... other deps ...
, commandLineArgs ? ""  # NEW: Command-line arguments
}:

let
  # Disable Cursor's built-in updater (NixOS incompatible)
  finalCommandLineArgs = "--update=false " + commandLineArgs;  # NEW
  
  # ... rest of let block ...
in
stdenv.mkDerivation {
  # ... existing code ...
  
  installPhase = ''
    # ... existing wrapper code ...
    
    makeWrapper $out/share/cursor/cursor $out/bin/cursor \
      --prefix LD_LIBRARY_PATH : "..." \
      # ... existing flags ...
      --add-flags "${finalCommandLineArgs}"  # NEW: Add update disable flag
  '';
  
  passthru = {
    unwrapped = cursor-extracted;
    updateScript = ./update.sh;  # NEW: Update automation
    inherit sources;  # NEW: Expose sources for update script
  };
}
```

**Key changes**:
- Add `commandLineArgs` parameter with `--update=false` default
- Pass to wrapper as `--add-flags`
- Add `updateScript` to passthru
- Expose `sources` attrset for update script access

---

### Step 2: Create `cursor/update.sh`

**Purpose**: Automated version checking and hash updating.

**Location**: `projects/cursor-with-mcp/cursor/update.sh`

```bash
#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq coreutils common-updater-scripts nix-prefetch
set -eu -o pipefail

# Cursor API endpoint for stable releases
CURSOR_API="https://api2.cursor.sh/updates/api/download/stable"

# Get current version from package
currentVersion=$(nix-instantiate --eval -E "with import ./. {}; cursor.version or (lib.getVersion cursor)" | tr -d '"')

echo "Current version: $currentVersion"

# Platform mapping (Cursor API uses different names than Nix)
declare -A platforms=(
  [x86_64-linux]='linux-x64'
  [aarch64-linux]='linux-arm64'
)

declare -A updates=()
first_version=""

# Check each platform for updates
for platform in "${!platforms[@]}"; do
  api_platform=${platforms[$platform]}
  
  echo "Checking $platform ($api_platform)..."
  
  # Query Cursor API
  result=$(curl -s "$CURSOR_API/$api_platform/cursor")
  version=$(echo "$result" | jq -r '.version')
  
  echo "  Latest version: $version"
  
  # Check if already up to date
  if [[ "$version" == "$currentVersion" ]]; then
    echo "Already up to date!"
    exit 0
  fi
  
  # Ensure consistent version across platforms
  if [[ -z "$first_version" ]]; then
    first_version=$version
    first_platform=$platform
  elif [[ "$version" != "$first_version" ]]; then
    >&2 echo "ERROR: Version mismatch! $first_version ($first_platform) vs $version ($platform)"
    exit 1
  fi
  
  # Get download URL
  url=$(echo "$result" | jq -r '.downloadUrl')
  
  # Verify URL is accessible
  if ! curl --output /dev/null --silent --head --fail "$url"; then
    >&2 echo "ERROR: Cannot download from $url"
    exit 1
  fi
  
  updates+=( [$platform]="$result" )
done

# Apply updates to default.nix
echo ""
echo "Updating cursor package to version $first_version..."

for platform in "${!updates[@]}"; do
  result=${updates[$platform]}
  version=$(echo "$result" | jq -r '.version')
  url=$(echo "$result" | jq -r '.downloadUrl')
  
  echo "  Updating $platform..."
  echo "    URL: $url"
  
  # Prefetch the file and calculate SRI hash
  source=$(nix-prefetch-url "$url" --name "cursor-$version")
  hash=$(nix-hash --to-sri --type sha256 "$source")
  
  echo "    Hash: $hash"
  
  # Update the version and hash in default.nix
  update-source-version cursor "$version" "$hash" "$url" \
    --system="$platform" \
    --ignore-same-version \
    --source-key="officialVersions.\"$version\".$platform"
done

echo ""
echo "✅ Update complete! New version: $first_version"
echo ""
echo "Next steps:"
echo "  1. Test the build: nix build .#cursor"
echo "  2. Update flake.lock: nix flake update"
echo "  3. Commit changes: git add cursor/default.nix flake.lock"
echo "  4. Tag release: git tag v$first_version"
```

**Features**:
- Queries Cursor's official API for latest version
- Verifies version consistency across platforms
- Prefetches AppImages and calculates SRI hashes
- Updates `officialVersions` in `default.nix`
- Validates downloads before applying changes

---

### Step 3: Restructure `officialVersions` in `cursor/default.nix`

**Current format** (problematic for update script):

```nix
officialVersions = {
  "0.42.5" = {
    x86_64-linux = { url = "..."; hash = "..."; };
    aarch64-linux = { url = "..."; hash = "..."; };
  };
};
```

**Updated format** (matches nixpkgs pattern):

```nix
sources = {
  x86_64-linux = fetchurl {
    url = "https://downloads.cursor.com/production/COMMIT_HASH/linux/x64/Cursor-VERSION-x86_64.AppImage";
    hash = "sha256-HASH_HERE";
  };
  aarch64-linux = fetchurl {
    url = "https://downloads.cursor.com/production/COMMIT_HASH/linux/arm64/Cursor-VERSION-aarch64.AppImage";
    hash = "sha256-HASH_HERE";
  };
};

appImageSrc = sources.${stdenv.hostPlatform.system} or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");
```

**Why this change**:
- Simpler for update script to modify
- Matches nixpkgs convention
- Single source of truth per platform
- Version derived from filename, not attrset key

---

### Step 4: Update Home Manager Module

**Change**: Document that `allowSelfUpdate` doesn't work on NixOS.

```nix
# programs.cursor-ide options (if using the old home.nix format)

updateChannel = mkOption {
  type = types.enum [ "stable" "nightly" ];
  default = "stable";
  description = ''
    Update channel for Cursor.
    
    Note: On NixOS, Cursor's built-in updater is disabled because
    applications reside in the read-only /nix/store. Updates are
    handled via Nix package management instead.
    
    To update Cursor:
      1. nix flake update (updates flake inputs)
      2. nixos-rebuild switch (applies system changes)
      3. home-manager switch (applies user changes)
  '';
};

allowSelfUpdate = mkOption {
  type = types.bool;
  default = false;  # Changed from true
  description = ''
    Allow Cursor to self-update (DISABLED on NixOS).
    
    This option has no effect on NixOS because Cursor's updater
    requires write access to its installation directory, which
    is read-only in /nix/store.
    
    Use Nix's update mechanisms instead:
      - nix flake update cursor-with-mcp
      - nixos-rebuild switch
  '';
};
```

---

### Step 5: CI/CD Automation (Future Enhancement)

**Goal**: Automatically detect new Cursor releases and create PRs.

**Implementation** (GitHub Actions):

```yaml
# .github/workflows/update-cursor.yml
name: Update Cursor

on:
  schedule:
    - cron: '0 12 * * 1,4'  # Monday and Thursday at 12:00 UTC
  workflow_dispatch:        # Manual trigger

jobs:
  check-update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: cachix/install-nix-action@v25
        with:
          nix_path: nixpkgs=channel:nixos-unstable
      
      - name: Check for Cursor updates
        id: update
        run: |
          cd cursor
          ./update.sh || echo "update_available=false" >> $GITHUB_OUTPUT
          
          # Check if files changed
          if git diff --quiet cursor/default.nix; then
            echo "update_available=false" >> $GITHUB_OUTPUT
            echo "No updates available"
          else
            NEW_VERSION=$(nix-instantiate --eval -E "with import ./. {}; cursor.version" | tr -d '"')
            echo "update_available=true" >> $GITHUB_OUTPUT
            echo "new_version=$NEW_VERSION" >> $GITHUB_OUTPUT
            echo "Update available: $NEW_VERSION"
          fi
      
      - name: Create Pull Request
        if: steps.update.outputs.update_available == 'true'
        uses: peter-evans/create-pull-request@v5
        with:
          commit-message: "chore: Update Cursor to ${{ steps.update.outputs.new_version }}"
          title: "Update Cursor to ${{ steps.update.outputs.new_version }}"
          body: |
            Automated update of Cursor IDE to version ${{ steps.update.outputs.new_version }}.
            
            **Changes**:
            - Updated cursor/default.nix with new version and hashes
            - All platforms verified and prefetched
            
            **Testing Required**:
            - [ ] Build succeeds on x86_64-linux
            - [ ] Build succeeds on aarch64-linux
            - [ ] All MCP servers still functional
            - [ ] No breaking changes in Cursor
            
            **Merge Checklist**:
            - [ ] CI/CD passes
            - [ ] Manual testing complete
            - [ ] CHANGELOG.md updated
            - [ ] Tag created: v${{ steps.update.outputs.new_version }}
          branch: "auto-update-cursor-${{ steps.update.outputs.new_version }}"
          delete-branch: true
```

**Benefits**:
- Automatic detection of new Cursor releases
- Creates PR with prefetched hashes
- Maintainer reviews and merges manually
- Ensures no breaking changes slip through

---

## 📖 User Documentation

### For End Users

**Before** (broken on NixOS):
```
Cursor → Help → Check for Updates
❌ "Please download the latest version from cursor.com"
```

**After** (Nix-managed updates):
```bash
# Update your Cursor installation
nix flake update cursor-with-mcp

# Apply updates (Home Manager)
home-manager switch

# Or for NixOS system package
nixos-rebuild switch
```

### Update Frequency

**Flake maintainer responsibilities**:
- Monitor Cursor releases: https://cursor.com/changelog
- Run `cursor/update.sh` when new version released
- Test on at least 1 platform
- Tag release matching Cursor version
- Update CHANGELOG.md

**Recommended schedule**:
- **Stable channel**: 2-4 weeks after Cursor release (after testing)
- **Unstable channel**: 1 week after Cursor release
- **Security updates**: Immediate (within 48 hours)

---

## 🚀 Release Process (Post-Update)

### After Running update.sh

```bash
# 1. Verify the changes
git diff cursor/default.nix

# 2. Test build locally
cd projects/cursor-with-mcp
nix build .#cursor
./result/bin/cursor --version

# 3. Test with MCP servers
nix build .#homeConfigurations.test-user.activationPackage
./result/activate

# 4. Commit if successful
git add cursor/default.nix
git commit -m "chore: Update Cursor to $(nix eval .#cursor.version --raw)"

# 5. Update flake.lock (pulls in any dependency updates)
nix flake update

# 6. Tag the release
NEW_VERSION=$(nix eval .#cursor.version --raw)
git tag "v$NEW_VERSION"
git push origin main --tags

# 7. Create GitHub release
gh release create "v$NEW_VERSION" \
  --title "Cursor $NEW_VERSION with MCP" \
  --notes "Updated to Cursor $NEW_VERSION. See CHANGELOG.md for details."
```

---

## 🐛 Troubleshooting

### Update Script Fails

**Problem**: `curl: (22) The requested URL returned error: 404`

**Solution**: Cursor changed their API or download URLs.

**Fix**:
1. Check https://cursor.com/changelog for new download structure
2. Update `CURSOR_API` in `update.sh`
3. Verify URL format with browser DevTools during manual download

---

### Version Mismatch Between Platforms

**Problem**: `ERROR: Version mismatch! 2.0.65 (x86_64-linux) vs 2.0.64 (aarch64-linux)`

**Cause**: Cursor releases ARM and x64 builds separately (rare but possible).

**Solution**:
1. Wait 24 hours for all platforms to publish
2. Re-run update script
3. If persists, manually specify newer version only

---

### Hash Verification Fails

**Problem**: `error: hash mismatch in fixed-output derivation`

**Cause**: Download URL changed after prefetch or network error.

**Solution**:
```bash
# Clear Nix store cache
nix-store --delete /nix/store/*cursor*.AppImage

# Re-run update script
cd cursor
./update.sh

# If still fails, manually prefetch
nix-prefetch-url <URL> --name cursor-VERSION.AppImage
```

---

## 📊 Comparison: Before vs After

| Aspect | Before (Broken) | After (Nix-managed) |
|--------|----------------|---------------------|
| **Update Method** | Cursor's built-in (fails) | `nix flake update` |
| **User Experience** | Redirects to website | Seamless Nix update |
| **Automation** | None | CI/CD auto-detects |
| **Rollback** | Reinstall old AppImage | `nix profile rollback` |
| **Reproducibility** | ❌ Version drift | ✅ Locked with flake.lock |
| **Multi-device** | Manual sync | Declarative (same flake) |
| **Offline Updates** | ❌ Requires download | ✅ Cached in /nix/store |

---

## ✅ Implementation Checklist

### Phase 1: Core Functionality
- [ ] Add `commandLineArgs` to `cursor/default.nix`
- [ ] Add `--update=false` flag to wrapper
- [ ] Restructure `officialVersions` → `sources`
- [ ] Create `cursor/update.sh` script
- [ ] Make `update.sh` executable: `chmod +x`
- [ ] Test update script on current version (should detect no update)
- [ ] Add `passthru.updateScript` to derivation
- [ ] Update `passthru.sources` exposure

### Phase 2: Documentation
- [ ] Update README.md with update instructions
- [ ] Add AUTO_UPDATE_IMPLEMENTATION.md to docs/
- [ ] Update RELEASE_STRATEGY.md with update workflow
- [ ] Document `allowSelfUpdate = false` in Home Manager module
- [ ] Create user-facing "How to Update" guide

### Phase 3: Testing
- [ ] Test `update.sh` with mock version bump
- [ ] Verify hash calculations are correct
- [ ] Test update on both x86_64-linux and aarch64-linux
- [ ] Ensure MCP servers still work after update
- [ ] Test rollback: `nix profile rollback`

### Phase 4: Automation (Future)
- [ ] Create GitHub Actions workflow
- [ ] Set up automated PR creation
- [ ] Add CI/CD tests for new versions
- [ ] Configure release tagging automation

### Phase 5: Public Release Prep
- [ ] Add update documentation to public repo
- [ ] Include update.sh in release
- [ ] Document maintainer responsibilities
- [ ] Create update schedule (stable vs unstable)

---

## 🎓 Key Learnings

### Why Cursor's Updater Fails on NixOS

**Typical Linux app update**:
1. Download new AppImage to `/tmp/`
2. Replace `/usr/local/bin/cursor` with new AppImage
3. Restart application

**NixOS reality**:
1. Cursor binary lives in `/nix/store/HASH-cursor-2.0.64/bin/cursor`
2. `/nix/store` is **read-only** (immutable)
3. Cursor updater tries to write → **Permission denied**
4. Falls back to "please download manually"

**Nix solution**:
1. New version → new `/nix/store/HASH2-cursor-2.0.65/`
2. Symlink updated: `/run/current-system/sw/bin/cursor` → new store path
3. Old version retained for rollback
4. Garbage collection cleans old versions when safe

### Why `--update=false` is Critical

Without this flag:
- Cursor **will** try to update itself on startup (if update available)
- Update **will** fail (read-only `/nix/store`)
- User sees annoying "update failed" message **every time**
- User clicks "Download" → manual install → conflicts with Nix

With this flag:
- Cursor never checks for updates
- User updates via Nix (declarative, reproducible)
- No confusing error messages
- Clean user experience

---

## 📅 Timeline

**Week 1** (Current):
- Implement core update mechanism
- Test update script locally
- Document user update process

**Week 2**:
- Add CI/CD automation
- Test on multiple devices
- Prepare for public release

**Week 3**:
- Public release with working updates
- Monitor community feedback
- Iterate on update frequency

---

## 🙏 Credits

**Upstream Implementation**:
- Nixpkgs `code-cursor` package: https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/co/code-cursor/package.nix
- Update script pattern: https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/co/code-cursor/update.sh
- Cursor API: https://api2.cursor.sh/updates/api/download/stable/{platform}/cursor

**Our Contribution**:
- MCP server integration
- Declarative Home Manager module
- Multi-monitor/window support
- Playwright automation fixes

---

**Last Updated**: 2025-11-22  
**Status**: Implementation Plan Ready  
**Next Step**: Implement Phase 1 changes to cursor/default.nix
