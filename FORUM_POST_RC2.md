# NixOS Package for Cursor IDE with Automated Updates - RC2 Testing

Hi all, I've been working on a native NixOS package for Cursor that includes an automated update system. It's now in Release Candidate 2 testing (v2.0.64-rc2) and I'd love to get feedback from the community before the stable release.

## Important: Why 2.0.64?

Before I get into the technical details, I need to address the version number. This package is intentionally pinned to **Cursor 2.0.64**, which is the last version before custom agents were deprecated in 2.1.0. For those who don't know, custom agents let you define specialized AI behaviors, custom system prompts, and project-specific workflows. It's a feature I rely on heavily in my development workflow, and based on forum discussions, many other users feel the same way.

I initially planned to release RC1 with 2.1.20 (the latest version), but after discovering that custom agents were removed, I had to pivot immediately. The entire point of packaging software properly is to serve users' actual needs, and removing a critical workflow feature isn't acceptable for a stable release. So we're tracking 2.0.64 until custom agents are restored or we figure out how to reimplement them ourselves, possibly through MCP integration or some other mechanism. If you don't use custom agents and want the latest Cursor, you can still use the official AppImage, and I plan to add a `cursor-latest` variant in the future for users who prefer that.

The full version tracking policy is documented in the repository's `CURSOR_VERSION_TRACKING.md` file.

## The Technical Challenges

There are lots of challenges to this project idea, to say the least. If you remember, this is not the first attempt someone has made at making a Cursor IDE flake/nix pkg (no shade, burnout happens). I will outline my plan to keep the project going indefinitely, despite the many technical hurdles present in Cursor and the underlying editor. Chances are, if you are using NixOS, you are technical enough to want to know the details, so strap in, you don't get a tl:dr.

The biggest issue to solve for is the built in updater, which has actually gotten easier (in my opinion) to solve for after the team stopped using the VS Code style of update (take all of this with some salt, as I am not a vs code or cursor contributor, and only kind of know what I am talking about). Currently, the regular appimage does still break, as it is stored in the readonly /nix/store. The second biggest issue (for me) was the lack of gpu acceleration. In its appimage form, as of writing, it does not include gpu acceleration libraries. So, if you are running cursor on some random nutjob of a dev's system that has 6 monitors, 2 gpus that are from different vendors, but technically all the hardware is barely compatible (like my setup might be), then cursor can really start to chug and break. I also saw that there have been keybinding issues (think it was in the old thread, but idk), so that is likely an issue too.

## The Solutions

First off, the update system. Since Cursor can't update itself on NixOS (that readonly /nix/store strikes again), I built something that works with the grain instead of against it. The package now ships with a systemd user timer that checks Cursor's official API daily for new versions. When an update is available, you get a nice desktop notification telling you about it. No more manually checking the website or wondering if you're five versions behind. But here's the actually cool part: there's a command called `cursor-update` that does the entire update workflow for you. It auto-detects where your flake lives (or you can tell it if you're doing something weird), runs `nix flake update nixos-cursor`, rebuilds your Home Manager or NixOS configuration, and then tells you what version you just upgraded to. The whole thing takes maybe 30 seconds and requires zero manual intervention beyond typing the command. If you're a purist and want to do it the traditional Nix way (cd to your flake, update, rebuild), that still works fine too.

The technical implementation here is actually pretty straightforward, which is why I think it'll hold up long term. The check-update script just queries Cursor's download API endpoint, parses the version from the JSON response, compares it to what you have installed, and bails out if they match. The update script is a bash wrapper that handles the Nix rebuild dance. Nothing fancy, nothing that's going to break when Cursor changes their internal architecture for the third time this year. The built-in updater itself is disabled with a simple `--update=false` flag passed to the wrapper, so you don't get confusing error messages about updates failing.

For the GPU acceleration issues, the fix was actually simpler than I expected once I figured out what was missing. The AppImage doesn't include libGL or libxkbfile, which means no hardware acceleration and no proper keyboard mapping on Wayland. The NixOS package uses `autoPatchelfHook` to patch the binary's ELF headers to point at NixOS's libraries directly. This means the package gets access to your system's libGL (for GPU acceleration), libxkbfile (for keyboard mapping), and all the other libraries it needs to actually run properly on modern Linux systems. I also added all the Wayland flags and GPU optimization flags to the wrapper, so if you're running on Wayland like a civilized person in 2025, you get window decorations, hardware video decoding, zero-copy rendering, and all that good stuff. If you're still on X11, it works there too, no judgment.

The keyboard mapping thing was particularly annoying to track down. Turns out the native-keymap module in Electron needs libxkbfile to function properly, and without it you get all sorts of weird behavior with key bindings. Once I added that library to the build inputs and patched it in, keyboard shortcuts started working consistently. If you've been using Cursor on NixOS and noticed weird keyboard behavior, this should fix it.

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

The goal here is to make this something that can get upstreamed to nixpkgs eventually, or at minimum become the de facto way NixOS users install Cursor. But I need to know it actually works for people first, hence the RC period. So if you're on NixOS and use Cursor, please give this a shot and let me know what breaks. Bug reports welcome, feature requests welcome, pull requests extremely welcome.

## Get Involved

Repository: https://github.com/Distracted-E421/nixos-cursor

Full testing guide in `TESTING_RC.md` that walks through everything you should check.

Version tracking policy: `CURSOR_VERSION_TRACKING.md` explains the 2.0.64 decision in detail.

That's the situation. Cursor on NixOS, properly packaged, with an update system that doesn't make you want to quit Nix entirely, and pinned to a version that preserves critical workflow features. Let me know how it goes.

