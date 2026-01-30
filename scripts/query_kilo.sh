#!/bin/bash
# query_kilo.sh - Query Kilo Code CLI
#
# Usage: ./query_kilo.sh "question" [context_file] [output_file]
#
# Environment variables:
#   KILO_MODEL   - Model to use (default: uses Kilo's internal provider)
#   KILO_TIMEOUT - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Innovator" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/kilo_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Kilo"
MODEL_USED="${KILO_MODEL:-kilo}"

# --- Check prerequisites ---
check_command "$KILO_CMD" "Kilo Code CLI" "npm install -g @kilocode/cli" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Kilo Code" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)
TEMP_RAW=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT" "$TEMP_RAW"' EXIT

# Build command args with optional model and -- separator for safety
KILO_ARGS=("$KILO_CMD" "--auto" "--json" "--timeout" "$((KILO_TIMEOUT_SECONDS - 10))")
if [[ -n "${KILO_MODEL:-}" ]]; then
    KILO_ARGS+=("--model" "$KILO_MODEL")
fi
KILO_ARGS+=("--" "$FULL_QUERY")

# Use run_with_timeout for cross-platform support (Linux/macOS/POSIX)
log_info "Consulting Kilo Code (timeout: ${KILO_TIMEOUT_SECONDS}s)..."

if run_with_timeout "$KILO_TIMEOUT_SECONDS" "${KILO_ARGS[@]}" > "$TEMP_RAW" 2>&1; then
    exit_code=0
else
    exit_code=$?
fi

# --- Extract completion_result content from Kilo's JSON stream ---
if [[ -f "$TEMP_RAW" && -s "$TEMP_RAW" ]]; then
    # Kilo outputs multiple JSON lines with ANSI codes; extract the final answer
    CONTENT=$(LC_ALL=C cat -v "$TEMP_RAW" \
        | { grep 'completion_result' || true; } \
        | { grep '"partial":false' || true; } \
        | head -1 \
        | LC_ALL=C sed 's/.*"content":"\([^"]*\)".*/\1/') || true

    if [[ -n "${CONTENT:-}" ]]; then
        echo "$CONTENT" > "$TEMP_OUTPUT"
        exit_code=0
        log_success "[Kilo Code] Response received (${#CONTENT} chars)"
    else
        log_error "[Kilo Code] Could not extract response"
        exit_code=1
    fi
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Post-processing: use shared helper ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
