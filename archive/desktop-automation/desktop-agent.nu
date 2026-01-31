#!/usr/bin/env nu

# Desktop Automation Agent - Native Nushell Implementation
# Uses kdotool for window management, ydotool/dotool for input simulation
# NO MCP - direct tool execution with structured output

# ============================================================================
# CONFIGURATION
# ============================================================================

const YDOTOOL_SOCKET = "/tmp/.ydotool_socket"

def config [] {
    {
        screenshot_dir: ($env.HOME | path join "Pictures" "desktop-agent")
        log_file: ($env.HOME | path join ".local" "share" "desktop-agent" "agent.log")
        input_delay_ms: 50
        screenshot_tool: "spectacle"  # or "grim" for pure wayland
    }
}

# ============================================================================
# WINDOW MANAGEMENT (via kdotool)
# ============================================================================

# List all windows with their properties
export def "windows list" [] {
    let result = (kdotool search "." | lines | each {|id|
        let name = (kdotool getwindowname $id | str trim)
        let class = (kdotool getwindowclassname $id | str trim)
        let geom = (kdotool getwindowgeometry $id | lines | reduce -f {} {|line, acc|
            let parts = ($line | split row ":" | each { str trim })
            if ($parts | length) >= 2 {
                $acc | insert ($parts.0 | str downcase) ($parts.1 | into int)
            } else {
                $acc
            }
        })
        {
            id: $id
            name: $name
            class: $class
            x: ($geom.x? | default 0)
            y: ($geom.y? | default 0)
            width: ($geom.width? | default 0)
            height: ($geom.height? | default 0)
        }
    })
    $result
}

# Search for windows by name pattern
export def "windows search" [pattern: string] {
    kdotool search --name $pattern | lines | each {|id| $id | str trim } | where { $in != "" }
}

# Get the active window
export def "windows active" [] {
    let id = (kdotool getactivewindow | str trim)
    let name = (kdotool getwindowname $id | str trim)
    { id: $id, name: $name }
}

# Focus a window by ID
export def "windows focus" [window_id: string] {
    kdotool windowactivate $window_id
    { success: true, window_id: $window_id }
}

# Focus a window by name pattern
export def "windows focus-name" [pattern: string] {
    let ids = (windows search $pattern)
    if ($ids | length) == 0 {
        { success: false, error: $"No window matching '($pattern)'" }
    } else {
        windows focus ($ids | first)
    }
}

# Move window to position
export def "windows move" [window_id: string, x: int, y: int] {
    kdotool windowmove $window_id $x $y
    { success: true, window_id: $window_id, position: { x: $x, y: $y } }
}

# Resize window
export def "windows resize" [window_id: string, width: int, height: int] {
    kdotool windowsize $window_id $width $height
    { success: true, window_id: $window_id, size: { width: $width, height: $height } }
}

# Minimize window
export def "windows minimize" [window_id: string] {
    kdotool windowminimize $window_id
    { success: true, action: "minimize", window_id: $window_id }
}

# Close window
export def "windows close" [window_id: string] {
    kdotool windowclose $window_id
    { success: true, action: "close", window_id: $window_id }
}

# ============================================================================
# VIRTUAL DESKTOP MANAGEMENT (via qdbus)
# ============================================================================

# Get current virtual desktop
export def "desktop current" [] {
    let id = (qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.current | str trim)
    { desktop_id: $id }
}

# List all virtual desktops
export def "desktop list" [] {
    let count = (qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.count | str trim | into int)
    0..($count - 1) | each {|i| { index: $i }}
}

# Switch to desktop
export def "desktop switch" [desktop_id: string] {
    qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.setCurrent $desktop_id
    { success: true, desktop_id: $desktop_id }
}

# Create new desktop
export def "desktop create" [name: string = "AI Workspace"] {
    let count = (qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.count | str trim | into int)
    qdbus org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop $count $name
    { success: true, name: $name, position: $count }
}

# ============================================================================
# INPUT SIMULATION (via dotool - simpler than ydotool)
# ============================================================================

# Check if dotool/ydotool is available
export def "input check" [] {
    let dotool_available = (which dotool | length) > 0
    let ydotool_available = (which ydotool | length) > 0
    let in_input_group = (groups | str contains "input")
    
    {
        dotool: $dotool_available
        ydotool: $ydotool_available
        input_group: $in_input_group
        ready: ($dotool_available or $ydotool_available) and $in_input_group
    }
}

# Move mouse to absolute position (percentage 0.0-1.0)
export def "input mouse-to" [x: float, y: float] {
    $"mouseto ($x) ($y)" | dotool
    { success: true, action: "mouseto", x: $x, y: $y }
}

# Move mouse relative
export def "input mouse-move" [dx: int, dy: int] {
    $"mousemove ($dx) ($dy)" | dotool
    { success: true, action: "mousemove", dx: $dx, dy: $dy }
}

# Click mouse button
export def "input click" [button: string = "left"] {
    $"click ($button)" | dotool
    { success: true, action: "click", button: $button }
}

# Double click
export def "input double-click" [button: string = "left"] {
    $"click ($button)\nclick ($button)" | dotool
    { success: true, action: "double-click", button: $button }
}

# Type text
export def "input type" [text: string] {
    $"type ($text)" | dotool
    { success: true, action: "type", length: ($text | str length) }
}

# Press key(s)
export def "input key" [keys: string] {
    $"key ($keys)" | dotool
    { success: true, action: "key", keys: $keys }
}

# Hold key down
export def "input keydown" [keys: string] {
    $"keydown ($keys)" | dotool
    { success: true, action: "keydown", keys: $keys }
}

