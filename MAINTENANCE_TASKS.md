# Maintenance Tasks - nixos-cursor

> **Purpose**: Low-risk maintenance tasks that can be delegated to a lesser model (Gemini 3 Flash)
> **Generated**: 2025-12-19
> **Status**: Ready for background work

---

## 🗓️ Maintenance Log - Jan 2026

### Task 1.1 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Updated README.md with accurate version counts (64+) and latest version (2.3.10). Added cursor-isolation tools to feature list.
**Files Changed**: `README.md`

### Task 1.2 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Added "Safety & Isolation" section to CONTRIBUTING.md documenting cursor-test and backup workflows.
**Files Changed**: `CONTRIBUTING.md`

### Task 2.1 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Staged untracked directories `tools/cursor-tui` and `docs`. Updated .gitignore to exclude `nohup.out` and `*.log`.
**Files Changed**: `.gitignore`, staged `tools/cursor-tui/`, `docs/`

### Task 2.2 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Updated .cursorignore to include log files.
**Files Changed**: `.cursorignore`

### Task 2.3 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Removed local build result symlinks (`result`, `result-*`).
**Files Changed**: Deleted symlinks

### Task 4.2 Completed - 2026-01-12
**Status**: ⚠️ Issues Found
**Summary**: Checked flake.lock freshness.
**Findings**:
- Last update: Nov 22, 2025 (~50 days ago)
**Recommendations**:
- Run `nix flake update` to refresh dependencies (nixpkgs is > 30 days old)
**Files Changed**: None

### Task 6.2 Completed - 2026-01-12
**Status**: ✅ Complete (Partial)
**Summary**: Verified `examples/basic-flake` and `examples/with-mcp`.
**Findings**:
- `examples/basic-flake` passed `nix flake check`.
- `examples/with-mcp` required lockfile update but passed check.
**Files Changed**: `examples/with-mcp/flake.lock` (updated)

### Task 1.3 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Updated `tools/cursor-isolation/README.md` with documentation for `cursor-share-data` and `sync-versions`. Added warnings about data sharing.
**Files Changed**: `tools/cursor-isolation/README.md`

### Task 2.4 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Verified root `cursor-core/` and `cursor-tui/` were stale (missing Cargo.toml) and redundant with `tools/cursor-tui/`. Deleted them.
**Files Changed**: Deleted `cursor-core/`, `cursor-tui/`

### Task 3.1 Completed - 2026-01-12
**Status**: ✅ Complete
**Summary**: Reviewed branch status.
**Findings**:
- `dev` and `feature/npm-security-system` are fully merged into `main` and stale.
- `experimental/darwin-support` has 1 unmerged commit.
- `cursor-docs-0.3.0-pre` is being merged into `pre-release`.
**Recommendations**:
- Safe to delete `dev` and `feature/npm-security-system`.

### Task 3.2 Completed - 2026-01-12
**Status**: ✅ Analysis Complete
**Summary**: Analyzed `pre-release` vs `main`.
**Findings**:
- `pre-release` is significantly ahead of `main` (contains v0.3.0 features).
- Merging would be a major release event.
**Recommendations**:
- Continue stabilizing v0.3.0 on `pre-release`.

---

## 🔧 Recent Fixes Applied

### Fix 1: Invalid JSON in gorky-neon.json
**Date**: 2025-12-19
**Issue**: Extra `}` character causing JSON parse failure
**Location**: `.cursor/agents/gorky-neon.json` at position 5070
**Fix**: Removed duplicate `}` in testing_workflows array closure
**Status**: ✅ Fixed

This could have contributed to agent injection failures where requests were counted but no output was produced. When Cursor's mode system tried to load invalid JSON, it may have failed silently while the request was already counted.

### Investigation: "Requests with No Output"

**Root Cause Analysis**:
1. **Invalid Agent JSON**: `gorky-neon.json` had malformed JSON that would fail to parse
2. **Proxy Streaming Issues**: The cursor-proxy intercepts gRPC streaming but may break the HTTP/2 framing
3. **Version Checksum Mismatch**: The `x-cursor-checksum` header validation fails, causing empty responses

