#!/usr/bin/env nu

# Script: gc-helper.nu
# Purpose: Safe, interactive garbage collection for NixOS/nix-darwin
# Usage: nu gc-helper.nu [command] [options]
#
# Replaces: scripts/storage/gc-helper.sh

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

const VERSION = "2.0.0"
const DEFAULT_KEEP_GENERATIONS = 5
const DEFAULT_KEEP_DAYS = 7

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def header [title: string] {
    print $"(ansi blue)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi blue)║              (ansi white_bold)($title)(ansi reset)(ansi blue)                     ║(ansi reset)"
    print $"(ansi blue)╚═══════════════════════════════════════════════════════════════════╝(ansi reset)"
    print ""
}

def success [msg: string] { print $"(ansi green)✓(ansi reset)  ($msg)" }
def warn [msg: string] { print $"(ansi yellow)⚠(ansi reset)  ($msg)" }
def error [msg: string] { print $"(ansi red)✗(ansi reset)  ($msg)" }
def info [msg: string] { print $"(ansi cyan)ℹ(ansi reset)  ($msg)" }

def confirm [prompt: string]: nothing -> bool {
    print -n $"(ansi yellow)($prompt) [y/N]: (ansi reset)"
    let response = (input)
    $response =~ "^[yY]"
}

# ─────────────────────────────────────────────────────────────────────────────
# ANALYSIS FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Get dead store paths that can be garbage collected
def get-dead-paths [] {
    let result = (^nix-store --gc --print-dead 2>/dev/null | complete)
    if $result.exit_code == 0 {
        $result.stdout | lines | where { |l| $l starts-with "/nix/store" }
    } else {
        []
    }
}

# Get system generations
def get-system-generations [] {
    let result = (do { sudo nix-env --list-generations --profile /nix/var/nix/profiles/system } | complete)
    if $result.exit_code != 0 { return [] }
    
    $result.stdout 
    | lines 
    | where { |l| $l =~ '^\s*\d+' }
    | each { |line|
        let parts = ($line | str trim | split row -r '\s+')
        {
            generation: ($parts.0 | into int)
            date: $parts.1
            time: ($parts.2? | default "")
            current: ($line =~ '\(current\)')
        }
    }
}

# Get user profile generations
def get-user-generations [] {
    let result = (^nix-env --list-generations | complete)
    if $result.exit_code != 0 { return [] }
    
    $result.stdout 
    | lines 
    | where { |l| $l =~ '^\s*\d+' }
    | each { |line|
        let parts = ($line | str trim | split row -r '\s+')
        {
            generation: ($parts.0 | into int)
            date: $parts.1
            time: ($parts.2? | default "")
            current: ($line =~ '\(current\)')
        }
    }
}

