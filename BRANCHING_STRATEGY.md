# Branching Strategy - nixos-cursor

**Repository**: `git@github.com:Distracted-E421/nixos-cursor.git`  
**Last Updated**: 2025-11-23

---

## 🌿 Branch Overview

### `dev` (Private Development Branch)

**Purpose**: Active development, testing, debugging, and iteration.

**Visibility**: Private (not pushed to public remote)

**Contains**:
- ✅ `.cursor/` folder with rules, hooks, agents, documentation
- ✅ Development chat history (sanitized)
- ✅ Work-in-progress features
- ✅ Experimental changes
- ✅ Development scripts and utilities
- ✅ Personal notes and TODOs

**Git Configuration**:
```bash
# This branch uses .gitignore-dev (more permissive)
git checkout dev
cp .gitignore-dev .gitignore
```

**DO NOT** push this branch to public GitHub.

---

### `pre-release` (Public Testing Branch)

**Purpose**: Release candidates for community testing before stable release.

**Visibility**: Public (pushed to GitHub)

**Contains**:
- ✅ Feature-complete code
- ✅ Cleaned documentation (no personal notes)
- ❌ **NO `.cursor/` directory at all** (entire directory excluded)
- ❌ Work-in-progress features

**Git Configuration**:
```bash
# This branch uses .gitignore-public (restrictive)
git checkout pre-release
# .gitignore excludes entire .cursor/ directory
```

**Version Pattern**: `v2.1.20-rc1`, `v2.1.20-rc2`, etc.

---

### `main` (Public Stable Branch)

**Purpose**: Stable, production-ready releases.

**Visibility**: Public (pushed to GitHub)

**Contains**:
- ✅ Tested, stable code
- ✅ Complete, polished documentation
- ❌ **NO `.cursor/` directory at all** (entire directory excluded)
- ❌ Any development artifacts
- ❌ Personal configuration

**Git Configuration**:
```bash
# This branch uses .gitignore-public (restrictive)
git checkout main
# .gitignore excludes entire .cursor/ directory
```

**Version Pattern**: `v2.1.20`, `v2.2.0`, etc.

---

## 🔄 Workflow

### Phase 1: Development (dev branch)

```bash
# Work on dev branch
git checkout dev

# Make changes, test, iterate
# All .cursor/ contents are tracked

# Commit frequently
git add .
git commit -m "feat: Implement new feature"

# Keep dev branch local (do not push)
```

---

### Phase 2: Prepare Pre-Release (dev → pre-release)

When ready to share with testers:

```bash
# Use the cleanup script
./scripts/prepare-public-branch.sh pre-release

# This script:
# 1. Checks out pre-release branch
# 2. Merges dev (selective)
# 3. Removes .cursor/chat-history/
# 4. Removes agent configs (maxim.json, gorky.json)
# 5. Cleans personal notes from docs
# 6. Tags as release candidate

# Review changes
git diff main..pre-release

# Push to GitHub
git push origin pre-release
git push origin v2.1.20-rc1  # Release candidate tag
```

---

### Phase 3: Release to Main (pre-release → main)

After testing confirms stability:

```bash
# Use the release script
./scripts/release-to-main.sh v2.1.20

# This script:
# 1. Checks out main
# 2. Merges pre-release
# 3. Tags with version
# 4. Pushes to GitHub

# Or manually:
git checkout main
git merge pre-release
git tag -a v2.1.20 -m "Release v2.1.20"
git push origin main
git push origin v2.1.20
```

---

### Phase 4: Continue Development (main → dev)

Sync stable changes back to dev:

```bash
git checkout dev
git merge main --no-commit
# Resolve any conflicts (likely .gitignore)
# Keep dev's .gitignore-dev as .gitignore
git commit -m "chore: Sync main v2.1.20 into dev"
```

---

## 📁 What Goes Where?

### `.cursor/` Folder Organization

```
.cursor/
├── chat-history/          # PRIVATE (dev only)
│   ├── *.md               # Development conversations
│   └── README.md          # Optional: explain what this is
├── docs/                  # PRIVATE (dev only, or selective public)
│   ├── *.md               # Internal guides
│   └── PLAYWRIGHT_*.md    # May be useful publicly
├── hooks/                 # PUBLIC (transferable)
│   ├── *.sh               # Automation scripts
│   └── README.md          # Usage guide
├── rules/                 # PUBLIC (transferable)
│   ├── *.mdc              # Cursor rules
│   └── README.md          # Explanation of rules
├── maxim.json             # PRIVATE (dev only)
├── gorky.json             # PRIVATE (dev only)
└── README.md              # PUBLIC (explains .cursor structure)
```

### Gitignore Strategy

**On `dev` branch** (use `.gitignore-dev`):
- Track `.cursor/rules/` ✅
- Track `.cursor/hooks/` ✅
- Track `.cursor/docs/` ✅ (for internal use)
- Track `.cursor/chat-history/` ✅ (sanitized)
- Track agent configs ✅

**On `pre-release` and `main`** (use `.gitignore-public`):
- Exclude entire `.cursor/` directory ❌
- No `.cursor/` content whatsoever in public branches

