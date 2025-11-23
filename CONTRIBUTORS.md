# Contributing to nixos-cursor

Thank you for your interest in contributing to nixos-cursor! This guide explains how to contribute to the project.

---

## 🌿 Understanding the Branch Structure

This project uses a **public/private branching strategy**:

- **`main`** (public) - Stable releases
- **`pre-release`** (public) - Release candidates
- **`dev`** (private) - Active development (you won't see this)

As a contributor, you'll primarily interact with **`main`** and **`pre-release`**.

---

## 🚀 Getting Started

### 1. Fork the Repository

```bash
# Fork on GitHub, then clone your fork
git clone git@github.com:YOUR_USERNAME/nixos-cursor.git
cd nixos-cursor
```

### 2. Set Up Upstream

```bash
# Add upstream remote
git remote add upstream git@github.com:Distracted-E421/nixos-cursor.git

# Fetch branches
git fetch upstream
```

### 3. Create a Feature Branch

```bash
# Create branch from main
git checkout main
git pull upstream main
git checkout -b feature/your-feature-name
```

---

## 💻 Making Changes

### Code Changes

1. **Make your changes** to the codebase
2. **Test locally**:
   ```bash
   nix flake check
   nix build .#cursor
   ```
3. **Commit with conventional commits**:
   ```bash
   git add .
   git commit -m "feat: Add support for X"
   # OR
   git commit -m "fix: Resolve issue with Y"
   ```

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation only
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Maintenance tasks

---

## 📝 Documentation Changes

If you're improving documentation:

```bash
# Edit docs
vim README.md
vim cursor/README.md

# Commit
git commit -m "docs: Improve installation instructions"
```

---

## 🧪 Testing

Before submitting a PR, ensure:

1. **Nix flake validation passes**:
   ```bash
   nix flake check
   ```

2. **Package builds successfully**:
   ```bash
   nix build .#cursor
   ./result/bin/cursor --version
   ```

3. **Examples work** (if applicable):
   ```bash
   cd examples/basic-flake
   nix build
   ```

---

## 📤 Submitting a Pull Request

### 1. Push to Your Fork

```bash
git push origin feature/your-feature-name
```

### 2. Create Pull Request on GitHub

- **Base branch**: `main` (for most contributions)
- **Compare branch**: `feature/your-feature-name`
- **Title**: Clear, descriptive summary
- **Description**: 
  - What does this PR do?
  - Why is this change needed?
  - How was it tested?

### 3. PR Checklist

- [ ] Code follows existing style
- [ ] `nix flake check` passes
- [ ] Package builds successfully
- [ ] Documentation updated (if needed)
- [ ] No private content included (see below)
- [ ] Commit messages follow conventions

---

## 🔐 What NOT to Include

**Do NOT include** in your PR:

- ❌ `.cursor/chat-history/` - Development conversations
- ❌ `.cursor/maxim.json`, `gorky.json` - Personal agent configs
- ❌ Personal email addresses (use generic in commits)
- ❌ Absolute file paths (use relative: `./file.nix` not `/home/user/file.nix`)
- ❌ API keys, tokens, or secrets

**OK to include**:

- ✅ `.cursor/rules/` - Useful AI agent rules
- ✅ `.cursor/hooks/` - Automation scripts
- ✅ Code improvements
- ✅ Documentation improvements

---

## 🎨 Code Style

### Nix

- Use 2-space indentation
- Follow [nixpkgs style guide](https://nixos.org/manual/nixpkgs/stable/#chap-conventions)
- Run formatter: `nix fmt`

### Shell Scripts

- Use `#!/usr/bin/env bash`
- Include `set -euo pipefail`
- Add comments for complex logic
- Make scripts executable: `chmod +x script.sh`

### Markdown

- Use headers consistently
- Include code examples in triple backticks
- Link to related docs with relative paths

---

## 🤝 Review Process

1. **Automated checks** will run via GitHub Actions:
   - Nix flake validation
   - Build tests
   - Linting

2. **Maintainer review**:
   - Code quality
   - Testing coverage
   - Documentation completeness

3. **Feedback**:
   - Address review comments
   - Push updates to same branch
   - PR will auto-update

4. **Merge**:
   - Maintainer will merge once approved
   - Your contribution will appear in next release!

---

## 🐛 Reporting Issues

### Bug Reports

Create an issue with:
- **Title**: Clear, concise description
- **Environment**: NixOS version, system (x86_64/aarch64)
- **Steps to reproduce**
- **Expected behavior**
- **Actual behavior**
- **Logs/errors** (if applicable)

### Feature Requests

Create an issue with:
- **Title**: Feature description
- **Use case**: Why is this needed?
- **Proposed solution**: How could it work?
- **Alternatives**: Other approaches considered

---

## 🎓 Understanding .cursor/

The `.cursor/` directory contains:

- **Public** (OK in PRs):
  - `.cursor/rules/` - AI agent behavior rules
  - `.cursor/hooks/` - Automation scripts
  - `.cursor/README.md` - Documentation

- **Private** (NOT in PRs):
  - `.cursor/chat-history/` - Development logs
  - `.cursor/docs/` - Internal guides
  - Agent configs (`maxim.json`, `gorky.json`)

See [.cursor/README.md](.cursor/README.md) for details.

---

## 📚 Additional Resources

- [BRANCHING_STRATEGY.md](BRANCHING_STRATEGY.md) - Full branching workflow
- [RELEASE_STRATEGY.md](RELEASE_STRATEGY.md) - Versioning and releases
- [README.md](README.md) - Project overview
- [NixOS Manual](https://nixos.org/manual/nixos/stable/) - NixOS documentation

---

## 🙏 Thank You!

Your contributions help make Cursor better for the NixOS community. We appreciate:

- Bug reports and fixes
- Documentation improvements
- Feature suggestions and implementations
- Testing and feedback
- Helping other users

---

## 📧 Getting Help

- **GitHub Issues**: Ask questions, report bugs
- **GitHub Discussions**: General discussions
- **NixOS Discourse**: Community support

---

**Maintainer**: e421 (distracted.e421@gmail.com)  
**Status**: Actively maintained  
**Last Updated**: 2025-11-23
