#!/usr/bin/env bash
# Hash Computation Script for Cursor Downloads
# Downloads and computes SHA256 hashes for new versions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Output directory
HASH_DIR="$REPO_ROOT/.cursor/hashes"
mkdir -p "$HASH_DIR"

usage() {
    cat << 'USAGE_EOF'
Usage: compute-hashes.sh [OPTIONS] URL [URL...]

Compute SHA256 hashes for Cursor AppImages/DMGs

Options:
    -h, --help      Show this help message
    -v, --version   Specify version (auto-detected from URL if not provided)
    -o, --output    Output file for Nix format (default: stdout)
    --nix           Output in Nix attribute format
    --all           Compute hashes for all versions in URL files

Examples:
    compute-hashes.sh https://downloads.cursor.com/.../Cursor-2.1.34-x86_64.AppImage
    compute-hashes.sh --all --nix -o new-versions.nix
    compute-hashes.sh --version 2.1.34 URL
USAGE_EOF
}

compute_hash() {
    local url="$1"
    local version="${2:-}"
    
    # Auto-detect version from URL
    if [ -z "$version" ]; then
        if [[ "$url" =~ Cursor-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            version="${BASH_REMATCH[1]}"
        elif [[ "$url" =~ production/([a-f0-9]+)/ ]]; then
            # For URLs without version in filename, use commit hash
            version="unknown-${BASH_REMATCH[1]:0:8}"
        fi
    fi
    
    echo -e "${CYAN}Computing hash for $version...${NC}" >&2
    
    # Download to temp file
    local tmpfile
    tmpfile=$(mktemp)
    
    echo -e "  Downloading: ${BLUE}$url${NC}" >&2
    if ! curl -sL --connect-timeout 30 --max-time 600 -o "$tmpfile" "$url"; then
        echo -e "  ${RED}✗ Download failed${NC}" >&2
        rm -f "$tmpfile"
        return 1
    fi
    
    # Compute hash using nix-hash
    local sri_hash
    sri_hash="sha256-$(nix-hash --type sha256 --base64 "$tmpfile")"
    
    echo -e "  ${GREEN}✓${NC} Hash: ${GREEN}$sri_hash${NC}" >&2
    
    # Output
    echo "$version|$sri_hash|$url"
    
    rm -f "$tmpfile"
}

compute_all_missing() {
    local output_format="${1:-plain}"
    local linux_file="$REPO_ROOT/.cursor/linux -x64-version-urls.txt"
    local versions_file="$REPO_ROOT/cursor-versions.nix"
    
    echo -e "${CYAN}Finding versions without hashes...${NC}" >&2
    
    # Get versions already in cursor-versions.nix
    local existing_versions
    existing_versions=$(grep -oP 'version = "\K[0-9]+\.[0-9]+\.[0-9]+' "$versions_file" | sort -u)
    
    echo -e "Existing versions in cursor-versions.nix:" >&2
    echo "$existing_versions" | head -10 >&2
    echo "..." >&2
    
    # Get versions from URL file
    local url_versions=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^https://.*Cursor-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            url_versions+=("${BASH_REMATCH[1]}|$line")
        fi
    done < "$linux_file"
    
    # Find missing versions
    local missing=()
    for entry in "${url_versions[@]}"; do
        local ver="${entry%%|*}"
        if ! echo "$existing_versions" | grep -qx "$ver"; then
            missing+=("$entry")
        fi
    done
    
    echo -e "${YELLOW}Missing versions: ${#missing[@]}${NC}" >&2
    
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ All versions already have hashes!${NC}" >&2
        return 0
    fi
    
    echo -e "Missing versions:" >&2
    for entry in "${missing[@]}"; do
        echo "  - ${entry%%|*}" >&2
    done
    echo "" >&2
    
    # Compute hashes for missing versions
    if [ "$output_format" = "nix" ]; then
        echo "# Auto-generated Cursor version definitions"
        echo "# Generated: $(date -Iseconds)"
        echo ""
    fi
    
    for entry in "${missing[@]}"; do
        local ver="${entry%%|*}"
        local url="${entry#*|}"
        
        local result
        if result=$(compute_hash "$url" "$ver"); then
            local hash="${result#*|}"
            hash="${hash%%|*}"
            
            if [ "$output_format" = "nix" ]; then
                local attr_name="cursor-${ver//./_}"
                echo ""
                echo "  $attr_name = mkCursorVersion {"
                echo "    version = \"$ver\";"
                echo "    hash = \"$hash\";"
                echo "    srcUrl = \"$url\";"
                echo "    binaryName = \"cursor-$ver\";"
                echo "    dataStrategy = \"isolated\";"
                echo "  };"
            else
                echo "$result"
            fi
        fi
    done
}

# Parse arguments
OUTPUT_FORMAT="plain"
OUTPUT_FILE=""
COMPUTE_ALL=false
VERSION=""
URLS=()

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
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --nix)
            OUTPUT_FORMAT="nix"
            shift
            ;;
        --all)
            COMPUTE_ALL=true
            shift
            ;;
        https://*)
            URLS+=("$1")
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Execute
if [ "$COMPUTE_ALL" = true ]; then
    if [ -n "$OUTPUT_FILE" ]; then
        compute_all_missing "$OUTPUT_FORMAT" > "$OUTPUT_FILE"
        echo -e "${GREEN}✓ Output written to $OUTPUT_FILE${NC}"
    else
        compute_all_missing "$OUTPUT_FORMAT"
    fi
elif [ ${#URLS[@]} -gt 0 ]; then
    for url in "${URLS[@]}"; do
        compute_hash "$url" "$VERSION"
    done
else
    echo "No URLs provided. Use --all to compute all missing hashes." >&2
    usage
    exit 1
fi
