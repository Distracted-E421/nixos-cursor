# nixos-cursor

> **🚀 Release Candidate**: This is **v2.1.20-rc1** - currently in testing phase.  
> **👉 Want to help test?** See **[TESTING_RC.md](TESTING_RC.md)** for instructions.

**License**: [MIT](LICENSE) | **Maintained by**: e421  
**Repository**: https://github.com/Distracted-E421/nixos-cursor

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers** and automated updates.

## ✨ Features

- **Native NixOS packaging** of Cursor IDE 2.1.20
- **Wayland + X11 support** with GPU acceleration
- **MCP server integration** (filesystem, memory, NixOS, GitHub, Playwright)
- **Automated update system** with daily notifications
- **GPU fixes** (libGL, libxkbfile) for NixOS compatibility
- **Test instance** (`cursor-test`) for safe MCP experimentation

---

## 🚀 Quick Start

### Testing RC1 (No Installation)

**Fastest way to try it**:

```bash
# Run directly from GitHub (RC1 release)
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor
```

See **[TESTING_RC.md](TESTING_RC.md)** for full testing instructions.

---

### Installing RC1 via Home Manager

Add to your `flake.nix`:

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.1.20-rc1";
  
  outputs = { self, nixpkgs, nixos-cursor, home-manager, ... }: {
    homeConfigurations.youruser = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixos-cursor.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            mcp.enable = false;  # Optional: MCP servers
          };
        }
      ];
    };
  };
}
```

Then: `home-manager switch`

See [`examples/`](examples/) for more configurations.

---

## 🔄 Updating Cursor

### Automatic Notifications (Enabled by Default)

Cursor checks for updates **daily** and shows desktop notifications:

```nix
programs.cursor = {
  enable = true;
  updateCheck.enable = true;  # Default
  updateCheck.interval = "daily";  # or "weekly"
};
```

### One-Command Update

```bash
# Check for updates
cursor-check-update

# Update Cursor (auto-detects your flake location)
cursor-update
```

**How it works**:
1. Queries Cursor's API for latest version
2. Updates your flake: `nix flake update nixos-cursor`
3. Rebuilds: `home-manager switch`
4. Reports: `2.1.20 → 2.1.21`

### Manual Update (Traditional Nix Way)

```bash
cd ~/.config/home-manager
nix flake update nixos-cursor
home-manager switch
```

**Why Cursor can't self-update**: Cursor lives in the read-only `/nix/store` and requires `autoPatchelfHook` to run on NixOS. Every update needs a Nix rebuild.

See **[docs/AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md)** for full details.

---

## 📚 Documentation

### Getting Started
- **[TESTING_RC.md](TESTING_RC.md)** - RC1 testing guide (START HERE)
- **[INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md)** - MCP server setup
- **[examples/](examples/)** - Example configurations

### Technical Details
- **[docs/AUTO_UPDATE_IMPLEMENTATION.md](docs/AUTO_UPDATE_IMPLEMENTATION.md)** - Update system
- **[KNOWN_ISSUES.md](KNOWN_ISSUES.md)** - Known problems
- **[cursor/README.md](cursor/README.md)** - Package documentation

### Project Info
- **[LICENSE](LICENSE)** - MIT License
- **[RELEASE_STRATEGY.md](RELEASE_STRATEGY.md)** - Release process

---

## 🐛 Reporting Issues

Found a bug in RC1? Please report it!

1. Go to [GitHub Issues](https://github.com/Distracted-E421/nixos-cursor/issues)
2. Include system information (see [TESTING_RC.md](TESTING_RC.md#-system-information))
3. Describe the problem clearly

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file.

```
MIT License - Copyright (c) 2025 e421

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

[Full license text in LICENSE file]
```
