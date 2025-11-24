# RC3.2 Implementation Plan

**Date:** 2025-11-24  
**Goal:** Expand to 37+ versions with improved GUI, comprehensive documentation, and automated testing

---

## 📊 Current Status

**Versions:**
- RC3.1: 12 versions (2.0.60-77, 1.7.46-54)
- RC3.2 Target: 37 versions (1.6.45 through 2.0.77)
- **New versions to add: 25**

**Hash Status:** ✅ ALL COMPLETE (25/25)

---

## 🎯 Core Objectives

### 1. Version Expansion
**Add 25 new versions:**
- 2.0.x: 9 new (2.0.11, 32, 34, 38, 40, 43, 52, 54, 57)
- 1.7.x: 15 new (1.7.11, 12, 16, 17, 22, 23, 25, 28, 33, 36, 38, 39, 40, 43, 44)
- 1.6.x: 1 new (1.6.45)

**Total after RC3.2: 37 versions**

### 2. GUI Improvement
- Replace flat button list with dropdown menus
- Organize by major version (1.6.x, 1.7.x, 2.0.x)
- Better UX for large version count
- Add version info/tooltips

### 3. Documentation Overhaul
- Update all examples to RC3.2
- Create integration guide
- Create version selection guide
- Update README with clear methods
- Audit all documentation

### 4. CI/CD Automation
- Test all 37 versions separately
- Parallel builds with caching
- Pre-release validation
- Automated hash verification

---

## 📋 Task Breakdown

### Phase 1: Version Integration (2-3 hours)

#### Task 1.1: Update cursor-versions.nix
- [ ] Add all 25 new version definitions
- [ ] Verify URL format matches pattern
- [ ] Test at least 3 random versions build
- [ ] Total definitions: 37

**Implementation:**
```nix
# 2.0.x additions (9 new)
cursor-2_0_57, cursor-2_0_54, cursor-2_0_52, cursor-2_0_43,
cursor-2_0_40, cursor-2_0_38, cursor-2_0_34, cursor-2_0_32, cursor-2_0_11

# 1.7.x additions (15 new)
cursor-1_7_44, cursor-1_7_43, cursor-1_7_40, cursor-1_7_39, cursor-1_7_38,
cursor-1_7_36, cursor-1_7_33, cursor-1_7_28, cursor-1_7_25, cursor-1_7_23,
cursor-1_7_22, cursor-1_7_17, cursor-1_7_16, cursor-1_7_12, cursor-1_7_11

# 1.6.x addition (1 new)
cursor-1_6_45
```

#### Task 1.2: Update flake.nix
- [ ] Expose all 37 packages
- [ ] Organize with clear comments
- [ ] Update package count in comments

#### Task 1.3: Test Sample Builds
- [ ] Build 1.6.45 (oldest)
- [ ] Build 1.7.28 (middle classic)
- [ ] Build 2.0.40 (middle 2.0.x)
- [ ] Verify all work

---

### Phase 2: Dropdown GUI (2-3 hours)

#### Task 2.1: Design New Layout
```
┌──────────────────────────────────────────┐
│  Cursor Version Manager                  │
│  ────────────────────────────────────────│
│                                          │
│  Select Version Family:                  │
│  ┌────────────────────────────────────┐  │
│  │ ▼ 2.0.x Custom Modes (17 versions)│  │
│  └────────────────────────────────────┘  │
│                                          │
│  Select Specific Version:                │
│  ┌────────────────────────────────────┐  │
│  │ ▼ 2.0.77 (Stable - Recommended)   │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌─────────────────┐  ┌──────────────┐  │
│  │ Launch Version  │  │  Settings    │  │
│  └─────────────────┘  └──────────────┘  │
│                                          │
│  ☑ Sync Settings  ☑ Sync Global State   │
└──────────────────────────────────────────┘
```

#### Task 2.2: Implement Cascading Dropdowns
- [ ] Family dropdown (1.6.x, 1.7.x, 2.0.x, System)
- [ ] Version dropdown (updates based on family)
- [ ] Keep theme matching
- [ ] Keep config sync checkboxes

#### Task 2.3: Version Organization
```python
VERSIONS = {
    "2.0.x Custom Modes": {
        "2.0.77": {"recommended": True, "desc": "Latest stable with custom modes"},
        "2.0.75": {"desc": "Stable alternative"},
        # ... 17 total
    },
    "1.7.x Classic": {
        "1.7.54": {"recommended": True, "desc": "Latest pre-2.0"},
        "1.7.53": {"desc": "Stable classic"},
        # ... 19 total
    },
    "1.6.x Legacy": {
        "1.6.45": {"desc": "Legacy version"},
    },
    "System Default": {
        "cursor": {"desc": "System-wide installation"},
    }
}
```

---

### Phase 3: Documentation (3-4 hours)

#### Task 3.1: Create New Guides

**INTEGRATION_GUIDE.md**
- [ ] Decision tree ASCII flowchart
- [ ] Method comparison table
- [ ] Step-by-step for each method
- [ ] Common pitfalls
- [ ] Migration paths

**WHICH_VERSION.md**
- [ ] Version timeline visualization
- [ ] Feature matrix (1.6 vs 1.7 vs 2.0)
- [ ] Stability ratings
- [ ] Use case recommendations
- [ ] Known issues per version

**TROUBLESHOOTING.md**
- [ ] Installation issues
- [ ] Runtime issues
- [ ] Data sync issues
- [ ] GUI manager issues
- [ ] Version-specific quirks

