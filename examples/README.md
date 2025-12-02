# Cursor on NixOS - Examples

Real-world configuration examples for different use cases.

**Repository**: [github.com/Distracted-E421/nixos-cursor](https://github.com/Distracted-E421/nixos-cursor)  
**Version**: v0.2.0 - Cursor Studio dashboard, 48+ versions available

---

## 🆕 What's New in v0.2.0

- **Cursor Studio** 🎉 - Modern Rust/egui dashboard for Cursor management
  - Chat Library: Import, search, bookmark conversations
  - Security Scanning: Detect API keys/secrets in chats  
  - VS Code Themes: Full theme support
  - Multi-Version Management: Launch any version
  - Selective Version Cleanup: Remove specific versions (not all-or-nothing)
- **Nushell Scripts** - All scripts converted from bash
- **48+ Versions** - Download any historical version with hash verification

---

## 📁 Examples

### 1. [Basic Flake](basic-flake/) - Minimal Setup

**What**: Cursor IDE + Cursor Studio, no MCP servers

**Use case**: Just want Cursor and the management dashboard

**Complexity**: ⭐ Beginner

```nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor        # Latest stable
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio # Modern dashboard
];
```

---

### 2. [With MCP](with-mcp/) - Full AI Experience

**What**: Cursor + Cursor Studio + MCP servers configured separately

**Use case**: Full AI development environment (like a real homelab)

**Complexity**: ⭐⭐ Intermediate

**Includes**:
- filesystem - Read/write local files
- memory - Persistent AI context
- nixos - Package/option search
- github - Repository operations
- playwright - Browser automation

```nix
# Install packages directly (recommended approach)
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio
];

# MCP configuration is separate (in development modules)
```

---

### 3. [With agenix](with-agenix/) - Secure Secrets (SSH Keys)

**What**: Cursor + GitHub MCP with agenix-encrypted token

**Use case**: Personal homelab, SSH-based secret encryption

**Complexity**: ⭐⭐⭐ Intermediate

---

### 4. [With sops-nix](with-sops/) - Secure Secrets (Multi-Machine)

**What**: Cursor + GitHub MCP with sops-nix encrypted token

**Use case**: Multi-machine homelab, team environments

**Complexity**: ⭐⭐⭐ Intermediate

---

### 5. [Dev Shell](dev-shell/) - Project Dependencies

**What**: Cursor with `nix develop` integration

**Use case**: Project-specific dependencies

**Complexity**: ⭐⭐ Intermediate

```bash
nix develop --command cursor .
```

---

### 6. [Declarative Extensions](declarative-extensions/) - Extension Management

**What**: Semi-declarative extension installation

**Use case**: Reproducible extension list

**Complexity**: ⭐⭐⭐ Advanced

---

## 🎯 Quick Start

### Choose Your Path

**Just want Cursor + management dashboard?**
→ [basic-flake/](basic-flake/)

**Want AI tools (real homelab approach)?**
→ [with-mcp/](with-mcp/)

**Need project-specific tools?**
→ [dev-shell/](dev-shell/)

### Multi-Version Support

All examples support multiple Cursor versions:

```nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Latest (2.1.34)
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio   # Dashboard + CLI
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-2_0_64   # Reliable fallback
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # Classic pre-2.0
];

# Environment for `nix run` fallback
home.sessionVariables = {
  CURSOR_FLAKE_URI = "github:Distracted-E421/nixos-cursor";
};
```

**48+ versions available** - see main [README](../README.md) for full list.

---

## 📚 Recommended: Direct Package Installation

Based on real homelab usage, the recommended approach is:

```nix
# flake.nix inputs
nixos-cursor = {
  url = "github:Distracted-E421/nixos-cursor";
  # NOTE: cursor-studio is now included - no separate input needed
};

# home.nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-studio
  # Add specific versions as needed
];
```

**Why this approach?**
- More stable than Home Manager module
- Direct control over versions
- S3 URLs with verified SRI hashes
- MCP can be configured separately

---

## 🔧 Configuration Matrix

| Example | Cursor | Studio | MCP | Dev Shell |
|---------|--------|--------|-----|-----------|
| [basic-flake](basic-flake/) | ✅ | ✅ | ❌ | ❌ |
| [with-mcp](with-mcp/) | ✅ | ✅ | ✅ | ❌ |
| [dev-shell](dev-shell/) | ✅ | Optional | Optional | ✅ |
| [declarative-extensions](declarative-extensions/) | ✅ | ✅ | ✅ | ❌ |

---

## 🐛 Troubleshooting

**Cursor not starting**:
```bash
which cursor && cursor --version
```

**Cursor Studio issues**:
```bash
RUST_LOG=debug cursor-studio
cursor-studio-cli --help
```

**MCP servers not working**:
```bash
cat ~/.cursor/mcp.json
```

---

**Ready?** Pick an example and start: [basic-flake/](basic-flake/) | [with-mcp/](with-mcp/) | [dev-shell/](dev-shell/)

