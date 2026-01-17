#!/bin/bash
# query_claude.sh - Query Claude CLI as a consultant (v2.2 with Persona and Confidence)
#
# Usage: ./query_claude.sh "question" [context_file] [output_file]
#
# Environment variables:
#   CLAUDE_TIMEOUT - Timeout in seconds (default: 240)
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

# --- Check prerequisites ---
check_command "$CLAUDE_CMD" "Claude CLI" "Visit https://docs.anthropic.com/en/docs/claude-code" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Claude" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)

# Claude CLI uses --print for non-interactive mode
echo "$FULL_QUERY" | run_query \
    "Claude" \
    "$TEMP_OUTPUT" \
    "$CLAUDE_TIMEOUT_SECONDS" \
    "$CLAUDE_CMD" --print

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Helper: Build metadata JSON ---
build_metadata() {
    local latency="$1"
    local error="${2:-}"
    jq -n \
        --argjson latency "$latency" \
        --arg timestamp "$(date -Iseconds)" \
        --arg error "$error" \
        '{tokens_used: 0, latency_ms: $latency, model_version: "claude", timestamp: $timestamp} + (if $error != "" then {error: $error} else {} end)'
}

# --- Post-processing: wrap in full schema ---
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")

if [[ $exit_code -eq 0 && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    RAW_RESPONSE=$(cat "$TEMP_OUTPUT")
    rm -f "$TEMP_OUTPUT"

    # Check if response is already structured JSON
    if echo "$RAW_RESPONSE" | jq -e '.response.summary' > /dev/null 2>&1; then
        jq -n \
            --arg consultant "$CONSULTANT_NAME" \
            --arg persona "$PERSONA_NAME" \
            --argjson inner "$RAW_RESPONSE" \
            --argjson metadata "$(build_metadata "$LATENCY_MS")" \
            '{consultant: $consultant, model: "claude", persona: $persona, response: $inner.response, confidence: $inner.confidence, metadata: $metadata}' > "$OUTPUT_FILE"
    else
        # Fallback: wrap unstructured response
        jq -n \
            --arg consultant "$CONSULTANT_NAME" \
            --arg persona "$PERSONA_NAME" \
            --arg response "$RAW_RESPONSE" \
            --argjson metadata "$(build_metadata "$LATENCY_MS")" \
            '{consultant: $consultant, model: "claude", persona: $persona,
              response: {summary: "Unstructured response - see detailed", detailed: $response, approach: "unknown", pros: [], cons: [], caveats: ["Unstructured output"]},
              confidence: {score: 5, reasoning: "Confidence not provided", uncertainty_factors: ["Non-standard format"]},
              metadata: $metadata}' > "$OUTPUT_FILE"
    fi
else
    rm -f "$TEMP_OUTPUT"
    ERROR_MSG="Query failed with exit code $exit_code"
    jq -n \
        --arg consultant "$CONSULTANT_NAME" \
        --arg persona "$PERSONA_NAME" \
        --arg error "$ERROR_MSG" \
        --argjson metadata "$(build_metadata "$LATENCY_MS" "$ERROR_MSG")" \
        '{consultant: $consultant, model: "claude", persona: $persona,
          response: {summary: "ERROR: Consultation failed", detailed: $error, approach: "error", pros: [], cons: [], caveats: []},
          confidence: {score: 0, reasoning: "Consultation failed", uncertainty_factors: ["Execution error"]},
          metadata: $metadata}' > "$OUTPUT_FILE"
fi

cat "$OUTPUT_FILE"

exit $exit_code
