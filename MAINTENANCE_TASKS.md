# Maintenance Tasks - nixos-cursor

> **Purpose**: Low-risk maintenance tasks that can be delegated to a lesser model (Gemini 3 Flash)
> **Generated**: 2025-12-19
> **Status**: Ready for background work

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

### Task 1.1: Update Root README.md
**Priority**: 🟡 Medium
**Files**: `README.md`

**Current Issues**:
- Version numbers may be outdated
- Missing mention of new tools (cursor-isolation, cursor-proxy)
- Quick start might need updating

**Instructions**:
```
Review README.md and:
1. Verify version numbers match cursor-versions.nix
2. Add cursor-isolation tools to feature list
3. Update "What's New" section
4. Ensure all code examples work
```

---

### Task 1.2: Create CONTRIBUTING.md Updates
**Priority**: 🟢 Easy
**Files**: `CONTRIBUTING.md`

**Instructions**:
```
Add section about:
1. Using cursor-test for isolated development
2. Backup workflow before experiments
3. Testing with multiple Cursor versions
```

---

### Task 1.3: Document New Tools in tools/cursor-isolation/README.md
**Priority**: 🟢 Easy
**Files**: `tools/cursor-isolation/README.md`

**Instructions**:
```
Expand README with:
1. Usage examples for each script
2. Environment variable options
3. Integration with cursor-proxy
```

---

## 🧹 Category 2: Repository Cleanup

### Task 2.1: Stage Untracked Directories
**Priority**: 🟢 Easy
**Files**: `modules/`, `tools/cursor-proxy/`, `tools/cursor-agent-tui/`

**Current State**: These directories are untracked but contain important work.

**Instructions**:
```
Run: git status
Review each untracked directory:
1. modules/ - Probably should be tracked (NixOS modules)
2. tools/cursor-proxy/ - Core project work, should be tracked
3. tools/cursor-agent-tui/ - Core project work, should be tracked
4. scripts/cleanup-cursor-db.sh - Review and track if useful

For each: git add <directory> with appropriate .gitignore entries
```

---

### Task 2.2: Clean Up .cursorignore
**Priority**: 🟢 Easy  
**Files**: `.cursorignore`

**Current State**: Modified but not staged

**Instructions**:
```
Review .cursorignore for:
1. Remove any obsolete patterns
2. Add patterns for new directories
3. Ensure build artifacts are ignored
4. Stage changes: git add .cursorignore
```

---

### Task 2.3: Remove result-* Symlinks
**Priority**: 🟢 Easy
**Files**: `result-chat`, `result-manager`, `result-vscode`

**Instructions**:
```
These are Nix build result symlinks that should be gitignored.
1. Verify they're in .gitignore: grep "result" .gitignore
2. If not, add "result*" to .gitignore
3. Remove them locally if needed: rm -f result-*
```

---

## 🌳 Category 3: Branch Management

### Task 3.1: Review Branch Status
**Priority**: 🟡 Medium
**Branches**: Multiple feature branches exist

**Current Branches**:
```
* pre-release (current)
  cursor-docs-0.3.0-pre
  dev
  experimental/darwin-support
  feature/npm-security-system
  main
```

**Instructions**:
```
1. List all branches: git branch -a
2. Check if feature branches are merged: git log main..feature/npm-security-system
3. Identify stale branches (no commits in 30+ days)
4. Document which branches can be deleted
5. DO NOT delete any branches - just report findings
```

---

### Task 3.2: Sync pre-release to main
**Priority**: 🔴 Complex (DO NOT EXECUTE - just analyze)
**Notes**: Just document what commits are on pre-release but not main

**Instructions**:
```
1. git log main..pre-release --oneline
2. Document the commits that would be merged
3. Note any potential conflicts
4. DO NOT perform the merge - just report
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

---

### Task 4.2: Check flake.lock Freshness
**Priority**: 🟢 Easy
**Files**: `flake.lock`

**Instructions**:
```
1. Check last update date: git log -1 flake.lock
2. Check if nixpkgs is more than 30 days old
3. Report if update recommended
4. DO NOT run nix flake update - just report
```

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

---

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

---

### Task 6.2: Verify Example Directories
**Priority**: 🟢 Easy
**Files**: `examples/*/`

**Instructions**:
```
For each example:
1. Check if flake.nix is valid: nix flake check examples/<name>/flake.nix
2. Verify README is accurate
3. Test basic commands work
4. Document any issues found
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

---

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

**Last Updated**: 2025-12-19
**Next Review**: After completing all 🟢 Easy tasks

