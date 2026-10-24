#!/bin/bash
# query_meta.sh - Query Meta Muse via the Muse Code CLI (muse exec) or the Meta Model API
#
# Usage: ./query_meta.sh "question" [context_file] [output_file]
#
# Environment variables:
#   META_MODEL            - Model ID (default: muse-wonder-1.0; standard/economy: muse-spark-1.3)
#   META_REASONING_EFFORT - minimal|low|medium|high|xhigh|max (default: high; maximum tier: max)
#   META_TIMEOUT          - Timeout in seconds (default: 0, no limit)
#   META_API_MAX_TOKENS   - API reasoning + visible completion budget (default: 32768)
#   META_USE_API          - Use the Meta Model API instead of the CLI (default: true
#                           when META_API_KEY is set, otherwise false)
#   META_CMD              - CLI command (default: muse)
#   META_API_KEY          - Meta Model API key (required for API mode)
#   ENABLE_PERSONA        - Enable "The Systems Thinker" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/meta_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Meta"

# Contributor-mode models let Meta train on the prompt and context. They are
# never a default; say so when one is pinned.
if [[ "${META_MODEL:-}" == *-contributor ]]; then
    log_warn "[$CONSULTANT_NAME] $META_MODEL runs in Contributor mode: Meta may use the prompt, context and response to train its models"
fi

# --- API mode: delegate to the shared API-consultant runner ---
if is_api_mode "meta"; then
    log_api_mode_status "meta"
    source "$SCRIPT_DIR/lib/api_query.sh"
    run_api_consultant "$CONSULTANT_NAME" "$QUERY" "$CONTEXT_FILE" "$OUTPUT_FILE"
    exit $?
fi

# --- CLI mode (Muse Code) ---
log_api_mode_status "meta"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "$CONSULTANT_NAME" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)
PROMPT_FILE=$(mktemp)
META_CLI_VERSION=""
META_WORKSPACE=""
cleanup() {
    rm -f "$TEMP_OUTPUT" "${TEMP_OUTPUT}.err" "$PROMPT_FILE"
    remove_cli_workspace meta "$META_WORKSPACE"
}
trap cleanup EXIT

meta_cli_supports_required_interface() {
    local help flag
    help=$("$META_CMD" exec --help 2>&1 || true)
    for flag in --prompt-file --model --reasoning-effort --contributor-mode \
        --no-session-log --sandbox-network --disable-approval --workspace \
        --disable-shell --disable-write --disable-web-tools \
        --disable-request-user-input --no-foreign-personal-context; do
        grep -q -- "$flag" <<< "$help" || return 1
    done
}

check_command "$META_CMD" "Muse Code CLI" "curl -fsSL https://dev.meta.ai/install.sh | sh (then run muse once to sign in)" || exit 1
META_CLI_VERSION=$("$META_CMD" --version 2>/dev/null | head -1 || true)
[[ -n "$META_CLI_VERSION" ]] || META_CLI_VERSION=unknown
meta_cli_supports_required_interface || {
    log_error "[$CONSULTANT_NAME] Muse Code CLI lacks a required muse exec flag (reported version: $META_CLI_VERSION)"
    exit 1
}

# Muse models always reason, so none is rejected before dispatch. An empty
# setting leaves the CLI's own level.
META_CLI_EFFORT=""
if [[ -n "${META_REASONING_EFFORT:-}" ]]; then
    source "$SCRIPT_DIR/lib/api.sh"
    META_CLI_EFFORT=$(validate_reasoning_effort "$META_REASONING_EFFORT" "$CONSULTANT_NAME") || exit 1
    if [[ "$META_CLI_EFFORT" == none ]]; then
        log_error "[$CONSULTANT_NAME] $META_MODEL always reasons: META_REASONING_EFFORT must be minimal|low|medium|high|xhigh|max"
        exit 1
    fi
fi

# The prompt goes through --prompt-file: never argv (process list, ARG_MAX).
# Muse Code is an agent, so it runs advisory-only: a private empty workspace,
# no shell, no workspace writes, no web tools, no network in the sandbox and no
# personal rules or skills; the built context already holds every file the
# consultant should see. A headless run cannot answer approval or user-input
# prompts, so both are off. Subscriptions default to Contributor mode, so it is
# switched off on every run, and no session log is kept.
printf '%s' "$FULL_QUERY" > "$PROMPT_FILE"
META_ARGS=("$META_CMD" exec --prompt-file "$PROMPT_FILE" --model "$META_MODEL"
    --contributor-mode off --no-session-log --sandbox-network restricted
    --disable-shell --disable-write --disable-web-tools --disable-approval
    --disable-request-user-input --no-foreign-personal-context)
[[ -z "$META_CLI_EFFORT" ]] || META_ARGS+=(--reasoning-effort "$META_CLI_EFFORT")
META_WORKSPACE=$(make_cli_workspace meta)
[[ -z "$META_WORKSPACE" ]] || META_ARGS+=(--workspace "$META_WORKSPACE")

if (cd "${META_WORKSPACE:-.}" \
        && run_query "$CONSULTANT_NAME" "$TEMP_OUTPUT" "$META_TIMEOUT_SECONDS" "${META_ARGS[@]}") </dev/null; then
    exit_code=0
else
    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="$META_MODEL"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
if process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
        "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY"; then
    :
else
    response_rc=$?
    [[ $exit_code -ne 0 ]] || exit_code=$response_rc
fi

if [[ -s "$OUTPUT_FILE" ]]; then
    response_tmp=$(mktemp)
    if jq --arg cli_version "$META_CLI_VERSION" '
            .metadata.cli_version = $cli_version |
            .metadata.cli_compatibility = "capability-probed"
        ' "$OUTPUT_FILE" > "$response_tmp"; then
        mv "$response_tmp" "$OUTPUT_FILE"
    else
        rm -f "$response_tmp"
    fi
fi

cat "$OUTPUT_FILE"
exit $exit_code
