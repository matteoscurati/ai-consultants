#!/bin/bash
# query_kimi.sh - Query Kimi CLI (v2.9)
#
# Usage: ./query_kimi.sh "question" [context_file] [output_file]
#
# Environment variables:
#   KIMI_MODEL     - Model identifier (default: kimi-code/kimi-for-coding)
#   KIMI_TIMEOUT   - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Eastern Sage" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/kimi_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Kimi"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Kimi" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)

# Check CLI prerequisite
check_command "$KIMI_CMD" "Kimi CLI" "curl -L code.kimi.com/install.sh | bash" || exit 1

# Kimi CLI uses --quiet (equivalent to --print --output-format text --final-message-only)
# and --input-format text for piped stdin
echo "$FULL_QUERY" | run_query \
    "Kimi" \
    "$TEMP_OUTPUT" \
    "$KIMI_TIMEOUT_SECONDS" \
    "$KIMI_CMD" --quiet --input-format text

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="$KIMI_MODEL"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
