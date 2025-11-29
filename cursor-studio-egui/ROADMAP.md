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

### Bookmarks
- [x] Database schema for bookmarks
- [x] Add/remove bookmark buttons on messages (⭐/🔖)
- [x] Bookmark panel in conversation header
- [x] Bookmarks survive cache clears (persist by sequence)
- [x] Reattach bookmarks after reimport

### Import System
- [x] Async background import (doesn't freeze UI)
- [x] Progress tracking in status bar
- [x] Import warning (two-click confirm)
- [x] Multi-database support (default + versioned)

### UI Customization
- [x] Font scale slider (80%-150%)
- [x] Message spacing slider (4px-32px)
- [x] Status bar font size slider (8px-16px)
- [x] Theme selection (Dark/Light + VS Code themes)

### Analytics
- [x] Detailed stats in status bar
- [x] Tracks: user messages, AI responses, tool calls, thinking blocks, code blocks, bookmarks

---

## 🚧 In Progress

### Bold Text in Complex Blocks
- [ ] Nested **bold** within larger markdown blocks
- [ ] Bold + code mixing in same line

### Message Alignment (Recently Fixed)
- [x] All alignments now render tool calls, thinking, and content
- [x] Helper function `render_message_body()` consolidates rendering
- [ ] Verify visual consistency across all alignment modes

### Clear & Reimport (Just Added)
- [x] "Clear & Reimport" button in Dashboard
- [x] Preserves bookmarks during cache clear
- [x] Reattaches bookmarks to new message IDs by sequence
- [x] Reports reattach success/failure count

### Resource Settings (Just Added)
- [x] CPU Threads slider (1 to max cores)
- [x] RAM Limit slider (512MB - 16GB)
- [x] VRAM Limit slider (256MB - 32GB)
- [x] Storage Limit slider (1GB - 100GB)
- [ ] Actually enforce resource limits (future)
- [ ] GPU detection (NVIDIA, AMD, Intel)

### UI Fixes (Just Applied)
- [x] Message boxes now 2/3 width (was 85%)
- [x] Alignment buttons in order: Left, Center, Right
- [x] Alignment buttons show labels (◀ L, ◆ C, R ▶)
- [x] Sliders use vertical layout (prevents clipping)
- [x] Clear & Reimport description below button
- [ ] Text inside boxes always left-aligned (except toggle)

### Security Panel (Just Added)
- [x] Right sidebar mode switcher (💬 Chats | 🔒 Security)
- [x] VS Code-style icon tabs at top
- [x] Security Overview section with status card
- [x] Data Privacy section (storage location, encryption status)
- [x] API Keys & Tokens section (informational)
- [x] Security Scans section with working buttons
- [x] Audit Log section (recent activity)
- [x] Future features list
- [x] Sensitive data scanning (API keys, passwords, secrets via regex)
- [x] Scan results display with counts and previews
- [ ] Encrypted storage option
- [ ] Session timeout settings
- [ ] Audit log export

### Settings Persistence (Just Added)
- [x] Settings saved to config table in database
- [x] Settings loaded on startup
- [x] All sliders save on change (font scale, spacing, resources)
- [x] Clear & Reimport preserves favorites

### Tool Call Display (Just Added)
- [x] Full args display (collapsible, pretty-printed JSON)
- [x] Tool ID shown in header
- [x] "Show full args" toggle button

---

## 📋 Planned Features

### High Priority

#### Unicode Font Support
- [ ] Better font fallback for terminal symbols (❯, ⚡, etc.)
- [ ] Nerd Font integration
- [ ] Custom font loading from user config

#### Scroll to Bookmark
- [ ] Jump to specific message when clicking bookmark
- [ ] Highlight scrolled-to message
- [ ] Bookmark navigation (prev/next)

#### Request Segmentation
- [ ] Group messages by user request/response cycle
- [ ] Track files edited per request
- [ ] Jump between request segments
- [ ] Segment summary view

### Medium Priority

#### Files Edited Tracking
- [ ] Parse `edit_file`, `search_replace` tool calls
- [ ] Show list of files modified per conversation
- [ ] Quick link to file diffs

#### Export Features
- [ ] Export conversation to Markdown
- [ ] Export with code blocks highlighted
- [ ] Export bookmarked sections only
- [ ] Export to JSON for analysis

#### Search Improvements
- [ ] Full-text search across all conversations
- [ ] Search within conversation
- [ ] Filter by date range
- [ ] Filter by message type (user/AI/tool)

### Low Priority

#### Settings Persistence
- [ ] Save UI preferences to database
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
- [ ] Some Unicode characters from custom shells don't render
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

### v0.2.1 (Current Session - Nov 29, 2025)
**Security & Navigation:**
- Jump-to-message functionality for bookmarks and security findings
- NPM package security scanner with embedded blocklist
- Security panel with sensitive data detection (API keys, passwords, secrets)
- Scroll target highlighting for jumped-to messages

**Export Features:**
- Export conversation to Markdown (📤 button)
- Includes tool calls, thinking blocks in export
- Auto-creates export directory

**Search:**
- In-conversation search with ◀/▶ navigation
- Live search (auto-triggers after 2 characters)

### v0.2.0 - 2025-11-28
- Initial Cursor Studio with egui
- Full bookmark system
- Async imports
- UI customization

### v0.1.x
- Original cursor-manager (Python/Tkinter)
- Original chat-library (Python/Tkinter)
- Separate applications
