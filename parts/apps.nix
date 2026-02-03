# Cursor IDE Apps
# App definitions for `nix run` support
{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, lib, ... }:
    let
      isLinux = lib.hasInfix "linux" system;

      # Helper to create app entries
      mkApp = pkg: mainProgram: {
        type = "app";
        program = "${pkg}/bin/${mainProgram}";
      };

      # All version names for app generation
      versionApps = [
        # 2.4.x
        { name = "cursor-2_4_21"; bin = "cursor-2.4.21"; }
        { name = "cursor-2_4_20"; bin = "cursor-2.4.20"; }
        { name = "cursor-2_4_18"; bin = "cursor-2.4.18"; }
        { name = "cursor-2_4_14"; bin = "cursor-2.4.14"; }
        { name = "cursor-2_4_7"; bin = "cursor-2.4.7"; }
        # 2.3.x
        { name = "cursor-2_3_41"; bin = "cursor-2.3.41"; }
        { name = "cursor-2_3_40"; bin = "cursor-2.3.40"; }
        { name = "cursor-2_3_39"; bin = "cursor-2.3.39"; }
        { name = "cursor-2_3_35"; bin = "cursor-2.3.35"; }
        { name = "cursor-2_3_34"; bin = "cursor-2.3.34"; }
        { name = "cursor-2_3_33"; bin = "cursor-2.3.33"; }
        { name = "cursor-2_3_29"; bin = "cursor-2.3.29"; }
        { name = "cursor-2_3_26"; bin = "cursor-2.3.26"; }
        { name = "cursor-2_3_23"; bin = "cursor-2.3.23"; }
        { name = "cursor-2_3_21"; bin = "cursor-2.3.21"; }
        { name = "cursor-2_3_20"; bin = "cursor-2.3.20"; }
        { name = "cursor-2_3_15"; bin = "cursor-2.3.15"; }
        { name = "cursor-2_3_14"; bin = "cursor-2.3.14"; }
        { name = "cursor-2_3_10"; bin = "cursor-2.3.10"; }
        # 2.2.x
        { name = "cursor-2_2_27"; bin = "cursor-2.2.27"; }
        { name = "cursor-2_2_23"; bin = "cursor-2.2.23"; }
        { name = "cursor-2_2_20"; bin = "cursor-2.2.20"; }
        { name = "cursor-2_2_17"; bin = "cursor-2.2.17"; }
        { name = "cursor-2_2_14"; bin = "cursor-2.2.14"; }
        { name = "cursor-2_2_12"; bin = "cursor-2.2.12"; }
        { name = "cursor-2_2_9"; bin = "cursor-2.2.9"; }
        { name = "cursor-2_2_8"; bin = "cursor-2.2.8"; }
        { name = "cursor-2_2_7"; bin = "cursor-2.2.7"; }
        { name = "cursor-2_2_6"; bin = "cursor-2.2.6"; }
        { name = "cursor-2_2_3"; bin = "cursor-2.2.3"; }
        # 2.1.x
        { name = "cursor-2_1_50"; bin = "cursor-2.1.50"; }
        { name = "cursor-2_1_49"; bin = "cursor-2.1.49"; }
        { name = "cursor-2_1_48"; bin = "cursor-2.1.48"; }
        { name = "cursor-2_1_47"; bin = "cursor-2.1.47"; }
        { name = "cursor-2_1_46"; bin = "cursor-2.1.46"; }
        { name = "cursor-2_1_44"; bin = "cursor-2.1.44"; }
        { name = "cursor-2_1_42"; bin = "cursor-2.1.42"; }
        { name = "cursor-2_1_41"; bin = "cursor-2.1.41"; }
        { name = "cursor-2_1_39"; bin = "cursor-2.1.39"; }
        { name = "cursor-2_1_36"; bin = "cursor-2.1.36"; }
        { name = "cursor-2_1_34"; bin = "cursor-2.1.34"; }
        { name = "cursor-2_1_32"; bin = "cursor-2.1.32"; }
        { name = "cursor-2_1_26"; bin = "cursor-2.1.26"; }
        { name = "cursor-2_1_25"; bin = "cursor-2.1.25"; }
        { name = "cursor-2_1_24"; bin = "cursor-2.1.24"; }
        { name = "cursor-2_1_20"; bin = "cursor-2.1.20"; }
        { name = "cursor-2_1_19"; bin = "cursor-2.1.19"; }
        { name = "cursor-2_1_17"; bin = "cursor-2.1.17"; }
        { name = "cursor-2_1_15"; bin = "cursor-2.1.15"; }
        { name = "cursor-2_1_7"; bin = "cursor-2.1.7"; }
        { name = "cursor-2_1_6"; bin = "cursor-2.1.6"; }
        # 2.0.x
        { name = "cursor-2_0_77"; bin = "cursor-2.0.77"; }
        { name = "cursor-2_0_75"; bin = "cursor-2.0.75"; }
        { name = "cursor-2_0_74"; bin = "cursor-2.0.74"; }
        { name = "cursor-2_0_73"; bin = "cursor-2.0.73"; }
        { name = "cursor-2_0_69"; bin = "cursor-2.0.69"; }
        { name = "cursor-2_0_64"; bin = "cursor-2.0.64"; }
        { name = "cursor-2_0_63"; bin = "cursor-2.0.63"; }
        { name = "cursor-2_0_60"; bin = "cursor-2.0.60"; }
        { name = "cursor-2_0_57"; bin = "cursor-2.0.57"; }
        { name = "cursor-2_0_54"; bin = "cursor-2.0.54"; }
        { name = "cursor-2_0_52"; bin = "cursor-2.0.52"; }
        { name = "cursor-2_0_43"; bin = "cursor-2.0.43"; }
        { name = "cursor-2_0_40"; bin = "cursor-2.0.40"; }
        { name = "cursor-2_0_38"; bin = "cursor-2.0.38"; }
        { name = "cursor-2_0_34"; bin = "cursor-2.0.34"; }
        { name = "cursor-2_0_32"; bin = "cursor-2.0.32"; }
        { name = "cursor-2_0_11"; bin = "cursor-2.0.11"; }
        # 1.7.x
        { name = "cursor-1_7_54"; bin = "cursor-1.7.54"; }
        { name = "cursor-1_7_53"; bin = "cursor-1.7.53"; }
        { name = "cursor-1_7_52"; bin = "cursor-1.7.52"; }
        { name = "cursor-1_7_46"; bin = "cursor-1.7.46"; }
        { name = "cursor-1_7_44"; bin = "cursor-1.7.44"; }
        { name = "cursor-1_7_43"; bin = "cursor-1.7.43"; }
        { name = "cursor-1_7_40"; bin = "cursor-1.7.40"; }
        { name = "cursor-1_7_39"; bin = "cursor-1.7.39"; }
        { name = "cursor-1_7_38"; bin = "cursor-1.7.38"; }
        { name = "cursor-1_7_36"; bin = "cursor-1.7.36"; }
        { name = "cursor-1_7_33"; bin = "cursor-1.7.33"; }
        { name = "cursor-1_7_28"; bin = "cursor-1.7.28"; }
        { name = "cursor-1_7_25"; bin = "cursor-1.7.25"; }
        { name = "cursor-1_7_23"; bin = "cursor-1.7.23"; }
        { name = "cursor-1_7_22"; bin = "cursor-1.7.22"; }
        { name = "cursor-1_7_17"; bin = "cursor-1.7.17"; }
        { name = "cursor-1_7_16"; bin = "cursor-1.7.16"; }
        { name = "cursor-1_7_12"; bin = "cursor-1.7.12"; }
        { name = "cursor-1_7_11"; bin = "cursor-1.7.11"; }
      ];

      # Generate version apps dynamically
      generatedApps = lib.listToAttrs (
        builtins.filter (x: x != null) (
          map (v:
            if config.packages ? ${v.name} && config.packages.${v.name} != null
            then lib.nameValuePair v.name (mkApp config.packages.${v.name} v.bin)
            else null
          ) versionApps
        )
      );
    in
    {
      apps = {
        default = mkApp config.packages.cursor "cursor";
        cursor = mkApp config.packages.cursor "cursor";
        cursor-test = mkApp config.packages.cursor-test "cursor-test";
      }
      # Linux-specific apps
      // lib.optionalAttrs isLinux {
        cursor-studio = mkApp config.packages.cursor-studio "cursor-studio";
        cursor-studio-cli = mkApp config.packages.cursor-studio-cli "cursor-studio-cli";
        cs = mkApp config.packages.cs "cs";
        cursor-versions = mkApp config.packages.cursor-versions "cursor-versions";
        cursor-dialog-daemon = mkApp config.packages.cursor-dialog-daemon "cursor-dialog-daemon";
        cursor-dialog-cli = mkApp config.packages.cursor-dialog-cli "cursor-dialog-cli";
      }
      # Version-specific apps
      // generatedApps;
    };
}
