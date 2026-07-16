#!/bin/bash
# query_kimi.sh - Query Kimi CLI (v2.9)
#
# Usage: ./query_kimi.sh "question" [context_file] [output_file]
#
# Environment variables:
#   KIMI_MODEL     - Kimi CLI model alias (default: kimi-code/k3)
#   KIMI_TIMEOUT   - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Eastern Sage" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/kimi_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Kimi"

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Kimi" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)

# Check CLI prerequisite
check_command "$KIMI_CMD" "Kimi CLI" "curl -L code.kimi.com/install.sh | bash" || exit 1

# Kimi takes the prompt as the -p argument (it does NOT read stdin). The old
# `--quiet --input-format text` were NOT real flags on kimi 0.23.6 — commander
# rejected them ("unknown option --quiet") and Kimi never ran.
# Output format matters: `--output-format text` interleaves the model's
# chain-of-thought (each line bulleted "• ") and a "To resume this session:"
# footer with the actual answer, which breaks the JSON-envelope gate. stream-json
# instead emits one JSON object per line, so the real response is the assistant
# line's .content (extracted below). (-y/--yolo is rejected alongside -p, and kimi
# already declines tools for advisory questions, so no auto-approve flag is used.)
# Pass --model explicitly: KIMI_MODEL is a project-level override, while the
# CLI otherwise falls back to the user's config.toml and may silently use an
# older alias.
run_query \
    "Kimi" \
    "$TEMP_OUTPUT" \
    "$KIMI_TIMEOUT_SECONDS" \
    "$KIMI_CMD" --model "$KIMI_MODEL" -p "$FULL_QUERY" --output-format stream-json </dev/null

exit_code=$?

# Extract the model's response from the stream-json output: the
# {"role":"assistant","content":...} line's .content is our JSON envelope (as a
# string); drop kimi's {"role":"meta",...} session-resume line. -R + fromjson?
# tolerates any non-JSON line. process_consultant_response then de-fences + parses.
if [[ -s "$TEMP_OUTPUT" ]]; then
    # Take the LAST assistant message's .content (robust to streaming deltas /
    # multiple lines), tolerate non-object or non-JSON lines, and flatten a
    # block-array content ([{type,text},...]) -- so a stream-json schema variant
    # can't silently drop us to a persona-less confidence-5 fallback stub.
    kimi_content=$(_kimi_extract_content "$TEMP_OUTPUT")
    [[ -n "$kimi_content" ]] && printf '%s' "$kimi_content" > "$TEMP_OUTPUT"
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Configuration for response building ---
MODEL_USED="$KIMI_MODEL"
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

# --- Post-processing: use shared helper ---
process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
    "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"

cat "$OUTPUT_FILE"
exit $exit_code
