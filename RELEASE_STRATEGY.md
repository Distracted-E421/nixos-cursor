# Cursor with MCP - Release Strategy

**Project**: cursor-with-mcp  
**Repository**: (To be created) `github.com/yourusername/cursor-nixos`  
**Status**: Pre-release (Phase 2 testing)  
**Last Updated**: 2025-11-22  

---

## 🔄 Auto-Update System (NEW)

**Status**: ✅ Implemented (2025-11-22)

### How It Works

Unlike typical Linux apps, Cursor **cannot self-update** on NixOS because:
- Applications are stored in `/nix/store` (read-only, immutable)
- Cursor's updater expects to replace the AppImage file itself
- This fails on NixOS → "Please download from website" message

**Our Solution** (following nixpkgs pattern):
1. **Disable Cursor's built-in updater**: `--update=false` flag
2. **Automated update script**: `cursor/update.sh` queries Cursor's API
3. **User updates via Nix**: `nix flake update cursor-with-mcp`

### For Maintainers

**Running the update script**:

```bash
cd projects/cursor-with-mcp/cursor
./update.sh
```

The script will:
- Query `https://api2.cursor.sh/updates/api/download/stable` for latest version
- Download AppImages for x86_64-linux and aarch64-linux
- Calculate SRI hashes
- Update `cursor/default.nix` with new version and hashes

**After update**:
```bash
# Test build
cd .. && nix build .#cursor
./result/bin/cursor --version

# Commit changes
git add cursor/default.nix
git commit -m "chore: Update Cursor to $(nix eval .#cursor.version --raw)"
git tag "v$(nix eval .#cursor.version --raw)"
git push origin main --tags
```

### For End Users

**Updating Cursor**:

```bash
# Update flake inputs (fetches new Cursor version)
nix flake update cursor-with-mcp

# Apply update (Home Manager)
home-manager switch

# Or (NixOS system package)
nixos-rebuild switch
```

**Why Cursor won't self-update**: See [AUTO_UPDATE_IMPLEMENTATION.md](AUTO_UPDATE_IMPLEMENTATION.md)

---

## �� Package Versioning

### Version Format

**Pattern**: `cursor-VERSION-rcN` or `cursor-VERSION`

**Components**:
- `cursor-VERSION`: Upstream Cursor IDE version (e.g., `0.42.5`)
- `-rcN`: Release candidate suffix (e.g., `-rc1`, `-rc2`)
- Final release drops `-rc` suffix

**Examples**:
- `cursor-0.42.5-rc1` - First release candidate for Cursor 0.42.5
- `cursor-0.42.5-rc2` - Second release candidate (bug fixes)
- `cursor-0.42.5` - Stable release
- `cursor-0.43.0-rc1` - Next version release candidate

### Cursor Version Tracking

**Upstream Source**: Cursor IDE releases from `cursor.sh`

**Update Frequency**:
- **Stable Channel**: Every 2-4 weeks (after thorough testing)
- **Unstable Channel**: 1-2 weeks after upstream release

**Version Detection**:
```nix
officialVersions = {
  stable = { version = "0.42.5"; hash = "sha256-..."; };
  unstable = { version = "0.42.5"; hash = "sha256-..."; };
};
```

---

## 🎯 Release Channels

### Unstable Channel (Primary Development)

**Target Audience**: Early adopters, testers, developers  
**Update Frequency**: Weekly to bi-weekly  
**Testing Requirements**: Minimal (Phase 2 local tests)  

**Criteria for Unstable Release**:
- ✅ Cursor package builds successfully
- ✅ Basic MCP servers functional (1/5 minimum)
- ✅ Syntax validation passes on all examples
- ✅ Documentation updated
- ⚠️ Known issues documented but not blocking

**Unstable Version Pattern**: `cursor-X.Y.Z-rc1`, `cursor-X.Y.Z-rc2`

**Nixpkgs Target**: `nixpkgs-unstable`

---

### Stable Channel (Future)

**Target Audience**: Production users, conservative adopters  
**Update Frequency**: Monthly to quarterly  
**Testing Requirements**: Comprehensive (all Phase 2 tests + field testing)  

**Criteria for Stable Release**:
- ✅ All Phase 2 tests pass (15/15)
- ✅ All 5 MCP servers fully functional
- ✅ Tested on 3+ NixOS versions (24.05, 24.11, unstable)
- ✅ Tested on 3+ devices (Obsidian, neon-laptop, Framework)
- ✅ Zero critical bugs
- ✅ Documentation complete and accurate
- ✅ At least 2 weeks in unstable with no major issues

