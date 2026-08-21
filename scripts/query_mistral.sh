#!/bin/bash
# query_mistral.sh - Query Mistral Vibe CLI or API
#
# Usage: ./query_mistral.sh "question" [context_file] [output_file]
#
# Environment variables:
#   MISTRAL_MODEL - API model ID (default: mistral-large-3)
#   MISTRAL_CLI_MODEL - Vibe model alias (default: mistral-medium-3.5)
#   MISTRAL_TIMEOUT - Timeout in seconds (default: 180)
#   MISTRAL_USE_API - Use API mode instead of CLI (default: false)
#   MISTRAL_API_KEY - API key for API mode
#   ENABLE_PERSONA - Enable "The Devil's Advocate" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/mistral_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Mistral"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Mistral Vibe" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)
MISTRAL_RUNTIME_DIR=""
MODEL_IDENTITY_SOURCE="requested-only"
EFFECTIVE_MODEL=""

mistral_cli_supports_required_interface() {
    local help flag
    if ! help=$(run_with_timeout 8 "$MISTRAL_CMD" --help 2>&1); then
        return 1
    fi
    for flag in --prompt --output --agent --workdir --max-turns; do
        grep -q -- "$flag" <<<"$help" || return 1
    done
    grep -Eq 'builtin:.*plan' <<<"$help" || return 1
    grep -Fq 'VIBE_*' <<<"$help"
}

cleanup() {
    rm -f "$TEMP_OUTPUT" "${TEMP_OUTPUT}.err"
    local temp_prefix="${TMPDIR:-/tmp}"
    temp_prefix="${temp_prefix%/}/ai-consultants-mistral."
    if [[ -n "$MISTRAL_RUNTIME_DIR" && "$MISTRAL_RUNTIME_DIR" == "$temp_prefix"* ]]; then
        rm -rf -- "$MISTRAL_RUNTIME_DIR"
    fi
}
trap cleanup EXIT

if is_api_mode "mistral"; then
    # --- API Mode ---
    log_api_mode_status "mistral"
    validate_api_mode "mistral" || exit 1

    source "$SCRIPT_DIR/lib/api_query.sh"

    # Keep the failure inside an explicit conditional: a bare call whose
    # function returns non-zero aborts the script under `set -e` before
    # exit_code is read, so no error-response envelope is ever written and
    # the output file is left empty. Same guard run_query uses.
    if run_api_mode_query \
            "$CONSULTANT_NAME" \
            "$MISTRAL_MODEL" \
            "$FULL_QUERY" \
            "$TEMP_OUTPUT" \
            "$MISTRAL_TIMEOUT_SECONDS"; then
        exit_code=0
    else
        exit_code=$?
    fi
else
    # --- CLI Mode ---
    log_api_mode_status "mistral"
    warn_effort_ignored_in_cli "Mistral"
    check_command "$MISTRAL_CMD" "Mistral Vibe CLI" "pip install mistral-vibe" || exit 1
    if ! mistral_cli_supports_required_interface; then
        log_error "[$CONSULTANT_NAME] Mistral Vibe lacks the required bounded read-only interface or its help probe timed out"
        exit 1
    fi

    runtime_base="${TMPDIR:-/tmp}"
    runtime_base="${runtime_base%/}"
    MISTRAL_RUNTIME_DIR=$(mktemp -d "$runtime_base/ai-consultants-mistral.XXXXXX")
    chmod 700 "$MISTRAL_RUNTIME_DIR"
    isolated_workspace="$MISTRAL_RUNTIME_DIR/workspace"
    mkdir -p "$isolated_workspace"
    chmod 700 "$isolated_workspace"

    if run_query \
            "Mistral Vibe" \
            "$TEMP_OUTPUT" \
            "$MISTRAL_TIMEOUT_SECONDS" \
            env VIBE_ACTIVE_MODEL="$MISTRAL_CLI_MODEL" \
            "$MISTRAL_CMD" -p "$FULL_QUERY" --output text --agent plan \
            --workdir "$isolated_workspace" --max-turns 1 < /dev/null; then
        exit_code=0
    else
        exit_code=$?
    fi
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
if is_api_mode "mistral"; then
    MODEL_USED="$MISTRAL_MODEL"
    EFFECTIVE_MODEL="${_API_RESPONSE_MODEL:-$MODEL_USED}"
    MODEL_IDENTITY_SOURCE="${_API_MODEL_IDENTITY_SOURCE:-requested-only}"
else
    MODEL_USED="$MISTRAL_CLI_MODEL"
    EFFECTIVE_MODEL="$MODEL_USED"
fi
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: wrap in full schema using shared helpers ---
if [[ $exit_code -eq 0 && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    RAW_RESPONSE=$(cat "$TEMP_OUTPUT")
    read -r _TOK _TOK_SRC _TOK_IN _TOK_OUT <<< "$(resolve_response_tokens "$FULL_QUERY" "$RAW_RESPONSE")"
    clear_api_token_split
    rm -f "$TEMP_OUTPUT"

    # Try to parse as structured JSON
    if echo "$RAW_RESPONSE" | jq -e '.response.summary' > /dev/null 2>&1; then
        build_structured_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" "$RAW_RESPONSE" "$LATENCY_MS" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "" "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" > "$OUTPUT_FILE"
    else
        build_fallback_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" "$RAW_RESPONSE" "$LATENCY_MS" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "" "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" > "$OUTPUT_FILE"
    fi
else
    rm -f "$TEMP_OUTPUT"
    build_error_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" "Query failed with exit code $exit_code" "$LATENCY_MS" "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" > "$OUTPUT_FILE"
fi

cat "$OUTPUT_FILE"
exit $exit_code