---

## 🤖 Automation with GitHub Actions

### Workflow 1: Validate Pre-Release

**.github/workflows/validate-pre-release.yml**

Runs on `pre-release` branch:
- ✅ `nix flake check`
- ✅ Build Cursor package
- ✅ Check documentation links
- ✅ Verify no private artifacts leaked

### Workflow 2: Build and Test

**.github/workflows/build.yml**

Runs on all branches:
- ✅ Build for x86_64-linux and aarch64-linux
- ✅ Run example configurations
- ✅ Test MCP server integration
- ✅ Generate build artifacts

### Workflow 3: Release to Main

**.github/workflows/release.yml**

Triggered on tag push (`v*`):
- ✅ Build release artifacts
- ✅ Generate changelog from commits
- ✅ Create GitHub Release
- ✅ Attach build outputs

---

## 🔐 Security Considerations

### What NOT to Commit

**Never commit**:
- ❌ Personal API keys or tokens
- ❌ Private SSH keys
- ❌ Passwords or secrets
- ❌ Personal email addresses (use generic in public)
- ❌ Machine-specific paths (use relative paths)
- ❌ Unpolished personal notes

### Sanitizing Chat History

If sharing `.cursor/chat-history/` on dev:
1. Remove personal information (emails, IP addresses)
2. Remove sensitive debugging details
3. Keep technical discussions and solutions
4. Use `./scripts/sanitize-chat-history.sh` to automate

---

## 📊 Branch Status

### Current State

```
dev (local only)
├── All .cursor/ content tracked
├── Active development
└── Latest features

pre-release (public)
├── Release candidates
├── Cleaned .cursor/ (rules/hooks only)
└── Ready for community testing

main (public)
├── Stable releases
├── Polished documentation
└── Production-ready
```

---

## 🛠️ Helper Scripts

### `scripts/prepare-public-branch.sh`

Automates dev → pre-release transition:
- Merges code selectively
- Removes private artifacts
- Tags release candidate
- Validates cleanliness

### `scripts/release-to-main.sh`

Automates pre-release → main:
- Merges tested code
- Tags stable version
- Updates changelog
- Pushes to GitHub

### `scripts/sanitize-chat-history.sh`

Cleans development chat logs:
- Removes personal info
- Keeps technical content
- Generates sanitized exports

### `scripts/validate-public-branch.sh`

Checks for leaked private content:
- Scans for agent configs
- Checks for personal paths
- Validates documentation
- Reports issues

---

## 📝 Commit Message Conventions

Use conventional commits for clarity:

```
feat: Add new MCP server integration
fix: Resolve Playwright browser path issue
docs: Update installation guide
chore: Update Cursor to v0.43.0
test: Add integration tests for pre-release
refactor: Simplify wrapper script logic
```

---

## 🔄 Merge Strategy

### dev → pre-release

Use **selective merge** or **cherry-pick**:
```bash
git checkout pre-release
git merge dev --no-commit
# Remove private files
git reset HEAD .cursor/chat-history/
git reset HEAD .cursor/maxim.json .cursor/gorky.json
git checkout -- .cursor/chat-history/ .cursor/maxim.json .cursor/gorky.json
git commit -m "chore: Prepare v2.1.20-rc1 from dev"
```

### pre-release → main

Use **standard merge**:
```bash
git checkout main
git merge pre-release
git tag -a v2.1.20 -m "Release v2.1.20: Summary of changes"
```

### main → dev (sync back)

Use **merge with conflict resolution**:
```bash
git checkout dev
git merge main --no-commit
# Keep dev's .gitignore-dev
cp .gitignore-dev .gitignore
git add .gitignore
git commit -m "chore: Sync main v2.1.20 into dev"
```

---

## 🎯 Checklist for Public Release

Before pushing to `pre-release` or `main`:

**Code Quality**:
- [ ] `nix flake check` passes
- [ ] All examples build successfully
- [ ] No hard-coded personal paths
- [ ] No TODO/FIXME in critical code

**Documentation**:
- [ ] README.md accurate and complete
- [ ] CHANGELOG.md updated
- [ ] Installation guide tested
- [ ] Examples validated

**Privacy**:
- [ ] No `.cursor/chat-history/` included
- [ ] No agent configs (`maxim.json`, `gorky.json`)
- [ ] No personal email addresses in commits
- [ ] No API keys or tokens

**Testing**:
- [ ] Tested on at least 2 machines
- [ ] MCP servers functional
- [ ] Playwright integration working
- [ ] No critical bugs

**Versioning**:
- [ ] Version bumped in appropriate files
- [ ] Git tag created
- [ ] CHANGELOG reflects changes

---

## 📚 References

- [Git Branching Strategies](https://www.atlassian.com/git/tutorials/comparing-workflows)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)

---

**Next Steps**:
1. Set up GitHub Actions workflows
2. Create helper scripts (`prepare-public-branch.sh`, etc.)
3. Test the branching workflow
4. Document for contributors

**Status**: Ready for implementation
