#!/bin/bash
# query_minimax.sh - Query MiniMax via CLI (mmx / mmx-cli) or HTTP API
#
# Usage: ./query_minimax.sh "question" [context_file] [output_file]
#
# Environment variables:
#   MINIMAX_MODEL     - Model to use (default: MiniMax-M2.7)
#   MINIMAX_TIMEOUT   - Timeout in seconds (default: 180)
#   MINIMAX_USE_API   - Use the HTTP API instead of the mmx CLI (default: false)
#   MINIMAX_CMD       - CLI command (default: mmx)
#   MINIMAX_API_KEY   - API key for the MiniMax API (required for API mode)
#   ENABLE_PERSONA    - Enable "The Pragmatic Optimizer" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/minimax_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="MiniMax"

# API-mode-only knob; say so rather than ignoring it silently (see common.sh).
warn_effort_ignored_in_cli "MiniMax"

# --- API mode: delegate to the shared API-consultant runner (unchanged path) ---
# CLI is the default (CLI-first); API is opt-in via MINIMAX_USE_API=true.
if is_api_mode "minimax"; then
    log_api_mode_status "minimax"
    source "$SCRIPT_DIR/lib/api_query.sh"
    run_api_consultant "$CONSULTANT_NAME" "$QUERY" "$CONTEXT_FILE" "$OUTPUT_FILE"
    exit $?
fi

# --- CLI mode (mmx) ---
log_api_mode_status "minimax"
check_command "$MINIMAX_CMD" "MiniMax CLI" "npm install -g mmx-cli (auth: mmx auth login)" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "MiniMax" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)
TEMP_OUTPUT=$(mktemp)

# mmx takes the prompt via --message (an argument, not stdin) and prints the
# model's text with --output text. The persona instruction already forces the
# model to emit our JSON envelope, so that plain text IS the envelope.
MMX_ARGS=("$MINIMAX_CMD" "text" "chat" "--non-interactive" "--quiet" "--no-color" "--output" "text")
if [[ -n "${MINIMAX_MODEL:-}" ]]; then
    MMX_ARGS+=("--model" "$MINIMAX_MODEL")
fi
MMX_ARGS+=("--message" "$FULL_QUERY")

# run_query reads stdin via `cat`; mmx ignores stdin here (prompt is in --message),
# so redirect from /dev/null to give `cat` an immediate EOF instead of blocking.
run_query "$CONSULTANT_NAME" "$TEMP_OUTPUT" "$MINIMAX_TIMEOUT_SECONDS" "${MMX_ARGS[@]}" </dev/null
exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${MINIMAX_MODEL:-MiniMax-M2.7}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY"

cat "$OUTPUT_FILE"
exit $exit_code
