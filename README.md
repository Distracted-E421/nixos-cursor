# nixos-cursor

**Status**: Beta Release Candidate (v2.1.20)  
**License**: MIT  
**Maintained by**: e421 (distracted.e421@gmail.com)  

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers** and automated updates.

---

## 🔗 Related Projects

This package focuses on Cursor IDE packaging and MCP integration. For additional functionality:

- **[wayland-gpu-affinity](../wayland-gpu-affinity)** - General Wayland multi-monitor/GPU management (works with Niri, Hyprland, KDE, Cursor, etc.)
- **[cursor-focus-fix](../cursor-focus-fix)** - Fix multi-window focus issues on X11/Wayland
- **[cursor-cdp-daemon](../cursor-cdp-daemon)** - Chrome DevTools Protocol integration

---

## 🎯 Overview

This is a production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers**, including the challenging **Playwright browser automation** server.

### What Makes This Different?

Unlike the stock `code-cursor` package in nixpkgs, this provides:

- ✅ **Enhanced Cursor Package**: libxkbfile, OpenGL, Wayland fixes
- ✅ **5 MCP Servers Working**: filesystem, memory, nixos, github, playwright
- ✅ **Automatic Dependency Management**: mcp-servers-nix integration via overlay
- ✅ **Playwright Support on NixOS**: Solved the browser path configuration challenge
- ✅ **Declarative Configuration**: Home Manager module with sensible defaults
- ✅ **No User-Specific Paths**: Works for any user out of the box
- ✅ **Browser Auto-Detection**: Automatically finds system browsers
- ✅ **Multiple Browser Support**: Chrome, Chromium, Firefox (via config)

---

## 🔄 Auto-Update System

**Important**: Cursor's native updater **does not work** on NixOS!

### Why Updates Fail

On typical Linux systems, Cursor can update itself by replacing the AppImage file. On NixOS:
- Cursor is installed in `/nix/store` (read-only, immutable)
- Cursor's updater tries to replace the file → **Permission denied**
- Falls back to "Please download from cursor.com" message

### How to Update

**For End Users**:

```bash
# Update your flake inputs (fetches new Cursor version)
nix flake update cursor-with-mcp

# Apply the update
home-manager switch  # For Home Manager users
# OR
nixos-rebuild switch  # For system package
```

**For Maintainers**:

```bash
# Automatically fetch latest Cursor version and update hashes
cd cursor
./update.sh

# Test and commit
cd .. && nix build .#cursor
git add cursor/default.nix
git commit -m "chore: Update Cursor to $(nix eval .#cursor.version --raw)"
```

### Technical Details

This package uses the same approach as nixpkgs' `code-cursor`:
- Disables Cursor's built-in updater with `--update=false` flag
- Provides `cursor/update.sh` script that queries Cursor's API
- Users update via Nix package management instead

**See**: [AUTO_UPDATE_IMPLEMENTATION.md](AUTO_UPDATE_IMPLEMENTATION.md) for full technical details

---

## 📋 What Are MCP Servers?

**MCP (Model Context Protocol)** servers extend AI assistants (like Cursor) with additional capabilities:

- **filesystem**: Read/write files in specified directories (MIT)
- **memory**: Persistent knowledge across sessions (MIT)
- **nixos**: Search NixOS packages and options (MIT)
- **github**: Repository operations and code search (MIT)
- **playwright**: Browser automation for testing and web scraping (Apache 2.0)

**All MCP servers are open source!** See [LICENSING_AND_FOSS.md](LICENSING_AND_FOSS.md) for details.

Think of them as "tools" the AI can use to help you better.

---

## 🚀 Quick Start

### Option 1: Standalone Flake (Easiest)

Create a `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    cursor-with-mcp.url = "github:yourusername/cursor-nix";  # TODO: Update when published
  };

  outputs = { nixpkgs, home-manager, cursor-with-mcp, ... }: {
    homeConfigurations.yourusername = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      modules = [
        cursor-with-mcp.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            mcp = {
              enable = true;
              playwright.enable = true;  # Browser automation
            };
          };
        }
      ];
    };
  };
}
```

Then:

```bash
nix run .#homeConfigurations.yourusername.activationPackage
```

### Option 2: Existing Home Manager Configuration

Add to your `home.nix`:

```nix
{ config, pkgs, ... }:

{
  imports = [
    inputs.cursor-with-mcp.homeManagerModules.default
  ];

  programs.cursor = {
    enable = true;
    
    mcp = {
      enable = true;
      
      # Filesystem access (AI can read/write these paths)
      filesystemPaths = [
        "${config.home.homeDirectory}/projects"
        "${config.home.homeDirectory}/homelab"
      ];
      
      # Playwright browser automation
      playwright = {
        enable = true;
        browser = "chrome";  # or "chromium", "firefox"
        browserPackage = pkgs.google-chrome;
        headless = false;  # Headed mode (see browser window)
      };
    };
  };
}
```

