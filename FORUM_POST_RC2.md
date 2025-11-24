# NixOS Package for Cursor IDE with Automated Updates - RC2 Testing


## MCP Server Integration

Now, there's also MCP server integration, which I realize is probably niche but it's in there if you want it. Model Context Protocol is this framework for hooking up AI assistants to various tools and data sources. The package includes a Home Manager module that lets you declaratively configure filesystem access, GitHub integration, NixOS package search, memory/knowledge persistence, and browser automation via Playwright. You can enable them all with a single `mcp.enable = true` in your config, or pick and choose which ones you want. I'm not going to lie, the setup is a bit manual right now (you need Node.js for some of them, uvx for the NixOS one, etc.), but once they're running they're pretty useful if you're doing the whole AI-assisted development thing.

## How to Test

If you want to try this out right now without committing to anything, you can run:

```bash
nix run github:Distracted-E421/nixos-cursor/v2.0.64-rc2#cursor
```

It'll download and launch Cursor 2.0.64 with zero installation required. This is genuinely the best way to test it because if something's broken, you just close it and nothing on your system has changed.

If you like it and want to actually install it, there's a Home Manager module that handles everything:

```nix
{
  inputs.nixos-cursor.url = "github:Distracted-E421/nixos-cursor/v2.0.64-rc2";
  
  # In your Home Manager configuration:
  programs.cursor = {
    enable = true;
    
    # Automated updates (checks daily, provides cursor-update command)
    updateCheck.enable = true;
    flakeDir = "/path/to/your/flake";
    
    # Optional: MCP servers (disabled by default)
    mcp.enable = false;
  };
}
```

## What I Need From You

Here's what I actually need from the community though, because this is where the RC testing part comes in. I've tested this on my own system (x86_64, dual GPU nightmare setup as mentioned earlier), and it works great. But I need people to test on normal systems too. Does it build? Does it run? Do keyboard shortcuts work? Does GPU acceleration actually kick in? Does the update notification system function correctly? I'm especially looking for anyone on ARM64 (Apple Silicon Macs running NixOS via UTM or Asahi, ARM64 servers, whatever). The package builds for ARM64 in CI and the derivation evaluates fine, but I literally cannot test it because I don't have the hardware. If you're on ARM64 and this doesn't work, I need to know about it before calling this stable.

The other thing I'm trying to gauge is whether the MCP integration is useful to anyone besides me. It's there, it's documented, it works, but if nobody's using it then maybe it doesn't need to be in the default module. Or maybe people want it but the setup is too annoying and I should automate more of it. I genuinely don't know yet.

## Long-Term Sustainability

In terms of keeping this project going long-term, I've tried to make everything as maintainable as possible. The update checker uses Cursor's official API, so as long as they don't completely restructure their release system, it should keep working. The binary patching uses nixpkgs' standard `autoPatchelfHook`, which is battle-tested and used by tons of other packages. The Home Manager module follows all the standard patterns, so it should be easy for other people to understand and contribute to if they want. And critically, the update system means users can get new Cursor versions without waiting for me to manually update the package every single time. The hash update script still needs to be run when new versions come out, but that's a 30-second operation, not a "rebuild the entire packaging from scratch" situation.



## Get Involved

Repository: https://github.com/Distracted-E421/nixos-cursor

Full testing guide in `TESTING_RC.md` that walks through everything you should check.

Version tracking policy: `CURSOR_VERSION_TRACKING.md` explains the 2.0.64 decision in detail.

That's the situation. Cursor on NixOS, properly packaged, with an update system that doesn't make you want to quit Nix entirely, and pinned to a version that preserves critical workflow features. Let me know how it goes.


