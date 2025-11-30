# Development Scripts

This directory contains **automation scripts** for managing the nixos-cursor development workflow, including branch management, release preparation, validation, and storage management.

---

## 🏗️ Multi-Language Architecture

We use **the right tool for the job**, not just bash for everything:

| Directory | Language | Best For |
|-----------|----------|----------|
| `nu/` | [Nushell](https://www.nushell.sh/) | Data manipulation, structured output |
| `python/` | Python 3 | HTTP operations, complex logic |
| `bash/` (root) | Bash | Simple wrappers, git operations |
| `lib/` | Shared | Common utilities |

### Why Not Just Bash?

| Issue | Bash | Modern Alternative |
|-------|------|-------------------|
| JSON handling | Requires `jq` | Native (Nushell, Python) |
| Arithmetic | `$((a+b))` or `bc` | Native operators |
| Data types | Strings only | Tables, records, lists |
| Error handling | `set -e` (fragile) | Result types |

### Getting Started

```bash
# Enter development shell with all tools
nix develop

# Or run specific scripts directly
nix develop --command nu scripts/nu/disk-usage.nu
nix develop --command python scripts/python/compute_hashes.py --help
```

See [docs/internal/SCRIPTING_ARCHITECTURE.md](../docs/internal/SCRIPTING_ARCHITECTURE.md) for the full rationale.

---

## 📁 Directory Structure

```
scripts/
├── nu/                      # Nushell scripts (Tier 1)
│   ├── disk-usage.nu        # Nix store analysis
│   ├── gc-helper.nu         # Garbage collection
│   ├── validate-urls.nu     # URL validation
│   └── test-versions.nu     # Version testing
├── python/                  # Python scripts (Tier 1)
│   └── compute_hashes.py    # URL hash computation
├── elixir/                  # Elixir projects (Tier 1)
│   └── cursor_tracker/      # OTP app for data tracking
├── lib/                     # Shared utilities
│   └── colors.nu            # Nushell color helpers
├── legacy/                  # Deprecated bash scripts
│   ├── disk-usage.sh
│   ├── gc-helper.sh
│   ├── validate-urls.sh
│   └── all-versions-test.sh
├── storage/                 # Disk/GC management
├── validation/              # URL/hash validation
├── data-tracking/           # User data tracking
├── prepare-public-branch.sh # Release automation
├── release-to-main.sh       # Release automation
└── validate-public-branch.sh # Pre-release validation
```

---

## �� Available Scripts

### `prepare-public-branch.sh`

**Purpose**: Automate the transition from `dev` branch to `pre-release` branch.

**Usage**:
```bash
./scripts/prepare-public-branch.sh v2.1.20-rc1
```

**What it does**:
1. ✅ Switches to `pre-release` branch (creates if needed)
2. ✅ Merges `dev` branch changes
3. ✅ Removes private `.cursor/` artifacts:
   - `.cursor/chat-history/`
   - `.cursor/maxim.json`, `.cursor/gorky.json`
   - Internal development docs
4. ✅ Validates no sensitive content leaked
5. ✅ Commits changes
6. ✅ Tags as release candidate

**Requirements**:
- No uncommitted changes on `dev` branch
- Version tag in format `vX.Y.Z-rcN`

**Output**:
- Pre-release branch ready to push to GitHub
- Git tag created for release candidate

---

### `release-to-main.sh`

**Purpose**: Automate the transition from `pre-release` to `main` branch.

**Usage**:
```bash
./scripts/release-to-main.sh v2.1.20
```

**What it does**:
1. ✅ Switches to `main` branch
2. ✅ Confirms release with user
3. ✅ Merges `pre-release` branch
4. ✅ Tags as stable release
5. ✅ Runs tests (`nix flake check`)
6. ✅ Builds package to verify
7. ✅ Provides instructions for pushing

**Requirements**:
- No uncommitted changes
- Version tag in format `vX.Y.Z` (no `-rc` suffix)
- User confirmation required

**Output**:
- Main branch ready for stable release
- Git tag created for stable version

---

### `validate-public-branch.sh`

**Purpose**: Validate that a public branch contains no private content.

**Usage**:
```bash
./scripts/validate-public-branch.sh pre-release
./scripts/validate-public-branch.sh main
```

**What it checks**:
1. 🔍 No private `.cursor/` files:
   - `.cursor/chat-history/`
   - `.cursor/maxim.json`, `.cursor/gorky.json`
   - Internal development docs
2. 🔍 No personal email addresses (except in LICENSE)
3. 🔍 No absolute paths (`/home/e421/`)
4. 🔍 No API keys or secrets
5. 🔍 TODOs in critical files (warning only)
6. 🔍 `nix flake check` passes
7. 🔍 Required documentation present
8. 🔍 No large files (>1MB)

**Requirements**:
- Branch must exist

**Output**:
- Exit code 0 if validation passes
- Exit code 1 if issues found
- Detailed report of any problems

---

## 🔄 Typical Workflow

### Phase 1: Development (on `dev`)

```bash
# Work on dev branch normally
git checkout dev
# Make changes, commit frequently
git add .
git commit -m "feat: Implement new feature"
```

---

### Phase 2: Prepare Release Candidate

```bash
# From dev branch, prepare pre-release
./scripts/prepare-public-branch.sh v2.1.20-rc1

# Review what will be public
git diff dev..pre-release

# Validate before pushing
./scripts/validate-public-branch.sh pre-release

# If validation passes, push to GitHub
git push origin pre-release
git push origin v2.1.20-rc1
```

---

### Phase 3: Community Testing

```bash
# Monitor GitHub issues, test on multiple devices
# Fix bugs on dev branch:
git checkout dev
# ... make fixes ...
git commit -m "fix: Resolve issue #123"

# Re-release as rc2:
./scripts/prepare-public-branch.sh v2.1.20-rc2
git push origin pre-release --force-with-lease
git push origin v2.1.20-rc2
```

---

### Phase 4: Stable Release

```bash
# After successful testing, release to main
./scripts/release-to-main.sh v2.1.20

# Push stable release
git push origin main
git push origin v2.1.20

# Create GitHub Release manually or via workflow
```

---

### Phase 5: Sync Back to Dev

```bash
# Merge stable changes back to dev
git checkout dev
git merge main --no-commit
# Keep dev's .gitignore-dev
cp .gitignore-dev .gitignore
git add .gitignore
git commit -m "chore: Sync main v2.1.20 into dev"
```

---

## 🔐 Security Validation

### What's Checked

**Private Content**:
- `.cursor/chat-history/` - Development conversations
- `.cursor/maxim.json`, `gorky.json` - Agent configs
- `.cursor/docs/CURSOR_*` - Internal integration docs

**Sensitive Patterns**:
- Personal email addresses
- Absolute file paths
- API keys/tokens
- Secrets or passwords

**Quality Checks**:
- Nix flake validation
- Required documentation present
- No excessively large files

### Running Validation Manually

```bash
# Before pushing to public branch
git checkout pre-release
./scripts/validate-public-branch.sh pre-release

# If issues found, fix them:
git checkout dev
# ... fix issues ...
./scripts/prepare-public-branch.sh v2.1.20-rc1  # Re-run
```

---

## 🛠️ Script Maintenance

### Customizing for Your Project

These scripts can be adapted for other NixOS projects:

1. **Change branch names**:
   - Edit `SOURCE_BRANCH` and `TARGET_BRANCH` variables
   - Update `.gitignore` patterns

2. **Adjust private content patterns**:
   - Modify `PRIVATE_CURSOR_FILES` array in `validate-public-branch.sh`
   - Update validation patterns for your specific needs

3. **Add custom checks**:
   - Extend `validate-public-branch.sh` with project-specific validation
   - Add pre-release tests in `release-to-main.sh`

### Testing Scripts

```bash
# Dry-run mode (manual verification)
git checkout dev
git branch test-pre-release
git checkout test-pre-release
# ... manually run script commands one by one ...

# Delete test branch when done
git checkout dev
git branch -D test-pre-release
```

---

## 📚 References

- [BRANCHING_STRATEGY.md](../BRANCHING_STRATEGY.md) - Full branching workflow
- [GitHub Actions Workflows](../.github/workflows/) - Automated validation
- [.gitignore](../.gitignore) - Public branch exclusions
- [.gitignore-dev](../.gitignore-dev) - Dev branch inclusions

---

## ⚠️ Common Issues

### "Uncommitted changes detected"

**Solution**: Commit or stash changes before running scripts.

```bash
git status
git add .
git commit -m "chore: Save work in progress"
```

---

### "Merge conflicts detected"

**Solution**: Resolve conflicts manually, then re-run script.

```bash
git checkout pre-release
git merge dev
# Resolve conflicts
git add .
git commit -m "chore: Merge dev into pre-release"
```

---

### "Validation failed: Found personal email"

**Solution**: Remove personal email from tracked files.

```bash
# Find offending files
grep -r "your-email@example.com" . --exclude-dir=.git

# Edit files to remove email
# Then re-run prepare script
```

---

### "Version tag doesn't match expected format"

**Solution**: Use correct version format.

```bash
# Correct formats:
./scripts/prepare-public-branch.sh v2.1.20-rc1  # Release candidate
./scripts/release-to-main.sh v2.1.20            # Stable release

# Incorrect formats:
./scripts/prepare-public-branch.sh 2.1.20       # Missing 'v' prefix
./scripts/release-to-main.sh v2.1.20-rc1        # Stable shouldn't have '-rc'
```

---

**Status**: Production-ready automation scripts  
**Last Updated**: 2025-11-23
