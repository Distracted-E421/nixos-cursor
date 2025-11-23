#!/usr/bin/env bash
#
# Browser Test After Deploy Hook
#
# This hook detects when deployment-related files are edited and suggests
# browser-based verification of the deployed services.
#
# Triggers on:
# - NixOS configuration changes
# - Service configuration updates
# - Docker/k8s deployment files
# - Home Assistant configuration
#
# Suggests:
# - Browser-based health checks
# - Screenshot documentation
# - Console error verification
#

set -euo pipefail

# Get list of modified files from stdin
MODIFIED_FILES="${1:-}"

# Define patterns that indicate deployments
DEPLOYMENT_PATTERNS=(
    "nixos/.*configuration\.nix"
    "nixos/.*\.nix"
    "services/.*/docker-compose\.yml"
    "services/.*/deployment\.yaml"
    "devices/.*/config/.*\.conf"
    "services/home-assistant/.*\.yaml"
)

# Check if any modified files match deployment patterns
should_test=false
for pattern in "${DEPLOYMENT_PATTERNS[@]}"; do
    if echo "$MODIFIED_FILES" | grep -qE "$pattern"; then
        should_test=true
        break
    fi
done

if [ "$should_test" = true ]; then
    cat <<'EOF'

🌐 **Browser Testing Suggestion**

You've modified deployment-related files. Consider verifying with browser automation:

**Quick Checks:**
- `web health [service-name]` - Check if service is responding
- `web verify [service-name]` - Visual verification with screenshot

**Deep Testing:**
- `test [feature] in browser` - Full workflow testing
- `check console at [url]` - JavaScript error detection
- `analyze network requests at [url]` - Performance analysis

**Services You Might Want to Test:**
- Home Assistant: http://192.168.0.61:8123
- Grafana: http://obsidian:3000 (if deployed)
- Local dev servers: http://localhost:<port>

Use Playwright MCP for automated verification!

EOF
fi

exit 0
