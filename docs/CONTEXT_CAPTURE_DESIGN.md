# Context Capture Design for Cursor Studio

## Overview

This document outlines how cursor-studio can capture and export comprehensive context from Cursor IDE conversations, enabling full reconstruction of AI agent sessions.

## Data Sources

### 1. Global State Database
**Location:** `~/.config/Cursor/User/globalStorage/state.vscdb`

#### Tables
- `ItemTable` - Key-value store for IDE settings
- `cursorDiskKV` - Key-value store for conversation data

#### Key Prefixes in `cursorDiskKV`
| Prefix | Description |
|--------|-------------|
| `composerData:{uuid}` | Full conversation metadata and state |
| `bubbleId:{composer}:{bubble}` | Individual message data |
| `checkpointId:{uuid}` | Checkpoint/restore points |
| `codeBlockDiff:{uuid}` | Code diff data |
| `inlineDiffs-{timestamp}` | Inline diff history |

### 2. Workspace State Databases
**Location:** `~/.config/Cursor/User/workspaceStorage/{hash}/state.vscdb`

Contains workspace-specific context like:
- Disabled MCP servers
- Workspace-specific settings
- Recent file history

---

## Data Structures

### ComposerData (Conversation Level)

```json
{
  "_v": 1,
  "composerId": "uuid",
  "name": "Conversation title",
  "createdAt": 1733150000000,
  "lastUpdatedAt": 1733150000000,
  
  // === CONTEXT PROVIDED TO AGENT ===
  "context": {
    "cursorRules": [],           // Active .cursor/rules files
    "fileSelections": [],        // @-mentioned files
    "folderSelections": [],      // @-mentioned folders
    "selections": [],            // Code selections
    "terminalSelections": [],    // Terminal output shared
    "mentions": [],              // @-mentions
    "quotes": [],                // Quoted text
    "selectedDocs": [],          // Documentation references
    "selectedImages": [],        // Images shared
    "selectedCommits": [],       // Git commits referenced
    "selectedPullRequests": [],  // PRs referenced
    "externalLinks": [],         // URLs shared
    "consoleLogs": [],           // Console output
    "ideEditorsState": {},       // Open editors state
    "uiElementSelections": [],   // UI elements picked
    "cursorCommands": []         // Custom commands used
  },
  
  // === CAPABILITIES & MCP ===
  "capabilities": [],
  "capabilityContexts": {},
  
  // === CONVERSATION STATE ===
  "conversationMap": {},        // Message order
  "fullConversationHeadersOnly": [],
  
  // === MODEL CONFIGURATION ===
  "modelConfig": {},
  
  // === FILE CHANGES ===
  "addedFiles": [],
  "removedFiles": [],
  "newlyCreatedFiles": [],
  "newlyCreatedFolders": [],
  "originalFileStates": {},
  "filesChangedCount": 0,
  "totalLinesAdded": 0,
  "totalLinesRemoved": 0,
  
  // === METADATA ===
  "isAgentic": false,
  "isArchived": false,
  "status": "completed",
  "text": "user query text",
  "richText": {},
  "usageData": {}
}
```

### BubbleData (Message Level)

```json
{
  "_v": 1,
  "bubbleId": "uuid",
  "type": "user|assistant",
  "createdAt": 1733150000000,
  
  // === MESSAGE CONTENT ===
  "text": "message text",
  "richText": {},
  
  // === MODEL INFO ===
  "modelInfo": {
    "modelName": "claude-4.5-sonnet-thinking"
  },
  "tokenCount": 1234,
  
  // === CONTEXT FOR THIS MESSAGE ===
  "context": {},
  "contextPieces": [],
  "cursorRules": [],
  "attachedCodeChunks": [],
  "attachedFolders": [],
  "codebaseContextChunks": [],
  "recentlyViewedFiles": [],
  "recentLocationsHistory": [],
  "relevantFiles": [],
  
  // === MCP & TOOLS ===
  "mcpDescriptors": [],         // MCP server metadata
  "supportedTools": [],         // Available tools list
  "toolResults": [],            // Tool call results
  "capabilities": [],
  "capabilityContexts": [],
  "capabilityStatuses": [],
  
  // === AI THINKING ===
  "allThinkingBlocks": [],      // Claude's <thinking> blocks!
  
  // === CODE CHANGES ===
  "assistantSuggestedDiffs": [],
  "diffHistories": [],
  "suggestedCodeBlocks": [],
  "fileDiffTrajectories": [],
  "gitDiffs": [],
  "deletedFiles": [],
  
  // === EXTERNAL DATA ===
  "aiWebSearchResults": [],
  "webReferences": [],
  "docsReferences": [],
  "images": [],
  "interpreterResults": [],
  
  // === METADATA ===
  "isAgentic": false,
  "checkpointId": "uuid"
}
```

