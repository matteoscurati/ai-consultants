#!/bin/bash
# query_claude.sh - Query Claude CLI or API
#
# Usage: ./query_claude.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CLAUDE_MODEL - Model to use (default: claude-fable-5-1)
#   CLAUDE_TIMEOUT - Timeout in seconds (default: 240)
#   CLAUDE_USE_API - Use API mode instead of CLI (default: false)
#   CLAUDE_API_MAX_TOKENS - API thinking + visible-output budget (default: 16384)
#   ANTHROPIC_API_KEY - API key for API mode
#   CLAUDE_REASONING_EFFORT - Optional CLI/API reasoning effort
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
MODEL_USED="${CLAUDE_MODEL:-claude-fable-5-1}"

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
CLAUDE_SUPPORTS_AUTH_STATUS=false

claude_cli_supports_advisory_contract() {
    local help flag
    if ! help=$(run_with_timeout 8 "$CLAUDE_CMD" --help 2>&1); then
        return 1
    fi
    for flag in --print --model --output-format --no-session-persistence \
        --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode; do
        grep -q -- "$flag" <<<"$help" || return 1
    done
    if grep -Eq '^[[:space:]]+auth([[:space:]]|$)' <<<"$help"; then
        CLAUDE_SUPPORTS_AUTH_STATUS=true
    fi
}

claude_cli_is_authenticated() {
    local status
    if ! status=$(run_with_timeout 12 "$CLAUDE_CMD" auth status 2>&1); then
        return 1
    fi
    printf '%s' "$status" | jq -e '.loggedIn == true' >/dev/null 2>&1
}

if is_api_mode "claude"; then
    # --- API Mode ---
    log_api_mode_status "claude"
    if ! validate_api_mode "claude"; then
        build_error_response "$CONSULTANT_NAME" "$MODEL_USED" "$(get_persona_name "$CONSULTANT_NAME")" \
            "missing_anthropic_api_key_pre_dispatch" 0 "$MODEL_USED" requested-only > "$OUTPUT_FILE"
        rm -f "$TEMP_OUTPUT"
        cat "$OUTPUT_FILE"
        exit 1
    fi

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
else
    # --- CLI Mode ---
    log_api_mode_status "claude"
    check_command "$CLAUDE_CMD" "Claude CLI" "Visit https://docs.anthropic.com/en/docs/claude-code" || exit 1

    if ! claude_cli_supports_advisory_contract; then
        log_error "[$CONSULTANT_NAME] Claude CLI help probe timed out or lacks the stateless advisory interface"
        exit_code=1
        effort_ok=false
    elif [[ "$CLAUDE_SUPPORTS_AUTH_STATUS" == "true" ]]; then
        if ! claude_cli_is_authenticated; then
            log_error "[$CONSULTANT_NAME] Claude CLI reports logged-out auth or its auth probe timed out"
            exit_code=1
            effort_ok=false
        else
            effort_ok=true
        fi
    else
        log_warn "[$CONSULTANT_NAME] Claude CLI does not expose 'auth status'; dispatch will surface authentication errors"
        effort_ok=true
    fi

    # Optional CLI effort control. Unset leaves the CLI's own default alone;
    # when set, pass --effort through after the shared validation gate. Do not
    # invent a local allowlist — the provider rejects what it does not accept.
    CLAUDE_ARGS=("$CLAUDE_CMD" --print --model "$MODEL_USED" --output-format stream-json --verbose \
        --no-session-persistence --setting-sources "" --tools "" \
        --strict-mcp-config --mcp-config '{"mcpServers":{}}' --permission-mode plan)
    if [[ -n "${CLAUDE_REASONING_EFFORT:-}" ]]; then
        source "$SCRIPT_DIR/lib/api.sh"
        if ! cli_effort=$(validate_reasoning_effort "$CLAUDE_REASONING_EFFORT" "$CONSULTANT_NAME"); then
            effort_ok=false
            exit_code=1
        else
            CLAUDE_ARGS+=(--effort "$cli_effort")
        fi
    fi

    if [[ "$effort_ok" == "true" ]]; then
        # JSON output exposes provider-measured usage and cost. In particular,
        # output_tokens includes adaptive thinking that is absent from .result.
        # Keep failures inside an explicit conditional so `set -e` cannot skip
        # exit_code assignment (same guard as the API branch).
        if echo "$FULL_QUERY" | run_query \
                "Claude" \
                "$TEMP_OUTPUT" \
                "$CLAUDE_TIMEOUT_SECONDS" \
                "${CLAUDE_ARGS[@]}"; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")
MODEL_IDENTITY_SOURCE="requested-only"
EFFECTIVE_MODEL="$MODEL_USED"
if is_api_mode "claude"; then
    EFFECTIVE_MODEL="${_API_RESPONSE_MODEL:-$MODEL_USED}"
    MODEL_IDENTITY_SOURCE="${_API_MODEL_IDENTITY_SOURCE:-requested-only}"
fi

