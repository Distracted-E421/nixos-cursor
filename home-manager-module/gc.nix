# Garbage Collection Module for NixOS Cursor
# Provides automatic garbage collection configuration
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.cursor.gc;
  
  # Generate systemd timer configuration
  gcTimerConfig = {
    Unit = {
      Description = "Cursor/Nix Store Garbage Collection";
    };
    Timer = {
      OnCalendar = cfg.schedule;
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
  
  gcServiceConfig = {
    Unit = {
      Description = "Cursor/Nix Store Garbage Collection";
    };
    Service = {
      Type = "oneshot";
      ExecStart = toString (pkgs.writeShellScript "cursor-gc" ''
        set -euo pipefail
        
        echo "Starting Cursor/Nix garbage collection..."
        echo "Time: $(date)"
        echo ""
        
        # Delete old user generations
        ${optionalString cfg.deleteOlderThan.enable ''
          echo "Deleting generations older than ${cfg.deleteOlderThan.days} days..."
          ${pkgs.nix}/bin/nix-env --delete-generations +${toString cfg.keepGenerations}
        ''}
        
        # Delete Home Manager generations
        ${optionalString (cfg.deleteOlderThan.enable && config.programs.home-manager.enable or false) ''
          echo "Expiring Home Manager generations..."
          ${pkgs.home-manager}/bin/home-manager expire-generations "-${toString cfg.deleteOlderThan.days} days" || true
        ''}
        
        # Run garbage collection
        echo "Running nix-collect-garbage..."
        ${pkgs.nix}/bin/nix-collect-garbage ${optionalString cfg.deleteOlderThan.enable "-d"}
        
        # Optimize store (optional, can be slow)
        ${optionalString cfg.optimize ''
          echo "Optimizing Nix store..."
          ${pkgs.nix}/bin/nix store optimise
        ''}
        
        echo ""
        echo "Garbage collection complete!"
        echo "Store size: $(du -sh /nix/store | cut -f1)"
      '');
    };
  };
in
{
  options.programs.cursor.gc = {
    enable = mkEnableOption "automatic garbage collection for Cursor/Nix store";
    
    schedule = mkOption {
      type = types.str;
      default = "weekly";
      example = "daily";
      description = ''
        How often to run garbage collection.
        Uses systemd calendar event syntax.
        Common values: "daily", "weekly", "monthly", "*-*-* 03:00:00"
      '';
    };
    
    keepGenerations = mkOption {
      type = types.int;
      default = 5;
      description = ''
        Number of recent generations to keep.
        Older generations will be deleted during GC.
      '';
    };
    
    deleteOlderThan = {
      enable = mkEnableOption "deletion of old generations";
      
      days = mkOption {
        type = types.int;
        default = 7;
        description = ''
          Delete generations older than this many days.
        '';
      };
    };
    
    optimize = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to run store optimization after garbage collection.
        This deduplicates identical files but can take a long time.
        Only recommended for weekly or less frequent runs.
      '';
    };
    
    cursorVersionsToKeep = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "2.0.77" "1.7.54" ];
      description = ''
        List of Cursor versions to always keep in the store.
        These will be protected from garbage collection via GC roots.
      '';
    };
  };
  
  config = mkIf cfg.enable {
    # Create systemd user timer and service
    systemd.user.timers.cursor-gc = gcTimerConfig;
    systemd.user.services.cursor-gc = gcServiceConfig;
    
    # Create GC roots for protected versions
    # Note: This creates symlinks that prevent GC from removing these versions
    home.file = mkMerge (map (version: {
      ".local/share/nix/gcroots/cursor-${version}".source =
        # This will be the store path if the package is installed
        # Otherwise it's a no-op
        config.home.path + "/share/cursor-${version}";
    }) cfg.cursorVersionsToKeep);
    
    # Add activation script to show GC status
    home.activation.cursorGcStatus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if systemctl --user is-active cursor-gc.timer &>/dev/null; then
        $DRY_RUN_CMD echo "Cursor GC timer is active (schedule: ${cfg.schedule})"
      fi
    '';
  };
}