---

## 🔧 Configuration Options

### Complete Configuration Example

```nix
programs.cursor = {
  enable = true;
  package = pkgs.cursor-enhanced;  # Our enhanced package
  
  mcp = {
    enable = true;
    
    # Filesystem MCP Server
    filesystemPaths = [
      "${config.home.homeDirectory}"
      "/etc/nixos"
    ];
    
    # Memory MCP Server (persistent AI memory)
    memory.enable = true;
    
    # NixOS MCP Server (search packages/options)
    nixos.enable = true;
    
    # GitHub MCP Server (repository operations)
    github = {
      enable = true;
      token = null;  # Optional: for private repos
    };
    
    # Playwright Browser Automation
    playwright = {
      enable = true;
      browser = "chrome";  # "chrome", "chromium", "firefox", "webkit"
      browserPackage = pkgs.google-chrome;
      
      # Browser behavior
      headless = false;  # Set true for headless mode
      timeout = 60000;   # Navigation timeout (ms)
      
      # Session persistence
      userDataDir = "${config.home.homeDirectory}/.local/share/playwright/profile";
      saveSession = false;  # Save cookies/localStorage
      
      # Debugging
      saveTrace = false;    # Save Playwright traces
      saveVideo = false;    # Record browser sessions
    };
  };
};
```

### Option Reference

#### `programs.cursor.mcp.filesystemPaths`
- **Type**: `listOf str`
- **Default**: `[ config.home.homeDirectory ]`
- **Description**: Directories the filesystem MCP server can access

#### `programs.cursor.mcp.playwright.browser`
- **Type**: `enum ["chrome" "chromium" "firefox" "webkit"]`
- **Default**: `"chrome"`
- **Description**: Which browser to use for automation

#### `programs.cursor.mcp.playwright.browserPackage`
- **Type**: `package`
- **Default**: `pkgs.google-chrome`
- **Description**: Nix package providing the browser

---

## 🎓 Usage Examples

### Example 1: Basic Configuration

Perfect for most users:

```nix
programs.cursor = {
  enable = true;
  mcp.enable = true;  # Uses sensible defaults
};
```

This gives you:
- Cursor IDE
- Filesystem access to home directory
- Memory server for persistent context
- NixOS package search
- **No Playwright** (opt-in only)

### Example 2: Web Development

For testing web applications:

```nix
programs.cursor = {
  enable = true;
  mcp = {
    enable = true;
    filesystemPaths = [
      "${config.home.homeDirectory}/projects"
    ];
    playwright = {
      enable = true;
      browser = "chromium";
      browserPackage = pkgs.chromium;
      headless = false;
      saveTrace = true;  # Debug test failures
    };
  };
};
```

### Example 3: Multiple Browsers

Test across different browsers:

```nix
programs.cursor = {
  enable = true;
  mcp = {
    enable = true;
    playwright = {
      enable = true;
      # Primary browser
      browser = "chrome";
      browserPackage = pkgs.google-chrome;
    };
  };
  
  # Install additional browsers for manual switching
  home.packages = with pkgs; [
    chromium
    firefox
  ];
};
```

Then switch browser in Playwright MCP config when needed.

---

## 🧪 Testing Your Setup

### Verify MCP Configuration

```bash
# Check MCP config file
cat ~/.cursor/mcp.json | jq

# Verify browser is available
which google-chrome-stable

# Test browser launch
google-chrome-stable --version
```

### Test in Cursor

Open Cursor and use the MCP tools:

```typescript
// Navigate to a URL
mcp_playwright_browser_navigate({ url: "https://example.com" })

// Capture page snapshot
mcp_playwright_browser_snapshot()

// Take a screenshot
mcp_playwright_browser_take_screenshot({ filename: "test.png" })
```

---

## 🐛 Troubleshooting

### "Browser not found" Error

**Problem**: `browserType.launchPersistentContext: Chromium distribution 'chrome' is not found`

**Solution**: Specify the correct `browserPackage`:

```nix
playwright.browserPackage = pkgs.google-chrome;  # or pkgs.chromium
```

### MCP Server Not Starting

**Check logs**:

```bash
# Cursor logs
journalctl --user -u cursor-ide.service -f

# Check if MCP servers are running
ps aux | grep mcp-server
```

**Common causes**:
- Wrong browser path
- Missing dependencies
- Conflicting MCP config in `~/.cursor/mcp.json`

### Dev Shell Integration

**Problem**: Environment not passed to Cursor when using `nix develop`

