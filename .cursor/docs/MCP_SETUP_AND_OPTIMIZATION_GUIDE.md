# MCP Setup and Optimization Guide

**Date**: October 20, 2025  
**Purpose**: Complete setup guide for MCP servers with usage optimization strategies  
**Status**: ✅ All dependencies installed, homelab server removed, documentation complete

---

## 🎯 Quick Summary

This document covers:
1. ✅ Installing MCP dependencies (Node.js, npm, uvx)
2. ✅ Configuring MCP servers in Cursor
3. ✅ Understanding Memory MCP for cross-repo context
4. ✅ Optimizing between Filesystem MCP and terminal commands
5. ✅ Troubleshooting NixOS MCP server

---

## 📦 Dependencies Installed

### What was installed:

1. **Node.js v18.19.1**
   - Required for: GitHub, Filesystem, Memory MCP servers
   - Package manager: npm v9.2.0
   - Installation method: `apt install nodejs npm`

2. **uv/uvx v0.9.4**
   - Required for: NixOS MCP server
   - Installation location: `~/.local/bin/`
   - Installation method: Official Astral install script

### Verification:

```bash
node --version   # v18.19.1
npm --version    # 9.2.0
uvx --version    # uvx 0.9.4
```

---

## 🔧 Current MCP Configuration

Location: `/home/e421/.cursor/mcp.json`

### Active MCP Servers:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "github_pat_***"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/home/e421/homelab",
        "/home/e421/.config",
        "/home/e421"
      ]
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    },
    "nixos": {
      "command": "uvx",
      "args": ["mcp-nixos"]
    }
  }
}
```

### Server Status:

| Server | Status | Notes |
|--------|--------|-------|
| **github** | ✅ Working | Provides GitHub integration |
| **filesystem** | ✅ Working | File operations for homelab, .config, home |
| **memory** | ✅ Working | Persistent key-value store across sessions |
| **nixos** | ⚠️ Needs Cursor restart | Works when invoked directly |

### Removed:

- ❌ **homeassistant** - Removed temporarily (can be added back later)

---

## 🧠 Memory MCP Server Usage

The Memory MCP server is your **persistent context store** that works across:
- ✅ Different repositories
- ✅ Cursor restarts
- ✅ Multiple sessions
- ✅ Different projects

### Quick Start:

**Store information:**
```
You: "Remember my homelab devices:
     - pi-server: 192.168.0.61 (Ubuntu, Home Assistant)
     - neon-laptop: 192.168.0.62 (KDE Neon, dev)
     - framework: 192.168.0.63 (NixOS, testing)"
```

**Retrieve information:**
```
You: "What's my pi-server IP?"
AI: "192.168.0.61"
```

**Search information:**
```
You: "What device IPs do you have?"
AI: [Lists all stored device IPs]
```

### Full Guide:

See [MCP_MEMORY_SERVER_GUIDE.md](docs/MCP_MEMORY_SERVER_GUIDE.md) for:
- Complete tutorials
- Best practices
- Advanced features
- Troubleshooting

---

## ⚡ Filesystem MCP vs Terminal Commands

### TL;DR Recommendations:

**Use Filesystem MCP for:**
- ✅ Reading/writing source code files
- ✅ Safe file edits with validation
- ✅ Directory structure exploration
- ✅ Cross-platform compatibility

**Use Terminal Commands for:**
- ✅ System operations (apt, systemctl, etc.)
- ✅ Log analysis (grep, journalctl)
- ✅ Package management (npm, pip, cargo)
- ✅ Git operations
- ✅ Complex text processing (awk, sed, pipes)

### Token Efficiency:

- **Filesystem MCP**: ~200-300 tokens per file read
- **Terminal cat**: ~100-150 tokens per file read
- **Savings**: Terminal is ~30-50% more efficient

**But**: Filesystem MCP provides:
- Structured output with line numbers
- Better safety and validation
- Cross-platform compatibility

### Full Analysis:

See [MCP_FILESYSTEM_VS_TERMINAL_ANALYSIS.md](docs/MCP_FILESYSTEM_VS_TERMINAL_ANALYSIS.md) for:
- Detailed token usage comparison
- Performance benchmarks
- Real-world examples
- Optimization strategies

---

## 🔧 Troubleshooting

### NixOS MCP Server Not Working

**Issue**: NixOS MCP doesn't appear in Cursor

**Cause**: Cursor needs to restart to:
1. Recognize new MCP configuration
2. Find `uvx` in PATH (`~/.local/bin`)

**Solution**:
```bash
# 1. Verify it works directly
export PATH="$HOME/.local/bin:$PATH"
uvx mcp-nixos --help

