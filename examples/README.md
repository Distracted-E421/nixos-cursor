# Cursor on NixOS - Examples

Real-world configuration examples for different use cases.

**Repository**: [github.com/Distracted-E421/nixos-cursor](https://github.com/Distracted-E421/nixos-cursor)  
**Version**: v0.1.1 - 37 Cursor versions available, secrets support added

---

## 📁 Examples

### 1. [Basic Flake](basic-flake/) - Minimal Setup

**What**: Cursor IDE only, no MCP servers

**Use case**: Just want Cursor, don't need AI tools

**Complexity**: ⭐ Beginner

```nix
programs.cursor.enable = true;
```

---

### 2. [With MCP](with-mcp/) - Full AI Experience

**What**: Cursor + all 5 MCP servers

**Use case**: Full AI development environment

**Complexity**: ⭐⭐ Intermediate

**Includes**:
- filesystem - Read/write local files
- memory - Persistent AI context
- nixos - Package/option search
- github - Repository operations
- playwright - Browser automation

```nix
programs.cursor = {
  enable = true;
  mcp = {
    enable = true;
    github.enable = true;
    playwright.enable = true;
  };
};
```

---

### 3. [With agenix](with-agenix/) - Secure Secrets (SSH Keys)

**What**: Cursor + GitHub MCP with agenix-encrypted token

**Use case**: Personal homelab, SSH-based secret encryption

**Complexity**: ⭐⭐⭐ Intermediate

**Features**:
- Token encrypted with SSH keys
- Decrypted at NixOS activation
- Never stored in Nix store

```nix
# NixOS configuration
age.secrets.github-mcp-token = {
  file = ./secrets/github-token.age;
  owner = "myuser";
};

# Home Manager configuration
programs.cursor.mcp.github = {
  enable = true;
  tokenFile = "/run/agenix/github-mcp-token";
};
```

---

### 4. [With sops-nix](with-sops/) - Secure Secrets (Multi-Machine)

**What**: Cursor + GitHub MCP with sops-nix encrypted token

**Use case**: Multi-machine homelab, team environments

**Complexity**: ⭐⭐⭐ Intermediate

**Features**:
- Native Home Manager integration
- Multiple encryption backends (age, GPG, cloud KMS)
- YAML format for multiple secrets

```nix
# sops configuration
sops.secrets.github-mcp-token.key = "github_token";

# Cursor configuration  
programs.cursor.mcp.github = {
  enable = true;
  tokenFile = config.sops.secrets.github-mcp-token.path;
};
```

---

### 5. [Dev Shell](dev-shell/) - Project Dependencies

**What**: Cursor with `nix develop` integration

**Use case**: Project-specific dependencies

**Complexity**: ⭐⭐ Intermediate

**Solves**: "Can't use Cursor unless I install everything globally"

```bash
nix develop --command cursor .
```

**Key insight**: Use `buildInputs`, not `nativeBuildInputs`

---

### 6. [Declarative Extensions](declarative-extensions/) - Extension Management

**What**: Semi-declarative extension installation

**Use case**: Reproducible extension list

**Complexity**: ⭐⭐⭐ Advanced

**Status**: ⚠️ Semi-declarative (best effort)

```nix
home.activation.cursorExtensions = /* install script */;
```

**Limitation**: Extensions mutable (not fully immutable like VSCode)

---

## 🎯 Quick Start

### Choose Your Path

**Just want Cursor?**
→ [basic-flake/](basic-flake/)

**Want AI tools?**
→ [with-mcp/](with-mcp/)

**Need project-specific tools?**
→ [dev-shell/](dev-shell/)

**Want extension management?**
→ [declarative-extensions/](declarative-extensions/)

### Multi-Version Support

All examples support multiple Cursor versions! Add to any config:

```nix
home.packages = [
  inputs.nixos-cursor.packages.${pkgs.system}.cursor          # Latest (2.0.77)
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-1_7_54   # Classic
  inputs.nixos-cursor.packages.${pkgs.system}.cursor-manager  # GUI picker
];
```

**37 versions available** - see main [README](../README.md) for full list.

---

## 📚 Common Patterns

### Combining Examples

You can mix and match:

#### MCP + Dev Shell

```nix
# home.nix - Install Cursor with MCP
programs.cursor = {
  enable = true;
  mcp.enable = true;
};
```

```nix
# project/flake.nix - Project dependencies
devShells.default = pkgs.mkShell {
  buildInputs = [ pkgs.nodejs pkgs.python312 ];
};
```

**Usage**: `nix develop --command cursor .`

**Result**: MCP servers + project dependencies!

#### MCP + Extensions

```nix
programs.cursor = {
  enable = true;
  mcp.enable = true;
};

home.activation.cursorExtensions = /* install extensions */;
```

**Result**: AI tools + your favorite extensions

---

## 🔧 Configuration Matrix

| Example | Cursor | MCP | Dev Shell | Extensions |
|---------|--------|-----|-----------|----------|
| [basic-flake](basic-flake/) | ✅ | ❌ | ❌ | ❌ |
| [with-mcp](with-mcp/) | ✅ | ✅ All 5 | ❌ | ❌ |
| [dev-shell](dev-shell/) | ✅ | Optional | ✅ | ❌ |
| [declarative-extensions](declarative-extensions/) | ✅ | ✅ | ❌ | ✅ Semi |

---

## 🎓 Learning Path

### Beginner

1. Start with [basic-flake/](basic-flake/)
2. Try Cursor, get comfortable
3. Move to [with-mcp/](with-mcp/) when ready

### Intermediate

1. Use [with-mcp/](with-mcp/) for AI features
2. Learn [dev-shell/](dev-shell/) for project work
3. Combine as needed

### Advanced

1. Master all examples
2. Try [declarative-extensions/](declarative-extensions/)
3. Customize for your workflow

---

## 🐛 Troubleshooting

### General Issues

**Cursor not starting**:
```bash
# Check if installed
which cursor

# Check version
cursor --version

# Run from terminal to see errors
cursor
```

**MCP servers not working**:
```bash
# Check config
cat ~/.cursor/mcp.json

# Kill and restart
pkill -f mcp-server
cursor
```

### Example-Specific

- **basic-flake**: See [basic-flake/README.md](basic-flake/README.md)
- **with-mcp**: See [with-mcp/README.md](with-mcp/README.md#troubleshooting)
- **dev-shell**: See [dev-shell/README.md](dev-shell/README.md#troubleshooting)
- **declarative-extensions**: See [declarative-extensions/README.md](declarative-extensions/README.md#troubleshooting)

---

## 💡 Tips

### 1. Start Simple

Don't enable everything at once. Start with [basic-flake/](basic-flake/), then add features.

### 2. Test in VM

```bash
nixos-rebuild build-vm --flake '.#test'
```

### 3. Version Control

```bash
git add flake.nix
git commit -m "Add Cursor configuration"
```

### 4. Read the READMEs

Each example has detailed documentation - read them!

---

## 🔗 References

### Documentation

- [Main README](../README.md) - Package overview
- [VERSION_MANAGER_GUIDE.md](../VERSION_MANAGER_GUIDE.md) - Multi-version usage
- [CONTRIBUTING.md](../CONTRIBUTING.md) - How to contribute
- [cursor/README.md](../cursor/README.md) - Cursor package details

### External

- [Cursor Official](https://www.cursor.com/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [NixOS Wiki](https://nixos.wiki/)
- [Forum Thread](https://forum.cursor.com/t/cursor-is-now-available-on-nixos/16640)

---

## 🤝 Contributing

Found a better pattern? Submit a PR!

**Good example ideas**:
- Specific language setups (Rust, Go, etc.)
- CI/CD integration
- Multi-user configurations
- Remote development setups

---

## 📊 Comparison

### vs Other Approaches

| Approach | Reproducible | Declarative | Easy | Flexible |
|----------|-------------|-------------|------|----------|
| **Our examples** | ✅ | ✅ | ✅ | ✅ |
| Manual install | ❌ | ❌ | ✅ | ✅ |
| AppImage + scripts | ⚠️ | ❌ | ✅ | ⚠️ |
| nixpkgs `code-cursor` | ✅ | ✅ | ✅ | ⚠️ |

**Our advantage**: Best of all worlds!

---

## 🎯 Success Criteria

You've mastered these examples when you can:

- ✅ Install Cursor on fresh NixOS
- ✅ Enable MCP servers declaratively
- ✅ Use project-specific dependencies
- ✅ Manage extensions (semi-declaratively)
- ✅ Combine patterns for your workflow

---

**Ready?** Pick an example and start: [basic-flake/](basic-flake/) | [with-mcp/](with-mcp/) | [dev-shell/](dev-shell/) | [declarative-extensions/](declarative-extensions/)