**Solution**: Use `buildInputs` not `nativeBuildInputs`:

```nix
# flake.nix
devShells.default = pkgs.mkShell {
  buildInputs = [  # NOT nativeBuildInputs
    pkgs.cursor
    pkgs.nodejs
    pkgs.python3
  ];
};
```

---

## 📚 Documentation

- [Installation Guide](docs/INSTALLATION.md)
- [MCP Server Configuration](docs/MCP_SETUP.md)
- [Playwright Configuration](docs/PLAYWRIGHT_CONFIG.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [**Licensing & FOSS Status**](LICENSING_AND_FOSS.md) ⭐
- [Forum Issues Addressed](docs/FORUM_ISSUES_ADDRESSED.md)
- [Contributing](docs/CONTRIBUTING.md)

---

## 🔓 Open Source & Licensing

**Our packaging is 100% MIT licensed and open source.**

### What's FOSS?

- ✅ **Our code** (MIT) - This packaging, configs, docs
- ✅ **All MCP servers** (MIT/Apache 2.0) - filesystem, memory, nixos, github, playwright
- ✅ **Chromium/Firefox** (BSD/MPL) - Browser options
- ⚠️ **Cursor IDE** (Proprietary) - The IDE itself
- ⚠️ **Google Chrome** (Proprietary) - Optional browser

**For complete details**: See [LICENSING_AND_FOSS.md](LICENSING_AND_FOSS.md)

### FOSS Recommendation

For a fully open source stack, use:

```nix
programs.cursor.mcp.playwright = {
  browser = "chromium";  # or "firefox"
  browserPackage = pkgs.chromium;  # or pkgs.firefox
};
```

**Trade-off**: Cursor IDE itself is proprietary (but free to use)

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

### Ways to Contribute

- 🐛 Report bugs
- 📝 Improve documentation
- 🧪 Test on different systems
- 💡 Suggest features
- 🔧 Submit fixes/enhancements

---

## 🙏 Acknowledgments

### Upstream Projects

- **Cursor** - Created by [Anysphere, Inc.](https://www.cursor.com/)
- **Model Context Protocol** - Created by [Anthropic](https://www.anthropic.com/)
- **Playwright** - Created by [Microsoft](https://playwright.dev/)

### NixOS Community

- **@seclark**: Original `code-cursor` nixpkgs maintainer
- **@natsukium**: `mcp-servers-nix` flake maintainer
- **@cymenix**: `mcp-nixos` server creator
- **NixOS Forum Contributors**: Community feedback and testing

### Our Contribution

**What we built**:
- ✅ Solved Playwright MCP on NixOS (browser auto-detection)
- ✅ Integrated all 5 MCP servers (filesystem, memory, nixos, github, playwright)
- ✅ Automatic mcp-servers-nix dependency handling via flake overlay
- ✅ Generic Home Manager module (works for any user)
- ✅ Comprehensive documentation and examples
- ✅ Production-ready defaults with security in mind

**What we don't claim credit for**:
- ❌ Cursor IDE development (Anysphere)
- ❌ MCP protocol design (Anthropic)
- ❌ MCP server development (various authors)
- ❌ Browser development (Google, Mozilla, etc.)

### Related Projects

- [Cursor Official](https://www.cursor.com/)
- [nixpkgs code-cursor](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/code-cursor/default.nix)
- [mcp-servers-nix](https://github.com/natsukium/mcp-servers-nix)
- [Model Context Protocol](https://github.com/modelcontextprotocol)
- [Original Forum Thread](https://forum.cursor.com/t/cursor-is-now-available-on-nixos/16640)

---

## 📊 Project Status

### ✅ Completed
- [x] Enhanced Cursor package with NixOS fixes
- [x] All 5 MCP servers integrated and working
- [x] Playwright MCP with browser auto-detection
- [x] mcp-servers-nix flake integration via overlay
- [x] Generic Home Manager module (user-agnostic)
- [x] 4 comprehensive example configurations
- [x] MIT License with FOSS transparency
- [x] Production-ready documentation

### 🔨 In Progress (Phase 2 Testing - 20% Complete)
- [x] Syntax validation (all examples pass)
- [x] Dev shell integration (Python, Node.js, Rust)
- [x] MCP server configuration generation
- [ ] Multi-system testing (neon-laptop, framework)
- [ ] Integration tests with existing Cursor
- [ ] Performance benchmarks

### 📅 Planned
- [ ] Public GitHub repository
- [ ] Forum announcement post
- [ ] NixOS Discourse post
- [ ] Nixpkgs maintainer status

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file

---

**Last Updated**: 2025-11-18  
**Version**: 0.1.0-rc1 (Release Candidate)  
**Status**: Phase 2 Testing - MCP Integration Complete ✅
