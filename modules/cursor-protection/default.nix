# Cursor Process Protection Module
#
# Provides defense-in-depth protection against accidentally killing
# the main Cursor development session.
#
# Features:
#   - cursor-safe-kill: Wrapper that blocks killing protected sessions
#   - cursor-test-launch: Launcher that marks instances as safe to kill
#   - cursor-main.service: Systemd user service for protected main session
#   - Environment markers: CURSOR_SESSION_TYPE=main/test
#   - Cgroup isolation: Main session runs in named cgroup
#
# Usage in NixOS config:
#   imports = [ ./modules/cursor-protection ];
#   services.cursor-protection.enable = true;
#

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.cursor-protection;
  
  cursor-safe-kill = pkgs.writeShellApplication {
    name = "cursor-safe-kill";
    runtimeInputs = with pkgs; [ procps coreutils gnugrep gawk ];
    text = builtins.readFile ./cursor-safe-kill;
  };
  
  cursor-test-launch = pkgs.writeShellApplication {
    name = "cursor-test-launch";
    runtimeInputs = with pkgs; [ coreutils findutils iproute2 ];
    text = builtins.readFile ./cursor-test-launch;
  };
  
in {
  options.services.cursor-protection = {
    enable = mkEnableOption "Cursor process protection";
    
    cursorPackage = mkOption {
      type = types.package;
      default = pkgs.cursor or (throw "cursor package not available");
      description = "The Cursor package to use for the main session";
    };
    
    defaultFolder = mkOption {
      type = types.str;
      default = "";
      description = "Default folder to open in main Cursor session";
    };
    
    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra arguments to pass to main Cursor session";
    };
  };
  
  config = mkIf cfg.enable {
    # Install the protection scripts
    environment.systemPackages = [
      cursor-safe-kill
      cursor-test-launch
    ];
    
    # Systemd user service for main Cursor session
    systemd.user.services.cursor-main = {
      description = "Main Cursor Development Session (PROTECTED)";
      wantedBy = [ ]; # Don't auto-start, user controls this
      
      environment = {
        CURSOR_SESSION_TYPE = "main";
        # Inherit display from user session
        DISPLAY = ":0";
        WAYLAND_DISPLAY = "wayland-0";
      };
      
      serviceConfig = {
        Type = "simple";
        ExecStart = let
          args = cfg.extraArgs ++ (optionals (cfg.defaultFolder != "") ["--folder" cfg.defaultFolder]);
        in "${cfg.cursorPackage}/bin/cursor ${concatStringsSep " " args}";
        Restart = "on-failure";
        RestartSec = "5s";
        
        # Isolation - makes this session identifiable
        Slice = "app-cursor.slice";
      };
    };
    
    # Slice for Cursor processes (helps with cgroup identification)
    systemd.user.slices.app-cursor = {
      description = "Cursor IDE Processes";
    };
    
    # Shell aliases for convenience
    programs.bash.shellAliases = mkIf config.programs.bash.enable {
      cursor-kill = "cursor-safe-kill";
      cursor-test = "cursor-test-launch";
      cursor-list = "cursor-safe-kill --list";
    };
    
    programs.zsh.shellAliases = mkIf config.programs.zsh.enable {
      cursor-kill = "cursor-safe-kill";
      cursor-test = "cursor-test-launch";
      cursor-list = "cursor-safe-kill --list";
    };
  };
}