### ItemTable Keys (Global Settings)

| Key | Description |
|-----|-------------|
| `mcpService.knownServerIds` | List of configured MCP server IDs |
| `aicontext.personalContext` | User's personal context/preferences |
| `freeBestOfN.promptCount` | Usage statistics |

### Workspace-Specific Keys

| Key | Description |
|-----|-------------|
| `cursor/disabledMcpServers` | MCP servers disabled for this workspace |

---

## Export Format Design

### Full Session Export (JSON)

```json
{
  "version": "1.0.0",
  "exportedAt": "2025-12-02T12:00:00Z",
  "exportedBy": "cursor-studio v0.2.0",
  
  "session": {
    "id": "composer-uuid",
    "name": "Conversation Title",
    "createdAt": "2025-12-02T10:00:00Z",
    "lastUpdatedAt": "2025-12-02T12:00:00Z",
    "messageCount": 42,
    "totalTokens": 125000
  },
  
  "environment": {
    "cursorVersion": "0.44.11",
    "os": "linux",
    "workspace": "/home/user/project"
  },
  
  "mcpConfiguration": {
    "servers": [
      {
        "id": "user-filesystem",
        "name": "Filesystem",
        "enabled": true,
        "tools": ["read_file", "write_file", "list_directory"]
      }
    ]
  },
  
  "cursorRules": [
    {
      "path": ".cursor/rules/safety.mdc",
      "content": "# Safety Rules...",
      "appliedAt": "2025-12-02T10:00:00Z"
    }
  ],
  
  "context": {
    "files": [
      {
        "path": "src/main.rs",
        "content": "...",
        "selection": { "start": 10, "end": 50 }
      }
    ],
    "folders": ["/src", "/tests"],
    "images": [],
    "webLinks": [],
    "gitCommits": [],
    "pullRequests": []
  },
  
  "messages": [
    {
      "id": "bubble-uuid",
      "type": "user",
      "timestamp": "2025-12-02T10:00:00Z",
      "content": {
        "text": "User message...",
        "richText": {}
      },
      "attachments": [],
      "context": {}
    },
    {
      "id": "bubble-uuid-2",
      "type": "assistant",
      "timestamp": "2025-12-02T10:00:05Z",
      "model": {
        "name": "claude-4.5-sonnet-thinking",
        "provider": "anthropic"
      },
      "content": {
        "text": "Assistant response...",
        "richText": {}
      },
      "thinking": [
        "First, I need to understand...",
        "The approach should be..."
      ],
      "toolCalls": [
        {
          "tool": "read_file",
          "server": "filesystem",
          "input": { "path": "src/main.rs" },
          "output": "...",
          "duration": 50
        }
      ],
      "codeChanges": [
        {
          "file": "src/main.rs",
          "type": "edit",
          "diff": "...",
          "accepted": true
        }
      ],
      "webSearches": [],
      "tokenCount": 5000
    }
  ],
  
  "summary": {
    "filesModified": ["src/main.rs"],
    "filesCreated": ["src/new.rs"],
    "filesDeleted": [],
    "totalLinesAdded": 150,
    "totalLinesRemoved": 20,
    "toolCallsCount": 15,
    "webSearchesCount": 2
  }
}
```

### Markdown Export (Human Readable)