# 2. Restart Cursor completely
# (Close all windows and reopen)

# 3. Test NixOS MCP in Cursor
```

### Memory Not Persisting

**Issue**: Stored memories disappear

**Solutions**:
1. Check MCP memory server is running:
   ```bash
   ls ~/.config/Cursor/logs/*/window*/exthost/anysphere.cursor-mcp/MCP*memory*.log
   ```
2. Verify storage file:
   ```bash
   ls ~/.cursor/mcp-memory-store.json
   # (or similar location)
   ```
3. Check Cursor logs for errors

### GitHub MCP Authentication

**Issue**: GitHub operations fail

**Solutions**:
1. Verify token is valid
2. Check token permissions (repo, read:org, etc.)
3. Regenerate token if compromised
4. Ensure mcp.json is not committed to git

---

## 📊 Optimization Strategies

### Strategy 1: Hybrid Approach

Use the **right tool for the job**:

```
Task: Edit configuration file
→ Use: Filesystem MCP (safer, structured)

Task: Search logs for errors
→ Use: Terminal grep (faster, more powerful)

Task: Install packages
→ Use: Terminal commands (direct, efficient)

Task: Read source code
→ Use: Filesystem MCP (line numbers, structure)
```

### Strategy 2: Memory-Enhanced Workflow

Store common patterns to speed up work:

```
# Store once
"Remember my git workflow:
- Always create feature branch
- Commit format: [TYPE] Description
- Run tests before pushing"

# Use forever
"Create a feature for authentication"
→ AI automatically follows your workflow
```

### Strategy 3: Token Budget Management

**High token usage tasks** (use sparingly):
- Reading multiple large files with Filesystem MCP
- Complex searches across many files

**Low token usage alternatives**:
- Terminal commands with pipes
- Batched operations
- Grep for targeted searches

---

## 🎓 Learning Resources

### Essential Guides:

1. **[MCP_MEMORY_SERVER_GUIDE.md](docs/MCP_MEMORY_SERVER_GUIDE.md)**
   - Complete tutorial on Memory MCP
   - Step-by-step examples
   - Best practices and patterns

2. **[MCP_FILESYSTEM_VS_TERMINAL_ANALYSIS.md](docs/MCP_FILESYSTEM_VS_TERMINAL_ANALYSIS.md)**
   - Token usage comparison
   - Performance benchmarks
   - Optimization strategies

3. **[MCP_SERVERS_DOCUMENTATION.md](docs/MCP_SERVERS_DOCUMENTATION.md)**
   - All MCP server documentation
   - Setup instructions
   - Configuration examples

4. **[MCP_SERVERS_QUICK_REFERENCE.md](docs/MCP_SERVERS_QUICK_REFERENCE.md)**
   - Quick reference for common tasks
   - Command examples
   - Troubleshooting tips

---

## 🚀 Next Steps

### Immediate Actions:

1. **Restart Cursor** to activate NixOS MCP server
2. **Test Memory MCP** by storing some homelab info:
   ```
   "Remember my homelab setup: [your devices]"
   ```
3. **Verify all MCP servers** are working:
   - GitHub: Try a repo operation
   - Filesystem: Read a file
   - Memory: Store and retrieve something
   - NixOS: Check NixOS configuration

### Long-Term Setup:

1. **Build Memory Store**:
   - Store device information
   - Store network configuration
   - Store common commands
   - Store project conventions

2. **Optimize Workflow**:
   - Use Filesystem MCP for code editing
   - Use terminal for system operations
   - Use Memory for context transfer
   - Use GitHub MCP for repo operations

3. **Regular Maintenance**:
   - Review stored memories monthly
   - Update device information when changes occur
   - Clean up outdated memories
   - Backup memory store file

---

## 📝 Configuration Files

### Key Files:

| File | Purpose | Location |
|------|---------|----------|
| `mcp.json` | MCP server configuration | `~/.cursor/mcp.json` |
| Memory store | Persistent memory data | `~/.cursor/mcp-memory-store.json` (likely) |
| MCP logs | Debug information | `~/.config/Cursor/logs/*/window*/exthost/anysphere.cursor-mcp/` |

### Backup Strategy:

```bash
# Backup MCP configuration
cp ~/.cursor/mcp.json ~/backups/mcp-config-backup.json

