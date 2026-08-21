#!/bin/bash
# query_minimax.sh - Query MiniMax via CLI (mmx / mmx-cli) or HTTP API
#
# Usage: ./query_minimax.sh "question" [context_file] [output_file]
#
# Environment variables:
#   MINIMAX_MODEL     - Model to use (default: MiniMax-M2.7)
#   MINIMAX_TIMEOUT   - Timeout in seconds (default: 180)
#   MINIMAX_MAX_TOKENS - Visible + reasoning completion budget (default: 4096)
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
MINIMAX_SYSTEM_PROMPT=""
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    # mmx exposes a native system channel. Using it materially improves schema
    # adherence for M3; embedding these instructions in the user message was
    # observed to produce a complete-looking but unclosed/nested JSON object.
    MINIMAX_SYSTEM_PROMPT="$(get_persona "$CONSULTANT_NAME")

Respond in concise Markdown under 4000 characters. Do not emit JSON. Do not use tools or inspect files; answer solely from the supplied question and context."
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)
TEMP_OUTPUT=$(mktemp)

# Feed the user/context message through --messages-file - so code and secrets do
# not appear in argv and large contexts avoid ARG_MAX. The native system prompt
# contains only the persona and compact prose contract.
MMX_ARGS=("$MINIMAX_CMD" "text" "chat" "--non-interactive" "--quiet" "--no-color" "--output" "text")
if ! [[ "$MINIMAX_MAX_TOKENS" =~ ^[1-9][0-9]*$ ]]; then
    log_error "[$CONSULTANT_NAME] MINIMAX_MAX_TOKENS must be a positive integer (got: $MINIMAX_MAX_TOKENS)"
    build_error_response "$CONSULTANT_NAME" "${MINIMAX_MODEL:-unknown}" "$(get_persona_name "$CONSULTANT_NAME")" \
        "Invalid MINIMAX_MAX_TOKENS" 0 > "$OUTPUT_FILE"
    cat "$OUTPUT_FILE"
    exit 1
fi
MMX_ARGS+=("--max-tokens" "$MINIMAX_MAX_TOKENS")
if [[ -n "${MINIMAX_MODEL:-}" ]]; then
    MMX_ARGS+=("--model" "$MINIMAX_MODEL")
fi
if [[ -n "$MINIMAX_SYSTEM_PROMPT" ]]; then
    MMX_ARGS+=("--system" "$MINIMAX_SYSTEM_PROMPT")
fi
MMX_ARGS+=("--messages-file" -)
MINIMAX_MESSAGES=$(jq -n --arg content "$FULL_QUERY" '[{role: "user", content: $content}]')

# run_query reads stdin via `cat`; mmx ignores stdin here (prompt is in --message),
# so redirect from /dev/null to give `cat` an immediate EOF instead of blocking.
if printf '%s' "$MINIMAX_MESSAGES" | run_query "$CONSULTANT_NAME" "$TEMP_OUTPUT" "$MINIMAX_TIMEOUT_SECONDS" "${MMX_ARGS[@]}"; then
    exit_code=0
else
    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${MINIMAX_MODEL:-MiniMax-M2.7}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
if process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
        "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY"; then
    :
else
    response_rc=$?
    [[ $exit_code -ne 0 ]] || exit_code=$response_rc
fi

cat "$OUTPUT_FILE"
exit $exit_code
