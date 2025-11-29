# Cursor Studio Roadmap

> **See also:** [RELEASE_PLAN.md](./RELEASE_PLAN.md) for v0.3.0 release checklist

## ✅ Completed Features (v0.2.x)

### Core Application
- [x] VS Code-like UI layout (Activity Bar, Sidebars, Tabs, Status Bar)
- [x] Version Manager (left sidebar)
- [x] Chat Library (right sidebar)
- [x] Dashboard tab
- [x] Conversation tabs with message rendering

### Message Rendering
- [x] Tool call rendering with status icons (✓/⏳/✗)
- [x] Thinking blocks (custom collapsible, theme-aware)
- [x] Code block syntax highlighting
- [x] Markdown rendering (headings, bold, inline code, bullets)
- [x] Right-aligned user messages (bubble style)
- [x] Live display preference alignment (left/center/right)
- [x] Configurable message spacing
- [x] Full tool arguments display (collapsible, pretty-printed JSON)

### Bookmarks
- [x] Database schema for bookmarks
- [x] Add/remove bookmark buttons on messages (⭐/🔖)
- [x] Bookmark panel in conversation header
- [x] Bookmarks survive cache clears (persist by sequence)
- [x] Reattach bookmarks after reimport
- [x] Jump to bookmarked message (scroll + highlight)

### Import System
- [x] Async background import (doesn't freeze UI)
- [x] Progress tracking in status bar
- [x] Import warning (two-click confirm)
- [x] Multi-database support (default + versioned)
- [x] Clear & Reimport (preserves bookmarks)

### UI Customization
- [x] Font scale slider (80%-150%)
- [x] Message spacing slider (4px-32px)
- [x] Status bar font size slider (8px-16px)
- [x] Theme selection (Dark/Light + VS Code themes)
- [x] Settings persistence to database

### Security Features
- [x] Security Panel in right sidebar
- [x] Sensitive data scanning (API keys, passwords, secrets)
- [x] NPM Package Security Scanner with blocklist
- [x] Known malicious package detection (Shai-Hulud 2025, historical, typosquatting)

### Search & Export
- [x] In-conversation search with navigation
- [x] Export conversation to Markdown

### Resource Settings
- [x] CPU, RAM, VRAM, Storage sliders (UI only, not enforced)

---

## 🎯 v0.3.0 Release Focus

### P0 - Must Fix
- [ ] **Bold text rendering** - Nested bold in markdown
- [ ] **Unicode fonts** - Nerd Font fallback for terminal symbols
- [ ] **Settings on exit** - Persist window size/position

### P1 - Should Have
- [ ] **NPM scan UI** - Wire results to security panel
- [ ] **Export JSON** - Alternative export format
- [ ] **Global search** - Search across all conversations
- [ ] **Window persistence** - Remember size/sidebar widths

### P2 - Nice to Have
- [ ] Export bookmarked sections only
- [ ] Filter search by message type
- [ ] Keyboard shortcuts

---

## 🐛 Known Issues

- [ ] Some Unicode characters from shells don't render (❯, ⚡)
- [ ] Nested bold text may not render correctly
- [ ] Large conversations (1000+ messages) may lag
- [ ] Some Cursor tool call formats not fully parsed

---

## 🔮 Future Goals

### Post v0.3.0
- GPUI migration (Zed's framework)
- Plugin system
- Multi-device sync
- AI integration (auto-titles, summaries)
- Data playground (charts, heatmaps)

---

## 📊 Version History

### v0.2.1 - 2025-11-29
- Jump-to-message for bookmarks and security findings
- NPM package security scanner
- Security panel with sensitive data detection
- Export to Markdown
- In-conversation search

### v0.2.0 - 2025-11-28
- Initial Cursor Studio with egui
- Full bookmark system
- Async imports
- UI customization

### v0.1.x
- Original Python/Tkinter applications