# Release key
export def "input keyup" [keys: string] {
    $"keyup ($keys)" | dotool
    { success: true, action: "keyup", keys: $keys }
}

# Scroll wheel
export def "input scroll" [amount: int] {
    $"wheel ($amount)" | dotool
    { success: true, action: "scroll", amount: $amount }
}

# ============================================================================
# SCREENSHOTS (via spectacle/grim)
# ============================================================================

# Take screenshot of current monitor
export def "screenshot monitor" [--output (-o): string] {
    let cfg = (config)
    mkdir ($cfg.screenshot_dir)
    let filename = $output | default $"($cfg.screenshot_dir)/monitor-(date now | format date '%Y%m%d-%H%M%S').png"
    
    spectacle -b -m -n -o $filename
    sleep 500ms  # Wait for file to be written
    
    if ($filename | path exists) {
        { success: true, path: $filename, size: (ls $filename | get size.0) }
    } else {
        { success: false, error: "Screenshot failed" }
    }
}

# Take screenshot of active window
export def "screenshot window" [--output (-o): string] {
    let cfg = (config)
    mkdir ($cfg.screenshot_dir)
    let filename = $output | default $"($cfg.screenshot_dir)/window-(date now | format date '%Y%m%d-%H%M%S').png"
    
    spectacle -b -a -n -o $filename
    sleep 500ms
    
    if ($filename | path exists) {
        { success: true, path: $filename, size: (ls $filename | get size.0) }
    } else {
        { success: false, error: "Screenshot failed" }
    }
}

# Take screenshot of full desktop
export def "screenshot full" [--output (-o): string] {
    let cfg = (config)
    mkdir ($cfg.screenshot_dir)
    let filename = $output | default $"($cfg.screenshot_dir)/full-(date now | format date '%Y%m%d-%H%M%S').png"
    
    spectacle -b -f -n -o $filename
    sleep 500ms
    
    if ($filename | path exists) {
        { success: true, path: $filename, size: (ls $filename | get size.0) }
    } else {
        { success: false, error: "Screenshot failed" }
    }
}

# ============================================================================
# COMPOUND ACTIONS
# ============================================================================

# Click at specific screen coordinates (converts to percentage for dotool)
export def "action click-at" [x: int, y: int, --button (-b): string = "left"] {
    # Get screen dimensions from KWin
    let screen_info = (qdbus org.kde.KWin /KWin org.kde.KWin.queryWindowInfo | lines | reduce -f {} {|line, acc|
        let parts = ($line | split row ":" | each { str trim })
        if ($parts | length) >= 2 {
            $acc | insert ($parts.0) ($parts.1)
        } else {
            $acc
        }
    })
    
    # Assume 1920x1080 if we can't get screen size (TODO: get actual screen size)
    let screen_w = 1920
    let screen_h = 1080
    
    let pct_x = ($x / $screen_w)
    let pct_y = ($y / $screen_h)
    
    input mouse-to $pct_x $pct_y
    sleep 50ms
    input click $button
    
    { success: true, action: "click-at", x: $x, y: $y, button: $button }
}

# Focus window and click at position within it
export def "action click-in-window" [window_pattern: string, rel_x: int, rel_y: int] {
    let ids = (windows search $window_pattern)
    if ($ids | length) == 0 {
        return { success: false, error: $"No window matching '($window_pattern)'" }
    }
    
    let win_id = ($ids | first)
    windows focus $win_id
    sleep 200ms
    
    # Get window geometry
    let geom = (kdotool getwindowgeometry $win_id | lines | reduce -f {} {|line, acc|
        let parts = ($line | split row ":" | each { str trim })
        if ($parts | length) >= 2 {
            $acc | insert ($parts.0 | str downcase) ($parts.1 | into int)
        } else {
            $acc
        }
    })
    
    let abs_x = ($geom.x? | default 0) + $rel_x
    let abs_y = ($geom.y? | default 0) + $rel_y
    
    action click-at $abs_x $abs_y
}

# Type text in a specific window
export def "action type-in-window" [window_pattern: string, text: string] {
    let result = (windows focus-name $window_pattern)
    if not $result.success {
        return $result
    }
    sleep 200ms
    input type $text
    { success: true, action: "type-in-window", window: $window_pattern, text_length: ($text | str length) }
}

# ============================================================================
# SYSTEM INFO
# ============================================================================

export def "system info" [] {
    let input_status = (input check)
    let active_window = (windows active)
    let desktop = (desktop current)
    
    {
        input: $input_status
        active_window: $active_window
        current_desktop: $desktop
        timestamp: (date now | format date '%Y-%m-%d %H:%M:%S')
    }
}

# ============================================================================
# MAIN / CLI
# ============================================================================

def main [...args] {
    if ($args | length) == 0 {
        print "Desktop Automation Agent"
        print "========================"
        print ""
        print "Commands:"
        print "  windows list          - List all windows"
        print "  windows search <pat>  - Search windows by name"
        print "  windows focus <id>    - Focus window by ID"
        print "  windows active        - Get active window"
        print ""
        print "  desktop current       - Get current virtual desktop"
        print "  desktop list          - List all desktops"
        print "  desktop create <name> - Create new desktop"
        print ""
        print "  input check           - Check input simulation status"
        print "  input click <button>  - Click mouse button"
        print "  input type <text>     - Type text"
        print "  input key <keys>      - Press key combination"
        print ""
        print "  screenshot monitor    - Screenshot current monitor"
        print "  screenshot window     - Screenshot active window"
        print ""
        print "  system info           - Get system status"
        return
    }
    
    # Route to appropriate command
    let cmd = ($args | str join " ")
    print $"Running: ($cmd)"
}

