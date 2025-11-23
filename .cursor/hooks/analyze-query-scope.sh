#!/bin/bash
# Cursor Hook: beforeSubmitPrompt
# Analyzes whether the user query is open-ended (maximize work) or defined-scope (concise answer)

# Read JSON input from stdin
INPUT=$(cat)

# Extract prompt text
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')

# Define patterns for defined-scope queries
DEFINED_SCOPE_PATTERNS=(
  "^What is"
  "^Show me"
  "^Is .* running"
  "^Why does .* fail"
  "^How do I"
  "^Can you explain"
  "^What does .* mean"
  "^Check if"
  "^Tell me about"
)

# Check if this is a defined-scope query
IS_DEFINED_SCOPE=false
for pattern in "${DEFINED_SCOPE_PATTERNS[@]}"; do
  if echo "$PROMPT" | grep -qiE "$pattern"; then
    IS_DEFINED_SCOPE=true
    break
  fi
done

# Log the query type for analytics
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
LOG_DIR="/home/e421/homelab/.cursor/logs"
mkdir -p "$LOG_DIR"

if [ "$IS_DEFINED_SCOPE" = true ]; then
  echo "[$TIMESTAMP] DEFINED-SCOPE QUERY: $PROMPT" >> "$LOG_DIR/query-types.log"
  # For defined-scope queries, remind to be concise
  echo "$PROMPT

[System Note: This appears to be a defined-scope query. Provide a concise, focused answer while still offering valuable context.]" >> "$LOG_DIR/last-query-type.txt"
else
  echo "[$TIMESTAMP] OPEN-ENDED QUERY: $PROMPT" >> "$LOG_DIR/query-types.log"
  # For open-ended queries, activate maximization mode
  echo "$PROMPT

[System Note: This is an open-ended query. Activate token maximization mode: complete ALL related work, update documentation, create diagrams, run tests, commit changes, and continue until no more valuable work can be identified.]" >> "$LOG_DIR/last-query-type.txt"
fi

# Always allow the prompt to continue
echo '{"continue": true}'
exit 0
