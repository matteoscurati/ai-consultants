#!/bin/bash
# query_cursor.sh - Query Cursor CLI
#
# Usage: ./query_cursor.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CURSOR_MODEL   - Model to use (default: composer-2.5)
#   CURSOR_TIMEOUT - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Integrator" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/cursor_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Cursor"

# API-mode-only knob; say so rather than ignoring it silently (see common.sh).
warn_effort_ignored_in_cli "Cursor"
MODEL_USED="${CURSOR_MODEL:-cursor}"

# --- Check prerequisites and exact Cursor identity ---
check_command "$CURSOR_CMD" "Cursor CLI" "curl https://cursor.com/install -fsS | bash" || exit 1

cursor_cli_supports_required_interface() {
    local help flag
    if ! help=$(run_with_timeout 8 "$CURSOR_CMD" --help 2>&1); then
        CURSOR_PROBE_REASON="Cursor Agent help probe timed out or failed"
        return 1
    fi
    grep -Fq 'Start the Cursor Agent' <<<"$help" || return 1
    for flag in --print --output-format --mode --model --list-models --workspace --trust; do
        grep -q -- "$flag" <<<"$help" || return 1
    done
}

cursor_cli_exposes_requested_model() {
    local models
    if ! models=$(run_with_timeout 10 "$CURSOR_CMD" --list-models 2>&1); then
        CURSOR_PROBE_REASON="Cursor Agent model inventory timed out, failed, or requires login"
        printf '%s\n' "$models" >&2
        return 1
    fi
    if ! grep -Fq -- "$CURSOR_MODEL" <<<"$models"; then
        CURSOR_PROBE_REASON="Cursor Agent model inventory does not include $CURSOR_MODEL"
        return 1
    fi
}

CURSOR_PROBE_REASON="Cursor Agent lacks the required read-only interface"
if ! cursor_cli_supports_required_interface; then
    log_error "[Cursor] $CURSOR_PROBE_REASON"
    exit 1
fi
if ! cursor_cli_exposes_requested_model; then
    log_error "[Cursor] $CURSOR_PROBE_REASON"
    exit 1
fi

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Cursor" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)
CURSOR_RUNTIME_DIR=""
cleanup() {
    rm -f "$TEMP_OUTPUT" "${TEMP_OUTPUT}.err"
    local temp_prefix="${TMPDIR:-/tmp}"
    temp_prefix="${temp_prefix%/}/ai-consultants-cursor."
    if [[ -n "$CURSOR_RUNTIME_DIR" && "$CURSOR_RUNTIME_DIR" == "$temp_prefix"* ]]; then
        rm -rf -- "$CURSOR_RUNTIME_DIR"
    fi
}
trap cleanup EXIT

runtime_base="${TMPDIR:-/tmp}"
runtime_base="${runtime_base%/}"
CURSOR_RUNTIME_DIR=$(mktemp -d "$runtime_base/ai-consultants-cursor.XXXXXX")
chmod 700 "$CURSOR_RUNTIME_DIR"
isolated_workspace="$CURSOR_RUNTIME_DIR/workspace"
mkdir -p "$isolated_workspace"
chmod 700 "$isolated_workspace"

# Ask mode is Cursor's read-only Q&A contract. The empty temporary workspace
# prevents the advisory consultant from inheriting this repository's rules or
# files, while --workspace makes that boundary explicit to the CLI.
CMD_ARGS=("$CURSOR_CMD" "-p" "--mode" "ask" "--trust" "--workspace" "$isolated_workspace" "--output-format" "text")
if [[ -n "${CURSOR_MODEL:-}" ]]; then
    CMD_ARGS+=("--model" "$CURSOR_MODEL")
fi

if run_query \
        "Cursor" \
        "$TEMP_OUTPUT" \
        "$CURSOR_TIMEOUT_SECONDS" \
        "${CMD_ARGS[@]}" "$FULL_QUERY" < /dev/null; then
    exit_code=0
else
    exit_code=$?
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Post-processing: use shared helper ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY" \
    "$MODEL_USED" "capability-probed" "$MODEL_USED"

cat "$OUTPUT_FILE"
exit $exit_code
