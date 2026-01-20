#!/usr/bin/env bash
# capture-app.sh - Intelligent application screenshot capture for KDE/Wayland
# 
# Usage:
#   ./capture-app.sh                           # Capture current monitor
#   ./capture-app.sh "Cursor Studio"           # Capture specific app (if focused)
#   ./capture-app.sh --active                  # Capture active window
#   ./capture-app.sh --monitor                 # Capture current monitor
#   ./capture-app.sh --full                    # Capture all monitors
#   ./capture-app.sh --region                  # Interactive region select
#   ./capture-app.sh --record 5                # Record 5 seconds to GIF
#   ./capture-app.sh --frames recording.mp4   # Extract frames from video

set -euo pipefail

# Configuration
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1" >&2; }
log_info() { echo -e "${YELLOW}→${NC} $1"; }

# Check dependencies
check_deps() {
    local missing=()
    for cmd in spectacle grim ffmpeg; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with: nix-shell -p ${missing[*]}"
        return 1
    fi
}

# Get window info from KDE
get_window_info() {
    qdbus org.kde.KWin /KWin org.kde.KWin.queryWindowInfo 2>/dev/null || true
}

# Capture screenshot with spectacle
capture_spectacle() {
    local mode="$1"
    local output="$2"
    
    case "$mode" in
        active)   spectacle -b -a -n -o "$output" ;;
        monitor)  spectacle -b -m -n -o "$output" ;;
        full)     spectacle -b -f -n -o "$output" ;;
        region)   spectacle -b -r -n -o "$output" ;;
        cursor)   spectacle -b -u -n -o "$output" ;;
    esac
    
    # Wait for file to be written
    sleep 0.5
    
    if [[ -f "$output" ]]; then
        log_success "Captured: $output ($(du -h "$output" | cut -f1))"
        return 0
    else
        log_error "Capture failed"
        return 1
    fi
}

# Capture with grim (Wayland native)
capture_grim() {
    local geometry="$1"
    local output="$2"
    
    if [[ -n "$geometry" ]]; then
        grim -g "$geometry" "$output"
    else
        grim "$output"
    fi
    
    if [[ -f "$output" ]]; then
        log_success "Captured: $output ($(du -h "$output" | cut -f1))"
        return 0
    else
        log_error "Capture failed"
        return 1
    fi
}

# Record screen to GIF
record_gif() {
    local duration="$1"
    local output="${2:-${OUTPUT_DIR}/recording-${TIMESTAMP}.gif}"
    local mp4_temp="${output%.gif}.mp4"
    
    log_info "Recording for ${duration}s... (Press Ctrl+C to stop early)"
    
    # Record to MP4 first (better quality)
    ffmpeg -f x11grab -video_size 1920x1080 -framerate 30 -i :0 \
        -t "$duration" -c:v libx264 -preset ultrafast \
        "$mp4_temp" 2>/dev/null || true
    
    if [[ -f "$mp4_temp" ]]; then
        log_info "Converting to GIF..."
        ffmpeg -i "$mp4_temp" \
            -vf "fps=15,scale=800:-1:flags=lanczos" \
            "$output" 2>/dev/null
        
        rm -f "$mp4_temp"
        
        if [[ -f "$output" ]]; then
            log_success "Recorded: $output ($(du -h "$output" | cut -f1))"
            return 0
        fi
    fi
    
    log_error "Recording failed"
    return 1
}

# Extract frames from video
extract_frames() {
    local input="$1"
    local output_dir="${2:-${input%.mp4}-frames}"
    
    if [[ ! -f "$input" ]]; then
        log_error "Video file not found: $input"
        return 1
    fi
    
    mkdir -p "$output_dir"
    
    log_info "Extracting key frames..."
    
    # Extract frames where scene changes (good for detecting flickers)
    ffmpeg -i "$input" \
        -vf "select='gt(scene,0.05)'" \
        -vsync vfr \
        "${output_dir}/frame-%04d.png" 2>/dev/null
    
    local count=$(ls -1 "$output_dir"/*.png 2>/dev/null | wc -l)
    
    if [[ $count -gt 0 ]]; then
        log_success "Extracted $count frames to $output_dir/"
        
        # Also create a contact sheet
        ffmpeg -i "$input" \
            -vf "select='not(mod(n,30))',scale=320:-1,tile=4x4" \
            "${output_dir}/contact-sheet.png" 2>/dev/null
        
        if [[ -f "${output_dir}/contact-sheet.png" ]]; then
            log_success "Created contact sheet: ${output_dir}/contact-sheet.png"
        fi
        
        return 0
    fi
    
    log_error "Frame extraction failed"
    return 1
}

# Show current window info
show_window_info() {
    local info=$(get_window_info)
    
    if [[ -n "$info" ]]; then
        echo "Current focused window:"
        echo "$info" | grep -E "^(caption|resourceClass|x|y|width|height):" | sed 's/^/  /'
    else
        log_error "Could not query window info (KWin DBus not available?)"
    fi
}

# Main function
main() {
    check_deps || exit 1
    
    local mode="monitor"
    local app_name=""
    local duration=""
    local video_file=""
    local output=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --active|-a)
                mode="active"
                shift
                ;;
            --monitor|-m)
                mode="monitor"
                shift
                ;;
            --full|-f)
                mode="full"
                shift
                ;;
            --region|-r)
                mode="region"
                shift
                ;;
            --record)
                mode="record"
                duration="${2:-5}"
                shift 2
                ;;
            --frames)
                mode="frames"
                video_file="${2:-}"
                shift 2
                ;;
            --info|-i)
                show_window_info
                exit 0
                ;;
            --output|-o)
                output="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [options] [app-name]"
                echo ""
                echo "Options:"
                echo "  --active, -a     Capture active window"
                echo "  --monitor, -m    Capture current monitor (default)"
                echo "  --full, -f       Capture all monitors"
                echo "  --region, -r     Interactive region selection"
                echo "  --record N       Record N seconds to GIF"
                echo "  --frames FILE    Extract frames from video"
                echo "  --info, -i       Show current window info"
                echo "  --output, -o     Specify output file"
                echo "  --help, -h       Show this help"
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                app_name="$1"
                shift
                ;;
        esac
    done
    
    # Set default output filename
    if [[ -z "$output" ]]; then
        case "$mode" in
            record) output="${OUTPUT_DIR}/recording-${TIMESTAMP}.gif" ;;
            frames) output="${video_file%.mp4}-frames" ;;
            *)      output="${OUTPUT_DIR}/screenshot-${TIMESTAMP}.png" ;;
        esac
    fi
    
    # Execute based on mode
    case "$mode" in
        record)
            record_gif "$duration" "$output"
            ;;
        frames)
            if [[ -z "$video_file" ]]; then
                log_error "No video file specified"
                exit 1
            fi
            extract_frames "$video_file" "$output"
            ;;
        active|monitor|full|region|cursor)
            # If app name specified, check if it's focused
            if [[ -n "$app_name" ]]; then
                local info=$(get_window_info)
                local caption=$(echo "$info" | grep "^caption:" | cut -d' ' -f2-)
                
                if [[ "$caption" != *"$app_name"* ]]; then
                    log_error "App '$app_name' is not the focused window"
                    log_info "Current window: $caption"
                    log_info "Using --monitor mode instead..."
                    mode="monitor"
                else
                    log_info "Capturing: $caption"
                    mode="cursor"  # Window under cursor (captures the focused app)
                fi
            fi
            
            capture_spectacle "$mode" "$output"
            ;;
    esac
}

main "$@"

