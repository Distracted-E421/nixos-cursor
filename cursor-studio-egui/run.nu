#!/usr/bin/env nu
# Quick run script for Cursor Studio development
# Usage: nu run.nu [--release] [--clean]

def main [
    --release (-r)  # Build in release mode (slower build, faster run)
    --clean (-c)    # Clean build artifacts first
    --help (-h)     # Show help
] {
    if $help {
        print "Usage: nu run.nu [OPTIONS]"
        print ""
        print "Options:"
        print "  --release, -r    Build in release mode (slower build, faster run)"
        print "  --clean, -c      Clean build artifacts first"
        print "  --help, -h       Show this help"
        print ""
        print "For fastest iteration, use debug builds (default)."
        print "For distribution, use: nix build"
        return
    }
    
    # Change to script directory
    cd ($env.FILE_PWD? | default ".")
    
    # Clean if requested
    if $clean {
        print "🧹 Cleaning build artifacts..."
        cargo clean
    }
    
    # Build arguments
    let release_flag = if $release { ["--release"] } else { [] }
    
    # Check if we're in a nix shell
    if ($env.IN_NIX_SHELL? | is-empty) {
        print "⚡ Entering nix develop shell and building..."
        ^nix develop -c cargo run ...$release_flag
    } else {
        print "⚡ Building and running..."
        ^cargo run ...$release_flag
    }
}
