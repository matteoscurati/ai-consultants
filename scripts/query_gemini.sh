#!/bin/bash
# query_gemini.sh - Query Gemini via the Antigravity CLI (`agy`) or Google AI API
#
# CLI mode uses `agy` (Antigravity CLI), the successor to the deprecated Gemini
# CLI (transitioned 2026-06-18). Models are addressed by display name and the
# CLI prints the model's response as plain text (no JSON envelope wrapper).
#
# Usage: ./query_gemini.sh "question" [context_file] [output_file]
#
# Environment variables:
#   GEMINI_MODEL - agy model display name (default: "Gemini 3.1 Pro (High)")
#   GEMINI_TIMEOUT - Timeout in seconds (default: 180)
#   GEMINI_USE_API - Use Google AI API mode instead of the agy CLI (default: false)
#   GEMINI_API_MODEL - API model ID for API mode (default: gemini-3.1-pro-preview)
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

    # API mode addresses the Google AI endpoint, which needs an API model ID
    # (not an agy display name like "Gemini 3.1 Pro (High)").
    run_api_mode_query \
        "$CONSULTANT_NAME" \
        "$GEMINI_API_MODEL" \
        "$FULL_QUERY" \
        "$TEMP_OUTPUT" \
        "$GEMINI_TIMEOUT_SECONDS"

    exit_code=$?
else
    # --- CLI Mode (Antigravity CLI: agy) ---
    log_api_mode_status "gemini"
    check_command "$GEMINI_CMD" "Antigravity CLI" "curl -fsSL https://antigravity.google/cli/install.sh | bash" || exit 1

    # agy prints the model's response as plain text -- there is no CLI envelope
    # to unwrap. The persona instruction forces the model to emit our JSON schema
    # (some models wrap it in a ```json markdown fence; process_consultant_response
    # strips it centrally).
    # NOTE: agy's -p/--print/--prompt takes the prompt as its ARGUMENT value -- it
    # does NOT read stdin, and "-" is not a stdin sentinel. A prior `-p -` shipped
    # silently broken: agy answered a literal "-" with a generic greeting (exit 0,
    # so no error surfaced -> fallback envelope). The prompt therefore rides as the
    # -p argument. agy has --model (no -m alias) and no read-from-file flag, so a
    # very large FULL_QUERY goes through argv (ARG_MAX-bounded; fine for normal
    # contexts). stdin is /dev/null (agy ignores it; run_query's cat needs an EOF).
    run_query \
        "Gemini" \
        "$TEMP_OUTPUT" \
        "$GEMINI_TIMEOUT_SECONDS" \
        "$GEMINI_CMD" -p "$FULL_QUERY" --model "$GEMINI_MODEL" </dev/null

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="$GEMINI_MODEL"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
# No native_json_field: agy prints the model's JSON directly (top-level
# .response, possibly inside a ```json fence that process_consultant_response
# strips), so extracting ".response" here would strip a level. The old Gemini
# CLI wrapped output in {"response": "..."} and needed that argument.
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
