#!/usr/bin/env nu
# Cursor Disk Usage Analysis Script
# Analyzes Nix store usage for Cursor-related packages
#
# Nushell version - demonstrates structured data handling
# Compare to scripts/storage/disk-usage.sh for bash version

# Configuration
const STORE_PATH = "/nix/store"

# Get all Cursor-related entries from the Nix store
def get-cursor-entries [] {
    ls $STORE_PATH 
    | where { |e| $e.name =~ "(?i)cursor" }
    | select name size type
}

# Categorize store entries by type
def categorize-entry [entry: record] {
    let name = ($entry.name | path basename)
    
    if ($name =~ "AppImage") {
        "appimage"
    } else if ($name =~ "extracted") {
        "extracted"
    } else if ($name =~ "cursor-[0-9]") {
        "built"
    } else {
        "other"
    }
}

# Get version from entry name
def extract-version [name: string] {
    let match = ($name | parse -r '(?:cursor-?|Cursor-)(\d+\.\d+)')
    if ($match | is-empty) {
        "other"
    } else {
        $match.0.capture0
    }
}

# Main analysis function
def analyze-store [--detailed (-d)] {
    print $"(ansi blue)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi blue)║          (ansi white_bold)Cursor Nix Store Disk Usage Analysis(ansi reset)(ansi blue)                    ║(ansi reset)"
    print $"(ansi blue)╚═══════════════════════════════════════════════════════════════════╝(ansi reset)"
    print ""
    
    # Total store size (use du without flags for Nushell)
    let store_info = (du $STORE_PATH | first)
    let total_store = $store_info.apparent
    
    print $"(ansi white_bold)Nix Store Overview:(ansi reset)"
    print $"  Total store size: (ansi yellow)($total_store)(ansi reset)"
    print ""
    
    # Get all cursor entries
    let entries = (get-cursor-entries)
    
    if ($entries | is-empty) {
        print $"(ansi yellow)⚠(ansi reset)  No Cursor entries found in Nix store"
        return
    }
    
    # Add category to each entry
    let categorized = ($entries | each { |e|
        let cat = (categorize-entry $e)
        let ver = (extract-version $e.name)
        $e | insert category $cat | insert version $ver
    })
    
    print $"(ansi white_bold)Cursor Package Analysis:(ansi reset)"
    print $"  Total Cursor entries: (ansi cyan)($categorized | length)(ansi reset)"
    
    # Group by category
    let by_category = ($categorized | group-by category)
    
    # AppImages (use -o for optional, not -i)
    let appimages = ($by_category | get -o appimage | default [])
    let appimage_size = ($appimages | get size | math sum | default 0b)
    print $"  AppImages: (ansi cyan)($appimages | length)(ansi reset) (($appimage_size))"
    
    # Built packages
    let built = ($by_category | get -o built | default [])
    let built_size = ($built | get size | math sum | default 0b)
    print $"  Built packages: (ansi cyan)($built | length)(ansi reset) (($built_size))"
    
    # Extracted packages
    let extracted = ($by_category | get -o extracted | default [])
    let extracted_size = ($extracted | get size | math sum | default 0b)
    print $"  Extracted packages: (ansi cyan)($extracted | length)(ansi reset) (($extracted_size))"
    
    # Total
    let total_cursor = ($appimage_size + $built_size + $extracted_size)
    let total_store_bytes = ($total_store | into int)
    let total_cursor_bytes = ($total_cursor | into int)
    let percentage = if $total_store_bytes > 0 {
        ($total_cursor_bytes * 100 / $total_store_bytes | math round --precision 1)
    } else {
        0
    }
    
    print ""
    let pct_str = $"($percentage)%"
    print $"  (ansi white_bold)Total Cursor usage: (ansi yellow)($total_cursor)(ansi reset) \(($pct_str) of store\)"
    print ""
    
    # Detailed breakdown by version
    if $detailed {
        print $"(ansi white_bold)Version Breakdown:(ansi reset)"
        print ""
        
        let by_version = ($categorized | group-by version)
        
        # Create a table for nice output
        let version_table = ($by_version | items { |ver, items|
            let ver_appimage = ($items | where category == "appimage" | get size | math sum | default 0b)
            let ver_built = ($items | where category == "built" | get size | math sum | default 0b)
            let ver_extracted = ($items | where category == "extracted" | get size | math sum | default 0b)
            let ver_total = ($ver_appimage + $ver_built + $ver_extracted)
            
            {
                version: $"($ver).x"
                appimage: $ver_appimage
                built: $ver_built
                extracted: $ver_extracted
                total: $ver_total
            }
        } | sort-by total --reverse | where { |r| ($r.total | into int) > 0 })
        
        print ($version_table | table --theme rounded)
        print ""
    }
    
    # Recommendations
    print $"(ansi white_bold)Recommendations:(ansi reset)"
    
    let appimage_bytes = ($appimage_size | into int)
    if $appimage_bytes > (5 * 1024 * 1024 * 1024) {
        print $"  (ansi yellow)⚠(ansi reset)  AppImages using ($appimage_size) - consider running garbage collection"
    }
    
    if ($extracted | length) > 10 {
        print $"  (ansi yellow)⚠(ansi reset)  ($extracted | length) extracted packages - these can be rebuilt if needed"
    }
    
    # Check for dead paths
    let dead = (^nix-store --gc --print-dead 2>/dev/null | complete)
    if ($dead.stdout | str length) > 0 {
        print $"  (ansi green)✓(ansi reset)  Dead store paths exist - run 'nix-collect-garbage' to reclaim space"
    } else {
        print $"  (ansi green)✓(ansi reset)  No dead store paths - store is optimized"
    }
    
    print ""
    
    # Quick commands
    print $"(ansi white_bold)Quick Commands:(ansi reset)"
    print $"  (ansi cyan)nix-collect-garbage(ansi reset)           # Remove unused packages"
    print $"  (ansi cyan)nix-collect-garbage -d(ansi reset)        # Also delete old generations"
    print $"  (ansi cyan)nix store optimise(ansi reset)            # Deduplicate store"
    print $"  (ansi cyan)sudo nix-collect-garbage -d(ansi reset)   # Clean system generations too"
    print ""
}