#### Task 3.2: Update Existing Docs

**README.md**
- [ ] Update version count (12 → 37)
- [ ] Add integration methods section
- [ ] Link to new guides
- [ ] Update quick start

**VERSION_MANAGER_GUIDE.md**
- [ ] Document dropdown UI
- [ ] Add version selection strategy
- [ ] GUI troubleshooting
- [ ] Data sync details

**CURSOR_VERSION_TRACKING.md**
- [ ] Complete list of all 37 versions
- [ ] Add integration status column
- [ ] Add recommended/stable markers
- [ ] Add known issues notes

#### Task 3.3: Update Examples

**examples/README.md**
- [ ] Update for RC3.2
- [ ] Add multi-version examples
- [ ] Add cursor-manager examples
- [ ] Add mixing methods example

**examples/basic-flake/**
- [ ] Update to use 2.0.77
- [ ] Add version selection note
- [ ] Test on fresh system

**examples/with-mcp/**
- [ ] Update MCP setup for RC3.2
- [ ] Test all 5 MCP servers
- [ ] Verify instructions

**examples/dev-shell/**
- [ ] Test with latest cursor
- [ ] Verify nix develop works
- [ ] Update troubleshooting

**examples/declarative-extensions/**
- [ ] Test extension installation
- [ ] Verify across versions
- [ ] Update limitations

**NEW: examples/multi-version/**
- [ ] Create example using cursor-manager
- [ ] Show side-by-side versions
- [ ] Document use cases

---

### Phase 4: CI/CD Automation (2-3 hours)

#### Task 4.1: Version Matrix Testing

**File:** `.github/workflows/test-all-versions.yml`
```yaml
name: Test All Versions

on:
  push:
    branches: [pre-release]
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  test-versions:
    strategy:
      matrix:
        version:
          # 2.0.x (17 versions)
          - cursor-2_0_77
          - cursor-2_0_75
          # ... all 37 versions
      fail-fast: false
    
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - uses: cachix/cachix-action@v13
        with:
          name: nixos-cursor
      
      - name: Build ${{ matrix.version }}
        run: nix build .#${{ matrix.version }}
```

#### Task 4.2: Pre-release Validation
- [ ] Update validate-pre-release.yml
- [ ] Add hash verification
- [ ] Add documentation checks
- [ ] Add example testing

#### Task 4.3: Build Optimization
- [ ] Parallel builds with matrix
- [ ] Cachix caching
- [ ] Fail-fast: false (test all even if one fails)
- [ ] Build time estimation

---

### Phase 5: Testing & Polish (2-3 hours)

#### Task 5.1: Build Testing
- [ ] Test 5 random versions locally
- [ ] Verify GUI manager launches all versions
- [ ] Test data sync between versions
- [ ] Test isolated configs work

#### Task 5.2: Documentation Testing
- [ ] Run all commands in examples
- [ ] Verify all links work
- [ ] Test on fresh NixOS VM
- [ ] Get community feedback

#### Task 5.3: Final Polish
- [ ] Update CHANGELOG
- [ ] Create RC3.2 summary
- [ ] Prepare forum announcement
- [ ] Tag release

---

## 📊 Progress Tracking

### Version Integration
- [x] Hash collection (25/25)
- [ ] cursor-versions.nix update (0/25)
- [ ] flake.nix update
- [ ] Sample build tests

### GUI Development
- [ ] Design finalized
- [ ] Dropdown implementation
- [ ] Theme integration
- [ ] Testing

### Documentation
- [ ] INTEGRATION_GUIDE.md (0%)
- [ ] WHICH_VERSION.md (0%)
- [ ] TROUBLESHOOTING.md (0%)
- [ ] README.md update (0%)
- [ ] Examples update (0/5)

### CI/CD
- [ ] test-all-versions.yml (0%)
- [ ] Pre-release validation (0%)
- [ ] Caching setup (0%)

### Testing
- [ ] Local builds (0/5)
- [ ] GUI testing (0%)
- [ ] Documentation testing (0%)
- [ ] Community feedback (0%)

---

## ⏱️ Time Estimates

| Phase | Estimated Time | Priority |
|-------|---------------|----------|
| Version Integration | 2-3 hours | HIGH |
| Dropdown GUI | 2-3 hours | HIGH |
| Documentation | 3-4 hours | HIGH |
| CI/CD | 2-3 hours | MEDIUM |
| Testing | 2-3 hours | HIGH |
| **TOTAL** | **11-16 hours** | - |

---

## 🚀 Execution Order

1. **Version Integration** (do first - enables everything else)
2. **GUI Development** (parallel with docs)
3. **Documentation** (can start while GUI in progress)
4. **CI/CD** (after versions integrated)
5. **Testing** (final phase before release)

---

## ✅ Success Criteria

RC3.2 is ready when:
- [ ] All 37 versions build successfully
- [ ] Dropdown GUI works smoothly
- [ ] All documentation accurate and tested
- [ ] CI/CD tests all versions
- [ ] Community can install and use easily
- [ ] No broken links or outdated info

---

## 🎯 Next Immediate Steps

1. Start with `cursor-versions.nix` - add all 25 versions
2. Update `flake.nix` to expose them
3. Test 3-5 builds to verify pattern works
4. Move to GUI implementation
5. Parallel: Start documentation drafts

**Let's begin!**
