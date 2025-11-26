#!/usr/bin/env bash
# Cursor Data Tracker
# Git-based tracking for Cursor user data with diff, blame, and rollback
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

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Configuration
TRACKING_DIR="${CURSOR_TRACKING_DIR:-$HOME/.cursor-data-tracking}"
CURSOR_HOME="${CURSOR_HOME:-$HOME/.cursor}"
CURSOR_CONFIG="${CURSOR_CONFIG:-$HOME/.config/Cursor}"

# Files to track (relative to their parent directories)
TRACKED_FILES=(
    "User/settings.json"
    "User/keybindings.json"
    "User/snippets"
)

TRACKED_CURSOR_FILES=(
    "mcp.json"
    "argv.json"
    "agents"
    "rules"
    "extensions"  # Track extension list, not content
)

# Files to exclude from tracking
GITIGNORE_CONTENT='
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

usage() {
    cat << 'EOF'
Usage: cursor-data-tracker.sh [COMMAND] [OPTIONS]

Git-based tracking for Cursor user data

Commands:
    init            Initialize tracking for a Cursor data directory
    snapshot        Take a snapshot (git commit) of current state
    status          Show uncommitted changes
    diff            Show changes between snapshots or versions
    history         Show snapshot history
    blame           Show who/what changed a specific file
    rollback        Rollback to a previous snapshot
    compare         Compare data between two Cursor instances
    export          Export tracked data to archive
    import          Import tracked data from archive
    list            List all tracked instances

Options:
    -h, --help          Show this help
    -v, --version VER   Specify Cursor version (e.g., 2.0.77)
    -m, --message MSG   Commit message for snapshot
    -n, --number N      Number of entries to show
    --all               Include all tracked instances

Examples:
    cursor-data-tracker.sh init                    # Init tracking for default Cursor
    cursor-data-tracker.sh init -v 2.0.77         # Init tracking for isolated version
    cursor-data-tracker.sh snapshot -m "Before 2.1.34 upgrade"
    cursor-data-tracker.sh diff HEAD~1            # Diff with previous snapshot
    cursor-data-tracker.sh compare 2.0.77 2.1.34  # Compare two versions
    cursor-data-tracker.sh rollback HEAD~1        # Rollback to previous state
    cursor-data-tracker.sh blame mcp.json         # See history of mcp.json
EOF
}

log_info() { echo -e "${CYAN}ℹ${NC}  $*"; }
log_success() { echo -e "${GREEN}✓${NC}  $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
log_error() { echo -e "${RED}✗${NC}  $*" >&2; }

get_instance_dir() {
    local version="${1:-default}"
    if [ "$version" = "default" ]; then
        echo "$TRACKING_DIR/default"
    else
        echo "$TRACKING_DIR/cursor-$version"
    fi
}

get_cursor_data_dir() {
    local version="${1:-default}"
    if [ "$version" = "default" ]; then
        echo "$HOME/.config/Cursor"
    else
        echo "$HOME/.cursor-$version"
    fi
}

init_tracking() {
    local version="${1:-default}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    local cursor_dir
    cursor_dir=$(get_cursor_data_dir "$version")
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            ${BOLD}Initialize Cursor Data Tracking${NC}${BLUE}                        ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_info "Instance: ${CYAN}$version${NC}"
    log_info "Cursor data: ${CYAN}$cursor_dir${NC}"
    log_info "Tracking dir: ${CYAN}$instance_dir${NC}"
    echo ""
    
    # Check if Cursor data exists
    if [ ! -d "$cursor_dir" ]; then
        log_error "Cursor data directory not found: $cursor_dir"
        return 1
    fi
    
    # Create tracking directory
    mkdir -p "$instance_dir"
    cd "$instance_dir"
    
    # Initialize git if not already
    if [ ! -d .git ]; then
        git init --quiet
        log_success "Git repository initialized"
    else
        log_info "Git repository already exists"
    fi
    
    # Create .gitignore
    echo "$GITIGNORE_CONTENT" > .gitignore
    log_success "Created .gitignore"
    
    # Create metadata file
    cat > .cursor-tracking.json << EOF
{
    "version": "$version",
    "cursor_dir": "$cursor_dir",
    "cursor_home": "$CURSOR_HOME",
    "created": "$(date -Iseconds)",
    "updated": "$(date -Iseconds)"
}
EOF
    log_success "Created metadata file"
    
    # Copy trackable files
    sync_from_cursor "$version"
    
    # Initial commit
    git add -A
    if git diff --cached --quiet; then
        log_info "No files to commit"
    else
        git commit -m "Initial tracking snapshot for Cursor $version" --quiet
        log_success "Created initial snapshot"
    fi
    
    echo ""
    log_success "Tracking initialized for Cursor $version"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  - Take snapshots: ${CYAN}cursor-data-tracker.sh snapshot -v $version${NC}"
    echo "  - View history:   ${CYAN}cursor-data-tracker.sh history -v $version${NC}"
    echo "  - Compare changes: ${CYAN}cursor-data-tracker.sh diff -v $version${NC}"
}

sync_from_cursor() {
    local version="${1:-default}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    local cursor_dir
    cursor_dir=$(get_cursor_data_dir "$version")
    
    mkdir -p "$instance_dir"
    cd "$instance_dir"
    
    # Sync User settings
    if [ -d "$cursor_dir/User" ]; then
        mkdir -p User
        for file in settings.json keybindings.json; do
            if [ -f "$cursor_dir/User/$file" ]; then
                cp "$cursor_dir/User/$file" "User/$file"
            fi
        done
        # Sync snippets directory
        if [ -d "$cursor_dir/User/snippets" ]; then
            cp -r "$cursor_dir/User/snippets" User/
        fi
    fi
    
    # Sync .cursor files
    mkdir -p cursor-home
    for item in "${TRACKED_CURSOR_FILES[@]}"; do
        if [ -e "$CURSOR_HOME/$item" ]; then
            if [ -d "$CURSOR_HOME/$item" ]; then
                # For directories, only copy if they contain trackable files
                case "$item" in
                    agents|rules)
                        cp -r "$CURSOR_HOME/$item" "cursor-home/"
                        ;;
                    extensions)
                        # Just list extensions, don't copy content
                        ls -1 "$CURSOR_HOME/$item" 2>/dev/null > "cursor-home/extensions.txt" || true
                        ;;
                esac
            else
                cp "$CURSOR_HOME/$item" "cursor-home/"
            fi
        fi
    done
    
    # Create file manifest
    create_manifest "$version"
}

