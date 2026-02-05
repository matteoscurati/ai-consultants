#!/bin/bash
# query_gemini.sh - Query Google Gemini CLI or API (v2.6 with API mode support)
#
# Usage: ./query_gemini.sh "question" [context_file] [output_file]
#
# Environment variables:
#   GEMINI_MODEL - Model to use (default: gemini-3-pro-preview)
#   GEMINI_TIMEOUT - Timeout in seconds (default: 180)
#   GEMINI_USE_API - Use API mode instead of CLI (default: false)
#   GEMINI_API_KEY - API key for API mode
#   ENABLE_PERSONA - Enable "The Architect" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/gemini_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Gemini"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Gemini" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)

if is_api_mode "gemini"; then
    # --- API Mode ---
    log_api_mode_status "gemini"
    validate_api_mode "gemini" || exit 1

    source "$SCRIPT_DIR/lib/api_query.sh"

    run_api_mode_query \
        "$CONSULTANT_NAME" \
        "$GEMINI_MODEL" \
        "$FULL_QUERY" \
        "$TEMP_OUTPUT" \
        "$GEMINI_TIMEOUT_SECONDS"

    exit_code=$?
else
    # --- CLI Mode ---
    log_api_mode_status "gemini"
    check_command "$GEMINI_CMD" "Gemini CLI" "npm install -g @google/gemini-cli" || exit 1

    echo "$FULL_QUERY" | run_query \
        "Gemini" \
        "$TEMP_OUTPUT" \
        "$GEMINI_TIMEOUT_SECONDS" \
        "$GEMINI_CMD" -p - -m "$GEMINI_MODEL" --output-format json

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${GEMINI_MODEL:-gemini-3-pro-preview}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "response"

cat "$OUTPUT_FILE"
exit $exit_code
