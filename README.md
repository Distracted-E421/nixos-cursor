# nixos-cursor

**Status**: Release Candidate 3 (v2.0.77)  
**Status**: Release Candidate Testing  
**Current Version**: v2.1.20-rc1  
**License**: MIT  
**Maintained by**: e421

A production-ready NixOS package for **Cursor IDE** with built-in support for **Model Context Protocol (MCP) servers** and automated updates.

---

## Current Release

**v2.1.20-rc1** is now available for community testing!

- **Try it**: `nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor`
- **Documentation**: See [pre-release branch](https://github.com/Distracted-E421/nixos-cursor/tree/pre-release) for full docs
- **Testing Guide**: [TESTING_RC.md](https://github.com/Distracted-E421/nixos-cursor/blob/pre-release/TESTING_RC.md)

---

## Features

- Native NixOS packaging of Cursor IDE 2.1.20
- Wayland + X11 support with GPU acceleration
- MCP server integration (filesystem, memory, NixOS, GitHub, Playwright)
- Automated update system with daily notifications
- One-command updates (`cursor-update`)
- GPU fixes (libGL, libxkbfile) for NixOS compatibility
- Test instance for safe experimentation

---

## Quick Start

### Try Without Installing

```bash
# Run directly from GitHub
nix run github:Distracted-E421/nixos-cursor/v2.1.20-rc1#cursor
```

### Install via Home Manager

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.1.20-rc1";
  
  outputs = { nixos-cursor, home-manager, ... }: {
    homeConfigurations.youruser = home-manager.lib.homeManagerConfiguration {
      modules = [
        nixos-cursor.homeManagerModules.default
        {
          programs.cursor = {
            enable = true;
            updateCheck.enable = true;  # Daily update notifications
            mcp.enable = false;  # Optional: MCP servers
          };
        }
      ];
    };
  };
}
```

---

## Update System

Cursor includes an automated update system that:

- Checks for updates daily via systemd timer
- Shows desktop notifications when updates available
- Provides one-command updates: `cursor-update`
- Maintains Nix reproducibility guarantees

**Why?** Cursor can't self-update on NixOS (read-only `/nix/store`). Our system provides convenience while respecting Nix principles.

---

## Documentation

- **[Release Notes](https://github.com/Distracted-E421/nixos-cursor/releases/tag/v2.1.20-rc1)** - RC1 details
- **[Testing Guide](https://github.com/Distracted-E421/nixos-cursor/blob/pre-release/TESTING_RC.md)** - How to test RC1
- **[Update System](https://github.com/Distracted-E421/nixos-cursor/blob/pre-release/docs/AUTO_UPDATE_IMPLEMENTATION.md)** - Technical details
- **[Examples](https://github.com/Distracted-E421/nixos-cursor/tree/pre-release/examples)** - Configuration examples
- **[Known Issues](https://github.com/Distracted-E421/nixos-cursor/blob/pre-release/KNOWN_ISSUES.md)** - Limitations

---

## Reporting Issues

Found a bug? [Open an issue](https://github.com/Distracted-E421/nixos-cursor/issues) with:

- System information (`nixos-version`, `uname -m`)
- Steps to reproduce
- Expected vs actual behavior

---

## Development

- **Main branch**: Stable releases (coming soon)
- **Pre-release branch**: RC testing (current: v2.1.20-rc1)
- **Dev branch**: Active development

---

## License

MIT License - See [LICENSE](LICENSE) file.

```
MIT License - Copyright (c) 2025 e421

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
```
