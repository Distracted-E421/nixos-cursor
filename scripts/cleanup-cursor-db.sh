#!/usr/bin/env bash
#
# cleanup-cursor-db.sh - Clean up Cursor's bloated SQLite database
#
# WARNING: Close Cursor IDE before running this script!
#

set -euo pipefail

DB_PATH="$HOME/.config/Cursor/User/globalStorage/state.vscdb"
BACKUP_DIR="$HOME/.config/Cursor/User/globalStorage/backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Cursor is running
check_cursor_running() {
    if pgrep -f "cursor.*renderer" > /dev/null || pgrep -f "cursor.*extensionHost" > /dev/null; then
        log_error "Cursor IDE appears to be running!"
        log_error "Please close Cursor completely before running this script."
        exit 1
    fi
}

# Show current database stats
show_stats() {
    if [[ ! -f "$DB_PATH" ]]; then
        log_error "Database not found at $DB_PATH"
        exit 1
    fi

    local size=$(du -h "$DB_PATH" | cut -f1)
    log_info "Current database size: $size"

    # Get table sizes
    log_info "Table breakdown:"
    sqlite3 "$DB_PATH" "
    SELECT 
      '  ' || name || ': ' || ROUND(SUM(pgsize)/1024.0/1024.0, 2) || ' MB'
    FROM dbstat 
    GROUP BY name 
    ORDER BY SUM(pgsize) DESC 
    LIMIT 5;
    " 2>/dev/null || log_warn "Could not analyze database"

    # Get entry counts
    log_info "Entry counts:"
    sqlite3 "$DB_PATH" "
    SELECT '  bubbleId (conversations): ' || COUNT(*) FROM cursorDiskKV WHERE key LIKE 'bubbleId:%';
    " 2>/dev/null || true
    sqlite3 "$DB_PATH" "
    SELECT '  checkpointId (agent state): ' || COUNT(*) FROM cursorDiskKV WHERE key LIKE 'checkpointId:%';
    " 2>/dev/null || true
}

# Backup database
backup_db() {
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/state.vscdb.$(date +%Y%m%d_%H%M%S)"
    
    log_info "Creating backup..."
    cp "$DB_PATH" "$backup_file"
    log_success "Backup saved to: $backup_file"
}

# Clean checkpoints only (safest)
clean_checkpoints() {
    log_info "Removing agent checkpoints..."
    sqlite3 "$DB_PATH" "DELETE FROM cursorDiskKV WHERE key LIKE 'checkpointId:%';"
    local count=$(sqlite3 "$DB_PATH" "SELECT changes();")
    log_success "Removed $count checkpoint entries"
}

# Clean old conversations (keep recent)
clean_old_conversations() {
    local keep=${1:-500}
    log_info "Pruning old conversations (keeping last $keep)..."
    
    sqlite3 "$DB_PATH" "
    DELETE FROM cursorDiskKV 
    WHERE key LIKE 'bubbleId:%' 
    AND rowid NOT IN (
        SELECT rowid FROM cursorDiskKV 
        WHERE key LIKE 'bubbleId:%' 
        ORDER BY rowid DESC 
        LIMIT $keep
    );"
    
    local count=$(sqlite3 "$DB_PATH" "SELECT changes();")
    log_success "Removed $count old conversation entries"
}

# Vacuum database
vacuum_db() {
    log_info "Running VACUUM to reclaim space..."
    sqlite3 "$DB_PATH" "VACUUM;"
    log_success "VACUUM complete"
}

# Main cleanup
do_cleanup() {
    local mode="${1:-safe}"
    
    log_info "Starting cleanup (mode: $mode)..."
    
    case "$mode" in
        safe)
            # Just remove checkpoints
            clean_checkpoints
            ;;
        moderate)
            # Remove checkpoints and old conversations
            clean_checkpoints
            clean_old_conversations 500
            ;;
        aggressive)
            # Remove checkpoints and most conversations
            clean_checkpoints
            clean_old_conversations 100
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
    
    vacuum_db
}

# Show help
show_help() {
    cat << EOF
Cursor Database Cleanup Tool

Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    stats           Show current database statistics
    backup          Create a backup of the database
    clean           Clean the database (default: safe mode)
    
OPTIONS for 'clean':
    --safe          Remove only agent checkpoints (default)
    --moderate      Remove checkpoints + old conversations (keep 500)
    --aggressive    Remove checkpoints + most conversations (keep 100)

EXAMPLES:
    $0 stats                  # Show database stats
    $0 backup                 # Create backup only
    $0 clean --safe           # Safe cleanup (checkpoints only)
    $0 clean --moderate       # Moderate cleanup
    $0 clean --aggressive     # Aggressive cleanup

WARNING: Always close Cursor before running cleanup!
EOF
}

# Main
main() {
    case "${1:-help}" in
        stats)
            check_cursor_running
            show_stats
            ;;
        backup)
            check_cursor_running
            backup_db
            ;;
        clean)
            check_cursor_running
            show_stats
            echo ""
            
            local mode="safe"
            case "${2:-}" in
                --moderate) mode="moderate" ;;
                --aggressive) mode="aggressive" ;;
                --safe|"") mode="safe" ;;
                *) log_error "Unknown option: $2"; exit 1 ;;
            esac
            
            backup_db
            echo ""
            
            local before=$(du -b "$DB_PATH" | cut -f1)
            do_cleanup "$mode"
            local after=$(du -b "$DB_PATH" | cut -f1)
            
            echo ""
            local saved=$((before - after))
            local saved_mb=$((saved / 1024 / 1024))
            local saved_kb=$(((saved % (1024 * 1024)) / 1024))
            log_success "Cleanup complete!"
            log_success "Space saved: ${saved_mb}.${saved_kb} MB"
            echo ""
            show_stats
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