```markdown
# Cursor Session Export

**Session:** [Title]
**Date:** 2025-12-02 10:00 - 12:00
**Model:** claude-4.5-sonnet-thinking
**Messages:** 42 | **Tokens:** 125,000

---

## Environment

- **Cursor Version:** 0.44.11
- **Workspace:** /home/user/project
- **OS:** Linux

## MCP Servers Active

- ✅ Filesystem (read_file, write_file, list_directory)
- ✅ Memory (store, retrieve, search)
- ✅ GitHub (commit, push, create_pr)

## Cursor Rules Applied

### `.cursor/rules/safety.mdc`
```
# Safety Rules
...
```

---

## Conversation

### User (10:00:00)

> Please help me refactor the authentication module...

**Context Provided:**
- 📄 `src/auth/mod.rs` (lines 1-50)
- 📁 `/src/auth/`
- 🔗 https://docs.rs/jwt

---

### Assistant (10:00:05)

<thinking>
First, I need to understand the current authentication flow...
</thinking>

I'll help you refactor the authentication module. Let me first examine the current structure...

**Tool Calls:**
1. `read_file(src/auth/mod.rs)` → 150 lines
2. `list_directory(/src/auth)` → 5 files

**Code Changes:**
- `src/auth/mod.rs` (+50, -20 lines) ✅ Accepted

---

## Summary

| Metric | Value |
|--------|-------|
| Files Modified | 3 |
| Files Created | 1 |
| Lines Added | 150 |
| Lines Removed | 20 |
| Tool Calls | 15 |
| Web Searches | 2 |
```

---

## Implementation Plan

### Phase 1: Data Extraction (v0.2.x)

1. **Read composerData** - Extract conversation metadata
2. **Read bubbleData** - Extract message content and context
3. **Read ItemTable** - Extract MCP configuration
4. **Correlate workspace** - Match workspace hash to project path

### Phase 2: Context Reconstruction (v0.3.x)

1. **Reconstruct file context** - Match file selections to actual files
2. **Reconstruct MCP state** - Show which tools were available
3. **Reconstruct rules** - Show which cursor rules were active
4. **Link thinking blocks** - Associate Claude's thinking with messages

### Phase 3: Export Formats (v0.3.x)

1. **JSON export** - Full structured data
2. **Markdown export** - Human-readable conversation
3. **HTML export** - Interactive viewer with syntax highlighting

### Phase 4: Replay/Analysis (v0.4.x)

1. **Session replay** - Step through conversation with context
2. **Token analysis** - Visualize token usage over time
3. **Tool usage patterns** - Analyze MCP tool effectiveness
4. **Context efficiency** - Identify over/under-contextualization

---

## CLI Commands

```bash
# Export conversation with full context
cursor-studio-cli export <composer-id> --format json --output session.json

# Export with markdown for documentation
cursor-studio-cli export <composer-id> --format markdown --output session.md

# List all conversations with context summary
cursor-studio-cli list --show-context

# Analyze context usage in conversation
cursor-studio-cli analyze <composer-id> --context-usage

# Show MCP tool usage
cursor-studio-cli analyze <composer-id> --tool-usage
```

---

## GUI Features

### Export Dialog
- [ ] Select export format (JSON/Markdown/HTML)
- [ ] Choose what to include:
  - [ ] Full message content
  - [ ] Thinking blocks
  - [ ] Tool call details
  - [ ] Code diffs
  - [ ] Context files
  - [ ] Cursor rules
- [ ] Redaction options (API keys, paths)

### Context Viewer
- [ ] Show files attached to each message
- [ ] Show cursor rules that were active
- [ ] Show MCP servers and tools available
- [ ] Visualize token budget usage

### Session Replay
- [ ] Step through messages chronologically
- [ ] Show context at each step
- [ ] Highlight code changes
- [ ] Replay tool calls

---

## Security Considerations

### Data Redaction
- Detect and redact API keys/secrets
- Option to anonymize file paths
- Remove sensitive content from exports

### Export Permissions
- Warn when exporting to shared locations
- Option to encrypt exports
- Audit log of exports

---

## Database Query Examples

### Get all conversations with MCP usage
```sql
SELECT key, json_extract(value, '$.name') as name,
       json_extract(value, '$.modelConfig') as model
FROM cursorDiskKV 
WHERE key LIKE 'composerData:%'
ORDER BY json_extract(value, '$.lastUpdatedAt') DESC;
```

### Get messages with thinking blocks
```sql
SELECT key, 
       json_extract(value, '$.modelInfo.modelName') as model,
       json_array_length(json_extract(value, '$.allThinkingBlocks')) as thinking_count
FROM cursorDiskKV 
WHERE key LIKE 'bubbleId:%'
  AND json_array_length(json_extract(value, '$.allThinkingBlocks')) > 0;
```

### Get MCP server configuration
```sql
SELECT value FROM ItemTable 
WHERE key = 'mcpService.knownServerIds';
```

---

## References

- [Cursor Database Analysis Guide](CURSOR_DATABASE_ANALYSIS_GUIDE.md)
- [MCP Servers Documentation](../README.md)
- [cursor-studio README](../cursor-studio-egui/README.md)
