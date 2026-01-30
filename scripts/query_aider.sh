#!/bin/bash
# query_aider.sh - Query Aider CLI
#
# Usage: ./query_aider.sh "question" [context_file] [output_file]
#
# Environment variables:
#   AIDER_MODEL - Model to use (default: uses aider's default)
#   AIDER_TIMEOUT - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Pair Programmer" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/aider_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Aider"

# --- Check prerequisites ---
check_command "$AIDER_CMD" "Aider CLI" "pip install aider-chat" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Aider" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)

# Aider flags:
# --no-git: Don't use git
# --message: Send message and exit
# --yes: Answer yes to all prompts
# --no-check-update: Don't check for updates
# --no-suggest-shell-commands: Don't suggest shell commands
run_query \
    "Aider" \
    "$TEMP_OUTPUT" \
    "$AIDER_TIMEOUT_SECONDS" \
    "$AIDER_CMD" --no-git --no-check-update --no-suggest-shell-commands --yes --message "$FULL_QUERY"

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${AIDER_MODEL:-gpt-5.2-codex}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: wrap in full schema using shared helpers ---
if [[ $exit_code -eq 0 && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    RAW_RESPONSE=$(cat "$TEMP_OUTPUT")
    rm -f "$TEMP_OUTPUT"

    # Try to parse as structured JSON
    if echo "$RAW_RESPONSE" | jq -e '.response.summary' > /dev/null 2>&1; then
        build_structured_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" "$RAW_RESPONSE" "$LATENCY_MS" > "$OUTPUT_FILE"
    else
        build_fallback_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" "$RAW_RESPONSE" "$LATENCY_MS" > "$OUTPUT_FILE"
    fi
else
    rm -f "$TEMP_OUTPUT"
    build_error_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" "Query failed with exit code $exit_code" "$LATENCY_MS" > "$OUTPUT_FILE"
fi

cat "$OUTPUT_FILE"
exit $exit_code
