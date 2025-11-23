# Integration Guide: cursor-with-mcp

**Purpose**: How to integrate cursor-with-mcp into existing NixOS configurations  
**Target Devices**: neon-laptop, framework, and other homelab machines  
**Date**: 2025-11-18  

---

## 🎯 Integration Options

### Option 1: Homelab Flake Integration (Recommended)

Add cursor-with-mcp as a flake input to your main flake.nix:

**File**: `nixos/flake.nix`

```nix
{
  description = "Homelab NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # Add cursor-with-mcp
    cursor-with-mcp = {
      url = "path:./pkgs/cursor-with-mcp";  # Local path for development
      # url = "github:yourusername/cursor-nixos";  # Future: After public release
    };
  };

  outputs = { self, nixpkgs, home-manager, cursor-with-mcp, ... }: {
    # Pass cursor-with-mcp to home-manager configurations
    homeConfigurations = {
      "e421@neon-laptop" = home-manager.lib.homeManagerConfiguration {
        # ... other config ...
        extraSpecialArgs = { inherit cursor-with-mcp; };
      };
      "e421@framework" = home-manager.lib.homeManagerConfiguration {
        # ... other config ...
        extraSpecialArgs = { inherit cursor-with-mcp; };
      };
    };
  };
}
```

---

### Option 2: Per-User Home Manager Configuration

**For neon-laptop** (`nixos/users/e421/neon-laptop.nix`):

```nix
{ config, pkgs, cursor-with-mcp, ... }:

{
  # Import cursor-with-mcp Home Manager module
  imports = [
    cursor-with-mcp.homeManagerModules.default
  ];

  # Configure Cursor with MCP servers
  programs.cursor = {
    enable = true;
    
    # Enable MCP servers
    mcp = {
      filesystem.enable = true;
      filesystem.allowedPaths = [
        "/home/e421/homelab"
        "/home/e421/.config"
      ];
      
      memory.enable = true;
      
      nixos.enable = true;
      
      github.enable = true;
      github.token = "ghp_...";  # Or use agenix/sops-nix
      
      playwright.enable = true;
      playwright.browser = "chromium";
      playwright.headless = false;
    };
    
    # Cursor settings
    settings = {
      "cursor.general.enableBrowserIntegration" = true;
      "cursor.general.disableBrowserView" = false;
      # ... other settings ...
    };
  };
  
  # Install browser for Playwright (if enabled)
  home.packages = with pkgs; [
    chromium  # or google-chrome
  ];
}
```

**For framework** (`nixos/users/e421/framework.nix`):

```nix
{ config, pkgs, cursor-with-mcp, ... }:

{
  imports = [
    cursor-with-mcp.homeManagerModules.default
  ];

  programs.cursor = {
    enable = true;
    
    mcp = {
      filesystem.enable = true;
      filesystem.allowedPaths = [ "/home/e421/homelab" ];
      
      memory.enable = true;
      nixos.enable = true;
      
      github.enable = true;
      github.token = "ghp_...";
      
      # Framework might not need Playwright if headless-only
      playwright.enable = false;
    };
  };
}
```

---

## 🔄 Migration from Old cursor-ide Module

### Current Setup (OLD)

**neon-laptop** currently uses:
```nix
# modules/cursor-development.nix
services.cursor-development = {
  enable = true;
  user = "e421";
};
```

**framework** currently has: (to be checked)

### Migration Steps

1. **Add cursor-with-mcp to flake inputs**:
   ```bash
   cd ~/homelab/nixos
   # Edit flake.nix to add cursor-with-mcp input
   ```

2. **Update user home.nix files**:
   ```bash
   # neon-laptop
   vim nixos/users/e421/neon-laptop.nix
   # framework
   vim nixos/users/e421/framework.nix
   ```

3. **Remove old module imports** (after testing):
   ```nix
   # Remove from configuration.nix:
   # ../../modules/cursor-development.nix
   ```

4. **Test on one device first**:
   ```bash
   # Test rebuild
   sudo nixos-rebuild dry-build --flake ~/homelab/nixos#neon-laptop
   
   # If successful
   sudo nixos-rebuild switch --flake ~/homelab/nixos#neon-laptop
   ```

5. **Repeat for framework**:
   ```bash
   sudo nixos-rebuild switch --flake ~/homelab/nixos#framework
   ```

---

## 📝 Configuration Templates

### Minimal Cursor (No MCP)

