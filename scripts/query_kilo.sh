#!/bin/bash
# query_kilo.sh - Query Kilo Code CLI
#
# Usage: ./query_kilo.sh "question" [context_file] [output_file]
#
# Environment variables:
#   KILO_MODEL   - Model to use (default: uses Kilo's internal provider)
#   KILO_TIMEOUT - Timeout in seconds (default: 180)
#   ENABLE_PERSONA - Enable "The Innovator" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/kilo_response.json}"

# --- Configuration ---
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Kilo"
MODEL_USED="${KILO_MODEL:-kilo}"

# --- Check prerequisites ---
check_command "$KILO_CMD" "Kilo Code CLI" "npm install -g @kilocode/cli" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Kilo Code" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)
TEMP_RAW=$(mktemp)
trap 'rm -f "$TEMP_OUTPUT" "$TEMP_RAW"' EXIT

# Build command args: run subcommand + --auto + --dir /tmp (prevent SKILL.md loading)
KILO_ARGS=("$KILO_CMD" "run" "--auto" "--dir" "/tmp")
if [[ -n "${KILO_MODEL:-}" && "${KILO_MODEL}" != "auto" ]]; then
    KILO_ARGS+=("--model" "$KILO_MODEL")
fi
KILO_ARGS+=("$FULL_QUERY")

# Use run_with_timeout for cross-platform support (Linux/macOS/POSIX)
log_info "Consulting Kilo Code (timeout: ${KILO_TIMEOUT_SECONDS}s)..."

if run_with_timeout "$KILO_TIMEOUT_SECONDS" "${KILO_ARGS[@]}" > "$TEMP_RAW" 2>&1; then
    exit_code=0
else
    exit_code=$?
fi

# --- Strip ANSI escape codes from Kilo's text output ---
if [[ -f "$TEMP_RAW" && -s "$TEMP_RAW" ]]; then
    # Kilo outputs plain text with ANSI codes; strip them for clean output
    CONTENT=$(LC_ALL=C sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$TEMP_RAW" | sed '/^$/d') || true

    if [[ -n "${CONTENT:-}" ]]; then
        exit_code=0
        log_success "[Kilo Code] Response received (${#CONTENT} chars)"
    else
        log_error "[Kilo Code] Could not extract response"
        exit_code=1
    fi
fi

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Post-processing: extract structure from markdown output ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

if [[ $exit_code -eq 0 && -n "${CONTENT:-}" ]]; then
    # Check if Kilo returned valid JSON (unlikely but handle it)
    if echo "$CONTENT" | jq -e '.response.summary' > /dev/null 2>&1; then
        echo "$CONTENT" > "$TEMP_OUTPUT"
        process_consultant_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
            "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS"
    else
        # Extract structured fields from markdown/text output
        # Summary: first meaningful line(s), up to 200 chars
        local_summary=$(echo "$CONTENT" | head -5 | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)

        # Approach: look for headings or key phrases
        local_approach=$(echo "$CONTENT" | grep -iE '^#+\s|^approach:|^recommendation:|^solution:' | head -1 | \
            sed 's/^[#[:space:]]*//;s/^[Aa]pproach:[[:space:]]*//' | head -c 100)
        [[ -z "$local_approach" ]] && local_approach=$(echo "$local_summary" | head -c 60)

        # Confidence: estimate from language strength
        local_confidence=6
        if echo "$CONTENT" | grep -qiE 'highly recommend|strongly suggest|definitely|clearly the best'; then
            local_confidence=8
        elif echo "$CONTENT" | grep -qiE 'recommend|suggest|good approach|effective|solid'; then
            local_confidence=7
        elif echo "$CONTENT" | grep -qiE 'might|could|possibly|one option|uncertain|depends'; then
            local_confidence=5
        fi

        jq -n \
            --arg consultant "$CONSULTANT_NAME" \
            --arg model "$MODEL_USED" \
            --arg persona "$PERSONA_NAME" \
            --arg summary "$local_summary" \
            --arg detailed "$CONTENT" \
            --arg approach "$local_approach" \
            --argjson confidence "$local_confidence" \
            --argjson metadata "$(build_response_metadata "$LATENCY_MS" "$MODEL_USED")" \
            '{
                consultant: $consultant, model: $model, persona: $persona,
                response: {
                    summary: $summary, detailed: $detailed, approach: $approach,
                    pros: [], cons: [],
                    caveats: ["Structured fields extracted from unformatted CLI output"]
                },
                confidence: {
                    score: $confidence,
                    reasoning: "Confidence estimated from response language patterns",
                    uncertainty_factors: ["Non-JSON response format"]
                },
                metadata: $metadata
            }' > "$OUTPUT_FILE"
    fi
else
    build_error_response "$CONSULTANT_NAME" "$MODEL_USED" "$PERSONA_NAME" \
        "Query failed with exit code $exit_code" "$LATENCY_MS" > "$OUTPUT_FILE"
fi

cat "$OUTPUT_FILE"
exit $exit_code
