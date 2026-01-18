# Changelog

All notable changes to cursor-studio will be documented in this file.

## [v0.3.1] - 2026-01-18

### 🧹 Maintenance

#### Removed 1.6.x Version Support
- **cursor-1_6_45** removed from CI/CD workflows
- Cursor no longer supports 1.6.x versions (EOL)
- CI now tests 69 versions (2.3.x through 1.7.x)

### 📝 Documentation

- Updated README to v0.3.0 with Interactive Dialog System feature showcase
- Fixed version badge (was showing 0.2.1-pre)
- Updated GitHub Actions workflows to reflect current version inventory

---

## [v0.3.0] - 2026-01-18

### 🎉 New Features

#### Interactive Dialog System
A brand new way for AI agents to communicate with users without burning API requests!

- **Multiple Choice Dialogs** - Single or multi-select with descriptions
- **Text Input** - Single line or multiline with optional validation
- **Confirmation** - Yes/No with customizable labels
- **Slider** - Numeric input with min/max/step
- **Toast Notifications** - Non-blocking status updates (success, warning, error, info)

#### Comment Field on All Dialogs
Every dialog now has an optional comment field where you can add context or nuance that predefined options can't capture. The AI agent will receive this additional feedback.

#### Timer with Pause/Resume
Dialogs can have a timeout, but you can now pause/resume the timer if you need more time to think.

#### Notification Sidebar
- Click the 🔔 button to see notification history
- Notifications persist for later review
- Semi-transparent sidebar doesn't fully block content
- Mark all as read when opening

#### Sound Alerts
Toast notifications now play appropriate system sounds based on severity level.

#### Window Attention
Blocking dialogs now request window focus and flash in the taskbar to get your attention.

### ⚡ Performance

- **27% faster build times** (3m 31s → 2m 35s)
- Optimized dependency features
- Thin LTO for faster linking

### 🔧 cursor-studio Integration

New dialog commands in cursor-studio:
```bash
cursor-studio dialog enable   # Enable feature + start daemon
cursor-studio dialog disable  # Disable feature + stop daemon
cursor-studio dialog start    # Start daemon
cursor-studio dialog stop     # Stop daemon
cursor-studio dialog status   # Show status
cursor-studio dialog test     # Show test dialog
```

### 📝 Note from the Developer

Sorry for the delay! It's been over a month since v0.2.0. This release focused on building a robust foundation for agent interaction.

**Coming soon:** We have a larger feature in the pipeline - full system prompt injection and custom mode functionality via the proxy system. This is taking longer than expected to get right, but it will restore and enhance the pre-2.0.77 capabilities. Expect it in v0.4.0 or v0.5.0.

---

## [v0.2.0] - 2024-12-XX

- Initial cursor-studio launcher
- Proxy infrastructure groundwork
- Basic proxy commands

## [v0.1.0] - 2024-11-XX

- Project initialization
