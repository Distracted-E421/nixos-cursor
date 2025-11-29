# Cursor Studio v0.3.0 Release Plan

## 🎯 Target Audience

**Primary:** NixOS users (declarative configuration)
**Secondary:** macOS users (Nix/Homebrew)
**Future:** CLI/TUI interfaces for headless operation

## 🔄 CI/CD Pipeline (NixOS-Centric)

```
┌─────────────────────────────────────────────────────────────┐
│                   Phase 1: Validation                       │
│  ┌─────────────────┐                                        │
│  │ nix flake check │ → Validates all flakes                 │
│  └────────┬────────┘                                        │
│           │                                                 │
│           ▼                                                 │
├─────────────────────────────────────────────────────────────┤
│                   Phase 2: NixOS Builds                     │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ x86_64-linux    │  │ Darwin (macOS)  │                   │
│  │ (ubuntu-latest) │  │ (macos-14 ARM)  │                   │
│  └────────┬────────┘  └────────┬────────┘                   │
│           │                    │                            │
│           ▼                    ▼                            │
├─────────────────────────────────────────────────────────────┤
│                   Phase 3: Home Manager                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ • Module syntax validation                          │   │
│  │ • Options evaluation test                           │   │
│  │ • Example configurations check                      │   │
│  └─────────────────────────────────────────────────────┘   │
│           │                                                 │
│           ▼                                                 │
├─────────────────────────────────────────────────────────────┤
│                   Phase 4: Tests                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ cargo test (in nix develop shell)                   │   │
│  │ 13 unit tests (database, security, theme)           │   │
│  └─────────────────────────────────────────────────────┘   │
│           │                                                 │
│           ▼                                                 │
├─────────────────────────────────────────────────────────────┤
│              Phase 5: Release Candidate (manual)            │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │ NixOS binary    │  │ macOS binaries  │                   │
│  │ (primary)       │  │ (cargo builds)  │                   │
│  └─────────────────┘  └─────────────────┘                   │
│           │                                                 │
│           ▼                                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ GitHub Release (v0.3.0-rc1, v0.3.0-beta, v0.3.0)   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

| Phase | Check | Status |
|-------|-------|--------|
| 1 | Flake Check | ✅ Ready |
| 2 | NixOS x86_64 | ✅ Ready |
| 2 | NixOS Darwin | ✅ Ready |
| 3 | Home Manager | ✅ Ready |
| 4 | Rust Tests | ✅ Ready |
| 5 | Release | ⏳ Manual trigger |

**Workflow:** `.github/workflows/cursor-studio.yml`

## 🏠 Home Manager Integration

### Configuration Layers

```
User's home.nix
    │
    ├─► programs.cursor.enable = true
    │   └─► Installs Cursor IDE
    │
    ├─► programs.cursor.mcp.enable = true
    │   └─► Configures MCP servers
    │
    └─► programs.cursor-studio.enable = true  # Future
        ├─► GUI settings from flake
        ├─► CLI/TUI with same options
        └─► Settings sync across interfaces
