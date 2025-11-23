# Quick Reference - Branching Workflow

**One-page cheat sheet** for nixos-cursor development workflow.

---

## 📊 Branch Structure

```
dev (private)
 ├─ All .cursor/ content tracked
 ├─ Development work
 └─ NOT pushed to GitHub
     ↓
     ↓ ./scripts/prepare-public-branch.sh v2.1.20-rc1
     ↓
pre-release (public)
 ├─ .cursor/ partially tracked (rules/hooks only)
 ├─ Release candidates
 └─ Pushed to GitHub for testing
     ↓
     ↓ ./scripts/release-to-main.sh v2.1.20
     ↓
main (public)
 ├─ Stable releases
 ├─ Production-ready
 └─ Pushed to GitHub
```

---

## 🚀 Common Commands

### Development (dev branch)

```bash
# Work normally
git checkout dev
git add .
git commit -m "feat: Add feature"

# Keep dev branch local (DON'T PUSH)
```

---

### Prepare Release Candidate

```bash
# From dev branch
./scripts/prepare-public-branch.sh v2.1.20-rc1

# Validate
./scripts/validate-public-branch.sh pre-release

# Push to GitHub
git push origin pre-release
git push origin v2.1.20-rc1
```

---

### Release to Main

```bash
# After testing
./scripts/release-to-main.sh v2.1.20

# Push to GitHub
git push origin main
git push origin v2.1.20
```

---

### Sync Back to Dev

```bash
git checkout dev
git merge main --no-commit
cp .gitignore-dev .gitignore
git add .gitignore
git commit -m "chore: Sync main v2.1.20 into dev"
```

---

## 📁 What Goes Where?

| Content | dev | pre-release | main |
|---------|-----|-------------|------|
| Code | ✅ | ✅ | ✅ |
| Documentation | ✅ | ✅ | ✅ |
| `.cursor/rules/` | ✅ | ✅ | ✅ |
| `.cursor/hooks/` | ✅ | ✅ | ✅ |
| `.cursor/chat-history/` | ✅ | ❌ | ❌ |
| `.cursor/docs/` | ✅ | ❌ | ❌ |
| `maxim.json`, `gorky.json` | ✅ | ❌ | ❌ |

---

## 🔐 Validation Checks

Before pushing to public branches:

```bash
./scripts/validate-public-branch.sh pre-release
```

**Checks**:
- ❌ No `.cursor/chat-history/`
- ❌ No agent configs (`maxim.json`, `gorky.json`)
- ❌ No personal email (except LICENSE)
- ❌ No absolute paths (`/home/e421/`)
- ❌ No API keys or secrets
- ✅ `nix flake check` passes
- ✅ Required docs present

---

## 🐛 Common Issues

| Problem | Solution |
|---------|----------|
| Uncommitted changes | `git add . && git commit -m "msg"` |
| Wrong `.gitignore` | `cp .gitignore-dev .gitignore` (on dev) |
| Merge conflicts | Resolve manually, then re-run script |
| Validation failed | Fix issues, re-run `prepare-public-branch.sh` |

---

## 📚 Full Documentation

- [BRANCHING_STRATEGY.md](BRANCHING_STRATEGY.md) - Complete guide
- [scripts/README.md](scripts/README.md) - Script documentation
- [.cursor/README.md](.cursor/README.md) - .cursor/ structure

---

## 🎯 Version Format

**Release Candidates**: `v2.1.20-rc1`, `v2.1.20-rc2`  
**Stable Releases**: `v2.1.20`, `v2.2.0`

---

**Last Updated**: 2025-11-23
