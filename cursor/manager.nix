{ writeShellScriptBin, zenity, coreutils }:

writeShellScriptBin "cursor-manager" ''
  export PATH="${zenity}/bin:${coreutils}/bin:$PATH"
  
  # List of available versions
  VERSIONS=(
    "Launch 2.0.77 (Stable)" "Launch version 2.0.77 (Isolated Data)"
    "Launch 1.7.54 (Classic)" "Launch version 1.7.54 (Isolated Data)" 
    "Launch System Default" "Launch the default installed Cursor"
  )
  
  ACTION=$(zenity --list \
    --title="Cursor Version Manager" \
    --text="Select Cursor version to launch:" \
    --column="Action" --column="Description" \
    "''${VERSIONS[@]}" \
    --width=500 --height=350)
    
  case "$ACTION" in
    "Launch 2.0.77 (Stable)")
      if command -v cursor-2.0.77 >/dev/null; then
        nohup cursor-2.0.77 >/dev/null 2>&1 &
      else
        # Try running via nix run if not in PATH
        zenity --info --text="cursor-2.0.77 not in PATH. Attempting to run via nix..."
        nohup nix run github:Distracted-E421/nixos-cursor#cursor-2_0_77 --impure >/dev/null 2>&1 &
      fi
      ;;
    "Launch 1.7.54 (Classic)")
      if command -v cursor-1.7.54 >/dev/null; then
        nohup cursor-1.7.54 >/dev/null 2>&1 &
      else
        zenity --info --text="cursor-1.7.54 not in PATH. Attempting to run via nix..."
        nohup nix run github:Distracted-E421/nixos-cursor#cursor-1_7_54 --impure >/dev/null 2>&1 &
      fi
      ;;
    "Launch System Default")
      if command -v cursor >/dev/null; then
        nohup cursor >/dev/null 2>&1 &
      else
        zenity --error --text="cursor not found in PATH."
      fi
      ;;
  esac
''