```

### Future: Unified Config Interface

| Interface | Same Config | Status |
|-----------|-------------|--------|
| GUI (egui) | ✅ | Current |
| Flake/HM | ✅ | Planned |
| CLI | ✅ | Future |
| TUI | ✅ | Future |

All interfaces will read/write the same config schema

## 📊 Release Readiness Chart

```
Feature Area              Status    Polish Level   Release Ready?
─────────────────────────────────────────────────────────────────
Core UI                   ✅ Done    ████████░░ 80%    ⚠️ Minor
Message Rendering         ✅ Done    ███████░░░ 70%    ⚠️ Bold fix
Bookmarks                 ✅ Done    █████████░ 90%    ✅ Ready
Import System             ✅ Done    █████████░ 90%    ✅ Ready
Settings Panel            ✅ Done    ████████░░ 80%    ⚠️ Persist
Security Panel            ✅ Done    ███████░░░ 70%    ⚠️ NPM wire
Search (In-Chat)          ✅ Done    █████████░ 90%    ✅ Ready
Export (Markdown)         ✅ Done    █████████░ 90%    ✅ Ready
Theme System              ✅ Done    █████████░ 90%    ✅ Ready
─────────────────────────────────────────────────────────────────
OVERALL                              ████████░░ 83%    🔶 Almost
```

## 🎯 Critical Path to Release

### Phase 1: Bug Fixes (P0 - Must Have)
| Task | File | Priority | Est. Time |
|------|------|----------|-----------|
| Fix nested **bold** in markdown | `main.rs:render_text_line()` | P0 | 30m |
| Unicode font fallback | `main.rs:configure_fonts()` | P0 | 45m |
| Settings persistence on exit | `main.rs:on_close_event()` | P0 | 20m |

### Phase 2: Polish (P1 - Should Have)
| Task | File | Priority | Est. Time |
|------|------|----------|-----------|
| Wire up NPM scan results | `main.rs:show_security_panel()` | P1 | 30m |
| Jump-to from security findings | `main.rs:scroll_to_message()` | P1 | 20m |
| Export JSON format | `main.rs:export_*` | P1 | 30m |
| Global search across chats | `main.rs:global_search()` | P1 | 45m |
| Remember window size | `main.rs:save_window_settings()` | P1 | 15m |

### Phase 3: Nice to Have (P2)
| Task | File | Priority | Est. Time |
|------|------|----------|-----------|
| Export bookmarked only | `main.rs:export_bookmarks()` | P2 | 20m |
| Filter by message type | `main.rs:show_search_panel()` | P2 | 30m |
| Keyboard shortcuts | `main.rs:handle_input()` | P2 | 45m |
| Better status bar stats | `main.rs:show_status_bar()` | P2 | 20m |

## 📁 Files to Modify

### `src/main.rs`
- [ ] `configure_fonts()` - Add Nerd Font paths, improve fallback chain
- [ ] `render_text_line()` - Fix bold parsing for nested/complex cases
- [ ] `show_security_panel()` - Wire NPM scan results to UI
- [ ] `scroll_to_message()` - Ensure works from security panel
- [ ] `export_conversation_to_json()` - Implement JSON export
- [ ] `global_search()` - Search across all conversations
- [ ] `save_window_settings()` - Persist on app close

### `src/database.rs`
- [ ] `extract_message_content()` - Parse files_edited from tool calls
- [ ] Window settings config keys

### `src/security.rs`
- [ ] `scan_directory()` - Verify recursive scanning works
- [ ] Add more blocklist sources

## 🔄 Testing Checklist

### Before Release
- [ ] Import 100+ conversations - check performance
- [ ] Test all export formats (MD, JSON, bookmarks)
- [ ] Verify bookmarks persist across clear/reimport
- [ ] Test search with special characters
- [ ] Check Unicode rendering (emojis, symbols)
- [ ] Verify theme switching works
- [ ] Test on fresh database
- [ ] Check memory usage over time

### UI/UX Review
- [ ] All buttons have hover states
- [ ] All inputs have placeholder text
- [ ] Error messages are clear
- [ ] Loading states are visible
- [ ] Keyboard navigation works

## 📝 Documentation Needed

- [ ] README.md - Installation instructions
- [ ] CHANGELOG.md - v0.3.0 entry
- [ ] User guide for new features
- [ ] Keyboard shortcuts reference

## 🚀 Release Checklist

1. [ ] All P0 tasks complete
2. [ ] All P1 tasks complete or deferred
3. [ ] Build passes on Linux x86_64
4. [ ] Nix flake builds cleanly
5. [ ] No critical warnings in cargo check
6. [ ] README updated
7. [ ] CHANGELOG updated
8. [ ] Version bumped in Cargo.toml
9. [ ] Git tag created
10. [ ] Release branch merged to main

---

## 📅 Suggested Timeline

```
Day 1: Phase 1 (Bug Fixes)
  └── Bold text fix, Unicode fonts, Settings persist

Day 2: Phase 2 (Polish)  
  └── NPM wiring, Jump-to, Export JSON, Global search

Day 3: Testing & Documentation
  └── Full test pass, README, CHANGELOG

Day 4: Release
  └── Final review, tag, merge
```

---

*Last updated: 2025-11-29*
