#!/usr/bin/env nu

# Script: cursor-data-tracker.nu
# Purpose: Git-based tracking for Cursor user data with diff, blame, and rollback
# Usage: nu cursor-data-tracker.nu [command] [options]
#
# Replaces: scripts/data-tracking/cursor-data-tracker.sh
#
# Tracks:
#   - Settings (settings.json, keybindings.json)
#   - MCP configuration (mcp.json)
#   - Custom agents and rules (.cursor/agents/, .cursor/rules/)
#   - Extension settings
#   - Workspace configurations
#
# Excludes (too large/binary):
#   - state.vscdb (SQLite database, 100s of MB)
#   - Cache directories
#   - Blob storage

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

const VERSION = "2.0.0"

# Default directories
def get-tracking-dir [] {
    $env.CURSOR_TRACKING_DIR? | default $"($env.HOME)/.cursor-data-tracking"
}

def get-cursor-home [] {
    $env.CURSOR_HOME? | default $"($env.HOME)/.cursor"
}

def get-cursor-config [] {
    $env.CURSOR_CONFIG? | default $"($env.HOME)/.config/Cursor"
}

# Files to track
const TRACKED_USER_FILES = [
    "User/settings.json"
    "User/keybindings.json"
    "User/snippets"
]

const TRACKED_CURSOR_FILES = [
    "mcp.json"
    "argv.json"
    "agents"
    "rules"
]

# Git ignore content
const GITIGNORE_CONTENT = '
# Large binary files
*.vscdb
*.db
*.db-journal
*.db-shm
*.db-wal

# Cache directories
Cache/
CachedData/
CachedProfilesData/
Code Cache/
DawnGraphiteCache/
DawnWebGPUCache/
GPUCache/

# Temporary/runtime files
blob_storage/
Crashpad/
logs/
*.log
*.tmp
Cookies
Cookies-journal

# Extension data (track list separately)
extensions/*/
globalStorage/*/

# Workspace-specific (handled separately)
workspaceStorage/

# Backups (we make our own)
Backups/
*.backup

# OS files
.DS_Store
Thumbs.db
'

# ─────────────────────────────────────────────────────────────────────────────
# HELPER FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