**Recommendations**:
- Always validate agent JSON before use: `python3 -c "import json; json.load(open('file.json'))"`
- Use `cursor-test --env NAME` for isolated testing of injection changes
- Run `cursor-backup quick` before any proxy experiments

---

## 📋 Task Categories

### Priority Legend
- 🟢 **Easy** - Simple, isolated changes with no risk
- 🟡 **Medium** - Requires understanding context but safe
- 🔴 **Complex** - Needs careful attention (save for Claude)

---

## 🗂️ Category 1: Documentation Cleanup

### Task 1.1: Update Root README.md (Completed)
**Status**: ✅ Done

### Task 1.2: Create CONTRIBUTING.md Updates (Completed)
**Status**: ✅ Done

### Task 1.3: Document New Tools in tools/cursor-isolation/README.md (Completed)
**Status**: ✅ Done

---

## 🧹 Category 2: Repository Cleanup

### Task 2.1: Stage Untracked Directories (Completed)
**Status**: ✅ Done

### Task 2.2: Clean Up .cursorignore (Completed)
**Status**: ✅ Done

### Task 2.3: Remove result-* Symlinks (Completed)
**Status**: ✅ Done

### Task 2.4: Clean Up Redundant Root Directories (Completed)
**Status**: ✅ Done

---

## 🌳 Category 3: Branch Management

### Task 3.1: Review Branch Status (Completed)
**Status**: ✅ Done

### Task 3.2: Sync pre-release to main (Completed)
**Status**: ✅ Done

### Task 3.3: Expose New Tools in Flake
**Priority**: 🟡 Medium
**Files**: `flake.nix`

**Analysis**:
- `tools/cursor-tui` and `tools/cursor-agent-tui` exist but aren't in `flake.nix` packages/apps

**Instructions**:
```
1. Add `cursor-tui` package definition to flake.nix (using rustPlatform.buildRustPackage)
2. Add `cursor-agent-tui` package definition
3. Expose as apps: `nix run .#cursor-tui`
```

---

## 📦 Category 4: Nix/Package Cleanup

### Task 4.1: Verify Cursor Versions
**Priority**: 🟡 Medium
**Files**: `cursor-versions.nix`

**Instructions**:
```
For each version in cursor-versions.nix:
1. Verify the URL still works: curl -I <url>
2. Verify hash matches if downloaded
3. Note any 404s or changed URLs
4. DO NOT modify versions - just report status
```

### Task 4.2: Check flake.lock Freshness (Completed)
**Status**: ⚠️ Verified (Needs Update)

---

## 🔍 Category 5: Code Quality

### Task 5.1: Find TODO/FIXME Comments
**Priority**: 🟢 Easy
**Scope**: All source files

**Instructions**:
```
Search for todos and fixmes:
  rg -i "TODO|FIXME|HACK|XXX" --type rust --type python --type nix

