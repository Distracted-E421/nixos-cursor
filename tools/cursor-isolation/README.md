# Cursor Isolation & Recovery Tools

**Created after the December 2025 incident** where experimental proxy/injection work broke the main Cursor installation.

## 🎯 Purpose

These tools provide:
1. **Isolated test environments** - Test experimental changes without affecting your main Cursor
2. **Version management** - Run multiple Cursor versions side-by-side
3. **Backup/restore** - Quick snapshots before risky operations
4. **Recovery procedures** - Get back to working state quickly

## 🛠️ Tools

### `cursor-test` - Primary Isolation (Recommended)

Run Cursor with completely isolated user data:

```bash
# Run in default test environment
./cursor-test

# Use a named environment (e.g., for proxy testing)
./cursor-test --env proxy-dev

# Reset and start fresh
./cursor-test --reset

# Open specific workspace
./cursor-test ~/projects/my-project
```

**How it works:** Uses Cursor's `--user-data-dir` flag to store all config, extensions, and state in `~/.cursor-test-envs/<name>/`

### `cursor-versions` - Multiple Version Management

Download and run specific Cursor versions:

```bash
# List installed versions
./cursor-versions list

# Download a specific version
./cursor-versions download 2.2.36

# Run a specific version (auto-isolated)
./cursor-versions run 2.2.36

# Set default version
./cursor-versions default 2.2.36
```

**Available versions:**
- 2.2.36 (latest as of Dec 2025)
- 2.1.42
- 2.0.77

### `cursor-backup` - Configuration Backup

Create snapshots of your Cursor configuration:

```bash
# Quick timestamped backup
./cursor-backup quick

# Named backup before risky operation
./cursor-backup save before-proxy-test

# List backups
./cursor-backup list

# Restore from backup
./cursor-backup restore before-proxy-test
```

**What's backed up:**
- User settings and keybindings
- Extension settings
- State database (conversations, agent state)
- NOT cached data (regenerated automatically)

### `cursor-sandbox` - Full Environment Isolation

More aggressive isolation using modified HOME:

```bash
./cursor-sandbox
./cursor-sandbox --reset --name experimental
```

## 📋 Recovery Procedures

### Scenario 1: Cursor crashes on startup

```bash
# 1. Try isolated instance to verify it's config-related
./cursor-test --reset

# 2. If isolated works, restore from backup
./cursor-backup list
./cursor-backup restore <last-known-good>
```

### Scenario 2: Proxy/injection broke API calls

```bash
# 1. Disable proxy
cursor-proxy disable

# 2. Check for lingering iptables rules
sudo iptables -t nat -L -n | grep REDIRECT

# 3. Clear any injection config
rm ~/.config/cursor-studio/injection-rules.toml

# 4. Restart Cursor
```

### Scenario 3: Need to test experimental code safely

```bash
# 1. Backup current state
./cursor-backup save pre-experiment

# 2. Run isolated test version
./cursor-versions run 2.2.36

# 3. Test your changes in the isolated environment

# 4. If something breaks, just reset:
./cursor-test --reset --env v2.2.36
```

### Scenario 4: Database corruption

```bash
# 1. Check integrity
sqlite3 ~/.config/Cursor/User/globalStorage/state.vscdb "PRAGMA integrity_check;"

# 2. If corrupt, restore from backup
./cursor-backup restore <name>

# 3. Or start fresh (loses conversations)
rm ~/.config/Cursor/User/globalStorage/state.vscdb
```

## 🏗️ Architecture

```
~/.cursor-test-envs/           # Isolated test environments
├── test/                      # Default test env
├── proxy-dev/                 # For proxy development
├── v2.2.36/                   # Version-specific isolated env
└── v2.0.77/

~/.cursor-versions/            # AppImage storage
├── Cursor-2.2.36-x86_64.AppImage
├── Cursor-2.1.42-x86_64.AppImage
└── .default                   # Current default version

~/.cursor-backups/             # Configuration backups
├── pre-experiment/
├── quick_20251219_120000/
└── emergency_*/               # Auto-created during restores
```

## ⚠️ Lessons Learned (Dec 2025 Incident)

1. **Always test proxy/injection in isolated environment first**
2. **Backup before ANY experiment that touches API traffic**
3. **The `--user-data-dir` flag is your friend**
4. **Never enable experimental features in your main Cursor**
5. **Keep at least one known-good AppImage version downloaded**

## 🔧 Integration with NixOS

Add these tools to your path via home-manager:

```nix
home.packages = [
  (pkgs.writeShellScriptBin "cursor-test" (builtins.readFile ./cursor-isolation/cursor-test))
  # ... etc
];
```

Or just symlink them:

```bash
ln -sf ~/nixos-cursor/tools/cursor-isolation/cursor-* ~/.local/bin/
```
