#!/usr/bin/env bash
# URL Validation Script for Cursor Downloads
# Validates that all download URLs are accessible and returns HTTP status codes

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

# Output files
RESULTS_DIR="$REPO_ROOT/.cursor/validation-results"
mkdir -p "$RESULTS_DIR"

VALID_URLS="$RESULTS_DIR/valid-urls.txt"
INVALID_URLS="$RESULTS_DIR/invalid-urls.txt"
FULL_REPORT="$RESULTS_DIR/validation-report.md"

# Counters
TOTAL=0
VALID=0
INVALID=0
REDIRECT=0

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Cursor Download URL Validation                        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Initialize result files
> "$VALID_URLS"
> "$INVALID_URLS"

validate_url() {
    local url="$1"
    local version="$2"
    local platform="$3"
    
    # Use curl to check URL (follow redirects, get final status)
    local http_code
    http_code=$(curl -sL -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "000")
    
    case "$http_code" in
        200)
            echo -e "  ${GREEN}✓${NC} $version ($platform): ${GREEN}200 OK${NC}"
            echo "$version|$platform|$url|200" >> "$VALID_URLS"
            ((VALID++)) || true
            ;;
        301|302|303|307|308)
            echo -e "  ${YELLOW}→${NC} $version ($platform): ${YELLOW}$http_code Redirect${NC}"
            echo "$version|$platform|$url|$http_code" >> "$VALID_URLS"
            ((REDIRECT++)) || true
            ((VALID++)) || true
            ;;
        000)
            echo -e "  ${RED}✗${NC} $version ($platform): ${RED}Timeout/Connection Error${NC}"
            echo "$version|$platform|$url|timeout" >> "$INVALID_URLS"
            ((INVALID++)) || true
            ;;
        *)
            echo -e "  ${RED}✗${NC} $version ($platform): ${RED}$http_code${NC}"
            echo "$version|$platform|$url|$http_code" >> "$INVALID_URLS"
            ((INVALID++)) || true
            ;;
    esac
    
    ((TOTAL++)) || true
}

# Parse and validate Linux x64 URLs
echo -e "${CYAN}Validating Linux x64 URLs...${NC}"
LINUX_FILE="$REPO_ROOT/.cursor/linux -x64-version-urls.txt"

if [ -f "$LINUX_FILE" ]; then
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^# || "$line" =~ ^- || "$line" =~ ^Pre || "$line" =~ ^✅ || "$line" =~ ^📦 || "$line" =~ ^🔒 || "$line" =~ ^🎯 || "$line" =~ ^🧪 || "$line" =~ ^Cursor || "$line" =~ ^INTEGRATION ]] && continue
        
        # Extract URL
        if [[ "$line" =~ ^https://downloads\.cursor\.com ]]; then
            # Extract version from URL
            if [[ "$line" =~ Cursor-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
                version="${BASH_REMATCH[1]}"
                validate_url "$line" "$version" "linux-x64"
            fi
        fi
    done < "$LINUX_FILE"
else
    echo -e "${RED}Linux URL file not found: $LINUX_FILE${NC}"
fi

echo ""

# Parse and validate Darwin URLs
echo -e "${CYAN}Validating Darwin (macOS) URLs...${NC}"
DARWIN_FILE="$REPO_ROOT/.cursor/darwin-all-urls.txt"

if [ -f "$DARWIN_FILE" ]; then
    current_version=""
    while IFS= read -r line; do
        # Skip empty lines and separators
        [[ -z "$line" || "$line" =~ ^- ]] && continue
        
        # Capture version from comment
        if [[ "$line" =~ ^#\ Cursor\ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
            current_version="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Skip non-URL lines
        [[ ! "$line" =~ ^https://downloads\.cursor\.com ]] && continue
        
        # Determine architecture from URL
        local arch=""
        if [[ "$line" =~ darwin/universal ]]; then
            arch="darwin-universal"
        elif [[ "$line" =~ darwin/x64 ]]; then
            arch="darwin-x64"
        elif [[ "$line" =~ darwin/arm64 ]]; then
            arch="darwin-arm64"
        fi
        
        if [ -n "$current_version" ] && [ -n "$arch" ]; then
            validate_url "$line" "$current_version" "$arch"
        fi
    done < "$DARWIN_FILE"
else
    echo -e "${RED}Darwin URL file not found: $DARWIN_FILE${NC}"
fi

echo ""

# Generate report
echo -e "${CYAN}Generating validation report...${NC}"

cat > "$FULL_REPORT" << REPORT_EOF
# Cursor URL Validation Report

Generated: $(date -Iseconds)

## Summary

| Metric | Count |
|--------|-------|
| Total URLs | $TOTAL |
| Valid (200 OK) | $((VALID - REDIRECT)) |
| Redirects (3xx) | $REDIRECT |
| Invalid/Failed | $INVALID |
| Success Rate | $(echo "scale=1; $VALID * 100 / $TOTAL" | bc)% |

## Valid URLs

$(cat "$VALID_URLS" 2>/dev/null || echo "None")

## Invalid URLs

$(cat "$INVALID_URLS" 2>/dev/null || echo "None")
REPORT_EOF

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   Validation Summary                      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Total URLs checked: ${CYAN}$TOTAL${NC}"
echo -e "  Valid (200 OK):     ${GREEN}$((VALID - REDIRECT))${NC}"
echo -e "  Redirects (3xx):    ${YELLOW}$REDIRECT${NC}"
echo -e "  Invalid/Failed:     ${RED}$INVALID${NC}"
echo ""
echo -e "  Report saved to: ${BLUE}$FULL_REPORT${NC}"
echo ""

if [ "$INVALID" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some URLs failed validation. Check $INVALID_URLS${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All URLs validated successfully!${NC}"
fi
