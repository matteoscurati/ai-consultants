#!/bin/bash
# query_codex.sh - Query OpenAI Codex CLI or API (isolated CLI runtime)
#
# Usage: ./query_codex.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CODEX_MODEL - Model to use (default: gpt-6-astra)
#   CODEX_TIMEOUT - Timeout in seconds (default: 180)
#   CODEX_USE_API - Use API mode instead of CLI (default: false)
#   OPENAI_API_KEY - API key for API mode
#   CODEX_REASONING_EFFORT - Optional CLI/API reasoning effort
#   ENABLE_PERSONA - Enable "The Pragmatist" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/codex_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Codex"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Codex" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)
CODEX_RUNTIME_DIR=""
exit_code=1

cleanup() {
    rm -f "$TEMP_OUTPUT" "${TEMP_OUTPUT}.err"

    # CODEX_RUNTIME_DIR is always created by this script under the system temp
    # directory. Validate the prefix before recursive cleanup so an unexpected
    # empty or overridden value can never widen the deletion target.
    local temp_prefix="${TMPDIR:-/tmp}"
    temp_prefix="${temp_prefix%/}/ai-consultants-codex."
    if [[ -n "$CODEX_RUNTIME_DIR" && "$CODEX_RUNTIME_DIR" == "$temp_prefix"* ]]; then
        rm -rf -- "$CODEX_RUNTIME_DIR"
    fi
}
trap cleanup EXIT

if is_api_mode "codex"; then
    # --- API Mode ---
    log_api_mode_status "codex"
    if ! validate_api_mode "codex"; then
        build_error_response "$CONSULTANT_NAME" "$CODEX_MODEL" "$(get_persona_name "$CONSULTANT_NAME")" \
            "missing_openai_api_key_pre_dispatch" 0 "$CODEX_MODEL" requested-only > "$OUTPUT_FILE"
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
            "$CODEX_MODEL" \
            "$FULL_QUERY" \
            "$TEMP_OUTPUT" \
            "$CODEX_TIMEOUT_SECONDS"; then
        exit_code=0
    else
        exit_code=$?
    fi
