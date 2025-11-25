# nixos-cursor Bug Report: Multi-Version Package Conflicts & Integration Issues

**Repository**: [Distracted-E421/nixos-cursor](https://github.com/Distracted-E421/nixos-cursor)  
**Branch Tested**: `pre-release` (RC3.3)  
**Commit**: `cc71487f806cef5cd454238cca8ad2fcd8f381d1`  
**Date**: 2025-11-25  
**Reporter**: Real-world integration testing from NixOS 25.11 homelab

---

## ✅ STATUS: ALL ISSUES RESOLVED IN RC3.4

This bug report has been **fully addressed** in RC3.4 (commit `4ae9c21`).

| Issue | Status | Resolution |
|-------|--------|------------|
| Package Path Conflicts | ✅ FIXED | Version-specific paths (`/share/cursor-VERSION/`) |
| Missing `apps` Attribute | ✅ FIXED | Added `apps` flake output |
| Main Branch Outdated | ⚠️ KNOWN | Use `/pre-release` branch (documented) |

---

## 🐛 Original Issue Summary

There ~~are~~ **were** **three main issues** preventing smooth multi-version Cursor installation:

1. ~~**Package Path Conflicts**~~ ✅ FIXED - Multiple Cursor versions ~~cannot~~ **can now** be installed simultaneously
2. ~~**Missing `apps` Attribute**~~ ✅ FIXED - `nix run` ~~requires verbose full paths~~ **works with clean syntax**
3. **Main Branch Outdated** - Default branch lacks versioned packages (documented workaround: use `/pre-release`)

---

## Issue 1: Package Path Conflicts (Critical)

### Problem

All Cursor version packages install their binary to the **same path**: `/share/cursor/cursor`

This causes `pkgs.buildEnv` conflicts when users try to install multiple versions:

```
pkgs.buildEnv error: two given paths contain a conflicting subpath:
  `/nix/store/x4r5xy1m9ch2k0byrykjzzpj4iq43iz4-cursor-2.0.64/share/cursor/cursor' and
  `/nix/store/dv4k760iwzax3pn22hiw83y5rqw0myhv-cursor-2.0.77/share/cursor/cursor'
hint: this may be caused by two different versions of the same package in buildEnv's `paths` parameter
```

### Steps to Reproduce

```nix
# In home.nix or configuration.nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor          # 2.0.77
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_0_64   # 2.0.64
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # 1.7.54
];
```

```bash
# Build fails with:
nixos-rebuild switch --flake .#hostname
# ERROR: conflicting subpath /share/cursor/cursor
```

### Expected Behavior

Users should be able to install **multiple Cursor versions simultaneously** as advertised:
- `cursor` → launches 2.0.77
- `cursor-2_0_64` → launches 2.0.64
- `cursor-1_7_54` → launches 1.7.54

### Root Cause Analysis

The issue is likely in the package derivation - all versions are installing to:
```
$out/share/cursor/cursor
$out/bin/cursor  # symlink to above
```

Instead, each version should install to version-specific paths:
```
$out/share/cursor-2.0.77/cursor
$out/bin/cursor-2_0_77  # unique binary name

$out/share/cursor-2.0.64/cursor  
$out/bin/cursor-2_0_64  # unique binary name
```

### Suggested Fix

Option A: **Version-specific installation paths**
```nix
# In the package derivation
installPhase = ''
  mkdir -p $out/share/cursor-${version}
  mkdir -p $out/bin
  # ... install to version-specific directory
  ln -s $out/share/cursor-${version}/cursor $out/bin/cursor-${lib.replaceStrings ["."] ["_"] version}
'';
```

Option B: **Use `symlinkJoin` with `postBuild` to rename**
```nix
# Create unique binary names for each version
postBuild = ''
  mv $out/bin/cursor $out/bin/cursor-${lib.replaceStrings ["."] ["_"] version}
'';
```

Option C: **Provide a `meta.mainProgram` with version suffix**
```nix
meta = {
  mainProgram = "cursor-${lib.replaceStrings ["."] ["_"] version}";
};
```

---

## Issue 2: Missing `apps` Attribute

### Problem

The flake only exports `packages`, not `apps`. This means `nix run` fails with the intuitive command:

```bash
# This FAILS
nix run github:Distracted-E421/nixos-cursor/pre-release#cursor-1_7_54
# error: flake does not provide attribute 'apps.x86_64-linux.cursor-1_7_54'
```

### Workaround (Verbose)

Users must specify the full path:
```bash
# This WORKS but is verbose
nix run github:Distracted-E421/nixos-cursor/pre-release#packages.x86_64-linux.cursor-1_7_54
```

### Expected Behavior

```bash
# Should just work
nix run github:Distracted-E421/nixos-cursor/pre-release#cursor-1_7_54
```

### Suggested Fix

Add `apps` output to `flake.nix`:

```nix
# Using flake-parts
perSystem = { pkgs, system, ... }: {
  apps = builtins.mapAttrs (name: pkg: {
    type = "app";
    program = "${pkg}/bin/${pkg.meta.mainProgram or name}";
  }) self.packages.${system};
};
```

Or manually:
```nix
apps.x86_64-linux = {
  cursor = {
    type = "app";
    program = "${self.packages.x86_64-linux.cursor}/bin/cursor";
  };
  cursor-1_7_54 = {
    type = "app";
    program = "${self.packages.x86_64-linux.cursor-1_7_54}/bin/cursor-1_7_54";
  };
  # ... etc
};
```

---

## Issue 3: Main Branch Outdated

### Problem

The default `main` branch only contains:
- `cursor` (single version)
- `cursor-test`
- `default`

But `pre-release` branch contains **37 versioned packages**.

### Impact

When users run:
```bash
nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
```

It defaults to `main` branch, which doesn't have `cursor-1_7_54`.

### Verification

```bash
# Main branch - limited packages
$ nix flake show github:Distracted-E421/nixos-cursor
└───packages
    └───x86_64-linux
        ├───cursor
        ├───cursor-test
        └───default

# Pre-release branch - full packages  
$ nix flake show github:Distracted-E421/nixos-cursor/pre-release
└───packages
    └───x86_64-linux
        ├───cursor
        ├───cursor-1_6_45
        ├───cursor-1_7_11
        ... (37 total packages)
        ├───cursor-2_0_77
        └───cursor-manager
```

### Suggested Fix

Either:
1. **Merge pre-release into main** when stable
2. **Set pre-release as default branch** temporarily
3. **Document prominently** that users must use `/pre-release` ref

---

## 🎯 Ideal User Experience

### What Users Want

```nix
# flake.nix input
inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor";

# In configuration
home.packages = with inputs.nixos-cursor.packages.${pkgs.system}; [
  cursor           # Latest (currently 2.0.77)
  cursor-2_0_64    # Specific older version
  cursor-1_7_54    # Classic version
  cursor-manager   # GUI launcher
];
```

```bash
# Terminal usage
$ cursor           # Opens 2.0.77
$ cursor-2_0_64    # Opens 2.0.64  
$ cursor-1_7_54    # Opens 1.7.54
$ cursor-manager   # Opens GUI picker

# nix run usage
$ nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54
# Just works!
```

### Current Reality

- ❌ Cannot install multiple versions (path conflicts)
- ❌ Must specify full `packages.x86_64-linux.` path for `nix run`
- ❌ Must remember to use `/pre-release` branch ref
- ⚠️ Only single version works at a time

---

## 📋 Environment Details

```
OS: NixOS 25.11 (Xantusia)
Architecture: x86_64-linux
Nix Version: 2.28+
Integration Method: Direct package import in home.packages
Flake Input: github:Distracted-E421/nixos-cursor/pre-release
```

### Test Configuration

```nix
# flake.nix
{
  inputs.nixos-cursor = {
    url = "github:Distracted-E421/nixos-cursor/pre-release";
  };
  
  outputs = { nixos-cursor, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        home-manager.nixosModules.home-manager
        {
          home-manager.extraSpecialArgs = { inherit inputs; };
        }
      ];
    };
  };
}

# home.nix
{ inputs, pkgs, ... }: {
  home.packages = [
    inputs.nixos-cursor.packages.${pkgs.system}.cursor
    inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_0_64
    # ^ This causes the conflict
  ];
}
```

---

## ✅ What Works

1. **Single version installation** - Installing just `cursor` works perfectly
2. **cursor-manager** - GUI launcher works
3. **S3 URLs with SRI hashes** - No DNS issues (great fix!)
4. **Isolated user-data directories** - Each version has separate config
5. **Direct nix run with full path** - `nix run ...#packages.x86_64-linux.cursor-1_7_54`

---

## 🔧 Proposed Solution Summary

| Issue | Fix | Priority |
|-------|-----|----------|
| Path conflicts | Version-specific binary names (`cursor-2_0_77`) | **Critical** |
| Missing apps | Add `apps` flake output | Medium |
| Main branch outdated | Merge pre-release or document | Low |

### Minimal Fix for Path Conflicts

The core issue is that all packages produce `/bin/cursor`. Each versioned package should instead produce:

```
cursor          → /bin/cursor (alias to latest)
cursor-2_0_77   → /bin/cursor-2_0_77
cursor-2_0_64   → /bin/cursor-2_0_64
cursor-1_7_54   → /bin/cursor-1_7_54
cursor-manager  → /bin/cursor-manager
```

This allows concurrent installation of all versions.

---

## 📚 Additional Feedback

### Documentation Suggestions

1. Add a **Quick Start** section showing the recommended flake input:
   ```nix
   inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/pre-release";
   ```

2. Document the **Home Manager integration** pattern:
   ```nix
   { inputs, pkgs, ... }: {
     home.packages = [
       inputs.nixos-cursor.packages.${pkgs.system}.cursor
     ];
   }
   ```

3. Clarify **extraSpecialArgs requirement** for passing `inputs`:
   ```nix
   home-manager.extraSpecialArgs = { inherit inputs; };
   ```

### Feature Suggestions

1. **Default package alias** - `default` should point to latest stable
2. **Version groups** - `cursor-latest-1_x`, `cursor-latest-2_x` for "latest in major version"
3. **Health check command** - `cursor-check` to verify installation

---

## 🙏 Thanks

The S3 URL migration and SRI hashes are a **huge improvement** - the DNS issues with `downloader.cursor.sh` were painful. The multi-version concept is exactly what power users need. These fixes will make it production-ready!

---

*Report generated during real-world integration testing on NixOS 25.11 homelab*
