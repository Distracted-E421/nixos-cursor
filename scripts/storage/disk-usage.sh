#!/usr/bin/env bash
# Cursor Disk Usage Analysis Script
# Analyzes Nix store usage for Cursor-related packages

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
STORE_PATH="/nix/store"
HUMAN_READABLE="${HUMAN_READABLE:-true}"
DETAILED="${DETAILED:-false}"

usage() {
    cat << 'EOF'
Usage: disk-usage.sh [OPTIONS]

Analyze Nix store disk usage for Cursor packages

Options:
    -h, --help          Show this help
    -d, --detailed      Show detailed breakdown
    -j, --json          Output in JSON format
    --no-color          Disable colored output
    --gc-roots          Show GC roots for Cursor packages

Examples:
    disk-usage.sh                    # Quick summary
    disk-usage.sh --detailed         # Full breakdown
    disk-usage.sh --gc-roots         # Show what's keeping versions alive
EOF
}

format_size() {
    local bytes=$1
    if [ "$HUMAN_READABLE" = true ]; then
        numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
    else
        echo "$bytes"
    fi
}

bytes_to_gb() {
    awk "BEGIN {printf \"%.2f\", $1 / 1024 / 1024 / 1024}"
}

print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          ${BOLD}Cursor Nix Store Disk Usage Analysis${NC}${BLUE}                    ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

