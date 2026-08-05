#!/bin/bash
# query_codex.sh - Query OpenAI Codex CLI or API (isolated CLI runtime)
#
# Usage: ./query_codex.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CODEX_MODEL - Model to use (default: gpt-5.6-sol)
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
    validate_api_mode "codex" || exit 1

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

    cli_effort=""
    effort_ok=true
    if [[ -n "${CODEX_REASONING_EFFORT:-}" ]]; then
        # Keep the existing validate_reasoning_effort gate; pass the value
        # through and let the CLI reject what it does not accept.
        source "$SCRIPT_DIR/lib/api.sh"
        if ! cli_effort=$(validate_reasoning_effort "$CODEX_REASONING_EFFORT" "$CONSULTANT_NAME"); then
            effort_ok=false
            exit_code=1
        fi
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
MODEL_USED="${CODEX_MODEL:-gpt-5.6-sol}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
# process_consultant_response returns the consultant exit code. Guard the call
# so a non-zero return does not abort under set -e before we cat the output
# file and exit with that code.
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY" || true

cat "$OUTPUT_FILE"
exit $exit_code
