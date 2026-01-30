#!/bin/bash
# query_cursor.sh - Query Cursor CLI
#
# Usage: ./query_cursor.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CURSOR_MODEL   - Model to use (default: uses Cursor's default)
#   CURSOR_TIMEOUT - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Integrator" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/cursor_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Cursor"
MODEL_USED="${CURSOR_MODEL:-cursor}"

# --- Check prerequisites ---
check_command "$CURSOR_CMD" "Cursor CLI" "curl https://cursor.com/install -fsS | bash" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Cursor" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT"' EXIT

# Build command args with optional model
CMD_ARGS=("$CURSOR_CMD" "-p" "-" "--output-format" "text")
if [[ -n "${CURSOR_MODEL:-}" ]]; then
    CMD_ARGS+=("--model" "$CURSOR_MODEL")
fi

echo "$FULL_QUERY" | run_query \
    "Cursor" \
    "$TEMP_OUTPUT" \
    "$CURSOR_TIMEOUT_SECONDS" \
    "${CMD_ARGS[@]}"

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Post-processing: use shared helper ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