For each found:
1. Document location and context
2. Categorize: bug fix, feature, cleanup
3. Estimate complexity
4. DO NOT fix them - just document
```

### Task 5.2: Check for Dead Code in Scripts
**Priority**: 🟡 Medium
**Files**: `scripts/`, `tools/`

**Instructions**:
```
Review each script file:
1. Check if referenced anywhere
2. Check last modification date
3. Test if it runs without errors
4. Mark candidates for archival
```

---

## 📊 Category 6: Project Inventory Updates

### Task 6.1: Update PROJECT_INVENTORY.md
**Priority**: 🟡 Medium
**Files**: `PROJECT_INVENTORY.md`

**Instructions**:
```
Review and update:
1. Check if all sub-projects listed
2. Verify status columns are accurate
3. Add any missing integration points
4. Update lines of code estimates
```

### Task 6.2: Verify Example Directories (Completed)
**Status**: ✅ Done

### Task 6.3: Audit Project Inventory
**Priority**: 🟢 Easy
**Files**: `PROJECT_INVENTORY.md`

**Missing Items**:
- `tools/cursor-tui` (TUI Client)
- `tools/cursor-agent-tui` (Agent TUI)
- `tools/cursor-isolation` (Isolation Scripts)
- `scripts/rust/cursor-manager` (Rust CLI Manager)

**Instructions**:
```
1. Add new section for TUI tools in PROJECT_INVENTORY.md
2. Add section for Isolation tools
3. Clarify role of scripts/rust/cursor-manager
```

### Task 6.4: Clarify CLI Tools
**Priority**: 🟡 Medium
**Files**: `scripts/rust/cursor-manager`, `cursor-studio-egui`

**Analysis**:
- `cursor-studio-cli` is `cursor-studio-egui`'s CLI
- `scripts/rust/cursor-manager` is a standalone Rust CLI
- `cursor-versions` is a bash script wrapper

**Instructions**:
```
1. Decide if `scripts/rust/cursor-manager` is deprecated or the future `cs`
2. If deprecated, move to archive/
3. If active, document difference from cursor-studio-cli
```

---

## 🛡️ Category 7: Security Review

### Task 7.1: Review Security Blocklists
**Priority**: 🟡 Medium
**Files**: `security/blocklists/`

**Instructions**:
```
1. Check last update date of known-malicious.json
2. Verify JSON schema is valid
3. Cross-reference with any recent NPM security advisories
4. Document any packages that should be added
```

### Task 7.2: Verify No Secrets in Repo
**Priority**: 🟢 Easy
**Scope**: Entire repository

**Instructions**:
```
Search for potential secrets:
  rg -i "api[_-]?key|password|secret|token" --type-not rust

Review each match:
1. Confirm it's not an actual secret (e.g., placeholder, comment)
2. Check .gitignore covers sensitive files
3. Report any concerns
```

---

## ⚙️ Category 8: CI/CD Review

### Task 8.1: Review GitHub Actions
**Priority**: 🟡 Medium
**Files**: `.github/workflows/`

**Instructions**:
```
1. List all workflow files
2. Check if they run successfully (check GitHub Actions tab)
3. Verify they reference correct branches
4. Document any failing/disabled workflows
```

---

## 📝 Output Format

For each task completed, create an entry in this format:

```markdown
### Task X.Y Completed - [DATE]

**Status**: ✅ Complete / ⚠️ Issues Found / ❌ Blocked

**Summary**: Brief description of what was done

**Findings**:
- Finding 1
- Finding 2

**Recommendations**:
- Action item 1
- Action item 2

**Files Changed** (if any):
- file1.md (documentation update)
- file2.nix (comment added)
```

---

## 🚫 Tasks NOT for Lesser Models

These require Claude for deep reasoning:

1. **Proxy Protocol Work** - Complex Rust, HTTP/2, Protobuf
2. **Agent System Changes** - Risk of breaking Cursor
3. **NixOS Module Architecture** - Requires Nix expertise
4. **Security Vulnerability Fixes** - High risk
5. **Git Force Operations** - Destructive potential
6. **Database Schema Changes** - Data integrity risk

---

## 📋 Quick Start Prompt

Copy this prompt to start a Gemini 3 Flash session:

```
You are working on the nixos-cursor repository maintenance tasks.

Repository: /home/e421/nixos-cursor
Current Branch: pre-release

Read MAINTENANCE_TASKS.md for the full task list.

Rules:
1. Work on 🟢 Easy or 🟡 Medium tasks only
2. DO NOT modify code logic - documentation and cleanup only
3. DO NOT run git push or git merge
4. Report findings, don't fix complex issues
5. Stage changes with git add but DO NOT commit
6. Ask before any destructive operation

Start with Task 1.1 (README review) and work sequentially.
Report your findings clearly at the end.
```

---

## 🔄 Parallel Work Strategy

While running maintenance tasks with Gemini:

**In Another Session (Claude)**:
- Work on cursor-proxy Rust code
- Debug protocol issues
- Implement streaming endpoints
- Complex architecture decisions

This maximizes productivity by:
- Using cheap model for routine tasks
- Reserving expensive model for complex work
- Both can run simultaneously

---

**Last Updated**: 2026-01-12
**Next Review**: After completing all 🟢 Easy tasks
