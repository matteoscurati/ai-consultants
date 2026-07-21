#!/bin/bash
# query_qwen3.sh - Query Qwen3 via CLI (qwen-code) or HTTP API
#
# Usage: ./query_qwen3.sh "question" [context_file] [output_file]
#
# Environment variables:
#   QWEN3_MODEL     - Model to use (default: qwen3.7-max)
#   QWEN3_TIMEOUT   - Timeout in seconds (default: 180)
#   QWEN3_USE_API   - Use API mode instead of CLI (default: false)
#   QWEN3_API_KEY   - API key for the endpoint in QWEN3_API_URL (required for API mode)
#   QWEN3_REASONING_EFFORT - none|minimal|low|medium|high|xhigh|max (API mode,
#                     OpenAI-compatible wire format only - see docs/RECIPES.md)
#   ENABLE_PERSONA  - Enable "The Analyst" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/qwen3_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Qwen3"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Qwen3" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution (CLI or API mode) ---
TEMP_OUTPUT=$(mktemp)

if is_api_mode "qwen3"; then
    # --- API Mode (DashScope, or any endpoint set via QWEN3_API_URL) ---
    log_api_mode_status "qwen3"
    validate_api_mode "qwen3" || exit 1

    # An empty model would be sent as "model": "" and rejected with a 400 by
    # every endpoint. In CLI mode an empty value is meaningful (let the CLI use
    # its own configured model); here it is only ever a misconfiguration.
    if [[ -z "${QWEN3_MODEL:-}" ]]; then
        log_error "[Qwen3] API mode requires QWEN3_MODEL to be set"
        exit 1
    fi

    source "$SCRIPT_DIR/lib/api_query.sh"

    # Keep the failure inside an explicit conditional: a bare call whose
    # function returns non-zero aborts the script under `set -e` before
    # exit_code is read, so no error-response envelope is ever written and
    # the output file is left empty. Same guard run_query uses.
    if run_api_mode_query \
            "$CONSULTANT_NAME" \
            "$QWEN3_MODEL" \
            "$FULL_QUERY" \
            "$TEMP_OUTPUT" \
            "$QWEN3_TIMEOUT_SECONDS"; then
        exit_code=0
    else
        exit_code=$?
    fi
else
    # --- CLI Mode (qwen-code) ---
    log_api_mode_status "qwen3"

    # Emitted BEFORE the CLI check: it diagnoses the configuration, so it must
    # reach a user whose CLI is also missing. For qwen specifically the level
    # lives in ~/.qwen/settings.json (model.reasoningEffort) or /effort.
    warn_effort_ignored_in_cli "Qwen3"

    check_command "$QWEN3_CMD" "Qwen CLI" "npm install -g @qwen-code/qwen-code@latest" || exit 1

    # qwen-code uses -p for prompt, reads from stdin with -p -
    # Build command args with optional model
    QWEN_ARGS=("$QWEN3_CMD")
    if [[ -n "${QWEN3_MODEL:-}" ]]; then
        QWEN_ARGS+=("-m" "$QWEN3_MODEL")
    fi
    QWEN_ARGS+=("-p" "-")

    echo "$FULL_QUERY" | run_query \
        "Qwen3" \
        "$TEMP_OUTPUT" \
        "$QWEN3_TIMEOUT_SECONDS" \
        "${QWEN_ARGS[@]}"

    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
# Not a model name: when QWEN3_MODEL is empty the -m flag is skipped above and
# the CLI uses its OWN configured model, which this script cannot know. Naming
# any specific model here would mislabel the response.
MODEL_USED="${QWEN3_MODEL:-unknown}"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY"

cat "$OUTPUT_FILE"
exit $exit_code