**Stable Version Pattern**: `cursor-X.Y.Z` (no `-rc` suffix)

**Version Pegging Strategy**:
- Pin specific Cursor AppImage version that's proven stable
- Pin MCP server versions (npm packages, uvx packages)
- Pin browser version for Playwright MCP
- Lock `flake.lock` for reproducibility

**Nixpkgs Target**: `nixpkgs-stable` (after 6+ months of stability)

---

## 🚀 Release Thresholds

### Patch Release (X.Y.Z → X.Y.Z+1)

**Triggers**:
- Cursor IDE patch update upstream
- Bug fixes in our packaging
- Documentation corrections
- Minor MCP configuration tweaks

**Requirements**:
- ✅ No new features
- ✅ Backward compatible
- ✅ Syntax validation passes
- ✅ Basic functionality test (1 device)

**Timeline**: 1-3 days after identifying need

---

### Minor Release (X.Y.Z → X.Y+1.0)

**Triggers**:
- Cursor IDE minor update upstream
- New MCP server addition
- Significant feature additions
- Major documentation overhaul

**Requirements**:
- ✅ All features documented
- ✅ Examples updated for new features
- ✅ Tested on 2+ devices
- ✅ All existing tests pass
- ⚠️ May introduce new functionality

**Timeline**: 1-2 weeks for testing and validation

---

### Major Release (X.Y.Z → X+1.0.0)

**Triggers**:
- Cursor IDE major version change
- Breaking changes in packaging
- Complete architecture redesign
- NixOS module system changes

**Requirements**:
- ✅ Migration guide provided
- ✅ All tests pass on all supported NixOS versions
- ✅ Deprecation warnings for removed features
- ✅ Community feedback incorporated
- ✅ 1+ month testing period

**Timeline**: 1-3 months for comprehensive testing

---

## 📊 Quality Gates

### Pre-Release Checklist

**Code Quality**:
- [ ] All examples pass `nix flake check`
- [ ] No syntax errors in Nix files
- [ ] Proper variable scoping
- [ ] No hard-coded user paths

**Functionality**:
- [ ] Cursor package builds
- [ ] Desktop launcher works
- [ ] All enabled MCP servers start
- [ ] Wrapper script functions correctly
- [ ] Extension management works

**Documentation**:
- [ ] README accurate
- [ ] CHANGELOG updated
- [ ] Examples tested and working
- [ ] Troubleshooting guide current
- [ ] FOSS vs proprietary clearly documented

**Testing**:
- [ ] Local tests pass (Obsidian)
- [ ] At least 1 other device tested
- [ ] No critical bugs open
- [ ] Performance acceptable

---

## 🐛 Bug Severity Classification

### Critical (Blocks Release)

**Examples**:
- Cursor won't launch
- All MCP servers fail to start
- Data loss potential
- Security vulnerabilities

**Action**: Fix immediately, delay release

---

### Major (Delays Release)

**Examples**:
- 1+ MCP server non-functional
- Performance regression >20%
- Documentation completely wrong
- Broken on specific NixOS version

**Action**: Fix before stable release, document for unstable

---

### Minor (Document & Track)

**Examples**:
- UI glitches
- Non-critical MCP tool missing
- Documentation typos
- Incomplete examples

**Action**: Document in known issues, fix in next patch

---

### Trivial (Track Only)

**Examples**:
- Cosmetic issues
- Optional feature requests
- Documentation suggestions

**Action**: Add to backlog, fix when convenient

---

## 📈 Release Process

### Stage 1: Preparation (1-2 days)

1. **Version Bump**:
   ```nix
   version = "0.42.6";
   hash = "sha256-NEW_HASH";
   ```

2. **Update CHANGELOG**:
   ```markdown
   ## [0.42.6] - 2025-11-20
   
   ### Added
   - Feature descriptions
   
   ### Fixed
   - Bug fix descriptions
   
   ### Changed
   - Breaking changes (if any)
   ```

3. **Update Documentation**:
   - README version references
   - Example flake inputs
   - Installation instructions

4. **Run Local Tests**:
   ```bash
   cd nixos/pkgs/cursor-with-mcp
   nix flake check
   nix build .#cursor
   ```

---

### Stage 2: Testing (3-7 days)

1. **Multi-Device Testing**:
   - Test on Obsidian (NixOS 25.11)
   - Test on neon-laptop (NixOS 24.05)
   - Test on Framework (NixOS 24.05)

2. **MCP Server Validation**:
   - filesystem MCP
   - memory MCP
   - nixos MCP
   - github MCP
   - playwright MCP

