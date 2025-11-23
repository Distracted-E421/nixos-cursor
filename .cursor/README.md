# .cursor/ Directory

This directory contains **Cursor IDE configuration and automation** for the nixos-cursor project.

---

## 📁 Directory Structure

```
.cursor/
├── chat-history/          # PRIVATE (dev branch only)
│   └── *.md               # Development conversation logs
├── docs/                  # PRIVATE (dev branch only)
│   └── *.md               # Internal integration guides
├── hooks/                 # PUBLIC (transferable to users)
│   ├── *.sh               # Git hooks and automation scripts
│   └── README.md          # Hook documentation
├── rules/                 # PUBLIC (transferable to users)
│   ├── *.mdc              # Cursor AI agent rules
│   └── README.md          # Rule explanations
├── maxim.json             # PRIVATE (dev only - Maxim agent config)
├── gorky.json             # PRIVATE (dev only - Gorky agent config)
└── README.md              # This file
```

---

## 🌿 Branch Visibility

### `dev` Branch (Private)

On the **dev** branch, this entire `.cursor/` directory is tracked including:
- ✅ All subdirectories
- ✅ Agent configurations (`maxim.json`, `gorky.json`)
- ✅ Chat history (sanitized)
- ✅ Internal documentation

### `pre-release` and `main` Branches (Public)

On **public** branches, only transferable content is included:
- ✅ `.cursor/rules/` - AI agent rules (useful to users)
- ✅ `.cursor/hooks/` - Automation scripts (useful to users)
- ❌ `.cursor/chat-history/` - Development logs (excluded)
- ❌ `.cursor/docs/` - Internal guides (excluded)
- ❌ `.cursor/maxim.json`, `gorky.json` - Agent configs (excluded)

---

## 📖 What Each Directory Contains

### `chat-history/` (Private)

Development conversation logs exported from Cursor IDE. These contain:
- Technical discussions and debugging
- Feature planning and implementation notes
- Problem-solving approaches

**Why Private**: May contain personal information, unpolished thoughts, or sensitive debugging details.

---

### `docs/` (Private or Selective)

Internal documentation about Cursor integration:
- `MCP_SETUP_AND_OPTIMIZATION_GUIDE.md`
- `PLAYWRIGHT_INTEGRATION_SUMMARY.md`
- `CURSOR_RULES_INTEGRATION_SUCCESS.md`

**Why Private**: Specific to development workflow, may contain outdated or incomplete information.

**Exception**: Some guides (like Playwright reference) may be useful publicly and can be moved to main docs.

---

### `hooks/` (Public - Transferable)

Git hooks and automation scripts that enhance the development workflow:
- `analyze-query-scope.sh` - Analyzes task complexity
- `browser-test-after-deploy.sh` - Web service testing
- `safety-command-check.sh` - Validates dangerous commands
- `track-edits.sh` - Monitors file changes

**Why Public**: These scripts are useful to contributors and users who want to adopt similar workflows.

**Usage**:
```bash
# Enable hooks
cp .cursor/hooks/* .git/hooks/
chmod +x .git/hooks/*
```

---

### `rules/` (Public - Transferable)

Cursor AI agent behavioral rules (`.mdc` files):
- `d2-diagram-design-standards.mdc` - Diagram generation guidelines
- `documentation-management.mdc` - Doc consistency rules
- `safety-guardrails.mdc` - Prevent destructive operations
- `token-maximization-planning.mdc` - Efficient AI workflows
- And more...

**Why Public**: These rules define best practices that benefit other Cursor users working on NixOS projects.

**Usage**:
```bash
# Reference in your Cursor settings
"cursor.rules": [
  ".cursor/rules/*.mdc"
]
```

---

### `maxim.json` and `gorky.json` (Private)

Custom AI agent configurations for Cursor IDE:
- **Maxim**: Complex reasoning, implementation, NixOS expertise
- **Gorky**: Testing, debugging, visual analysis

**Why Private**: Specific to personal workflow, contains agent-specific settings.

---

## 🎯 For Users

If you're using this project, the **public** branches (`main`, `pre-release`) contain:
- `.cursor/rules/` - Adopt these rules for your own Cursor projects
- `.cursor/hooks/` - Use these automation scripts to enhance your workflow

You **will NOT** see:
- Development chat history
- Agent configurations
- Internal documentation

---

## 🔧 For Contributors

If you're contributing to nixos-cursor:

1. **Clone the repository**:
   ```bash
   git clone git@github.com:Distracted-E421/nixos-cursor.git
   ```

2. **Work on public branches** (`main`, `pre-release`):
   - `.cursor/` may be empty or contain only `rules/` and `hooks/`

3. **Customize for yourself**:
   - Create your own `.cursor/rules/` with project-specific guidelines
   - Adopt hooks from `.cursor/hooks/` if useful

4. **Submit PRs** to public branches:
   - PRs should not include `.cursor/chat-history/` or agent configs
   - You can propose improvements to public rules/hooks

---

## 🚀 For Maintainers (dev branch)

When working on the `dev` branch:

1. **All `.cursor/` content is tracked**:
   - Chat history, docs, agent configs, everything

2. **Before releasing** (dev → pre-release):
   - Use `./scripts/prepare-public-branch.sh`
   - This automatically removes private artifacts
   - Validates no sensitive content leaked

3. **Syncing back** (main → dev):
   - `git merge main` on dev branch
   - Keep dev's `.gitignore-dev` to continue tracking `.cursor/`

---

## 📚 References

- [BRANCHING_STRATEGY.md](../BRANCHING_STRATEGY.md) - Full workflow documentation
- [.cursor/rules/README.md](.cursor/rules/README.md) - Detailed rule explanations
- [.cursor/hooks/README.md](.cursor/hooks/README.md) - Hook usage guide

---

**Status**: This directory structure is part of the nixos-cursor development workflow.  
**Last Updated**: 2025-11-23
