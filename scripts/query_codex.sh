#!/bin/bash
# query_codex.sh - Query OpenAI Codex CLI or API (v2.6 with API mode support)
#
# Usage: ./query_codex.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CODEX_MODEL - Model to use (default: gpt-5.2-codex)
#   CODEX_TIMEOUT - Timeout in seconds (default: 180)
#   CODEX_USE_API - Use API mode instead of CLI (default: false)
#   OPENAI_API_KEY - API key for API mode
#   ENABLE_PERSONA - Enable "The Pragmatist" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/codex_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Codex"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Codex" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)

if is_api_mode "codex"; then
    # --- API Mode ---
    log_api_mode_status "codex"
    validate_api_mode "codex" || exit 1

    source "$SCRIPT_DIR/lib/api_query.sh"

    run_api_mode_query \
        "$CONSULTANT_NAME" \
        "$CODEX_MODEL" \
        "$FULL_QUERY" \
        "$TEMP_OUTPUT" \
        "$CODEX_TIMEOUT_SECONDS"

    exit_code=$?
else
    # --- CLI Mode ---
    log_api_mode_status "codex"
    check_command "$CODEX_CMD" "Codex CLI" "npm install -g @openai/codex" || exit 1

    # Build command
    CMD_ARGS=("$CODEX_CMD" "exec" "--skip-git-repo-check")
    if [[ -n "$CODEX_MODEL" ]]; then
        CMD_ARGS+=("-m" "$CODEX_MODEL")
    fi

    # Codex uses query as the last argument, not from stdin
    run_query \
        "Codex" \
        "$TEMP_OUTPUT" \
        "$CODEX_TIMEOUT_SECONDS" \
        "${CMD_ARGS[@]}" "$FULL_QUERY" < /dev/null

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${CODEX_MODEL:-gpt-5.2-codex}"
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