sync_to_cursor() {
    local version="${1:-default}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    local cursor_dir
    cursor_dir=$(get_cursor_data_dir "$version")
    
    cd "$instance_dir"
    
    # Sync User settings back
    if [ -d "User" ] && [ -d "$cursor_dir/User" ]; then
        for file in settings.json keybindings.json; do
            if [ -f "User/$file" ]; then
                cp "User/$file" "$cursor_dir/User/$file"
            fi
        done
        if [ -d "User/snippets" ]; then
            cp -r "User/snippets" "$cursor_dir/User/"
        fi
    fi
    
    # Sync .cursor files back
    if [ -d "cursor-home" ]; then
        for item in mcp.json argv.json; do
            if [ -f "cursor-home/$item" ]; then
                cp "cursor-home/$item" "$CURSOR_HOME/"
            fi
        done
        for dir in agents rules; do
            if [ -d "cursor-home/$dir" ]; then
                cp -r "cursor-home/$dir" "$CURSOR_HOME/"
            fi
        done
    fi
}

create_manifest() {
    local version="${1:-default}"
    local cursor_dir
    cursor_dir=$(get_cursor_data_dir "$version")
    
    cat > manifest.json << EOF
{
    "generated": "$(date -Iseconds)",
    "version": "$version",
    "files": {
        "settings": $([ -f "$cursor_dir/User/settings.json" ] && echo "true" || echo "false"),
        "keybindings": $([ -f "$cursor_dir/User/keybindings.json" ] && echo "true" || echo "false"),
        "mcp": $([ -f "$CURSOR_HOME/mcp.json" ] && echo "true" || echo "false"),
        "agents": $([ -d "$CURSOR_HOME/agents" ] && echo "true" || echo "false"),
        "rules": $([ -d "$CURSOR_HOME/rules" ] && echo "true" || echo "false")
    },
    "sizes": {
        "user_data": "$(du -sh "$cursor_dir" 2>/dev/null | cut -f1 || echo "N/A")",
        "cursor_home": "$(du -sh "$CURSOR_HOME" 2>/dev/null | cut -f1 || echo "N/A")"
    }
}
EOF
}

