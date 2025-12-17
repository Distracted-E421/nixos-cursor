#!/usr/bin/env nu

# UI Screenshot Tool for Cursor Studio Development
# Captures screenshots of Cursor Studio window for AI visual feedback

def main [
    --window (-w): string = "Cursor Studio"  # Window title to capture
    --output (-o): string = ""                # Output filename (auto-generated if empty)
    --full (-f)                               # Capture full screen instead of window
    --delay (-d): int = 0                     # Delay before capture (seconds)
] {
    # Create screenshots directory
    let screenshot_dir = ($env.HOME | path join "nixos-cursor/screenshots")
    mkdir $screenshot_dir
    
    # Generate filename with timestamp
    let timestamp = (date now | format date "%Y%m%d_%H%M%S")
    let filename = if ($output | is-empty) {
        $"cursor-studio-($timestamp).png"
    } else {
        $output
    }
    let output_path = ($screenshot_dir | path join $filename)
    
    # Delay if requested
    if $delay > 0 {
        print $"⏳ Waiting ($delay) seconds..."
        sleep ($delay * 1sec)
    }
    
    if $full {
        # Full screen capture
        print "📸 Capturing full screen..."
        grim $output_path
    } else {
        # Window-specific capture using hyprctl
        print $"📸 Capturing window: ($window)..."
        
        # Find window by title
        let windows = (hyprctl clients -j | from json)
        let target = ($windows | where title =~ $window | first)
        
        if ($target | is-empty) {
            print $"❌ Window '($window)' not found"
            print "Available windows:"
            $windows | select title class | print
            return
        }
        
        # Get window geometry
        let x = $target.at.0
        let y = $target.at.1
        let w = $target.size.0
        let h = $target.size.1
        let geometry = $"($x),($y) ($w)x($h)"
        
        print $"📐 Window geometry: ($geometry)"
        grim -g $geometry $output_path
    }
    
    if ($output_path | path exists) {
        print $"✅ Screenshot saved: ($output_path)"
        
        # Also create a symlink to latest
        let latest = ($screenshot_dir | path join "latest.png")
        rm -f $latest
        ln -s $output_path $latest
        print $"🔗 Latest symlink: ($latest)"
        
        # Return metadata as JSON for AI consumption
        {
            path: $output_path,
            latest: $latest,
            timestamp: $timestamp,
            window: $window,
            size: (ls $output_path | first | get size)
        } | to json
    } else {
        print "❌ Screenshot failed"
    }
}

# Helper: List all windows
def "main list" [] {
    print "📋 Available windows:"
    hyprctl clients -j | from json | select title class address | print
}

# Helper: Watch mode - take screenshots at interval
def "main watch" [
    --interval (-i): int = 30  # Seconds between screenshots
    --count (-c): int = 10     # Number of screenshots to take
] {
    print $"👁️ Watch mode: ($count) screenshots every ($interval)s"
    
    for i in 1..($count + 1) {
        print $"\n📸 Screenshot ($i)/($count)"
        main
        if $i < $count {
            sleep ($interval * 1sec)
        }
    }
    
    print "\n✅ Watch complete"
}