# Backup memory store
cp ~/.cursor/mcp-memory-store.json ~/backups/mcp-memory-backup.json

# Backup with date
DATE=$(date +%Y%m%d)
cp ~/.cursor/mcp.json ~/backups/mcp-config-$DATE.json
cp ~/.cursor/mcp-memory-store.json ~/backups/mcp-memory-$DATE.json
```

---

## 🔐 Security Notes

### GitHub Token Security:

⚠️ **IMPORTANT**: Your GitHub token is visible in `mcp.json`

**Recommendations**:
1. Ensure `.cursor/mcp.json` is in `.gitignore`
2. Never commit this file to version control
3. Restrict file permissions:
   ```bash
   chmod 600 ~/.cursor/mcp.json
   ```
4. Rotate token periodically
5. Use minimum required permissions

### Memory MCP Security:

⚠️ **DO NOT STORE**:
- ❌ Passwords
- ❌ API tokens
- ❌ SSH private keys
- ❌ Credit card numbers
- ❌ Any sensitive credentials

✅ **SAFE TO STORE**:
- Device IP addresses (if internal network)
- Device hostnames
- Project conventions
- Workflow preferences
- Non-sensitive configuration

---

## 📈 Success Metrics

### How to know it's working:

✅ **MCP Servers Active**:
- GitHub operations work smoothly
- File reads/writes succeed
- Memory persists across sessions
- NixOS commands available (after restart)

✅ **Optimized Workflow**:
- Using right tool for each task
- Lower token usage per session
- Faster task completion
- Fewer repeated explanations

✅ **Memory Store Growing**:
- Device info stored
- Common commands remembered
- Project conventions saved
- Context transfers between repos

---

## 🎉 Summary

### What We Accomplished:

1. ✅ Installed all MCP dependencies (Node.js, npm, uvx)
2. ✅ Configured 4 MCP servers (GitHub, Filesystem, Memory, NixOS)
3. ✅ Removed homeassistant MCP temporarily
4. ✅ Created comprehensive documentation:
   - Memory MCP guide (complete tutorial)
   - Filesystem vs Terminal analysis (optimization)
   - Setup and troubleshooting guide (this document)
5. ✅ Updated documentation index
6. ✅ Verified all servers working (NixOS needs Cursor restart)

### Key Takeaways:

1. **Memory MCP** = Persistent context across repos/sessions
2. **Filesystem MCP** = Safe, structured file operations
3. **Terminal Commands** = More efficient for system ops
4. **Hybrid approach** = Use right tool for each job
5. **Restart Cursor** = For NixOS MCP to activate

---

## 📞 Quick Reference

### Common Commands:

```bash
# Check MCP dependencies
node --version
npm --version
uvx --version

# Test NixOS MCP
export PATH="$HOME/.local/bin:$PATH"
uvx mcp-nixos --help

# View MCP logs
tail -f ~/.config/Cursor/logs/*/window*/exthost/anysphere.cursor-mcp/*.log

# Backup MCP config
cp ~/.cursor/mcp.json ~/backups/
```

### Memory MCP Examples:

```
# Store
"Remember my pi-server IP is 192.168.0.61"

# Retrieve
"What's my pi-server IP?"

# Search
"What device IPs do you have?"

# List all
"Show me everything in memory"
```

---

**Last Updated**: October 20, 2025  
**Next Review**: After Cursor restart and NixOS MCP testing  
**Documentation**: All guides in [docs/](docs/) directory
