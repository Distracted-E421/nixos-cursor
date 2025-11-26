#!/usr/bin/env bash
# Cursor Garbage Collection Helper
# Safe, interactive garbage collection for Cursor-related Nix store entries

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
DRY_RUN="${DRY_RUN:-true}"
KEEP_GENERATIONS="${KEEP_GENERATIONS:-5}"
KEEP_DAYS="${KEEP_DAYS:-7}"
INTERACTIVE="${INTERACTIVE:-true}"
SYSTEM_GC="${SYSTEM_GC:-false}"

usage() {
    cat << 'EOF'
Usage: gc-helper.sh [OPTIONS] [COMMAND]

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
    -n, --dry-run           Show what would be done without doing it (default)
    --no-dry-run            Actually perform the operations
    --keep-generations N    Keep last N generations (default: 5)
    --keep-days N           Keep generations from last N days (default: 7)
    --system                Also clean system generations (requires sudo)

Examples:
    gc-helper.sh                           # Analyze (dry-run)
    gc-helper.sh collect --no-dry-run      # Actually collect garbage
    gc-helper.sh generations --keep-generations 3  # Keep only last 3
    gc-helper.sh full --no-dry-run -y      # Full cleanup, no prompts

Safety Features:
    - Dry-run by default (use --no-dry-run to actually clean)
    - Preserves recent generations
    - Shows space that will be freed
    - Confirmation prompts (use -y to skip)
EOF
}

format_size() {
    numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

confirm() {
    local prompt="$1"
    if [ "$INTERACTIVE" = false ]; then
        return 0
    fi
    
    echo -en "${YELLOW}$prompt [y/N]: ${NC}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              ${BOLD}Cursor Garbage Collection Helper${NC}${BLUE}                     ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}⚠ DRY RUN MODE - No changes will be made${NC}"
        echo -e "${YELLOW}  Use --no-dry-run to actually perform cleanup${NC}"
        echo ""
    fi
}

analyze_garbage() {
    echo -e "${CYAN}Analyzing garbage...${NC}"
    echo ""
    
    # Check dead paths
    local dead_paths dead_count dead_size
    dead_paths=$(nix-store --gc --print-dead 2>/dev/null || true)
    dead_count=$(echo "$dead_paths" | grep -c "^/nix/store" || echo 0)
    
    if [ "$dead_count" -gt 0 ]; then
        # Calculate size of dead paths
        dead_size=0
        while IFS= read -r path; do
            if [ -e "$path" ]; then
                local path_size
                path_size=$(du -sb "$path" 2>/dev/null | cut -f1 || echo 0)
                dead_size=$((dead_size + path_size))
            fi
        done <<< "$dead_paths"
        
        echo -e "${BOLD}Dead Store Paths:${NC}"
        echo -e "  Count: ${CYAN}$dead_count${NC} paths"
        echo -e "  Size:  ${YELLOW}$(format_size "$dead_size")${NC} can be reclaimed"
        echo ""
        
        # Show cursor-related dead paths
        local cursor_dead
        cursor_dead=$(echo "$dead_paths" | grep -iE "cursor" || true)
        if [ -n "$cursor_dead" ]; then
            local cursor_dead_count
            cursor_dead_count=$(echo "$cursor_dead" | wc -l)
            echo -e "  Cursor-related dead paths: ${CYAN}$cursor_dead_count${NC}"
            echo "$cursor_dead" | head -5 | while read -r p; do
                echo -e "    - $(basename "$p")"
            done
            if [ "$cursor_dead_count" -gt 5 ]; then
                echo -e "    ... and $((cursor_dead_count - 5)) more"
            fi
            echo ""
        fi
    else
        echo -e "${GREEN}✓ No dead store paths found${NC}"
        echo ""
    fi
    
    # Check generations
    echo -e "${BOLD}System Generations:${NC}"
    local gen_count current_gen
    gen_count=$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | wc -l)
    current_gen=$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | grep "(current)" | awk '{print $1}')
    echo -e "  Total generations: ${CYAN}$gen_count${NC}"
    echo -e "  Current generation: ${GREEN}$current_gen${NC}"
    echo -e "  Would keep: ${CYAN}$KEEP_GENERATIONS${NC} recent generations"
    echo ""
    
    # Check user profile generations
    echo -e "${BOLD}User Profile Generations:${NC}"
    local user_gen_count user_current_gen
    user_gen_count=$(nix-env --list-generations 2>/dev/null | wc -l)
    user_current_gen=$(nix-env --list-generations 2>/dev/null | grep "(current)" | awk '{print $1}' || echo "?")
    echo -e "  Total generations: ${CYAN}$user_gen_count${NC}"
    echo -e "  Current generation: ${GREEN}$user_current_gen${NC}"
    echo ""
    
    # Home Manager generations
    if command -v home-manager &>/dev/null; then
        echo -e "${BOLD}Home Manager Generations:${NC}"
        local hm_gen_count
        hm_gen_count=$(home-manager generations 2>/dev/null | wc -l)
        echo -e "  Total generations: ${CYAN}$hm_gen_count${NC}"
        echo ""
    fi
}