analyze_store() {
    echo -e "${CYAN}Analyzing Nix store...${NC}"
    echo ""
    
    # Total store size
    local total_store_bytes
    total_store_bytes=$(du -sb "$STORE_PATH" 2>/dev/null | cut -f1)
    local total_store_human
    total_store_human=$(format_size "$total_store_bytes")
    
    echo -e "${BOLD}Nix Store Overview:${NC}"
    echo -e "  Total store size: ${YELLOW}$total_store_human${NC}"
    echo ""
    
    # Cursor-specific analysis
    echo -e "${BOLD}Cursor Package Analysis:${NC}"
    
    # Count entries
    local cursor_entries
    cursor_entries=$(find "$STORE_PATH" -maxdepth 1 -name "*cursor*" -o -name "*Cursor*" 2>/dev/null | wc -l)
    echo -e "  Total Cursor entries: ${CYAN}$cursor_entries${NC}"
    
    # AppImages
    local appimage_count appimage_bytes
    appimage_count=$(find "$STORE_PATH" -maxdepth 1 -name "*Cursor*AppImage*" 2>/dev/null | wc -l)
    appimage_bytes=$(du -sb "$STORE_PATH"/*Cursor*AppImage* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    echo -e "  AppImages: ${CYAN}$appimage_count${NC} ($(format_size "$appimage_bytes"))"
    
    # Built packages
    local built_count built_bytes
    built_count=$(find "$STORE_PATH" -maxdepth 1 -type d -name "*cursor-[0-9]*" 2>/dev/null | wc -l)
    built_bytes=$(du -sb "$STORE_PATH"/*cursor-[0-9]* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    echo -e "  Built packages: ${CYAN}$built_count${NC} ($(format_size "$built_bytes"))"
    
    # Extracted packages
    local extracted_count extracted_bytes
    extracted_count=$(find "$STORE_PATH" -maxdepth 1 -type d -name "*cursor*extracted*" 2>/dev/null | wc -l)
    extracted_bytes=$(du -sb "$STORE_PATH"/*cursor*extracted* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    echo -e "  Extracted packages: ${CYAN}$extracted_count${NC} ($(format_size "$extracted_bytes"))"
    
    # Total Cursor usage
    local total_cursor_bytes=$((appimage_bytes + built_bytes + extracted_bytes))
    local cursor_percentage
    cursor_percentage=$(awk "BEGIN {printf \"%.1f\", $total_cursor_bytes * 100 / $total_store_bytes}")
    
    echo ""
    echo -e "  ${BOLD}Total Cursor usage: ${YELLOW}$(format_size "$total_cursor_bytes")${NC} (${cursor_percentage}% of store)"
    echo ""
    
    # Version breakdown
    if [ "$DETAILED" = true ]; then
        echo -e "${BOLD}Version Breakdown:${NC}"
        echo ""
        
        # Get unique versions and their sizes
        echo -e "  ${CYAN}Version${NC}       ${CYAN}AppImage${NC}    ${CYAN}Built${NC}       ${CYAN}Extracted${NC}   ${CYAN}Total${NC}"
        echo "  ─────────────────────────────────────────────────────────────"
        
        for ver in 2.1 2.0 1.7 1.6; do
            local ver_appimage ver_built ver_extracted ver_total
            ver_appimage=$(du -sb "$STORE_PATH"/*Cursor-${ver}*AppImage* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            ver_built=$(du -sb "$STORE_PATH"/*cursor-${ver}* 2>/dev/null | grep -v extracted | awk '{sum+=$1} END {print sum+0}')
            ver_extracted=$(du -sb "$STORE_PATH"/*cursor-${ver}*extracted* 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            ver_total=$((ver_appimage + ver_built + ver_extracted))
            
            if [ "$ver_total" -gt 0 ]; then
                printf "  %-12s %-11s %-11s %-11s %-11s\n" \
                    "${ver}.x" \
                    "$(format_size "$ver_appimage")" \
                    "$(format_size "$ver_built")" \
                    "$(format_size "$ver_extracted")" \
                    "$(format_size "$ver_total")"
            fi
        done
        echo ""
    fi
    
    # Recommendations
    echo -e "${BOLD}Recommendations:${NC}"
    
    if [ "$appimage_bytes" -gt $((5 * 1024 * 1024 * 1024)) ]; then  # > 5GB
        echo -e "  ${YELLOW}⚠${NC}  AppImages using $(format_size "$appimage_bytes") - consider running garbage collection"
    fi
    
    if [ "$extracted_count" -gt 10 ]; then
        echo -e "  ${YELLOW}⚠${NC}  $extracted_count extracted packages - these can be rebuilt if needed"
    fi
    
    local dead_bytes
    dead_bytes=$(nix-store --gc --print-dead 2>/dev/null | wc -c)
    if [ "$dead_bytes" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC}  Dead store paths exist - run 'nix-collect-garbage' to reclaim space"
    else
        echo -e "  ${GREEN}✓${NC}  No dead store paths - store is optimized"
    fi
    
    echo ""
}

show_gc_roots() {
    echo -e "${BOLD}GC Roots for Cursor Packages:${NC}"
    echo ""
    
    # Find all cursor-related GC roots
    for root in /nix/var/nix/gcroots/auto/*; do
        local target
        target=$(readlink -f "$root" 2>/dev/null || true)
        if [[ "$target" == *cursor* ]] || [[ "$target" == *Cursor* ]]; then
            echo -e "  ${CYAN}$(basename "$root")${NC} → $target"
        fi
    done
    
    # Check current profile
    echo ""
    echo -e "${BOLD}Current Profile References:${NC}"
    nix-store --query --roots /nix/store/*cursor-2* 2>/dev/null | head -10 || echo "  (none found)"
    echo ""
}

# Parse arguments
SHOW_GC_ROOTS=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--detailed)
            DETAILED=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        --no-color)
            RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' NC=''
            shift
            ;;
        --gc-roots)
            SHOW_GC_ROOTS=true
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
analyze_store

if [ "$SHOW_GC_ROOTS" = true ]; then
    show_gc_roots
fi

# Quick tips
echo -e "${BOLD}Quick Commands:${NC}"
echo -e "  ${CYAN}nix-collect-garbage${NC}           # Remove unused packages"
echo -e "  ${CYAN}nix-collect-garbage -d${NC}        # Also delete old generations"
echo -e "  ${CYAN}nix store optimise${NC}            # Deduplicate store (can take a while)"
echo -e "  ${CYAN}sudo nix-collect-garbage -d${NC}   # Clean system generations too"
echo ""