3. **Example Verification**:
   - basic-flake works
   - with-mcp works
   - dev-shell works
   - declarative-extensions works

4. **Performance Benchmarks**:
   - Startup time < 5s
   - MCP response times acceptable
   - No memory leaks

---

### Stage 3: Release Candidate (Optional for Major Releases)

1. **Tag RC Version**:
   ```bash
   git tag -a v0.43.0-rc1 -m "Release candidate 1 for 0.43.0"
   git push origin v0.43.0-rc1
   ```

2. **Community Testing** (if applicable):
   - Share in NixOS forum thread
   - Collect feedback
   - Fix reported issues

3. **RC Iteration**:
   - If bugs found: `v0.43.0-rc2`, `rc3`, etc.
   - If stable: Proceed to final release

---

### Stage 4: Final Release

1. **Create Release Tag**:
   ```bash
   git tag -a v0.42.6 -m "Cursor 0.42.6 with MCP servers"
   git push origin v0.42.6
   ```

2. **Update GitHub Release**:
   - Release notes from CHANGELOG
   - Installation instructions
   - Known issues
   - Links to documentation

3. **Update flake.lock**:
   ```bash
   nix flake update
   git add flake.lock
   git commit -m "chore: Update flake.lock for v0.42.6"
   ```

4. **Announce**:
   - NixOS Discourse forum post
   - Update original thread
   - Social media (optional)

---

## 🔄 Update Strategy

### Following Upstream Cursor Releases

**Monitoring**:
- Check `https://cursor.sh/releases` weekly
- Subscribe to Cursor changelog RSS (if available)
- Monitor Cursor GitHub releases

**Decision Process**:
1. **Cursor patch release** (X.Y.Z → X.Y.Z+1):
   - Update within 1 week
   - Minimal testing (local + 1 device)
   - Fast-track to unstable

2. **Cursor minor release** (X.Y.Z → X.Y+1.0):
   - Update within 2 weeks
   - Full Phase 2 testing
   - RC period recommended

3. **Cursor major release** (X.Y.Z → X+1.0.0):
   - Evaluate breaking changes
   - Full Phase 2 + extended testing
   - Mandatory RC period
   - Consider delaying until stable

---

## 📝 Changelog Management

### Changelog Format (Keep a Changelog)

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New features not yet released

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security fixes

## [0.42.5] - 2025-11-18

### Added
- Initial release with 5 MCP servers
- Home Manager module
- 4 example configurations
```

### Changelog Update Triggers

**On Every Commit** (if user-facing):
- Add entry to "Unreleased" section
- Categorize appropriately

**On Release**:
- Move "Unreleased" to new version section
- Add release date
- Create GitHub release notes from this section

---

## 🎯 Success Metrics

### Release Health Indicators

**Good Release**:
- ✅ Zero critical bugs reported within 1 week
- ✅ <5 minor bugs reported
- ✅ Positive community feedback
- ✅ No rollback requests

**Problem Release**:
- ❌ Critical bugs within 24 hours
- ❌ Multiple device failures
- ❌ Negative community feedback
- ❌ Requires immediate hotfix

### Stability Criteria (for Stable Channel)

**Minimum Requirements**:
- 2+ weeks in unstable with zero critical bugs
- 10+ successful user installations (via forum feedback)
- All Phase 2 tests passing on 3+ devices
- Complete documentation with zero user confusion reports

---

## 🔐 Security Considerations

### Security Updates

**Priority**: Critical (immediate release)

**Process**:
1. Assess vulnerability severity
2. Apply fix
3. Test minimally (critical path only)
4. Release as patch version
5. Notify users via GitHub Security Advisory

### Dependency Security

**Regular Audits**:
- Monthly: Check MCP server npm packages for CVEs
- Quarterly: Review Cursor AppImage for security issues
- Ongoing: Monitor NixOS security announcements

---

## 📦 Package Distribution

### Current Strategy (Pre-Release)

- **Primary**: GitHub repository
- **Installation**: Users add as flake input
- **Updates**: Users run `nix flake update`

### Future Strategy (Post-Release)

**Nixpkgs Integration** (6-12 months out):
1. Submit to `nixpkgs` once stable
2. Maintain as `pkgs.cursor-with-mcp`
3. Separate stable/unstable expressions if needed

**Flakes Registry** (3-6 months out):
1. Register as `cursor-nixos` in flakes registry
2. Enable `nix run cursor-nixos#cursor` without URL

---

## 🤝 Community Engagement

### Forum Presence

**NixOS Discourse Thread**:
- Original: https://forum.cursor.com/t/cursor-is-now-available-on-nixos/16640
- Create dedicated thread for our package
- Regular updates on releases
- Collect feedback and feature requests