```nix
programs.cursor = {
  enable = true;
};
```

### Cursor with Essential MCP Servers

```nix
programs.cursor = {
  enable = true;
  
  mcp = {
    filesystem.enable = true;
    filesystem.allowedPaths = [ "/home/e421/homelab" ];
    
    memory.enable = true;
    nixos.enable = true;
  };
};
```

### Full MCP Setup (All 5 Servers)

```nix
programs.cursor = {
  enable = true;
  
  mcp = {
    filesystem.enable = true;
    filesystem.allowedPaths = [
      "/home/e421/homelab"
      "/home/e421/.config"
    ];
    
    memory.enable = true;
    
    nixos.enable = true;
    
    github.enable = true;
    github.token = config.age.secrets.github-token.path;  # Using agenix
    
    playwright.enable = true;
    playwright.browser = "chromium";
    playwright.userDataDir = "/home/e421/.cursor/playwright-profile";
    playwright.headless = false;
  };
  
  settings = {
    "cursor.general.enableBrowserIntegration" = true;
    "cursor.general.disableBrowserView" = false;
  };
};

home.packages = with pkgs; [
  chromium
];
```

---

## 🎯 Device-Specific Recommendations

### neon-laptop (ThinkPad T14, NixOS 24.05)

**Recommended Configuration**:
- ✅ All 5 MCP servers (development machine)
- ✅ Playwright with GUI browser (testing)
- ✅ Full filesystem access to homelab
- ✅ GitHub MCP for git operations

**Rationale**: Primary development and testing device

---

### framework (Framework Laptop 13, NixOS 24.05)

**Recommended Configuration**:
- ✅ Essential MCP servers (filesystem, memory, nixos, github)
- ⚠️ Playwright optional (consider headless if enabled)
- ✅ Filesystem access to homelab
- ✅ GitHub MCP for mobile development

**Rationale**: Mobile workstation, may be resource-constrained

---

### Obsidian (NixOS 25.11)

**Current Configuration**: Already using cursor-with-mcp directly

**Status**: ✅ Reference implementation

---

## 🔍 Testing Checklist

After integration on each device:

- [ ] Cursor launches successfully
- [ ] Desktop launcher present
- [ ] MCP servers show in Cursor settings
- [ ] filesystem MCP: Can read homelab files
- [ ] memory MCP: Can store/retrieve entities
- [ ] nixos MCP: Can search packages
- [ ] github MCP: Can perform git operations (if enabled)
- [ ] playwright MCP: Can navigate to URLs (if enabled)
- [ ] No errors in Cursor logs
- [ ] Performance acceptable

---

## 🐛 Troubleshooting

### Build Errors

**Issue**: `error: attribute 'cursor-with-mcp' missing`

**Solution**: Ensure flake input is added and `nix flake update` has been run

---

### MCP Servers Not Showing

**Issue**: MCP servers configured but not appearing in Cursor

**Solution**:
1. Check `~/.cursor/mcp.json` was generated
2. Restart Cursor completely
3. Check Cursor logs: Output → MCP

---

### GitHub MCP Fails

**Issue**: "GitHub MCP server failed to start"

**Solution**:
1. Verify token is valid
2. Check token has correct permissions (repo, workflow)
3. Ensure token is accessible to Cursor process
4. Consider using agenix/sops-nix for token management

---

### Playwright Browser Not Found

**Issue**: "Browser executable not found"

**Solution**:
1. Ensure browser package installed: `chromium` or `google-chrome`
2. Check `programs.cursor.mcp.playwright.browser` matches installed browser
3. Verify browser in PATH

---

## 📚 Related Documentation

- **Main README**: `nixos/pkgs/cursor-with-mcp/README.md`
- **Home Manager Module**: `nixos/pkgs/cursor-with-mcp/home-manager-module/default.nix`
- **Examples**: `nixos/pkgs/cursor-with-mcp/examples/`
- **Release Strategy**: `nixos/pkgs/cursor-with-mcp/RELEASE_STRATEGY.md`

---

## 🚀 Next Steps

1. **Add flake input** to main homelab flake
2. **Update neon-laptop** user configuration
3. **Test** on neon-laptop
4. **Update framework** user configuration
5. **Test** on framework
6. **Document** any device-specific quirks
7. **Remove** old cursor-development module (after migration complete)

---

**Created**: 2025-11-18  
**Status**: Ready for implementation  
**Priority**: High (Phase 2 testing continuation)
