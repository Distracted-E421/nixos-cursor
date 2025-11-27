# Cursor User Data Persistence

**Issue**: After updating Cursor or switching versions, custom agents/settings don't show up.

**Root Cause**: Cursor stores user data in `~/.config/Cursor/` and `~/.cursor/`, but some features (like custom agents) are **workspace-specific**, stored in `.cursor/agents/` within each project.

---

## 📁 Where Cursor Stores Data

### Global Data (Persists Across Updates)

- **`~/.config/Cursor/User/settings.json`** - Global settings
- **`~/.config/Cursor/User/keybindings.json`** - Custom keybindings
- **`~/.config/Cursor/extensions/`** - Installed extensions
- **`~/.cursor/mcp.json`** - MCP server config (symlinked by Home Manager)

### Workspace-Specific Data (Per Project)

- **`.cursor/agents/`** - Custom agents (Maxim, Gorky, etc.)
- **`.cursor/rules/`** - Workspace rules
- **`.cursorrules`** - Cursor rules file
- **`.cursor/mcp.json`** - Workspace MCP config (overrides global)

### Version-Specific Data (Multi-Version Mode)

With nixos-cursor v0.1.0+, each version can have isolated data:

- **`~/.cursor-2.0.77/`** - Data for version 2.0.77
- **`~/.cursor-1.7.54/`** - Data for version 1.7.54
- **`~/.cursor-VERSION/extensions/`** - Version-specific extensions

### Shared Data (Unique Feature)

The **Share Docs & Auth** feature symlinks `globalStorage` across versions:

- **Single login** - Authenticate once, use everywhere
- **Shared indexed docs** - `@Docs` available in all versions
- This is **not possible in base Cursor**!

---

## ✅ Solutions

### Option 1: Always Open Cursor with Workspace

```bash
# Add to your shell aliases
alias cursor='cursor ~/homelab'

# Or create a launcher script
cat > ~/bin/cursor-homelab << 'EOF'
#!/usr/bin/env bash
cursor ~/homelab "$@"
EOF
chmod +x ~/bin/cursor-homelab
```

### Option 2: Make Agents Global (Symlink)

```bash
# Symlink workspace agents to global location
mkdir -p ~/.cursor/agents
ln -sf ~/homelab/.cursor/agents/* ~/.cursor/agents/

# Cursor will then load these agents globally
```

**Note**: Workspace-specific agents are intentional - different projects may need different agents.

### Option 3: Verify Workspace on Startup

Add to your Cursor `settings.json`:

```json
{
  "window.restoreWindows": "all",
  "window.reopenFolders": "all"
}
```

This ensures Cursor reopens your last workspace (homelab) on startup.

---

## 🧪 Testing After Update

After running `./update.sh` and updating Cursor:

### 1. Check Agents Load

```bash
# Open Cursor with homelab workspace
cursor ~/homelab

# Verify agents show in UI
# Top right → Agent selector → Should see: Maxim, Gorky, etc.
```

### 2. Check MCP Servers

```bash
# Verify MCP config
cat ~/.cursor/mcp.json | jq '.mcpServers | keys'

# Should show: filesystem, memory, nixos, github, playwright
```

### 3. Check Settings Persisted

```bash
# Verify settings
cat ~/.config/Cursor/User/settings.json | jq
```

---

## 🔧 Troubleshooting

### Agents Missing After Update

**Check**:

```bash
ls -la ~/homelab/.cursor/agents/
# Should show: maxim.json, gorky.json, etc.
```

**Verify** Cursor opened with workspace:

```bash
ps aux | grep cursor | grep homelab
# Should show cursor process with /home/e421/homelab argument
```

**If still missing**:

1. Close all Cursor windows
2. Open explicitly: `cursor ~/homelab`
3. Check agent selector in UI

### MCP Servers Not Working

**Check** symlink:

```bash
ls -la ~/.cursor/mcp.json
# Should point to: /nix/store/.../home-manager-files/.cursor/mcp.json
```

**Restart** MCP servers:

```bash
# Kill existing servers
pkill -f 'mcp-server'

# Cursor will restart them automatically
```

### MCP First-Run Terminal Prompt Issues

**Symptom**: When MCP servers start for the first time, you see prompts in the terminal but:

- Text input is invisible (no echo when typing)
- No feedback after entering values
- Terminal appears to hang or "break"

**Cause**: The `npx` command downloads MCP packages on first run. Some npm packages may have initialization prompts that don't handle terminal I/O properly.