# Analyze garbage and return structured report
def analyze-garbage [] {
    print $"(ansi cyan)Analyzing garbage...(ansi reset)"
    print ""
    
    # Get dead paths
    let dead_paths = (get-dead-paths)
    let dead_count = ($dead_paths | length)
    
    # Calculate size of dead paths
    let dead_size = if $dead_count > 0 {
        $dead_paths 
        | each { |p| 
            if ($p | path exists) {
                (du $p | first | get apparent)
            } else { 
                0b 
            }
        }
        | math sum
    } else {
        0b
    }
    
    print $"(ansi white_bold)Dead Store Paths:(ansi reset)"
    if $dead_count > 0 {
        print $"  Count: (ansi cyan)($dead_count)(ansi reset) paths"
        print $"  Size:  (ansi yellow)($dead_size)(ansi reset) can be reclaimed"
        print ""
        
        # Show cursor-related dead paths
        let cursor_dead = ($dead_paths | where { |p| $p =~ "(?i)cursor" })
        let cursor_dead_count = ($cursor_dead | length)
        
        if $cursor_dead_count > 0 {
            print $"  Cursor-related dead paths: (ansi cyan)($cursor_dead_count)(ansi reset)"
            $cursor_dead | first 5 | each { |p| print $"    - ($p | path basename)" }
            if $cursor_dead_count > 5 {
                print $"    ... and ($cursor_dead_count - 5) more"
            }
            print ""
        }
    } else {
        success "No dead store paths found"
        print ""
    }
    
    # System generations
    let sys_gens = (get-system-generations)
    let current_gen = ($sys_gens | where current | first | get -o generation | default "?")
    
    print $"(ansi white_bold)System Generations:(ansi reset)"
    print $"  Total generations: (ansi cyan)($sys_gens | length)(ansi reset)"
    print $"  Current generation: (ansi green)($current_gen)(ansi reset)"
    print ""
    
    # User profile generations
    let user_gens = (get-user-generations)
    let user_current = ($user_gens | where current | first | get -o generation | default "?")
    
    print $"(ansi white_bold)User Profile Generations:(ansi reset)"
    print $"  Total generations: (ansi cyan)($user_gens | length)(ansi reset)"
    print $"  Current generation: (ansi green)($user_current)(ansi reset)"
    print ""
    
    # Home Manager generations
    let hm_result = (do { home-manager generations } | complete)
    if $hm_result.exit_code == 0 {
        let hm_count = ($hm_result.stdout | lines | length)
        print $"(ansi white_bold)Home Manager Generations:(ansi reset)"
        print $"  Total generations: (ansi cyan)($hm_count)(ansi reset)"
        print ""
    }
    
    # Return summary
    {
        dead_paths: $dead_count
        dead_size: $dead_size
        system_generations: ($sys_gens | length)
        user_generations: ($user_gens | length)
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTION FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Run garbage collection
def do-collect [dry_run: bool, interactive: bool, system_gc: bool] {
    print $"(ansi cyan)Running garbage collection...(ansi reset)"
    print ""
    
    if $dry_run {
        warn "[DRY RUN] Would run: nix-collect-garbage"
        print ""
        let dead = (get-dead-paths)
        print "Dead paths that would be collected:"
        $dead | first 20 | each { |p| print $"  ($p)" }
        if ($dead | length) > 20 {
            print $"  ... and (($dead | length) - 20) more"
        }
        return
    }
    
    if $interactive {
        if not (confirm "Run garbage collection?") {
            print "Cancelled."
            return
        }
    }
    
    print $"Running: (ansi cyan)nix-collect-garbage(ansi reset)"
    ^nix-collect-garbage
    
    if $system_gc {
        print ""
        print $"Running: (ansi cyan)sudo nix-collect-garbage(ansi reset)"
        sudo nix-collect-garbage
    }
    
    print ""
    success "Garbage collection complete"
}

# Manage generations
def do-generations [dry_run: bool, interactive: bool, keep: int] {
    print $"(ansi cyan)Managing generations...(ansi reset)"
    print ""
    
    # Show current state
    print $"(ansi white_bold)Current System Generations:(ansi reset)"
    let gens = (get-system-generations)
    $gens | last 10 | table
    print ""
    
    if $dry_run {
        warn $"[DRY RUN] Would delete generations older than +($keep)"
        
        # Calculate which would be deleted
        let to_delete = ($gens | drop $keep | get generation)
        if ($to_delete | length) > 0 {
            print $"Would delete generations: (ansi red)($to_delete | str join ', ')(ansi reset)"
        } else {
            success "No generations would be deleted"
        }
        return
    }
    
    if $interactive {
        if not (confirm $"Delete old generations \(keeping last ($keep)\)?") {
            print "Cancelled."
            return
        }
    }
    
    print $"Running: (ansi cyan)sudo nix-env --delete-generations +($keep) --profile /nix/var/nix/profiles/system(ansi reset)"
    sudo nix-env --delete-generations $"+($keep)" --profile /nix/var/nix/profiles/system
    
    print $"Running: (ansi cyan)nix-env --delete-generations +($keep)(ansi reset)"
    ^nix-env --delete-generations $"+($keep)"
    
    # Clean Home Manager if available
    let hm_result = (do { home-manager expire-generations $"-($DEFAULT_KEEP_DAYS) days" } | complete)
    if $hm_result.exit_code == 0 {
        print $"Running: (ansi cyan)home-manager expire-generations(ansi reset)"
    }
    
    print ""
    success "Generation cleanup complete"
}

# Optimize store
def do-optimize [dry_run: bool, interactive: bool] {
    print $"(ansi cyan)Optimizing Nix store...(ansi reset)"
    print ""
    
    warn "Note: Store optimization can take a long time (10-30+ minutes)"
    print "This deduplicates identical files across the store."
    print ""
    
    if $dry_run {
        warn "[DRY RUN] Would run: nix store optimise"
        return
    }
    
    if $interactive {
        if not (confirm "Run store optimization? (This can take a while)") {
            print "Cancelled."
            return
        }
    }
    
    print $"Running: (ansi cyan)nix store optimise(ansi reset)"
    nix store optimise
    
    print ""
    success "Store optimization complete"
}

# Full cleanup
def do-full [dry_run: bool, interactive: bool, keep: int] {
    print $"(ansi cyan)Running full cleanup...(ansi reset)"
    print ""
    
    if $dry_run {
        warn "[DRY RUN] Full cleanup would:"
        print $"  1. Delete old generations \(keep last ($keep)\)"
        print "  2. Run garbage collection"
        print "  3. Optimize store (deduplicate)"
        print ""
        analyze-garbage | ignore
        return
    }
    
    print $"(ansi white_bold)Full cleanup will:(ansi reset)"
    print $"  1. Delete old generations \(keep last ($keep)\)"
    print "  2. Run garbage collection"
    print "  3. Optimize store (deduplicate)"
    print ""
    
    if $interactive {
        if not (confirm "Proceed with full cleanup?") {
            print "Cancelled."
            return
        }
    }
    
    print ""
    
    # Don't prompt for individual steps
    do-generations false false $keep
    print ""
    
    do-collect false false false
    print ""
    
    do-optimize false false
    print ""
    
    print $"(ansi green)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi green)║                    Full Cleanup Complete!                          ║(ansi reset)"
    print $"(ansi green)╚═══════════════════════════════════════════════════════════════════╝(ansi reset)"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main [
    command?: string                    # Command: analyze, collect, generations, optimize, full
    --dry-run (-n)                      # Show what would be done without doing it
    --yes (-y)                          # Non-interactive mode (no confirmations)
    --keep-generations: int = 5         # Keep last N generations
    --system                            # Also clean system generations
    --help (-h)                         # Show help
] {
    # Handle help
    if $help {
        print "
Usage: nu gc-helper.nu [COMMAND] [OPTIONS]

Safe garbage collection for NixOS/nix-darwin systems

Commands:
    analyze         Show what would be collected (default)
    collect         Run garbage collection
    generations     Manage system generations
    optimize        Run store optimization
    full            Full cleanup (generations + gc + optimize)

Options:
    -h, --help              Show this help
    -y, --yes               Non-interactive mode (no confirmations)
    -n, --dry-run           Show what would be done without doing it
    --keep-generations N    Keep last N generations (default: 5)
    --system                Also clean system generations

Examples:
    nu gc-helper.nu                           # Analyze (default)
    nu gc-helper.nu collect --dry-run         # Dry-run garbage collection
    nu gc-helper.nu generations --keep 3      # Keep only last 3 generations
    nu gc-helper.nu full --yes                # Full cleanup, no prompts

Safety Features:
    - Shows space that will be freed before any action
    - Preserves recent generations
    - Confirmation prompts (use -y to skip)
"
        return
    }
    
    # Default command
    let cmd = ($command | default "analyze")
    let interactive = not $yes
    let keep = $keep_generations
    
    header "Cursor Garbage Collection Helper"
    
    if $dry_run {
        warn "DRY RUN MODE - No changes will be made"
        print ""
    }
    
    match $cmd {
        "analyze" => { analyze-garbage | ignore }
        "collect" => { do-collect $dry_run $interactive $system }
        "generations" => { do-generations $dry_run $interactive $keep }
        "optimize" => { do-optimize $dry_run $interactive }
        "full" => { do-full $dry_run $interactive $keep }
        _ => {
            error $"Unknown command: ($cmd)"
            print "Use --help for usage information"
        }
    }
}