take_snapshot() {
    local version="${1:-default}"
    local message="${2:-Snapshot at $(date -Iseconds)}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    
    if [ ! -d "$instance_dir/.git" ]; then
        log_error "Tracking not initialized for $version. Run: cursor-data-tracker.sh init -v $version"
        return 1
    fi
    
    cd "$instance_dir"
    
    echo -e "${CYAN}Taking snapshot for Cursor $version...${NC}"
    
    # Sync latest data
    sync_from_cursor "$version"
    
    # Update metadata
    jq ".updated = \"$(date -Iseconds)\"" .cursor-tracking.json > .cursor-tracking.json.tmp
    mv .cursor-tracking.json.tmp .cursor-tracking.json
    
    # Stage and commit
    git add -A
    
    if git diff --cached --quiet; then
        log_info "No changes to snapshot"
        return 0
    fi
    
    # Show what's changed
    echo ""
    echo -e "${BOLD}Changes:${NC}"
    git diff --cached --stat
    echo ""
    
    git commit -m "$message" --quiet
    
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD)
    log_success "Snapshot created: ${GREEN}$commit_hash${NC} - $message"
}

show_status() {
    local version="${1:-default}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    
    if [ ! -d "$instance_dir/.git" ]; then
        log_error "Tracking not initialized for $version"
        return 1
    fi
    
    cd "$instance_dir"
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}Cursor Data Status: $version${NC}${BLUE}                          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Sync to check for changes
    sync_from_cursor "$version"
    
    # Show status
    local changes
    changes=$(git status --porcelain)
    
    if [ -z "$changes" ]; then
        log_success "No uncommitted changes"
    else
        echo -e "${YELLOW}Uncommitted changes:${NC}"
        echo ""
        git status --short
        echo ""
        echo -e "Run ${CYAN}cursor-data-tracker.sh snapshot -v $version${NC} to save these changes"
    fi
    
    echo ""
    echo -e "${BOLD}Last snapshot:${NC}"
    git log -1 --format="  %h - %s (%cr)" 2>/dev/null || echo "  (none)"
    
    echo ""
    echo -e "${BOLD}Total snapshots:${NC} $(git rev-list --count HEAD 2>/dev/null || echo 0)"
}

show_diff() {
    local version="${1:-default}"
    local ref="${2:-HEAD~1}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    
    if [ ! -d "$instance_dir/.git" ]; then
        log_error "Tracking not initialized for $version"
        return 1
    fi
    
    cd "$instance_dir"
    
    # Sync to include current changes
    sync_from_cursor "$version"
    git add -A  # Stage for comparison
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}Changes since $ref${NC}${BLUE}                                    ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Summary
    echo -e "${BOLD}Files changed:${NC}"
    git diff --cached --stat "$ref" 2>/dev/null || git diff --stat "$ref" 2>/dev/null
    echo ""
    
    # Detailed diff
    echo -e "${BOLD}Detailed changes:${NC}"
    git diff --cached "$ref" 2>/dev/null || git diff "$ref" 2>/dev/null
}

show_history() {
    local version="${1:-default}"
    local count="${2:-20}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    
    if [ ! -d "$instance_dir/.git" ]; then
        log_error "Tracking not initialized for $version"
        return 1
    fi
    
    cd "$instance_dir"
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}Snapshot History: $version${NC}${BLUE}                            ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    git log --oneline --decorate -n "$count" --format="  ${GREEN}%h${NC} %s ${DIM}(%cr)${NC}"
}

show_blame() {
    local version="${1:-default}"
    local file="$2"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    
    if [ ! -d "$instance_dir/.git" ]; then
        log_error "Tracking not initialized for $version"
        return 1
    fi
    
    if [ -z "$file" ]; then
        log_error "File path required"
        echo "Usage: cursor-data-tracker.sh blame -v $version <file>"
        echo ""
        echo "Tracked files:"
        cd "$instance_dir"
        find . -type f -not -path './.git/*' | sed 's|^\./||'
        return 1
    fi
    
    cd "$instance_dir"
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}File History: $file${NC}${BLUE}                                   ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    echo -e "${BOLD}Change history:${NC}"
    git log --oneline --follow -- "$file" | head -20
    echo ""
    
    echo -e "${BOLD}Line-by-line blame:${NC}"
    git blame "$file" 2>/dev/null || echo "  (file has no history yet)"
}

