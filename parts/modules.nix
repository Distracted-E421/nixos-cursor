# Cursor IDE Modules
# NixOS and Home Manager modules for system integration
{ inputs, self, ... }:
{
  flake = {
    # Home Manager module
    homeManagerModules = {
      default = import ../home-manager-module;
      cursor-with-mcp = import ../home-manager-module;
    };

    # NixOS modules
    nixosModules = {
      # Isolated proxy testing environment with network namespace
      cursor-proxy-isolated = import ../modules/nixos/cursor-proxy-isolated.nix;

      # Legacy proxy module (deprecated)
      cursor-proxy = import ../modules/nixos/cursor-proxy.nix;
    };

    # Overlays
    overlays.default = final: prev: {
      cursor = final.callPackage ../cursor {
        version = "2.0.77";
        hash = "sha256-/r7cmjgFhec7fEKUfFKw3vUoB9LJB2P/646cMeRKp/0=";
        srcUrl = "https://downloads.cursor.com/production/ba90f2f88e4911312761abab9492c42442117cfe/linux/x64/Cursor-2.0.77-x86_64.AppImage";
      };

      # MCP server packages from mcp-servers-nix
      mcp-server-memory = inputs.mcp-servers-nix.packages.${final.system}.mcp-server-memory or null;
      playwright-mcp = inputs.mcp-servers-nix.packages.${final.system}.playwright-mcp or null;

      # NPM security module for MCP servers
      npm-security = final.callPackage ../security { };
    };

    # Security module (standalone import)
    lib.npmSecurity = import ../security;
  };
}