**Solution** (v0.1.2+): The Home Manager module now:

1. **Pre-caches packages** during `home-manager switch` activation
2. **Uses wrapper scripts** with `NPM_CONFIG_YES=true` and `CI=true` environment variables
3. **Avoids interactive prompts** entirely

**Manual Fix** (if using older version):

```bash
# Pre-download MCP packages manually
export NPM_CONFIG_YES=true
export CI=true
npx -y @modelcontextprotocol/server-filesystem --help
npx -y @modelcontextprotocol/server-github --help

# Now restart Cursor - no prompts should appear
```

**If still experiencing issues**:

```bash
# Clear npm cache and retry
npm cache clean --force
rm -rf ~/.npm/_npx

# Re-run home-manager to trigger pre-caching
home-manager switch
```

### Settings Reset After Update

**Symptom**: Font sizes, themes, keybindings reset

**Cause**: Cursor reads `~/.config/Cursor/User/settings.json` - this should persist

**Check**:

```bash
# Verify settings file exists
cat ~/.config/Cursor/User/settings.json

# Check modification time
ls -l ~/.config/Cursor/User/settings.json
```

**If reset**: Settings were likely in an old version-specific location. Re-apply via Home Manager:

```nix
programs.cursor-ide.userSettings = {
  "window.zoomLevel" = 1.75;
  # ... your settings ...
};
```

---

## 📊 What Persists vs. What Doesn't

| Data Type | Location | Persists Across Updates? |
|-----------|----------|-------------------------|
| **Global settings** | `~/.config/Cursor/User/settings.json` | ✅ Yes |
| **Keybindings** | `~/.config/Cursor/User/keybindings.json` | ✅ Yes |
| **Extensions** | `~/.config/Cursor/extensions/` | ✅ Yes |
| **MCP config (global)** | `~/.cursor/mcp.json` | ✅ Yes (symlinked) |
| **Workspace agents** | `~/homelab/.cursor/agents/` | ✅ Yes (if workspace opened) |
| **Workspace rules** | `~/homelab/.cursor/rules/` | ✅ Yes (if workspace opened) |
| **Auth & Docs (shared)** | `~/.cursor-VERSION/globalStorage/` | ✅ Yes (if sharing enabled) |
| **Cache** | `~/.config/Cursor/Cache/` | ❌ No (rebuilt per version) |
| **Code Cache** | `~/.config/Cursor/Code Cache/` | ❌ No (version-specific) |

---

## 🎯 Recommended Workflow

### When Updating Cursor

1. **Close Cursor** (save any unsaved work)
2. **Run update script**: `cd cursor && ./update.sh`
3. **Build new version**: `nix build .#cursor`
4. **Test before switching**:

   ```bash
   # Test new version
   ./result/bin/cursor ~/homelab
   
   # Check agents load
   # Check MCP servers work
   # Check settings persisted
   ```

5. **If good, commit and switch**: `home-manager switch`
6. **If issues, rollback**: `home-manager switch --rollback`

### Always Open with Workspace

```bash
# ~/.bashrc or ~/.zshrc
alias cursor='cursor ~/homelab'
```

This ensures agents always load.

---

## 🔐 Data Safety

**What's Safe to Delete (Cache)**:

- `~/.config/Cursor/Cache/` - Cursor will rebuild
- `~/.config/Cursor/CachedData/` - Version-specific cache
- `~/.config/Cursor/Code Cache/` - Renderer cache

**What's NEVER Safe to Delete**:

- `~/.config/Cursor/User/` - **YOUR SETTINGS**
- `~/.config/Cursor/extensions/` - Installed extensions
- `~/homelab/.cursor/` - **YOUR CUSTOM AGENTS**

---

## 📝 Future Improvements

### Home Manager Integration (Planned)

```nix
programs.cursor-ide = {
  enable = true;
  
  # Global agents (applied to all workspaces)
  globalAgents = {
    maxim = ./agents/maxim.json;
    gorky = ./agents/gorky.json;
  };
  
  # Workspace-specific agents (only for homelab)
  workspaceAgents = {
    "/home/e421/homelab" = {
      maxim-neon = ./agents/maxim-neon.json;
      gorky-neon = ./agents/gorky-neon.json;
    };
  };
};
```

This would make agents part of your declarative config.

---

**Last Updated**: 2025-11-27 (v0.1.2)  
**Status**: Documented  
**See Also**: [VERSION_MANAGER_GUIDE.md](../VERSION_MANAGER_GUIDE.md) for multi-version usage