do_rollback() {
    local version="${1:-default}"
    local ref="${2:-HEAD~1}"
    local instance_dir
    instance_dir=$(get_instance_dir "$version")
    
    if [ ! -d "$instance_dir/.git" ]; then
        log_error "Tracking not initialized for $version"
        return 1
    fi
    
    cd "$instance_dir"
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}Rollback to $ref${NC}${BLUE}                                      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show what we're rolling back to
    echo -e "${BOLD}Rolling back to:${NC}"
    git log -1 --format="  %h - %s (%cr)" "$ref"
    echo ""
    
    # Show what will change
    echo -e "${BOLD}Changes that will be reverted:${NC}"
    git diff --stat "$ref" HEAD
    echo ""
    
    echo -en "${YELLOW}Proceed with rollback? [y/N]: ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            # Take a backup snapshot first
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "Auto-backup before rollback to $ref" --quiet
                log_success "Backup snapshot created"
            fi
            
            # Checkout the old state
            git checkout "$ref" -- .
            
            # Sync back to Cursor
            sync_to_cursor "$version"
            
            # Commit the rollback
            git add -A
            git commit -m "Rollback to $ref" --quiet
            
            log_success "Rolled back to $ref"
            echo ""
            echo -e "${YELLOW}Note: Restart Cursor to apply changes${NC}"
            ;;
        *)
            echo "Cancelled."
            ;;
    esac
}

compare_instances() {
    local version1="${1:-}"
    local version2="${2:-}"
    
    if [ -z "$version1" ] || [ -z "$version2" ]; then
        log_error "Two versions required"
        echo "Usage: cursor-data-tracker.sh compare <version1> <version2>"
        return 1
    fi
    
    local dir1
    dir1=$(get_instance_dir "$version1")
    local dir2
    dir2=$(get_instance_dir "$version2")
    
    if [ ! -d "$dir1/.git" ]; then
        log_error "Tracking not initialized for $version1"
        return 1
    fi
    
    if [ ! -d "$dir2/.git" ]; then
        log_error "Tracking not initialized for $version2"
        return 1
    fi
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      ${BOLD}Comparing $version1 ↔ $version2${NC}${BLUE}                               ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Sync both to latest
    sync_from_cursor "$version1"
    sync_from_cursor "$version2"
    
    # Compare common files
    echo -e "${BOLD}Settings comparison:${NC}"
    diff -u "$dir1/User/settings.json" "$dir2/User/settings.json" 2>/dev/null || echo "  (files differ or missing)"
    echo ""
    
    echo -e "${BOLD}MCP configuration comparison:${NC}"
    diff -u "$dir1/cursor-home/mcp.json" "$dir2/cursor-home/mcp.json" 2>/dev/null || echo "  (files differ or missing)"
    echo ""
    
    echo -e "${BOLD}Full directory comparison:${NC}"
    diff -rq "$dir1" "$dir2" --exclude='.git' 2>/dev/null | head -20
}

list_instances() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}Tracked Cursor Instances${NC}${BLUE}                             ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ! -d "$TRACKING_DIR" ]; then
        log_info "No tracked instances yet"
        echo ""
        echo "Initialize tracking with: ${CYAN}cursor-data-tracker.sh init${NC}"
        return 0
    fi
    
    for dir in "$TRACKING_DIR"/*/; do
        if [ -d "$dir/.git" ]; then
            local name
            name=$(basename "$dir")
            local snapshots
            snapshots=$(cd "$dir" && git rev-list --count HEAD 2>/dev/null || echo 0)
            local last_update
            last_update=$(cd "$dir" && git log -1 --format="%cr" 2>/dev/null || echo "never")
            
            echo -e "  ${GREEN}●${NC} ${BOLD}$name${NC}"
            echo -e "      Snapshots: $snapshots"
            echo -e "      Last update: $last_update"
            echo ""
        fi
    done
}

# Parse arguments
VERSION="default"
MESSAGE=""
COUNT=20
COMMAND=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -m|--message)
            MESSAGE="$2"
            shift 2
            ;;
        -n|--number)
            COUNT="$2"
            shift 2
            ;;
        init|snapshot|status|diff|history|blame|rollback|compare|export|import|list)
            COMMAND="$1"
            shift
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# Default command
[ -z "$COMMAND" ] && COMMAND="status"

# Execute command
case "$COMMAND" in
    init)
        init_tracking "$VERSION"
        ;;
    snapshot)
        take_snapshot "$VERSION" "${MESSAGE:-Snapshot at $(date -Iseconds)}"
        ;;
    status)
        show_status "$VERSION"
        ;;
    diff)
        show_diff "$VERSION" "${EXTRA_ARGS[0]:-HEAD~1}"
        ;;
    history)
        show_history "$VERSION" "$COUNT"
        ;;
    blame)
        show_blame "$VERSION" "${EXTRA_ARGS[0]:-}"
        ;;
    rollback)
        do_rollback "$VERSION" "${EXTRA_ARGS[0]:-HEAD~1}"
        ;;
    compare)
        compare_instances "${EXTRA_ARGS[0]:-}" "${EXTRA_ARGS[1]:-}"
        ;;
    list)
        list_instances
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
