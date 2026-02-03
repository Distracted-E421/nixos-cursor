{
  description = "Cursor IDE with MCP Servers for NixOS and macOS";

  nixConfig = {
    extra-substituters = [
      "https://nixos-cursor.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-cursor.cachix.org-1:8YAZIsMXbzdSJh6YF71XIVR2OgnRXXZ+7e82dL5yCqI="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # MCP servers (memory, playwright, etc.)
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, mcp-servers-nix }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Supported systems
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Import modular parts
      imports = [
        ./parts/packages.nix
        ./parts/apps.nix
        ./parts/dev-shells.nix
        ./parts/modules.nix
      ];

      # Per-system configuration
      perSystem = { config, self', inputs', pkgs, system, lib, ... }: {
        # Use unfree packages (Cursor is proprietary)
        _module.args.pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      };
    };
}