# Show GC roots for Cursor packages
def show-gc-roots [] {
    print $"(ansi white_bold)GC Roots for Cursor Packages:(ansi reset)"
    print ""
    
    let roots = (ls /nix/var/nix/gcroots/auto/* 
        | each { |r|
            let target = (^readlink -f $r.name | complete)
            if ($target.stdout =~ "(?i)cursor") {
                { root: ($r.name | path basename), target: ($target.stdout | str trim) }
            }
        }
        | compact)
    
    if ($roots | is-empty) {
        print "  (no Cursor-related GC roots found)"
    } else {
        print ($roots | table)
    }
    print ""
}

# JSON output mode
def analyze-json [] {
    let entries = (get-cursor-entries | each { |e|
        let cat = (categorize-entry $e)
        let ver = (extract-version $e.name)
        $e | insert category $cat | insert version $ver
    })
    
    let by_category = ($entries | group-by category)
    
    {
        total_entries: ($entries | length)
        appimages: {
            count: ($by_category | get -o appimage | default [] | length)
            size: ($by_category | get -o appimage | default [] | get size | math sum | default 0b | into int)
        }
        built: {
            count: ($by_category | get -o built | default [] | length)
            size: ($by_category | get -o built | default [] | get size | math sum | default 0b | into int)
        }
        extracted: {
            count: ($by_category | get -o extracted | default [] | length)
            size: ($by_category | get -o extracted | default [] | get size | math sum | default 0b | into int)
        }
    } | to json
}

# Main entry point
def main [
    --detailed (-d)    # Show detailed breakdown by version
    --json (-j)        # Output in JSON format
    --gc-roots (-g)    # Show GC roots for Cursor packages
] {
    if $json {
        analyze-json
    } else {
        analyze-store --detailed=$detailed
        
        if $gc_roots {
            show-gc-roots
        }
    }
}