collect_garbage() {
    echo -e "${CYAN}Running garbage collection...${NC}"
    echo ""
    
    local gc_args=""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would run: nix-collect-garbage${NC}"
        nix-store --gc --print-dead 2>/dev/null | head -20
        echo "..."
        return 0
    fi
    
    if ! confirm "Run garbage collection?"; then
        echo "Cancelled."
        return 1
    fi
    
    echo -e "Running: ${CYAN}nix-collect-garbage${NC}"
    nix-collect-garbage
    
    if [ "$SYSTEM_GC" = true ]; then
        echo ""
        echo -e "Running: ${CYAN}sudo nix-collect-garbage${NC}"
        sudo nix-collect-garbage
    fi
    
    echo ""
    echo -e "${GREEN}✓ Garbage collection complete${NC}"
}

manage_generations() {
    echo -e "${CYAN}Managing generations...${NC}"
    echo ""
    
    # Show current state
    echo -e "${BOLD}Current System Generations:${NC}"
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | tail -10
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would delete generations older than +$KEEP_GENERATIONS${NC}"
        
        # Show what would be deleted
        local to_delete
        to_delete=$(sudo nix-env --list-generations --profile /nix/var/nix/profiles/system 2>/dev/null | head -n -"$KEEP_GENERATIONS" | awk '{print $1}')
        if [ -n "$to_delete" ]; then
            echo -e "Would delete generations: ${RED}$to_delete${NC}"
        else
            echo -e "${GREEN}No generations would be deleted${NC}"
        fi
        return 0
    fi
    
    if ! confirm "Delete old generations (keeping last $KEEP_GENERATIONS)?"; then
        echo "Cancelled."
        return 1
    fi
    
    echo -e "Running: ${CYAN}sudo nix-env --delete-generations +$KEEP_GENERATIONS --profile /nix/var/nix/profiles/system${NC}"
    sudo nix-env --delete-generations +"$KEEP_GENERATIONS" --profile /nix/var/nix/profiles/system
    
    # Also clean user generations
    echo -e "Running: ${CYAN}nix-env --delete-generations +$KEEP_GENERATIONS${NC}"
    nix-env --delete-generations +"$KEEP_GENERATIONS"
    
    # Clean Home Manager generations if available
    if command -v home-manager &>/dev/null; then
        echo -e "Running: ${CYAN}home-manager expire-generations '-${KEEP_DAYS} days'${NC}"
        home-manager expire-generations "-${KEEP_DAYS} days" || true
    fi
    
    echo ""
    echo -e "${GREEN}✓ Generation cleanup complete${NC}"
}

optimize_store() {
    echo -e "${CYAN}Optimizing Nix store...${NC}"
    echo ""
    
    echo -e "${YELLOW}Note: Store optimization can take a long time (10-30+ minutes)${NC}"
    echo -e "This deduplicates identical files across the store."
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Would run: nix store optimise${NC}"
        return 0
    fi
    
    if ! confirm "Run store optimization? (This can take a while)"; then
        echo "Cancelled."
        return 1
    fi
    
    echo -e "Running: ${CYAN}nix store optimise${NC}"
    nix store optimise
    
    echo ""
    echo -e "${GREEN}✓ Store optimization complete${NC}"
}

full_cleanup() {
    echo -e "${CYAN}Running full cleanup...${NC}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN] Full cleanup would:${NC}"
        echo "  1. Delete old generations (keep last $KEEP_GENERATIONS)"
        echo "  2. Run garbage collection"
        echo "  3. Optimize store (deduplicate)"
        echo ""
        analyze_garbage
        return 0
    fi
    
    echo -e "${BOLD}Full cleanup will:${NC}"
    echo "  1. Delete old generations (keep last $KEEP_GENERATIONS)"
    echo "  2. Run garbage collection"
    echo "  3. Optimize store (deduplicate)"
    echo ""
    
    if ! confirm "Proceed with full cleanup?"; then
        echo "Cancelled."
        return 1
    fi
    
    echo ""
    INTERACTIVE=false  # Don't prompt for individual steps
    
    manage_generations
    echo ""
    
    collect_garbage
    echo ""
    
    optimize_store
    echo ""
    
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Full Cleanup Complete!                          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
}

# Parse arguments
COMMAND="analyze"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -y|--yes)
            INTERACTIVE=false
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-dry-run)
            DRY_RUN=false
            shift
            ;;
        --keep-generations)
            KEEP_GENERATIONS="$2"
            shift 2
            ;;
        --keep-days)
            KEEP_DAYS="$2"
            shift 2
            ;;
        --system)
            SYSTEM_GC=true
            shift
            ;;
        analyze|collect|generations|optimize|full)
            COMMAND="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Main execution
print_header

case "$COMMAND" in
    analyze)
        analyze_garbage
        ;;
    collect)
        collect_garbage
        ;;
    generations)
        manage_generations
        ;;
    optimize)
        optimize_store
        ;;
    full)
        full_cleanup
        ;;
esac
