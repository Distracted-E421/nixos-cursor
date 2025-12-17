# Custom Modes System for Cursor Studio

## Overview

The Custom Modes System is a comprehensive replacement for Cursor's removed built-in custom modes feature (removed in version 2.1.x). It provides full control over AI behavior, tool access, model selection, and context injection.

## Why This Exists

Starting with Cursor 2.1.6, the built-in custom modes feature was removed. This external system:

- **Restores full functionality** of custom modes
- **Works with ANY Cursor version** (2.0.x, 2.1.x, 2.2.x)
- **Provides MORE control** than the original implementation
- **Supports unlimited mode profiles**
- **Enables quick swap to vanilla** without losing configurations

## Key Features

### 🎭 Mode Management
- **Create unlimited custom modes** - No restrictions on number of profiles
- **Built-in modes** - Agent, Code Review, Planning, and Maxim (your setup)
- **Quick mode switching** - Change modes without restarting Cursor
- **Vanilla swap** - Instantly disable all customization to test vanilla Cursor

### 🔧 Tool Access Control
Three access modes for fine-grained control:

1. **All Allowed** (🔓) - Full tool access
2. **Allowlist** (🔒) - Only specified tools are available
3. **Blocklist** (🚫) - All tools except specified ones

### 🤖 Model Configuration
- **Primary model selection** - claude-opus-4, claude-4.5-sonnet, gpt-4o, etc.
- **Fallback model** - Automatic fallback if primary unavailable
- **Temperature override** - Control creativity/consistency
- **Max tokens** - Control response length

### 📜 System Prompts
- **Full system prompt control** - Define exactly how the AI should behave
- **Mode-specific instructions** - Different prompts for different tasks
- **Context injection** - Automatic environment info injection

### 🌍 Context Injection
- **Environment awareness** - Hostname, OS, user automatically included
- **Git state** - Branch, uncommitted changes, status
- **Project context** - Project-specific hints and files
- **Custom injection** - Add any text to context

## Available Toggles

### Basic Info
| Field | Description |
|-------|-------------|
| **Name** | Display name for the mode |
| **Icon** | Emoji icon (🤖, 🔍, 📋, etc.) |
| **Description** | Brief description of mode purpose |

### Tool Access
| Option | Description |
|--------|-------------|
| **Access Mode** | All Allowed / Allowlist / Blocklist |
| **Allowed Tools** | Tools available when using Allowlist mode |
| **Blocked Tools** | Tools blocked when using Blocklist mode |

### Common Tools
- `read_file` - Read file contents
- `write` - Write/create files
- `edit_file` - Edit existing files
- `delete_file` - Delete files
- `grep` - Search in files
- `run_terminal_cmd` - Execute terminal commands
- `mcp_memory_*` - Memory MCP tools
- `mcp_github_*` - GitHub MCP tools

### Model Configuration
| Option | Description |
|--------|-------------|
| **Primary Model** | Model to use for this mode |
| **Fallback Model** | Backup if primary unavailable |
| **Temperature** | 0.0-2.0 (creativity control) |
| **Max Tokens** | Maximum response length |

### Available Models
- `claude-opus-4` - Most capable, deep reasoning
- `claude-4.5-sonnet` - Balanced (recommended)
- `claude-4-sonnet` - Previous generation
- `claude-3.5-haiku` - Fast and efficient
- `gpt-4o` - OpenAI's latest
- `gpt-4-turbo` - OpenAI turbo
- `o1` / `o1-mini` - Reasoning models
- `gemini-2.0-flash` - Google's latest

### Context Configuration
| Option | Description |
|--------|-------------|
| **Include Environment** | Hostname, OS, user info |
| **Include Git** | Branch, status, uncommitted changes |
| **Include Project** | Project-specific context files |
| **Additional Files** | Paths to include in context |
| **Custom Injection** | Raw text to append |

## Injection Targets

Modes can be injected to multiple targets:

### `.cursorrules` (📄)
- Single file in project root
- Cursor reads automatically
- Contains full mode configuration

### `.cursor/rules/` (📁)
- Mode-specific rule file
- Named `<mode-name>.mdc`
- Part of Cursor's rules system

### AI Workspace (🧠)
- Updates `.ai-workspace/hints.md`
- Updates `.ai-workspace/relevant-tools.md`
- Updates `.ai-workspace/context/current.json`

### All Targets (🎯)
- Injects to all three targets
- Maximum coverage and redundancy

## Built-in Modes

### Agent (🤖)
- **Purpose**: Full autonomous agent
- **Tools**: All allowed
- **Model**: claude-opus-4
- **Focus**: Complete task autonomously

### Code Review (🔍)
- **Purpose**: Review code without modifications
- **Tools**: Write/edit/delete blocked
- **Model**: claude-4.5-sonnet
- **Focus**: Quality, security, maintainability

### Planning (📋)
- **Purpose**: Create detailed plans before execution
- **Tools**: Write/edit/delete/terminal blocked
- **Model**: claude-opus-4
- **Focus**: Think before acting

### Maxim (🖥️)
- **Purpose**: Your Obsidian workstation agent
- **Tools**: All allowed
- **Model**: claude-4.5-sonnet
- **Focus**: Proactive with safety guardrails

## Usage

### In Cursor Studio GUI

1. Click the **🎭** button in the activity bar
2. Select a mode from the dropdown or list
3. Click **▶️** to activate
4. Click **🚀** section to inject to Cursor

### Creating a New Mode

1. Click **➕ New** in the Modes panel header
2. Enter a name
3. Click **Create**
4. Edit all settings in the collapsible sections
5. Click **💾 Save**

### Switching Modes

1. Use the **Active Mode** dropdown
2. Or click **▶️** on any mode in the list
3. Use **⟲ Vanilla** for quick disable

### Injecting Mode

After activating a mode:
1. Scroll to **🚀 Inject Active Mode**
2. Choose target:
   - **📄 .cursorrules** - Main cursor rules
   - **📁 .cursor/rules/** - Rules directory
   - **🧠 AI Workspace** - AI context
   - **🎯 All** - All targets

## File Storage

Modes are stored in:
```
~/.config/cursor-studio/modes/
├── registry.json
├── agent.json
├── code-review.json
├── planning.json
├── maxim.json
└── <custom-modes>.json
```

## Integration with Cursor Versions

| Version | Native Modes | This System |
|---------|--------------|-------------|
| 2.0.x | ✅ Yes | ✅ Works |
| 2.1.x | ❌ Removed | ✅ Replacement |
| 2.2.x | ❌ Removed | ✅ Replacement |

## Best Practices

### For Code Review
```
- Block: write, edit_file, delete_file, run_terminal_cmd
- Use: read_file, grep, mcp_github_*
- Focus on analysis, not changes
```

### For Planning
```
- Block: write, edit_file, delete_file, run_terminal_cmd
- Include: Project context, git state
- Create detailed plans before approval
```

### For Development
```
- All tools allowed
- Include: Environment, git, project
- Use safety prompts from Maxim mode
```

## Version Compatibility

This system is designed to work across all Cursor versions:

- **2.0.77** (last with native modes) - Both systems work
- **2.1.6+** - This system is the only option
- **2.2.27** (latest) - Fully supported

## Future Roadmap

- [ ] Mode sharing/export/import
- [ ] Cloud sync for modes
- [ ] Mode templates marketplace
- [ ] Keyboard shortcuts for mode switching
- [ ] Automatic mode detection based on project type
- [ ] Integration with Cursor's internal APIs (when available)

---

*Part of the Cursor Studio project - Building a bridge out of the IDE dead end.*

