#!/bin/bash
# query_qwen3.sh - Query Qwen3 via CLI (qwen-code) or HTTP API (v2.7 with CLI/API mode switching)
#
# Usage: ./query_qwen3.sh "question" [context_file] [output_file]
#
# Environment variables:
#   QWEN3_MODEL     - Model to use (default: qwen3-max)
#   QWEN3_TIMEOUT   - Timeout in seconds (default: 180)
#   QWEN3_USE_API   - Use API mode instead of CLI (default: true for backward compat)
#   QWEN3_API_KEY   - API key for DashScope API (required for API mode)
#   ENABLE_PERSONA  - Enable "The Analyst" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/qwen3_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Qwen3"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Qwen3" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)

if is_api_mode "qwen3"; then
    # --- API Mode (DashScope) ---
    log_api_mode_status "qwen3"
    validate_api_mode "qwen3" || exit 1

    source "$SCRIPT_DIR/lib/api_query.sh"

    run_api_mode_query \
        "$CONSULTANT_NAME" \
        "$QWEN3_MODEL" \
        "$FULL_QUERY" \
        "$TEMP_OUTPUT" \
        "$QWEN3_TIMEOUT_SECONDS"

    exit_code=$?
else
    # --- CLI Mode (qwen-code) ---
    log_api_mode_status "qwen3"
    check_command "$QWEN3_CMD" "Qwen CLI" "npm install -g @qwen-code/qwen-code@latest" || exit 1

    # qwen-code uses -p for prompt, reads from stdin with -p -
    echo "$FULL_QUERY" | run_query \
        "Qwen3" \
        "$TEMP_OUTPUT" \
        "$QWEN3_TIMEOUT_SECONDS" \
        "$QWEN3_CMD" -p -

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${QWEN3_MODEL:-qwen3-max}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