def header [title: string] {
    print $"(ansi blue)╔═══════════════════════════════════════════════════════════════════╗(ansi reset)"
    print $"(ansi blue)║     (ansi white_bold)($title)(ansi reset)(ansi blue)(ansi reset)"
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

# Get instance directory for a version
def get-instance-dir [version: string]: nothing -> string {
    let tracking_dir = (get-tracking-dir)
    if $version == "default" {
        $"($tracking_dir)/default"
    } else {
        $"($tracking_dir)/cursor-($version)"
    }
}

# Get Cursor data directory for a version
def get-cursor-data-dir [version: string]: nothing -> string {
    if $version == "default" {
        get-cursor-config
    } else {
        $"($env.HOME)/.cursor-($version)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SYNC FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Sync data FROM Cursor to tracking directory
def sync-from-cursor [version: string] {
    let instance_dir = (get-instance-dir $version)
    let cursor_dir = (get-cursor-data-dir $version)
    let cursor_home = (get-cursor-home)
    
    mkdir $instance_dir
    cd $instance_dir
    
    # Sync User settings
    let user_dir = $"($cursor_dir)/User"
    if ($user_dir | path exists) {
        mkdir User
        for file in ["settings.json" "keybindings.json"] {
            let src = $"($user_dir)/($file)"
            if ($src | path exists) {
                cp $src $"User/($file)"
            }
        }
        # Sync snippets
        let snippets_dir = $"($user_dir)/snippets"
        if ($snippets_dir | path exists) {
            cp -r $snippets_dir User/
        }
    }
    
    # Sync .cursor files
    mkdir cursor-home
    for item in $TRACKED_CURSOR_FILES {
        let src = $"($cursor_home)/($item)"
        if ($src | path exists) {
            if ($src | path type) == "dir" {
                cp -r $src cursor-home/
            } else {
                cp $src $"cursor-home/($item)"
            }
        }
    }
    
    # Create extension list (not full content)
    let ext_dir = $"($cursor_home)/extensions"
    if ($ext_dir | path exists) {
        ls $ext_dir | get name | each { |p| $p | path basename } | str join "\n" | save -f cursor-home/extensions.txt
    }
    
    # Create manifest
    create-manifest $version
}

# Sync data TO Cursor from tracking directory
def sync-to-cursor [version: string] {
    let instance_dir = (get-instance-dir $version)
    let cursor_dir = (get-cursor-data-dir $version)
    let cursor_home = (get-cursor-home)
    
    cd $instance_dir
    
    # Sync User settings back
    let user_tracked = $"($instance_dir)/User"
    let user_cursor = $"($cursor_dir)/User"
    if ($user_tracked | path exists) and ($user_cursor | path exists) {
        for file in ["settings.json" "keybindings.json"] {
            let src = $"($user_tracked)/($file)"
            if ($src | path exists) {
                cp $src $"($user_cursor)/($file)"
            }
        }
        let snippets = $"($user_tracked)/snippets"
        if ($snippets | path exists) {
            cp -r $snippets $user_cursor
        }
    }
    
    # Sync .cursor files back
    let ch_tracked = $"($instance_dir)/cursor-home"
    if ($ch_tracked | path exists) {
        for item in ["mcp.json" "argv.json"] {
            let src = $"($ch_tracked)/($item)"
            if ($src | path exists) {
                cp $src $"($cursor_home)/($item)"
            }
        }
        for dir in ["agents" "rules"] {
            let src = $"($ch_tracked)/($dir)"
            if ($src | path exists) {
                cp -r $src $cursor_home
            }
        }
    }
}

# Create manifest file
def create-manifest [version: string] {
    let cursor_dir = (get-cursor-data-dir $version)
    let cursor_home = (get-cursor-home)
    let timestamp = (date now | format date "%Y-%m-%dT%H:%M:%S%z")
    
    let user_size = if ($cursor_dir | path exists) {
        (du $cursor_dir | first | get apparent | into string)
    } else { "N/A" }
    
    let home_size = if ($cursor_home | path exists) {
        (du $cursor_home | first | get apparent | into string)
    } else { "N/A" }
    
    {
        generated: $timestamp
        version: $version
        files: {
            settings: ($"($cursor_dir)/User/settings.json" | path exists)
            keybindings: ($"($cursor_dir)/User/keybindings.json" | path exists)
            mcp: ($"($cursor_home)/mcp.json" | path exists)
            agents: ($"($cursor_home)/agents" | path exists)
            rules: ($"($cursor_home)/rules" | path exists)
        }
        sizes: {
            user_data: $user_size
            cursor_home: $home_size
        }
    } | to json | save -f manifest.json
}

# ─────────────────────────────────────────────────────────────────────────────
# COMMANDS
# ─────────────────────────────────────────────────────────────────────────────

# Initialize tracking for a Cursor instance
def do-init [version: string] {
    let instance_dir = (get-instance-dir $version)
    let cursor_dir = (get-cursor-data-dir $version)
    
    header "Initialize Cursor Data Tracking"
    
    info $"Instance: (ansi cyan)($version)(ansi reset)"
    info $"Cursor data: (ansi cyan)($cursor_dir)(ansi reset)"
    info $"Tracking dir: (ansi cyan)($instance_dir)(ansi reset)"
    print ""
    
    # Check if Cursor data exists
    if not ($cursor_dir | path exists) {
        error $"Cursor data directory not found: ($cursor_dir)"
        return
    }
    
    # Create tracking directory
    mkdir $instance_dir
    cd $instance_dir
    
    # Initialize git if not already
    if not ($"($instance_dir)/.git" | path exists) {
        ^git init --quiet
        success "Git repository initialized"
    } else {
        info "Git repository already exists"
    }
    
    # Create .gitignore
    $GITIGNORE_CONTENT | save -f .gitignore
    success "Created .gitignore"
    
    # Create metadata
    let timestamp = (date now | format date "%Y-%m-%dT%H:%M:%S%z")
    {
        version: $version
        cursor_dir: $cursor_dir
        cursor_home: (get-cursor-home)
        created: $timestamp
        updated: $timestamp
    } | to json | save -f .cursor-tracking.json
    success "Created metadata file"
    
    # Copy trackable files
    sync-from-cursor $version
    
    # Initial commit
    ^git add -A
    let diff_result = (do { ^git diff --cached --quiet } | complete)
    if $diff_result.exit_code == 0 {
        info "No files to commit"
    } else {
        ^git commit -m $"Initial tracking snapshot for Cursor ($version)" --quiet
        success "Created initial snapshot"
    }
    
    print ""
    success $"Tracking initialized for Cursor ($version)"
    print ""
    print $"(ansi white_bold)Next steps:(ansi reset)"
    print $"  - Take snapshots: (ansi cyan)nu cursor-data-tracker.nu snapshot -v ($version)(ansi reset)"
    print $"  - View history:   (ansi cyan)nu cursor-data-tracker.nu history -v ($version)(ansi reset)"
    print $"  - Compare changes: (ansi cyan)nu cursor-data-tracker.nu diff -v ($version)(ansi reset)"
}

# Take a snapshot (git commit)
def do-snapshot [version: string, message: string] {
    let instance_dir = (get-instance-dir $version)
    
    if not ($"($instance_dir)/.git" | path exists) {
        error $"Tracking not initialized for ($version). Run: nu cursor-data-tracker.nu init -v ($version)"
        return
    }
    
    cd $instance_dir
    
    print $"(ansi cyan)Taking snapshot for Cursor ($version)...(ansi reset)"
    
    # Sync latest data
    sync-from-cursor $version
    
    # Update metadata timestamp
    let meta = (open .cursor-tracking.json)
    let timestamp = (date now | format date "%Y-%m-%dT%H:%M:%S%z")
    $meta | upsert updated $timestamp | to json | save -f .cursor-tracking.json
    
    # Stage all changes
    ^git add -A
    
    let diff_result = (do { ^git diff --cached --quiet } | complete)
    if $diff_result.exit_code == 0 {
        info "No changes to snapshot"
        return
    }
    
    # Show what's changed
    print ""
    print $"(ansi white_bold)Changes:(ansi reset)"
    ^git diff --cached --stat
    print ""
    
    ^git commit -m $message --quiet
    
    let commit_hash = (^git rev-parse --short HEAD | str trim)
    success $"Snapshot created: (ansi green)($commit_hash)(ansi reset) - ($message)"
}

# Show current status
def do-status [version: string] {
    let instance_dir = (get-instance-dir $version)
    
    if not ($"($instance_dir)/.git" | path exists) {
        error $"Tracking not initialized for ($version)"
        return
    }
    
    cd $instance_dir
    
    header $"Cursor Data Status: ($version)"
    
    # Sync to check for changes
    sync-from-cursor $version
    
    let changes = (^git status --porcelain | str trim)
    
    if ($changes | is-empty) {
        success "No uncommitted changes"
    } else {
        print $"(ansi yellow)Uncommitted changes:(ansi reset)"
        print ""
        ^git status --short
        print ""
        print $"Run (ansi cyan)nu cursor-data-tracker.nu snapshot -v ($version)(ansi reset) to save these changes"
    }
    
    print ""
    print $"(ansi white_bold)Last snapshot:(ansi reset)"
    let log_result = (do { ^git log -1 --format="%h - %s (%cr)" } | complete)
    if $log_result.exit_code == 0 {
        print $"  ($log_result.stdout | str trim)"
    } else {
        print "  (none)"
    }
    
    print ""
    let count = (do { ^git rev-list --count HEAD } | complete)
    let snapshot_count = if $count.exit_code == 0 { $count.stdout | str trim } else { "0" }
    print $"(ansi white_bold)Total snapshots:(ansi reset) ($snapshot_count)"
}

# Show diff between commits
def do-diff [version: string, ref: string] {
    let instance_dir = (get-instance-dir $version)
    
    if not ($"($instance_dir)/.git" | path exists) {
        error $"Tracking not initialized for ($version)"
        return
    }
    
    cd $instance_dir
    
    # Sync to include current changes
    sync-from-cursor $version
    ^git add -A
    
    header $"Changes since ($ref)"
    
    print $"(ansi white_bold)Files changed:(ansi reset)"
    ^git diff --cached --stat $ref
    print ""
    
    print $"(ansi white_bold)Detailed changes:(ansi reset)"
    ^git diff --cached $ref
}

# Show snapshot history
def do-history [version: string, count: int] {
    let instance_dir = (get-instance-dir $version)
    
    if not ($"($instance_dir)/.git" | path exists) {
        error $"Tracking not initialized for ($version)"
        return
    }
    
    cd $instance_dir
    
    header $"Snapshot History: ($version)"
    
    ^git log --oneline --decorate -n $count --format="  %C(green)%h%C(reset) %s %C(dim)(%cr)%C(reset)"
}

# Show blame for a file
def do-blame [version: string, file: string] {
    let instance_dir = (get-instance-dir $version)
    
    if not ($"($instance_dir)/.git" | path exists) {
        error $"Tracking not initialized for ($version)"
        return
    }
    
    cd $instance_dir
    
    if ($file | is-empty) {
        error "File path required"
        print $"Usage: nu cursor-data-tracker.nu blame -v ($version) <file>"
        print ""
        print "Tracked files:"
        glob **/* --exclude [.git/**] | each { |p| 
            if ($p | path type) == "file" {
                print $"  ($p)"
            }
        }
        return
    }
    
    header $"File History: ($file)"
    
    if not ($file | path exists) {
        error $"File not found: ($file)"
        return
    }
    
    print $"(ansi white_bold)Change history:(ansi reset)"
    ^git log --oneline --follow -- $file | lines | first 20 | each { |l| print $"  ($l)" }
    print ""
    
    print $"(ansi white_bold)Line-by-line blame:(ansi reset)"
    let blame_result = (do { ^git blame $file } | complete)
    if $blame_result.exit_code == 0 {
        print $blame_result.stdout
    } else {
        print "  (file has no history yet)"
    }
}

# Rollback to a previous snapshot
def do-rollback [version: string, ref: string] {
    let instance_dir = (get-instance-dir $version)
    
    if not ($"($instance_dir)/.git" | path exists) {
        error $"Tracking not initialized for ($version)"
        return
    }
    
    cd $instance_dir
    
    header $"Rollback to ($ref)"
    
    print $"(ansi white_bold)Rolling back to:(ansi reset)"
    ^git log -1 --format="  %h - %s (%cr)" $ref
    print ""
    
    print $"(ansi white_bold)Changes that will be reverted:(ansi reset)"
    ^git diff --stat $ref HEAD
    print ""
    
    if (confirm "Proceed with rollback?") {
        # Take backup first
        ^git add -A
        let diff_result = (do { ^git diff --cached --quiet } | complete)
        if $diff_result.exit_code != 0 {
            ^git commit -m $"Auto-backup before rollback to ($ref)" --quiet
            success "Backup snapshot created"
        }
        
        # Checkout old state
        ^git checkout $ref -- .
        
        # Sync back to Cursor
        sync-to-cursor $version
        
        # Commit rollback
        ^git add -A
        ^git commit -m $"Rollback to ($ref)" --quiet
        
        success $"Rolled back to ($ref)"
        print ""
        warn "Note: Restart Cursor to apply changes"
    } else {
        print "Cancelled."
    }
}

# List all tracked instances
def do-list [] {
    header "Tracked Cursor Instances"
    
    let tracking_dir = (get-tracking-dir)
    
    if not ($tracking_dir | path exists) {
        info "No tracked instances yet"
        print ""
        print $"Initialize tracking with: (ansi cyan)nu cursor-data-tracker.nu init(ansi reset)"
        return
    }
    
    ls $tracking_dir | where type == dir | each { |dir|
        let git_dir = $"($dir.name)/.git"
        if ($git_dir | path exists) {
            let name = ($dir.name | path basename)
            let count_result = (do { cd $dir.name; ^git rev-list --count HEAD } | complete)
            let snapshots = if $count_result.exit_code == 0 { $count_result.stdout | str trim } else { "0" }
            let log_result = (do { cd $dir.name; ^git log -1 --format="%cr" } | complete)
            let last_update = if $log_result.exit_code == 0 { $log_result.stdout | str trim } else { "never" }
            
            print $"  (ansi green)●(ansi reset) (ansi white_bold)($name)(ansi reset)"
            print $"      Snapshots: ($snapshots)"
            print $"      Last update: ($last_update)"
            print ""
        }
    }
}

# Compare two instances
def do-compare [version1: string, version2: string] {
    if ($version1 | is-empty) or ($version2 | is-empty) {
        error "Two versions required"
        print "Usage: nu cursor-data-tracker.nu compare <version1> <version2>"
        return
    }
    
    let dir1 = (get-instance-dir $version1)
    let dir2 = (get-instance-dir $version2)
    
    if not ($"($dir1)/.git" | path exists) {
        error $"Tracking not initialized for ($version1)"
        return
    }
    
    if not ($"($dir2)/.git" | path exists) {
        error $"Tracking not initialized for ($version2)"
        return
    }
    
    header $"Comparing ($version1) ↔ ($version2)"
    
    # Sync both to latest
    sync-from-cursor $version1
    sync-from-cursor $version2
    
    # Compare settings
    print $"(ansi white_bold)Settings comparison:(ansi reset)"
    let settings1 = $"($dir1)/User/settings.json"
    let settings2 = $"($dir2)/User/settings.json"
    if ($settings1 | path exists) and ($settings2 | path exists) {
        let diff_result = (do { diff -u $settings1 $settings2 } | complete)
        if ($diff_result.stdout | is-empty) {
            print "  (identical)"
        } else {
            print $diff_result.stdout
        }
    } else {
        print "  (one or both files missing)"
    }
    print ""
    
    # Compare MCP config
    print $"(ansi white_bold)MCP configuration comparison:(ansi reset)"
    let mcp1 = $"($dir1)/cursor-home/mcp.json"
    let mcp2 = $"($dir2)/cursor-home/mcp.json"
    if ($mcp1 | path exists) and ($mcp2 | path exists) {
        let diff_result = (do { diff -u $mcp1 $mcp2 } | complete)
        if ($diff_result.stdout | is-empty) {
            print "  (identical)"
        } else {
            print $diff_result.stdout
        }
    } else {
        print "  (one or both files missing)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────

def main [
    command?: string = "status"      # Command: init, snapshot, status, diff, history, blame, rollback, compare, list
    --version (-v): string = "default"  # Cursor version (e.g., 2.0.77)
    --message (-m): string = ""      # Commit message for snapshot
    --number (-n): int = 20          # Number of entries to show
    ref?: string = ""                # Reference for diff/rollback (e.g., HEAD~1)
    file?: string = ""               # File for blame command
    version2?: string = ""           # Second version for compare
    --help (-h)                      # Show help
] {
    if $help {
        print "
Usage: nu cursor-data-tracker.nu [COMMAND] [OPTIONS]

Git-based tracking for Cursor user data

Commands:
    init            Initialize tracking for a Cursor data directory
    snapshot        Take a snapshot (git commit) of current state
    status          Show uncommitted changes (default)
    diff [REF]      Show changes between snapshots or versions
    history         Show snapshot history
    blame <FILE>    Show who/what changed a specific file
    rollback [REF]  Rollback to a previous snapshot
    compare V1 V2   Compare data between two Cursor instances
    list            List all tracked instances

Options:
    -h, --help              Show this help
    -v, --version VER       Specify Cursor version (e.g., 2.0.77)
    -m, --message MSG       Commit message for snapshot
    -n, --number N          Number of entries to show

Examples:
    nu cursor-data-tracker.nu init                    # Init tracking for default Cursor
    nu cursor-data-tracker.nu init -v 2.0.77         # Init tracking for isolated version
    nu cursor-data-tracker.nu snapshot -m \"Before 2.1.34 upgrade\"
    nu cursor-data-tracker.nu diff HEAD~1            # Diff with previous snapshot
    nu cursor-data-tracker.nu compare 2.0.77 2.1.34  # Compare two versions
    nu cursor-data-tracker.nu rollback HEAD~1        # Rollback to previous state
    nu cursor-data-tracker.nu blame User/settings.json  # See history of settings
"
        return
    }
    
    let msg = if ($message | is-empty) {
        let timestamp = (date now | format date "%Y-%m-%dT%H:%M:%S")
        $"Snapshot at ($timestamp)"
    } else {
        $message
    }
    
    let reference = if ($ref | is-empty) { "HEAD~1" } else { $ref }
    
    match $command {
        "init" => { do-init $version }
        "snapshot" => { do-snapshot $version $msg }
        "status" => { do-status $version }
        "diff" => { do-diff $version $reference }
        "history" => { do-history $version $number }
        "blame" => { do-blame $version $file }
        "rollback" => { do-rollback $version $reference }
        "compare" => { do-compare $ref $version2 }
        "list" => { do-list }
        _ => {
            error $"Unknown command: ($command)"
            print "Use --help for usage information"
        }
    }
}
