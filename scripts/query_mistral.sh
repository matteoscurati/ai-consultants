#!/bin/bash
# query_mistral.sh - Query Mistral Vibe CLI (v2.0 with Persona and Confidence)
#
# Usage: ./query_mistral.sh "question" [context_file] [output_file]
#
# Environment variables:
#   MISTRAL_TIMEOUT - Timeout in seconds (default: 180)
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

# --- Check prerequisites ---
check_command "$MISTRAL_CMD" "Mistral Vibe CLI" "pip install mistral-vibe" || exit 1

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Mistral Vibe" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Execution ---
TEMP_OUTPUT=$(mktemp)
run_query \
    "Mistral Vibe" \
    "$TEMP_OUTPUT" \
    "$MISTRAL_TIMEOUT_SECONDS" \
    "$MISTRAL_CMD" --prompt "$FULL_QUERY" --auto-approve < /dev/null

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# --- Post-processing: wrap in full schema ---
if [[ $exit_code -eq 0 && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    RAW_RESPONSE=$(cat "$TEMP_OUTPUT")

    # Try to parse as structured JSON
    if echo "$RAW_RESPONSE" | jq -e '.response.summary' > /dev/null 2>&1; then
        # It's already in our format
        jq -n \
            --arg consultant "$CONSULTANT_NAME" \
            --arg model "mistral" \
            --arg persona "$(get_persona_name "$CONSULTANT_NAME")" \
            --argjson inner "$RAW_RESPONSE" \
            --argjson latency "$LATENCY_MS" \
            --arg timestamp "$(date -Iseconds)" \
            '{
                consultant: $consultant,
                model: $model,
                persona: $persona,
                response: $inner.response,
                confidence: $inner.confidence,
                metadata: {
                    tokens_used: 0,
                    latency_ms: $latency,
                    model_version: $model,
                    timestamp: $timestamp
                }
            }' > "$OUTPUT_FILE"
    else
        # Fallback: plain text response
        jq -n \
            --arg consultant "$CONSULTANT_NAME" \
            --arg model "mistral" \
            --arg persona "$(get_persona_name "$CONSULTANT_NAME")" \
            --arg response "$RAW_RESPONSE" \
            --argjson latency "$LATENCY_MS" \
            --arg timestamp "$(date -Iseconds)" \
            '{
                consultant: $consultant,
                model: $model,
                persona: $persona,
                response: {
                    summary: "Unstructured response - see detailed",
                    detailed: $response,
                    approach: "unknown",
                    pros: [],
                    cons: [],
                    caveats: ["Unstructured output from consultant"]
                },
                confidence: {
                    score: 5,
                    reasoning: "Confidence not provided by consultant",
                    uncertainty_factors: ["Non-standard response format"]
                },
                metadata: {
                    tokens_used: 0,
                    latency_ms: $latency,
                    model_version: $model,
                    timestamp: $timestamp
                }
            }' > "$OUTPUT_FILE"
    fi

    rm -f "$TEMP_OUTPUT"
    cat "$OUTPUT_FILE"
else
    # Error - create structured output
    jq -n \
        --arg consultant "$CONSULTANT_NAME" \
        --arg model "mistral" \
        --arg persona "$(get_persona_name "$CONSULTANT_NAME")" \
        --argjson latency "$LATENCY_MS" \
        --arg timestamp "$(date -Iseconds)" \
        --arg error "Query failed with exit code $exit_code" \
        '{
            consultant: $consultant,
            model: $model,
            persona: $persona,
            response: {
                summary: "ERROR: Consultation failed",
                detailed: $error,
                approach: "error",
                pros: [],
                cons: [],
                caveats: []
            },
            confidence: {
                score: 0,
                reasoning: "Consultation failed",
                uncertainty_factors: ["Execution error"]
            },
            metadata: {
                latency_ms: $latency,
                model_version: $model,
                timestamp: $timestamp,
                error: $error
            }
        }' > "$OUTPUT_FILE"

    rm -f "$TEMP_OUTPUT"
    cat "$OUTPUT_FILE"
fi

exit $exit_code
