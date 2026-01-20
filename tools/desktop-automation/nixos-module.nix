# Desktop Automation NixOS Module
# Provides kdotool, ydotool, dotool and proper permissions for desktop automation
#
# Usage in configuration.nix:
#   imports = [ ./tools/desktop-automation/nixos-module.nix ];
#   services.desktopAutomation.enable = true;

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.desktopAutomation;
in
{
  options.services.desktopAutomation = {
    enable = mkEnableOption "Desktop automation tools for AI agents";

    user = mkOption {
      type = types.str;
      default = "e421";
      description = "User to grant input permissions to";
    };

    enableYdotool = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ydotool daemon for input simulation";
    };

    enableDotool = mkOption {
      type = types.bool;
      default = true;
      description = "Install dotool for simpler input simulation";
    };
  };

  config = mkIf cfg.enable {
    # Required packages
    environment.systemPackages = with pkgs; [
      # Window management
      kdotool          # KDE Wayland window control

      # Input simulation
      (if cfg.enableDotool then dotool else null)
      (if cfg.enableYdotool then ydotool else null)

      # Screenshot tools
      spectacle        # KDE screenshot tool
      grim             # Wayland screenshot
      slurp            # Region selection

      # Utilities
      jq               # JSON processing
      libnotify        # Desktop notifications
    ];

    # Add user to input group for uinput access
    users.users.${cfg.user}.extraGroups = [ "input" ];

    # Ensure uinput module is loaded
    boot.kernelModules = [ "uinput" ];

    # Set up udev rules for uinput access
    services.udev.extraRules = ''
      # Allow users in input group to access uinput
      KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
    '';

    # ydotool daemon (if enabled)
    systemd.user.services.ydotoold = mkIf cfg.enableYdotool {
      description = "ydotool daemon for input simulation";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      
      serviceConfig = {
        ExecStart = "${pkgs.ydotool}/bin/ydotoold";
        Restart = "on-failure";
        RestartSec = 3;
      };

      # Set socket path
      environment = {
        YDOTOOL_SOCKET = "/tmp/.ydotool_socket";
      };
    };

    # Environment variables
    environment.sessionVariables = {
      YDOTOOL_SOCKET = "/tmp/.ydotool_socket";
    };
  };
}