### Issue Tracking

**GitHub Issues**:
- Bug reports (template provided)
- Feature requests (template provided)
- Questions (link to discussions)
- Security issues (private reporting)

### Contribution Guidelines

**Future**: Create CONTRIBUTING.md with:
- Code style guidelines
- Testing requirements
- PR process
- Communication channels

---

## 🎓 Lessons from Phase 2 Testing

### MCP Tool Limit Issue

**Problem**: Went slightly over Cursor's MCP tool limit (exact limit unknown)

**Impact**: Delayed recognition of issue

**Solution**:
- Document current tool count per MCP server
- Monitor total tools exposed
- Consider disabling optional tools if near limit
- Add to troubleshooting guide

**Future Consideration**:
- Make MCP servers optional/modular
- Allow users to disable unused servers
- Provide "minimal" and "full" configurations

### Custom Agent Permissions

**Problem**: Custom agents need explicit GitHub MCP access permission

**Impact**: GitHub operations failed initially

**Solution**:
- Document in setup guide
- Add to troubleshooting section
- Include in example configurations
- Test with fresh agent profiles

---

## 📅 Proposed Release Timeline

### Phase 2 Completion → First Unstable Release

**Target**: 2025-11-25 (1 week)

**Milestones**:
- [x] Phase 2 testing started
- [ ] Phase 2 testing complete (15/15 tests)
- [ ] All critical bugs fixed
- [ ] Documentation finalized
- [ ] Examples tested on 3 devices
- [ ] CHANGELOG drafted
- [ ] GitHub repository created

**Version**: `cursor-0.42.5-rc1`

---

### First Stable Release

**Target**: 2026-01-15 (2 months)

**Requirements**:
- `cursor-0.42.5-rc1` → `rc2` → `stable`
- 4+ weeks of community testing
- Zero critical bugs
- Positive user feedback
- Complete documentation
- Performance validated

**Version**: `cursor-0.42.5`

---

### Long-Term Roadmap

**Q1 2026**:
- Stable channel established
- Nixpkgs submission prepared
- Community engagement active

**Q2 2026**:
- Multiple stable versions released
- Flakes registry entry
- Consider automation for upstream updates

**Q3-Q4 2026**:
- Mature stable channel
- Potential Nixpkgs merge
- Expanded MCP server options

---

## 🏷️ Version Tagging Strategy

### Git Tags

**Format**: `vMAJOR.MINOR.PATCH[-rcN]`

**Examples**:
- `v0.42.5-rc1` - Release candidate
- `v0.42.5` - Stable release
- `v0.42.6` - Patch release
- `v0.43.0` - Minor version bump

### Flake Inputs

**Users Reference**:
```nix
inputs.cursor-nixos.url = "github:yourusername/cursor-nixos/v0.42.5";
```

**Rolling Unstable**:
```nix
inputs.cursor-nixos.url = "github:yourusername/cursor-nixos";
```

---

## 📊 Release Metrics to Track

### Quantitative

- Time from upstream release to our release
- Number of bugs per release
- Number of installations (via GitHub insights)
- Community engagement (forum posts, issues)
- Documentation completeness

### Qualitative

- User satisfaction (forum sentiment)
- Stability perception
- Ease of installation feedback
- Documentation clarity

---

## ✅ Release Checklist Template

Use this for every release:

```markdown
## Release Checklist: cursor-X.Y.Z

### Pre-Release
- [ ] Version bumped in cursor/default.nix
- [ ] CHANGELOG.md updated
- [ ] README.md version references updated
- [ ] All examples tested locally
- [ ] `nix flake check` passes
- [ ] Device changelog updated

### Testing
- [ ] Tested on Obsidian (NixOS 25.11)
- [ ] Tested on neon-laptop (NixOS 24.05)
- [ ] Tested on Framework (NixOS 24.05)
- [ ] All 5 MCP servers functional
- [ ] Performance benchmarks acceptable

### Documentation
- [ ] README accurate
- [ ] Examples work
- [ ] Troubleshooting updated
- [ ] Known issues documented

### Release
- [ ] Git tag created: vX.Y.Z
- [ ] GitHub release published
- [ ] Forum post updated
- [ ] flake.lock updated (if stable)

### Post-Release
- [ ] Monitor for critical bugs (24-48 hours)
- [ ] Respond to user feedback
- [ ] Update documentation based on questions
```

---

**Next Review**: After first release  
**Owner**: Package maintainer(s)  
**Status**: Living document - update as process evolves
