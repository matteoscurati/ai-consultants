#!/bin/bash
# query_claude.sh - Query Claude CLI or API
#
# Usage: ./query_claude.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CLAUDE_MODEL - Model to use (default: claude-opus-4-5-20251124)
#   CLAUDE_TIMEOUT - Timeout in seconds (default: 240)
#   CLAUDE_USE_API - Use API mode instead of CLI (default: false)
#   ANTHROPIC_API_KEY - API key for API mode
#   ENABLE_PERSONA - Enable "The Synthesizer" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/claude_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Claude"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
MODEL_USED="${CLAUDE_MODEL:-opus}"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Claude" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)

if is_api_mode "claude"; then
    # --- API Mode ---
    log_api_mode_status "claude"
    validate_api_mode "claude" || exit 1

    source "$SCRIPT_DIR/lib/api_query.sh"

    run_api_mode_query \
        "$CONSULTANT_NAME" \
        "$MODEL_USED" \
        "$FULL_QUERY" \
        "$TEMP_OUTPUT" \
        "$CLAUDE_TIMEOUT_SECONDS"

    exit_code=$?
else
    # --- CLI Mode ---
    log_api_mode_status "claude"
    check_command "$CLAUDE_CMD" "Claude CLI" "Visit https://docs.anthropic.com/en/docs/claude-code" || exit 1

    # Claude CLI uses --print for non-interactive mode
    echo "$FULL_QUERY" | run_query \
        "Claude" \
        "$TEMP_OUTPUT" \
        "$CLAUDE_TIMEOUT_SECONDS" \
        "$CLAUDE_CMD" --print --model "$MODEL_USED"

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
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
