#!/usr/bin/env nu
# Cursor Studio Rebuild Helper
# Fast rebuilds with feature presets and cargo caching
#
# Usage:
#   nu rebuild.nu              # Build with all features (default)
#   nu rebuild.nu --lite       # Core GUI only (fastest ~2 min)
#   nu rebuild.nu --sync       # GUI + sync features
#   nu rebuild.nu --features "p2p-sync"  # Custom features

def main [
    --lite (-l)                    # Core GUI only (no sync, fastest build)
    --sync (-s)                    # Include all sync features
    --features (-f): string = ""   # Custom feature list
    --release (-r)                 # Build release (default)
    --debug (-d)                   # Build debug (faster compile, slower runtime)
    --run                          # Run after building
    --install (-i)                 # Install to ~/.cargo/bin
    --clean (-c)                   # Clean before building
    --jobs (-j): int = 0           # Parallel jobs (0 = auto)
] {
    print "🔧 Cursor Studio Rebuild Helper"
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Determine features
    let feature_list = if $lite {
        print "📦 Mode: Lite (core GUI only)"
        "--no-default-features"
    } else if $sync {
        print "📦 Mode: Full Sync (p2p + server + surrealdb)"
        "--features full"
    } else if $features != "" {
        print $"📦 Mode: Custom features: ($features)"
        $"--features ($features)"
    } else {
        print "📦 Mode: Full (all features)"
        "--features full"
    }
    
    # Build profile
    let profile = if $debug {
        print "🔨 Profile: Debug (fast compile)"
        ""
    } else {
        print "🔨 Profile: Release (optimized)"
        "--release"
    }
    
    # Parallel jobs
    let jobs_arg = if $jobs > 0 {
        $"-j ($jobs)"
    } else {
        ""
    }
    
    # Clean if requested
    if $clean {
        print "🧹 Cleaning build artifacts..."
        cargo clean
    }
    
    # Build command
    let bins = [
        "--bin cursor-studio"
        "--bin cursor-studio-cli"
    ]
    
    # Add sync binaries if features include them
    let sync_bins = if ($feature_list | str contains "full") or ($feature_list | str contains "p2p-sync") {
        ["--bin p2p-sync"]
    } else {
        []
    }
    
    let server_bins = if ($feature_list | str contains "full") or ($feature_list | str contains "server-sync") {
        ["--bin sync-server" "--bin sync-cli"]
    } else {
        []
    }
    
    let all_bins = $bins | append $sync_bins | append $server_bins | str join " "
    
    print ""
    print $"📋 Building: ($all_bins)"
    print ""
    
    # Time the build
    let start = (date now)
    
    # Set cargo env for faster builds
    $env.CARGO_INCREMENTAL = "1"
    $env.CARGO_PROFILE_RELEASE_LTO = "thin"
    $env.CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16"
    
    # Build
    let cmd = $"cargo build ($profile) ($feature_list) ($all_bins) ($jobs_arg)"
    print $"🚀 Running: ($cmd)"
    print ""
    
    nu -c $cmd
    
    let elapsed = (date now) - $start
    print ""
    print $"✅ Build completed in ($elapsed | into string)"
    
    # Install if requested
    if $install {
        print ""
        print "📥 Installing to ~/.cargo/bin..."
        let target_dir = if $debug { "target/debug" } else { "target/release" }
        
        mkdir ~/.cargo/bin
        
        for bin in ["cursor-studio" "cursor-studio-cli"] {
            let src = $"($target_dir)/($bin)"
            if ($src | path exists) {
                cp $src ~/.cargo/bin/
                print $"  ✓ ($bin)"
            }
        }
        
        if ($feature_list | str contains "full") or ($feature_list | str contains "p2p-sync") {
            let src = $"($target_dir)/p2p-sync"
            if ($src | path exists) {
                cp $src ~/.cargo/bin/
                print "  ✓ p2p-sync"
            }
        }
        
        if ($feature_list | str contains "full") or ($feature_list | str contains "server-sync") {
            for bin in ["sync-server" "sync-cli"] {
                let src = $"($target_dir)/($bin)"
                if ($src | path exists) {
                    cp $src ~/.cargo/bin/
                    print $"  ✓ ($bin)"
                }
            }
        }
    }
    
    # Run if requested
    if $run {
        print ""
        print "🚀 Starting cursor-studio..."
        let target_dir = if $debug { "target/debug" } else { "target/release" }
        ^$"($target_dir)/cursor-studio"
    }
}
