# Rust + Nix Best Practices

**For**: cursor-monitor Rust daemon  
**Goal**: Reproducible, efficient Rust builds in Nix

---

## 🎯 Current Issue

**Problem**: Cargo.lock causes TOML parsing error in `buildRustPackage`

**Error**:
```
[error] toml::parse_key_value_pair: invalid key value separator `=`
```

---

## ✅ Best Practices for Rust in Nix

### Option 1: Use `cargoLock.lockFile` (Recommended)

**When to use**: Standard crates.io dependencies

```nix
rustPlatform.buildRustPackage {
  pname = "cursor-monitor";
  version = "0.1.0";
  
  src = ./.;
  
  cargoLock = {
    lockFile = ./Cargo.lock;
  };
  
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ dbus ];
}
```

**Steps**:
1. Ensure `Cargo.lock` is tracked in git
2. Commit to repository
3. Reference in flake

---

### Option 2: Use `cargoHash` (Simpler)

**When to use**: Don't want to commit `Cargo.lock`

```nix
rustPlatform.buildRustPackage {
  pname = "cursor-monitor";
  version = "0.1.0";
  
  src = ./.;
  
  # Set to empty hash first
  cargoHash = "";
  
  # Nix will tell you the correct hash on first build
  # Then replace with: cargoHash = "sha256-ACTUAL_HASH";
}
```

**Steps**:
1. Set `cargoHash = "";`
2. Run `nix build`
3. Copy hash from error message
4. Update `cargoHash` with real value

---

### Option 3: Use `crane` (Advanced)

**When to use**: Complex builds, incremental compilation

```nix
inputs.crane.url = "github:ipetkov/crane";

outputs = { nixpkgs, crane, ... }:
  let
    craneLib = crane.lib.${system};
  in {
    packages.cursor-monitor = craneLib.buildPackage {
      src = ./.;
      cargoArtifacts = craneLib.buildDepsOnly {
        src = ./.;
      };
    };
  };
```

**Benefits**:
- Incremental builds (caches dependencies)
- Better for large projects
- CI/CD friendly

---

### Option 4: Use `crate2nix` (Auto-generation)

**When to use**: Want Nix expressions auto-generated

```bash
# Generate Nix expressions from Cargo.toml
crate2nix generate

# Produces Cargo.nix which can be imported
nix-build -A rootCrate.build
```

---

## 🔧 Fix for cursor-monitor

### Immediate Fix (cargoHash method)

```nix
# nixos/modules/apps/cursor-monitor.nix
{
  cursor-monitor = pkgs.rustPlatform.buildRustPackage {
    pname = "cursor-monitor";
    version = "0.1.0";
    
    src = ./cursor-monitor;
    
    # Use cargoHash instead of cargoLock
    cargoHash = "";  # Build once to get real hash
    
    nativeBuildInputs = with pkgs; [ pkg-config ];
    buildInputs = with pkgs; [ dbus ];
    
    meta = {
      description = "High-performance AI activity monitor for Cursor IDE";
      license = lib.licenses.mit;
    };
  };
}
```

### Steps to Get cargoHash:

```bash
# 1. Update nixos/modules/apps/cursor-monitor.nix with cargoHash = ""
# 2. Try to build
cd nixos
sudo nixos-rebuild dry-build --flake '.#Obsidian'

# 3. Error message will show:
#    "got: sha256-XXXXXXXXXXX"
# 4. Copy that hash
# 5. Update: cargoHash = "sha256-XXXXXXXXXXX";
# 6. Rebuild - should work!
```

---

## 📦 Handling Git Dependencies

**If** `Cargo.toml` has git dependencies:

```nix
cargoLock = {
  lockFile = ./Cargo.lock;
  outputHashes = {
    "some-crate-0.1.0" = "sha256-HASH_HERE";
  };
};
```

**Get hashes**:
1. Set to `lib.fakeHash` initially
2. Build fails with real hash
3. Replace with real hash

---

## 🚀 Development Workflow

### Local Development Shell

```nix
# shell.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    cargo
    rustc
    rust-analyzer
    rustfmt
    clippy
    pkg-config
    dbus
  ];
  
  RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
}
```

**Enter shell**:
```bash
cd nixos/modules/apps/cursor-monitor
nix-shell
cargo build
cargo test
```

---

## 🔄 Keeping Dependencies Updated

### Update Cargo.lock

```bash
cd nixos/modules/apps/cursor-monitor
nix-shell
cargo update
git add Cargo.lock
git commit -m "chore: update Rust dependencies"
```

### Update cargoHash

```bash
# After updating Cargo.lock, recalculate hash
nix-prefetch '{ sha256 }: (pkgs.rustPlatform.buildRustPackage {
  pname = "cursor-monitor";
  version = "0.1.0";
  src = ./cursor-monitor;
  cargoHash = sha256;
  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = [ pkgs.dbus ];
}).cargoDeps'
```

---

## 📋 Checklist for Rust in Nix

- [ ] `Cargo.toml` has correct metadata (name, version, license)
- [ ] `Cargo.lock` committed to git (for `cargoLock.lockFile`)
- [ ] OR `cargoHash` set to actual hash (for `cargoHash` method)
- [ ] `nativeBuildInputs` includes build-time deps (`pkg-config`, etc.)
- [ ] `buildInputs` includes runtime deps (libraries)
- [ ] `meta` section filled out (description, license, etc.)
- [ ] Development `shell.nix` for local work

---

## 🎯 Recommendation for cursor-monitor

**Use cargoHash method**:

1. ✅ Simpler (no Cargo.lock tracking issues)
2. ✅ Works with flakes
3. ✅ Standard nixpkgs approach
4. ✅ Easy to update (just rebuild to get new hash)

**Implementation**:
```nix
cargoHash = "";  # Build to get hash
# Then: cargoHash = "sha256-ACTUAL_HASH_FROM_BUILD_ERROR";
```

---

## 📚 Resources

- [Nixpkgs Rust Manual](https://ryantm.github.io/nixpkgs/languages-frameworks/rust/)
- [crane](https://github.com/ipetkov/crane) - Advanced Rust builds
- [crate2nix](https://github.com/nix-community/crate2nix) - Auto-generation
- [rust-overlay](https://github.com/oxalica/rust-overlay) - Latest Rust versions

---

**Next Step**: Let's get the actual `cargoHash` and enable the Rust monitor!
