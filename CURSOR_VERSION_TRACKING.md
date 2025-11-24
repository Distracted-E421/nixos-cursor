# Cursor Version Tracking Strategy

## Current Version: 2.0.64

This package is currently pinned to **Cursor 2.0.64**, which is the last stable version before custom agents were deprecated.

## Why 2.0.64?

### Custom Agents Deprecation

Starting with **Cursor 2.1.0** (released mid-January 2025), the Cursor team deprecated the custom agents feature. Custom agents allowed users to:

- Define custom system prompts and behavior
- Create specialized agents for different tasks
- Share agent configurations across teams
- Build project-specific AI workflows

For many power users, custom agents were a critical workflow component that made Cursor uniquely valuable.

### Decision Rationale

We've chosen to track version 2.0.64 because:

1. **Workflow Preservation**: Custom agents are essential for many users' workflows
2. **Stability**: 2.0.64 is a mature, stable release  
3. **Feature Completeness**: 2.0.x has all core features except the very latest UI updates
4. **Community Need**: Multiple users have expressed the same concern

## When Will We Upgrade?

We will upgrade to 2.1.x+ when ONE of the following occurs:

### Option 1: Official Restoration

Cursor team restores custom agent functionality (even in a different form)

### Option 2: Community Reimplementation

We or the community develop a way to reimplement custom agent functionality:
- Via MCP server integration
- Via Cursor rules/configuration
- Via custom extension

### Option 3: Acceptable Alternative

Cursor 2.1+ provides an alternative workflow that achieves the same goals

### Option 4: Community Consensus

The majority of nixos-cursor users prefer to upgrade despite the feature loss

## Tracking 2.1.x Development

We are monitoring the Cursor changelog and community forums for:

- Custom agent restoration announcements
- Alternative workflow patterns
- Community solutions and workarounds

## For Users Who Don't Use Custom Agents

If you don't use custom agents and want the latest Cursor:

### Option 1: Use Official AppImage

```bash
# Download and run official AppImage
curl -L https://downloader.cursor.sh/linux/appImage/x64 -o cursor.AppImage
chmod +x cursor.AppImage
./cursor.AppImage
```

### Option 2: Track 2.1.x Branch (Planned)

We plan to create a `cursor-latest` variant that tracks the newest version:

```nix
{
  programs.cursor = {
    enable = true;
    package = pkgs.cursor-latest;  # Tracks newest version
  };
}
```

This is not yet implemented but is planned for a future release.

## Version Update Policy

Once we resume tracking latest Cursor versions, this package will:

1. **Automated Updates**: The `update.sh` script will automatically track new releases
2. **Update Notifications**: The built-in update checker will notify you daily
3. **Easy Upgrades**: The `cursor-update` command will handle the entire upgrade process

## How to Check Cursor's Custom Agent Status

**Official Changelog**: https://www.cursor.com/changelog

**Community Forum**: https://forum.cursor.com/

Look for topics related to:
- "Custom agents"
- "Custom modes"  
- "Agent configuration"
- ".cursor/agents" directory support

## Contributing

If you find a way to restore custom agent functionality or discover that Cursor has restored it, please:

1. Open an issue: https://github.com/Distracted-E421/nixos-cursor/issues
2. Submit a PR to update this document
3. Discuss in the community forum

## Questions?

**Why not just track latest anyway?**

Breaking users' workflows without warning is poor UX. This package prioritizes stability and workflow preservation.

**How do I know if I use custom agents?**

Check if you have a `.cursor/agents/` directory in your projects, or if you've configured custom system prompts in Cursor's settings.

**What about security updates?**

If a critical security issue is discovered in 2.0.64, we will immediately evaluate upgrading to 2.1.x despite the feature loss. Security always comes first.

---

**Last Updated**: 2025-11-24  
**Cursor Version**: 2.0.64  
**Custom Agent Status**: Deprecated in 2.1.0+  
**Package Maintainer**: e421 (distracted.e421@gmail.com)

