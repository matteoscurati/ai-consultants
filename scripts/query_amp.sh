#!/bin/bash
# query_amp.sh - Query Amp CLI (v2.8)
#
# Usage: ./query_amp.sh "question" [context_file] [output_file]
#
# Environment variables:
#   AMP_TIMEOUT   - Timeout in seconds (default: 180)
#   AMP_API_KEY   - API key for authentication (required)
#   ENABLE_PERSONA - Enable "The Systems Thinker" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/amp_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Amp"

# --- Check prerequisites ---
check_command "$AMP_CMD" "Amp CLI" "curl -fsSL https://ampcode.com/install.sh | bash" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Amp" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)

# Amp CLI uses -x (execute mode) for non-interactive usage
# Piped input with -x reads from stdin
echo "$FULL_QUERY" | run_query \
    "Amp" \
    "$TEMP_OUTPUT" \
    "$AMP_TIMEOUT_SECONDS" \
    "$AMP_CMD" -x

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="amp"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
