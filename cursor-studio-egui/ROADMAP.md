# Cursor Studio Roadmap

## ✅ Completed Features

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
- [x] **Jump to bookmarked message** (scroll to + highlight)

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

### Analytics
- [x] Detailed stats in status bar
- [x] Tracks: user messages, AI responses, tool calls, thinking blocks, code blocks, bookmarks

### Security Features
- [x] **Security Panel** in right sidebar (toggle 💬/🔒)
- [x] **Sensitive data scanning** (API keys, passwords, secrets via regex)
- [x] **Jump to sensitive data findings** (click → navigates to message)
- [x] **NPM Package Security Scanner** with embedded blocklist
- [x] **Known malicious package blocklist** (Shai-Hulud 2025, historical, typosquatting)
- [x] **Directory scanning** for package.json files
- [x] **CVE tracking** for blocked packages
- [x] Scan results display with counts and categories

### Resource Settings
- [x] CPU Threads slider (1 to max cores)
- [x] RAM Limit slider (512MB - 16GB)
- [x] VRAM Limit slider (256MB - 32GB)
- [x] Storage Limit slider (1GB - 100GB)

---

## 🚧 In Progress

### Unicode Font Support
- [x] Font loading from system and Nix paths
- [x] JetBrains Mono, DejaVu, Noto font families
- [ ] Better Nerd Font integration
- [ ] Custom font loading from user config

### Message Alignment
- [x] All alignments now render tool calls, thinking, and content
- [x] Helper function `render_message_body()` consolidates rendering
- [x] Scroll target highlighting for jumped-to messages

### Bold Text in Complex Blocks
- [ ] Nested **bold** within larger markdown blocks
- [ ] Bold + code mixing in same line

---

## 📋 Planned Features

### High Priority

#### Request Segmentation
- [ ] Group messages by user request/response cycle
- [ ] Track files edited per request
- [ ] Jump between request segments
- [ ] Segment summary view

#### Files Edited Tracking
- [ ] Parse `edit_file`, `search_replace` tool calls
- [ ] Show list of files modified per conversation
- [ ] Quick link to file diffs

### Medium Priority

#### Export Features
- [x] **Export conversation to Markdown** (📤 button in conversation header)
- [x] Tool calls, thinking blocks included in export
- [x] Auto-creates export directory
- [ ] Export bookmarked sections only
- [ ] Export to JSON for analysis

#### Search Improvements
- [ ] Full-text search across all conversations
- [x] **Search within conversation** (🔍 box in toolbar)
- [x] Navigate between results (◀/▶ buttons)
- [x] Live search (auto-searches after 2 characters)
- [ ] Filter by date range
- [ ] Filter by message type (user/AI/tool)

#### Security Enhancements
- [ ] Real-time CVE fetching from NVD API
- [ ] Socket.dev integration
- [ ] Encrypted local storage option
- [ ] Session timeout settings
- [ ] Audit log export
- [ ] Auto-update blocklist from GitHub

### Low Priority

#### Window Settings
- [ ] Remember window size/position
- [ ] Remember sidebar widths
- [ ] Remember last opened conversation

#### AI Integration
- [ ] Auto-generate conversation titles
- [ ] Auto-categorize conversations
- [ ] Summarize long conversations

#### Data Playground
- [ ] Interactive data exploration
- [ ] Charts for message statistics
- [ ] Timeline view of activity
- [ ] Heatmap of productive hours

---

## 🐛 Known Issues

### UI/UX
- [ ] Some Unicode characters from custom shells don't render (❯, ⚡)
- [ ] Nested bold text may not render correctly in all cases

### Performance
- [ ] Large conversations (1000+ messages) may lag during scroll
- [ ] Initial load with many chats can be slow

### Data
- [ ] Some Cursor tool call formats may not be fully parsed
- [ ] File edit tracking not yet implemented

---

## 🎯 Future Goals

### GPUI Migration
- Prepare codebase for migration to Zed's GPUI framework
- Native Wayland support without egui intermediary
- Better text rendering and performance

### Plugin System
- Allow custom widgets in sidebars
- User-defined message renderers
- Custom theme creation

### Multi-Device Sync
- Sync bookmarks and preferences across devices
- Export/import database
- Cloud backup option

---

## 📊 Version History

### v0.2.1 (Current Session)
- Jump-to-message functionality for bookmarks and security findings
- NPM package security scanner with embedded blocklist
- Security panel with sensitive data detection
- Scroll target highlighting
- **Export to Markdown** feature
- **In-conversation search** with navigation

### v0.2.0
- Initial Cursor Studio with egui
- Full bookmark system
- Async imports
- UI customization

### v0.1.x
- Original cursor-manager (Python/Tkinter)
- Original chat-library (Python/Tkinter)
- Separate applications