else
    # --- CLI Mode (isolated HOME/CWD; auth via real CODEX_HOME) ---
    log_api_mode_status "codex"
    check_command "$CODEX_CMD" "Codex CLI" "npm install -g @openai/codex" || exit 1

    # Resolve the real Codex home BEFORE overriding HOME. --ignore-user-config
    # skips config.toml but auth still resolves through CODEX_HOME; repointing
    # it at the isolated home would break authentication.
    real_codex_home="${CODEX_HOME:-${HOME}/.codex}"

    runtime_base="${TMPDIR:-/tmp}"
    runtime_base="${runtime_base%/}"
    CODEX_RUNTIME_DIR=$(mktemp -d "$runtime_base/ai-consultants-codex.XXXXXX")
    chmod 700 "$CODEX_RUNTIME_DIR"

    isolated_home="$CODEX_RUNTIME_DIR/home"
    isolated_cwd="$CODEX_RUNTIME_DIR/workspace"
    prompt_file="$CODEX_RUNTIME_DIR/prompt.txt"
    payload_file="$CODEX_RUNTIME_DIR/payload.txt"
    mkdir -p "$isolated_home" "$isolated_cwd"
    chmod 700 "$isolated_home" "$isolated_cwd"
    printf '%s' "$FULL_QUERY" > "$prompt_file"
    : > "$payload_file"
    chmod 600 "$prompt_file" "$payload_file"

    source "$SCRIPT_DIR/lib/api.sh"
    effort_ok=true
    if ! cli_effort=$(resolve_codex_effort "$CODEX_MODEL" "${CODEX_REASONING_EFFORT:-}"); then
        effort_ok=false
        exit_code=1
    fi

    if [[ "$effort_ok" == "true" ]]; then
        # Isolated Codex headless contract (verified against codex-cli 0.146.0):
        #   HOME is ephemeral so ambient ~/.codex config, hooks, MCP, and
        #   project instructions stay outside the consultation.
        #   CODEX_HOME stays on the real auth store.
        #   --ignore-user-config is safe here only because we pin the model with
        #   -m. It also makes Codex ignore any -p <profile>, which is why we
        #   must not add -p.
        #   -s read-only: the consultant answers; it never edits.
        #   -C points at an empty temp dir so the host repo's AGENTS.md stays out
        #   (build_context.sh already inlined the relevant files into FULL_QUERY).
        #   trailing - reads the prompt from stdin (no ARG_MAX / process-list).
        #   -o writes the final agent message to a private payload file.
        CMD_ARGS=(
            env
            HOME="$isolated_home"
            CODEX_HOME="$real_codex_home"
            "$CODEX_CMD"
            exec
            --json
            --ephemeral
            --ignore-user-config
            --ignore-rules
            --skip-git-repo-check
            -m "$CODEX_MODEL"
            -s read-only
            -C "$isolated_cwd"
            -o "$payload_file"
        )

        if [[ -n "$cli_effort" ]]; then
            CMD_ARGS+=("-c" "model_reasoning_effort=${cli_effort}")
        fi

        CMD_ARGS+=("-")

        # run_query buffers stdin once and replays it on each retry.
        if run_query \
                "Codex" \
                "$TEMP_OUTPUT" \
                "$CODEX_TIMEOUT_SECONDS" \
                "${CMD_ARGS[@]}" < "$prompt_file"; then
            exit_code=0
        else
            exit_code=$?
        fi

        # stdout is event telemetry; the -o payload alone is answer content.
        # input_tokens is treated as total input, including the cached subset.
        # Preserve the subset separately so estimates can be audited.
        if ! usage=$(jq -Rs '[split("\n")[] | fromjson? | objects | select(.type == "turn.completed") | .usage | objects] | last // {}' "$TEMP_OUTPUT" 2>/dev/null); then
            usage='{}'
        fi
        if printf '%s' "$usage" | jq -e 'all(.input_tokens, .output_tokens; type == "number" and . >= 0 and floor == .)' >/dev/null 2>&1; then
            set_api_token_split "$(printf '%s' "$usage" | jq -r '.input_tokens')" \
                "$(printf '%s' "$usage" | jq -r '.output_tokens')"
        fi
        CLI_CACHED_INPUT=$(printf '%s' "$usage" | jq -c '.cached_input_tokens | if type == "number" and . >= 0 and floor == . then . else null end')

        # Prefer the -o payload over stdout only when the run succeeded.
        # A non-empty payload must never rewrite a timeout, auth error, or
        # exhausted-retry into success — a partial answer would enter synthesis
        # as a healthy consultation. Exit 0 with an empty payload remains a
        # diagnosed failure.
        if [[ $exit_code -eq 0 ]]; then
            if [[ -s "$payload_file" ]]; then
                cp "$payload_file" "$TEMP_OUTPUT"
            else
                exit_code=1
                log_warn "[$CONSULTANT_NAME] Codex wrote an empty last-message payload"
                printf 'Codex wrote an empty last-message payload\n' > "${TEMP_OUTPUT}.err"
            fi
        fi
    fi
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="${CODEX_MODEL:-gpt-6-astra}"
MODEL_IDENTITY_SOURCE="requested-only"
EFFECTIVE_MODEL="$MODEL_USED"
if is_api_mode "codex"; then
    EFFECTIVE_MODEL="${_API_RESPONSE_MODEL:-$MODEL_USED}"
    MODEL_IDENTITY_SOURCE="${_API_MODEL_IDENTITY_SOURCE:-requested-only}"
fi
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
# process_consultant_response returns the consultant exit code. Guard the call
# so a non-zero return does not abort under set -e before we cat the output
# file and exit with that code.
if process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
        "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY" \
        "$MODEL_USED" "$MODEL_IDENTITY_SOURCE" "$EFFECTIVE_MODEL"; then
    :
else
    response_rc=$?
    [[ $exit_code -ne 0 ]] || exit_code=$response_rc
fi

if response_tmp=$(mktemp); then
    if jq --arg model "$MODEL_USED" --argjson cached "${CLI_CACHED_INPUT:-null}" '
        .metadata.cost_source = (if (.metadata.tokens_used // 0) == 0 then "unavailable"
            elif $model == "gpt-6-astra" and (.metadata.tokens_input // 0) > 272000 then "estimated-long-context-standard-rates"
            else "estimated-standard-rates" end) |
        .metadata.cost_note = "Estimate includes applicable long-context pricing; excludes cache writes, cache discounts and service-tier adjustments; not a provider invoice" |
        if $cached != null then .metadata.tokens_cached_input = $cached else . end' \
            "$OUTPUT_FILE" > "$response_tmp" && mv "$response_tmp" "$OUTPUT_FILE"; then :; else
        log_warn "[$CONSULTANT_NAME] Could not annotate cost estimate; original envelope retained"
    fi
    rm -f "$response_tmp"
fi
cat "$OUTPUT_FILE"
exit $exit_code
