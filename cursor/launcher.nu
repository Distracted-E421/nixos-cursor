#!/usr/bin/env nu
# Cursor Unified Launcher (Nushell)
# Reads configuration from cursor-manager and launches appropriate version
#
# Priority order for version selection:
# 1. Command-line argument: cursor --version 2.0.77
# 2. Environment variable: CURSOR_VERSION=2.0.77 cursor
# 3. Config file: ~/.config/cursor-manager/config.json
# 4. System default: flake-specified version

# Configuration paths
def config-dir [] {
    $env.XDG_CONFIG_HOME? | default $"($env.HOME)/.config" | path join "cursor-manager"
}

def config-file [] {
    config-dir | path join "config.json"
}

def cursor-config-dir [] {
    $env.XDG_CONFIG_HOME? | default $"($env.HOME)/.config" | path join "Cursor"
}

# Read config value with default fallback
def read-config [key: string, default: string = ""] {
    let file = config-file
    if not ($file | path exists) {
        return $default
    }
    
    try {
        open $file | get -i $key | default $default
    } catch {
        $default
    }
}

# Determine target version based on priority
def get-target-version [cli_version: string = ""] {
    # Priority 1: CLI argument
    if $cli_version != "" {
        return $cli_version
    }
    
    # Priority 2: Environment variable
    if ($env.CURSOR_VERSION? | is-not-empty) {
        return $env.CURSOR_VERSION
    }
    
    # Priority 3: Config file
    let config_version = read-config "defaultVersion" ""
    if $config_version != "" and $config_version != "null" and $config_version != "system" {
        return $config_version
    }
    
    # Priority 4: System default (placeholder - replaced by Nix)
    "@version@"
}

# Sync settings between version directories
def sync-settings [target_version: string] {
    let sync_enabled = (read-config "settings.syncSettingsOnLaunch" "true") == "true"
    if not $sync_enabled { return }
    
    let source_dir = cursor-config-dir | path join "User"
    if not ($source_dir | path exists) { return }
    
    # Don't sync for system default
    if $target_version == "@version@" { return }
    
    let target_dir = $"($env.HOME)/.cursor-($target_version)/User"
    mkdir $target_dir
    
    # Sync settings.json and keybindings.json
    for file in ["settings.json", "keybindings.json"] {
        let src = $source_dir | path join $file
        let dst = $target_dir | path join $file
        if ($src | path exists) and not ($dst | path exists) {
            cp $src $dst
        }
    }
    
    # Sync snippets
    let sync_snippets = (read-config "dataControl.syncSnippets" "true") == "true"
    if $sync_snippets {
        let src = $source_dir | path join "snippets"
        let dst = $target_dir | path join "snippets"
        if ($src | path exists) and not ($dst | path exists) {
            cp -r $src $dst
        }
    }
}

# Get binary path for version
def get-cursor-binary [version: string] {
    if $version == "@version@" {
        # System binary (replaced by Nix)
        return "@out@/share/@shareDirName@/cursor"
    }
    
    # Check for versioned binary in PATH
    let versioned = $"cursor-($version)"
    if (which $versioned | is-not-empty) {
        return (which $versioned | get 0.path)
    }
    
    # Fallback: use nix run
    $"nix-run:($version)"
}

# Main entry point
def main [
    --version (-v): string = ""  # Cursor version to launch
    ...args: string              # Pass-through arguments
] {
    let target_version = get-target-version $version
    
    # Sync settings if enabled
    sync-settings $target_version
    
    # Get binary
    let cursor_bin = get-cursor-binary $target_version
    
    if ($cursor_bin | str starts-with "nix-run:") {
        # Use nix run for non-installed version
        let nix_version = $cursor_bin | str replace "nix-run:" ""
        let pkg_name = $"cursor-($nix_version | str replace -a '.' '_')"
        let flake_uri = $env.CURSOR_FLAKE_URI? | default "github:Distracted-E421/nixos-cursor"
        
        ^nix run $"($flake_uri)#($pkg_name)" --impure -- ...$args
    } else {
        # Direct execution
        ^$cursor_bin --update=false ...$args
    }
}