# Parse even failed runs: terminal billing and partial usage remain evidence.
PROVIDER_COST=""
_TOK=0 _TOK_IN=0 _TOK_OUT=0 _TOK_SRC=estimated
BILLING_MODELS='[]'
if ! is_api_mode "claude" && [[ -s "$TEMP_OUTPUT" ]]; then
    if ! CLI_ENVELOPE=$(jq -Rs -f "$SCRIPT_DIR/lib/claude_stream.jq" "$TEMP_OUTPUT" 2>/dev/null); then
        log_error "[$CONSULTANT_NAME] Cannot parse Claude CLI stream"
        CLI_ENVELOPE='{"success":false,"input_tokens":0,"output_tokens":0,"tokens_source":"estimated","billing_models":[]}'
        [[ $exit_code -ne 0 ]] || exit_code=1
    fi
    CLI_REPORTED_MODEL=$(printf '%s' "$CLI_ENVELOPE" | jq -r '.content_model // empty')
    if [[ -n "$CLI_REPORTED_MODEL" ]]; then
        EFFECTIVE_MODEL="$CLI_REPORTED_MODEL"
        MODEL_IDENTITY_SOURCE=provider-reported
    else
        log_warn "[$CONSULTANT_NAME] Stream does not attest one valid content model"
    fi
    RAW_RESPONSE=$(printf '%s' "$CLI_ENVELOPE" | jq -r '.result // ""')
    _TOK_IN=$(printf '%s' "$CLI_ENVELOPE" | jq -r '.input_tokens')
    _TOK_OUT=$(printf '%s' "$CLI_ENVELOPE" | jq -r '.output_tokens')
    _TOK=$((_TOK_IN + _TOK_OUT))
    _TOK_SRC=$(printf '%s' "$CLI_ENVELOPE" | jq -r '.tokens_source')
    PROVIDER_COST=$(printf '%s' "$CLI_ENVELOPE" | jq -r '.cost // empty')
    BILLING_MODELS=$(printf '%s' "$CLI_ENVELOPE" | jq -c '.billing_models')
    if [[ "$_TOK_SRC" == estimated ]]; then
        read -r _TOK _TOK_SRC _TOK_IN _TOK_OUT <<< "$(resolve_response_tokens "$FULL_QUERY" "$RAW_RESPONSE")"
    fi
    if ! printf '%s' "$CLI_ENVELOPE" | jq -e '.success' >/dev/null; then
        [[ $exit_code -ne 0 ]] || exit_code=1
    fi
fi

# Failed API responses can still carry measured usage.
if is_api_mode "claude" && [[ -n "${_API_TOKEN_SPLIT:-}" ]]; then
    read -r _TOK _TOK_SRC _TOK_IN _TOK_OUT <<< "$(resolve_response_tokens "$FULL_QUERY" "$(cat "$TEMP_OUTPUT")")"
fi

# --- Post-processing: wrap in full schema using shared helpers ---
if [[ $exit_code -eq 0 && -s "$TEMP_OUTPUT" ]]; then
    if is_api_mode "claude"; then
        RAW_RESPONSE=$(cat "$TEMP_OUTPUT")
        read -r _TOK _TOK_SRC _TOK_IN _TOK_OUT <<< "$(resolve_response_tokens "$FULL_QUERY" "$RAW_RESPONSE")"
    fi
    clear_api_token_split
    rm -f "$TEMP_OUTPUT"

    if NORMALIZED_RESPONSE=$(normalize_consultant_response_text "$RAW_RESPONSE"); then
        normalization_rc=0
    else
        normalization_rc=$?
    fi
    if [[ $normalization_rc -eq 0 ]]; then
        build_structured_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" "$NORMALIZED_RESPONSE" "$LATENCY_MS" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "$PROVIDER_COST" "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" > "$OUTPUT_FILE"
    elif [[ $normalization_rc -eq 1 ]]; then
        build_fallback_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" "$NORMALIZED_RESPONSE" "$LATENCY_MS" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "$PROVIDER_COST" "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" > "$OUTPUT_FILE"
    else
        log_error "[$CONSULTANT_NAME] Provider returned malformed, truncated, or schema-invalid JSON"
        build_error_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" \
            "Provider returned malformed, truncated, or schema-invalid JSON" "$LATENCY_MS" \
            "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "$PROVIDER_COST" > "$OUTPUT_FILE"
        exit_code=1
    fi
else
    [[ $exit_code -ne 0 ]] || exit_code=1
    rm -f "$TEMP_OUTPUT"
    build_error_response "$CONSULTANT_NAME" "$EFFECTIVE_MODEL" "$PERSONA_NAME" "Query failed or incomplete terminal stream (exit code $exit_code)" "$LATENCY_MS" "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" "$_TOK" "$_TOK_SRC" "$_TOK_IN" "$_TOK_OUT" "$PROVIDER_COST" > "$OUTPUT_FILE"
fi

if ! is_api_mode "claude"; then
    if response_tmp=$(mktemp); then
        if jq --argjson models "$BILLING_MODELS" '.metadata.billing_models = $models' "$OUTPUT_FILE" > "$response_tmp" \
                && mv "$response_tmp" "$OUTPUT_FILE"; then :; else
            log_warn "[$CONSULTANT_NAME] Could not annotate billing models; original envelope retained"
        fi
        rm -f "$response_tmp"
    fi
fi
cat "$OUTPUT_FILE"
exit $exit_code
