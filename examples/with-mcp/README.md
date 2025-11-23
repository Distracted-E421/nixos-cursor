# Complete MCP Servers Example

Cursor with all MCP servers enabled - the full AI-powered experience.

## What This Does

- ✅ Installs Cursor IDE
- ✅ **filesystem** MCP - Read/write local files
- ✅ **memory** MCP - Persistent AI context
- ✅ **nixos** MCP - Package/option search
- ✅ **github** MCP - Repository operations
- ✅ **playwright** MCP - Browser automation

**Note:** You may need to disable a few of the tools you are not using per server, as well as ensure the built in cursor browser (currently broken, unknown if fixable for NixOS) is disabled. These are not the only mcp servers that work on NixOS, but these are the only ones I really use in my workflow.

## Usage

```bash
# Clone and configure
git clone https://github.com/yourusername/cursor-nixos
cd cursor-nixos/examples/with-mcp

# Edit username and paths
vim flake.nix  # Update username and filesystem paths

# Activate
nix run .#homeConfigurations.myuser.activationPackage
```

## What You Get

### Cursor IDE

- Enhanced with AI features
- All MCP tools available

### MCP Tools Available

**File Operations**:

```typescript
mcp_filesystem_read_file({ path: "..." })
mcp_filesystem_write_file({ path: "...", content: "..." })
```

**Memory/Context**:

```typescript
mcp_memory_create_entities({ entities: [...] })
mcp_memory_search_nodes({ query: "..." })
```

**NixOS**:

```typescript
mcp_nixos_nixos_search({ query: "firefox", search_type: "packages" })
```

**GitHub**:

```typescript
mcp_github_get_file_contents({ owner: "...", repo: "...", path: "..." })
mcp_github_search_code({ query: "..." })
```

**Browser Automation**:

```typescript
mcp_playwright_browser_navigate({ url: "https://example.com" })
mcp_playwright_browser_snapshot()
mcp_playwright_browser_take_screenshot({ filename: "test.png" })
```

## Configuration Options

### Filesystem Paths

Control which directories AI can access:

```nix
filesystemPaths = [
  "/home/myuser"              # Home directory
  "/home/myuser/projects"     # Projects only
  "/etc/nixos"                # System config (read-only recommended)
];
```

**Security**: Only include paths you trust the AI to modify.

### GitHub Token

For private repository access:

```nix
github = {
  enable = true;
  token = config.age.secrets.github-token.path;  # Using agenix
};
```

**Without token**: Public repositories only

### Browser Choice

Choose your browser:

```nix
playwright = {
  browser = "chromium";  # FOSS option
  # or "chrome" - proprietary but more compatible
  # or "firefox" - FOSS, different engine
  browserPackage = pkgs.chromium;
};
```

### Headless Mode

For CI/CD or background tasks:

```nix
playwright = {
  headless = true;  # No browser window
  saveTrace = true;  # Debug traces
  saveVideo = true;  # Record sessions
};
```

## Testing

After activation, test each MCP server:

```bash
# Check configuration
cat ~/.cursor/mcp.json

# Verify browser
chromium --version

# Launch Cursor
cursor
```

In Cursor, try:

- Ask AI to read a file
- Ask AI to search GitHub
- Ask AI to open a webpage

## Troubleshooting

### "Browser not found"

Check browser installation:

```bash
which chromium
# or
which google-chrome-stable
```

### MCP servers not starting

Kill and restart:

```bash
pkill -f mcp-server
# Then restart Cursor
```

### Permission denied (filesystem)

Check your `filesystemPaths` - make sure paths exist and are readable.

## Next Steps

- **Dev shells**: See [../dev-shell/](../dev-shell/)
- **Extensions**: See [../declarative-extensions/](../declarative-extensions/)
