#!/bin/bash
# query_claude.sh - Query Claude CLI or API
#
# Usage: ./query_claude.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CLAUDE_MODEL - Model to use (default: claude-opus-5)
#   CLAUDE_TIMEOUT - Timeout in seconds (default: 240)
#   CLAUDE_USE_API - Use API mode instead of CLI (default: false)
#   CLAUDE_API_MAX_TOKENS - API thinking + visible-output budget (default: 16384)
#   ANTHROPIC_API_KEY - API key for API mode
#   ENABLE_PERSONA - Enable "The Synthesizer" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/claude_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Claude"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
MODEL_USED="${CLAUDE_MODEL:-claude-opus-5}"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Claude" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)

if is_api_mode "claude"; then
    # --- API Mode ---
    log_api_mode_status "claude"
    validate_api_mode "claude" || exit 1

    source "$SCRIPT_DIR/lib/api_query.sh"

    # Keep the failure inside an explicit conditional: a bare call whose
    # function returns non-zero aborts the script under `set -e` before
    # exit_code is read, so no error-response envelope is ever written and
    # the output file is left empty. Same guard run_query uses.
    if run_api_mode_query \
            "$CONSULTANT_NAME" \
            "$MODEL_USED" \
            "$FULL_QUERY" \
            "$TEMP_OUTPUT" \
            "$CLAUDE_TIMEOUT_SECONDS"; then
        exit_code=0
    else
        exit_code=$?
    fi
warn_effort_ignored_in_cli "Claude"
else
    # --- CLI Mode ---
    log_api_mode_status "claude"
    check_command "$CLAUDE_CMD" "Claude CLI" "Visit https://docs.anthropic.com/en/docs/claude-code" || exit 1

    # JSON output exposes provider-measured usage and cost. In particular,
    # output_tokens includes adaptive thinking that is absent from .result.
    echo "$FULL_QUERY" | run_query \
        "Claude" \
        "$TEMP_OUTPUT" \
        "$CLAUDE_TIMEOUT_SECONDS" \
        "$CLAUDE_CMD" --print --model "$MODEL_USED" --output-format json

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: wrap in full schema using shared helpers ---
if [[ $exit_code -eq 0 && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    PROVIDER_COST=""
    if ! is_api_mode "claude"; then
        CLI_ENVELOPE=$(cat "$TEMP_OUTPUT")
        if ! echo "$CLI_ENVELOPE" | jq -e \
                '.type == "result" and (.result | type == "string")' >/dev/null 2>&1; then
            rm -f "$TEMP_OUTPUT"
            build_error_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
                "Claude CLI returned an invalid JSON result envelope" "$LATENCY_MS" > "$OUTPUT_FILE"
            cat "$OUTPUT_FILE"
            exit 1
        fi
        RAW_RESPONSE=$(echo "$CLI_ENVELOPE" | jq -r '.result')
        _TOK_IN=$(echo "$CLI_ENVELOPE" | jq -r \
            '([.modelUsage[]?
                | (.inputTokens // 0)
                  + (.cacheCreationInputTokens // 0)
                  + (.cacheReadInputTokens // 0)] | add)
             // ((.usage.input_tokens // 0)
                 + (.usage.cache_creation_input_tokens // 0)
                 + (.usage.cache_read_input_tokens // 0))')
        _TOK_OUT=$(echo "$CLI_ENVELOPE" | jq -r \
            '([.modelUsage[]? | (.outputTokens // 0)] | add)
             // (.usage.output_tokens // 0)')
        _TOK=$((_TOK_IN + _TOK_OUT))
        _TOK_SRC="measured"
        PROVIDER_COST=$(echo "$CLI_ENVELOPE" | jq -r \
            '[.modelUsage[]?.costUSD | numbers] | add // empty')
    else
        RAW_RESPONSE=$(cat "$TEMP_OUTPUT")
        read -r _TOK _TOK_SRC _TOK_IN _TOK_OUT <<< "$(resolve_response_tokens "$FULL_QUERY" "$RAW_RESPONSE")"
    fi
    clear_api_token_split
    rm -f "$TEMP_OUTPUT"

    # Try to parse as structured JSON
    if echo "$RAW_RESPONSE" | jq -e '.response.summary' > /dev/null 2>&1; then
        build_structured_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" "$RAW_RESPONSE" "$LATENCY_MS" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "$PROVIDER_COST" > "$OUTPUT_FILE"
    else
        build_fallback_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" "$RAW_RESPONSE" "$LATENCY_MS" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "$PROVIDER_COST" > "$OUTPUT_FILE"
    fi
else
    rm -f "$TEMP_OUTPUT"
    build_error_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" "Query failed with exit code $exit_code" "$LATENCY_MS" > "$OUTPUT_FILE"
fi

cat "$OUTPUT_FILE"
exit $exit_code
