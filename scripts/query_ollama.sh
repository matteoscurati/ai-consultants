#!/bin/bash
# query_ollama.sh - Query local Ollama models (v2.2 with Persona and Confidence)
#
# Enables fully local, privacy-preserving AI consultation using Ollama.
# Zero API costs, no data leaves your machine.
#
# Usage: ./query_ollama.sh "question" [context_file] [output_file]
#
# Environment variables:
#   OLLAMA_MODEL    - Model to use (default: llama3.2)
#   OLLAMA_HOST     - Ollama server URL (default: http://localhost:11434)
#   OLLAMA_TIMEOUT  - Timeout in seconds (default: 300)
#   ENABLE_PERSONA  - Enable "The Local Expert" persona (default: true)
#
# Prerequisites:
#   - Ollama installed: curl -fsSL https://ollama.com/install.sh | sh
#   - Model pulled: ollama pull llama3.2

set -euo pipefail

# Cleanup trap for temp files
TEMP_OUTPUT=""
cleanup() {
    [[ -n "$TEMP_OUTPUT" && -f "$TEMP_OUTPUT" ]] && rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
OLLAMA_TIMEOUT="${OLLAMA_TIMEOUT:-300}"
OLLAMA_TEMPERATURE="${OLLAMA_TEMPERATURE:-0.7}"
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Ollama"

# Parameters
QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/ollama_response.json}"

# =============================================================================
# PERSONA DEFINITION FOR OLLAMA
# =============================================================================

# Register Ollama persona if not already defined
OLLAMA_PERSONA_ID="${OLLAMA_PERSONA_ID:-16}"
OLLAMA_PERSONA="${OLLAMA_PERSONA:-The Local Expert}"
OLLAMA_PERSONA_PROMPT="${OLLAMA_PERSONA_PROMPT:-You are 'The Local Expert' - a privacy-conscious AI assistant running locally. You prioritize:
- Practical, implementable solutions
- Clear explanations without assumptions about external services
- Security and privacy considerations
- Efficient use of local resources}"

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

# Check if Ollama CLI is available
if ! command -v ollama &> /dev/null; then
    log_error "Ollama CLI not found"
    log_info "Install with: curl -fsSL https://ollama.com/install.sh | sh"
    exit 1
fi

# Check if Ollama server is running
check_ollama_server() {
    if ! curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
        log_error "Ollama server not responding at $OLLAMA_HOST"
        log_info "Start with: ollama serve"
        return 1
    fi
    return 0
}

# Check if the requested model is available
check_model_available() {
    local model="$1"
    local available_models
    available_models=$(curl -s "$OLLAMA_HOST/api/tags" 2>/dev/null | jq -r '.models[].name // empty' 2>/dev/null)

    if [[ -z "$available_models" ]]; then
        log_warn "Could not verify model availability"
        return 0
    fi

    # Check if model (or base model) is available
    local base_model="${model%%:*}"
    if echo "$available_models" | grep -q "^${base_model}"; then
        return 0
    fi

    log_error "Model '$model' not found locally"
    log_info "Pull with: ollama pull $model"
    return 1
}

# Run checks
check_ollama_server || exit 1
check_model_available "$OLLAMA_MODEL" || exit 1

# =============================================================================
# BUILD QUERY
# =============================================================================

# --- Build query ---
FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "Ollama" || exit 1

# --- Add persona if enabled ---
if [[ "$ENABLE_PERSONA" == "true" ]]; then
    PERSONA_PROMPT="$OLLAMA_PERSONA_PROMPT

You must respond in this EXACT JSON format:
{
  \"response\": {
    \"summary\": \"Brief TL;DR (2-3 sentences)\",
    \"detailed\": \"Full detailed response\",
    \"approach\": \"Name of the approach/solution\",
    \"pros\": [\"advantage 1\", \"advantage 2\"],
    \"cons\": [\"disadvantage 1\", \"disadvantage 2\"],
    \"caveats\": [\"important consideration\"]
  },
  \"confidence\": {
    \"score\": 7,
    \"reasoning\": \"Why this confidence level\",
    \"uncertainty_factors\": [\"What could affect this answer\"]
  }
}

IMPORTANT: Respond ONLY with valid JSON, no markdown or additional text.

"
    FULL_QUERY="${PERSONA_PROMPT}${FULL_QUERY}"
fi

# =============================================================================
# EXECUTE QUERY
# =============================================================================

# --- Timestamp for metadata ---
START_TIME=$(get_timestamp_ms)

# --- Build API request body ---
REQUEST_BODY=$(jq -n \
    --arg model "$OLLAMA_MODEL" \
    --arg prompt "$FULL_QUERY" \
    --argjson temperature "$OLLAMA_TEMPERATURE" \
    '{
        model: $model,
        prompt: $prompt,
        stream: false,
        options: {
            temperature: $temperature
        }
    }')

# --- Execute query ---
log_info "Consulting Ollama ($OLLAMA_MODEL) locally..."

TEMP_OUTPUT=$(mktemp)
HTTP_CODE=$(curl -s -w "%{http_code}" \
    --max-time "$OLLAMA_TIMEOUT" \
    -X POST "$OLLAMA_HOST/api/generate" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_BODY" \
    -o "$TEMP_OUTPUT" 2>/dev/null) || HTTP_CODE="000"

exit_code=$?

# --- Calculate latency ---
END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))

# =============================================================================
# PROCESS RESPONSE
# =============================================================================

if [[ "$HTTP_CODE" == "200" && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    # Extract response from Ollama format
    RAW_RESPONSE=$(cat "$TEMP_OUTPUT")

    # Get the response text and metadata
    INNER_RESPONSE=$(echo "$RAW_RESPONSE" | jq -r '.response // empty' 2>/dev/null)
    TOTAL_DURATION=$(echo "$RAW_RESPONSE" | jq -r '.total_duration // 0' 2>/dev/null)
    EVAL_COUNT=$(echo "$RAW_RESPONSE" | jq -r '.eval_count // 0' 2>/dev/null)

    if [[ -z "$INNER_RESPONSE" ]]; then
        log_error "Empty response from Ollama"
        exit_code=1
    else
        # Try to parse as JSON (from our structured prompt)
        PARSED_JSON=""

        # First try: direct JSON parse
        if echo "$INNER_RESPONSE" | jq -e '.response.summary' > /dev/null 2>&1; then
            PARSED_JSON="$INNER_RESPONSE"
        else
            # Second try: extract JSON from text
            EXTRACTED=$(echo "$INNER_RESPONSE" | sed -n '/{/,/}/p' | tr '\n' ' ')
            if [[ -n "$EXTRACTED" ]] && echo "$EXTRACTED" | jq -e '.response.summary' > /dev/null 2>&1; then
                PARSED_JSON="$EXTRACTED"
            fi
        fi

        if [[ -n "$PARSED_JSON" ]]; then
            # Structured response - wrap with metadata
            jq -n \
                --arg consultant "$CONSULTANT_NAME" \
                --arg model "$OLLAMA_MODEL" \
                --arg persona "$OLLAMA_PERSONA" \
                --argjson inner "$PARSED_JSON" \
                --argjson eval_count "$EVAL_COUNT" \
                --argjson latency "$LATENCY_MS" \
                --arg timestamp "$(date -Iseconds)" \
                '{
                    consultant: $consultant,
                    model: $model,
                    persona: $persona,
                    response: $inner.response,
                    confidence: $inner.confidence,
                    metadata: {
                        tokens_used: $eval_count,
                        latency_ms: $latency,
                        model_version: $model,
                        timestamp: $timestamp,
                        local: true,
                        cost: 0
                    }
                }' > "$OUTPUT_FILE"
        else
            # Unstructured response - create base structure
            jq -n \
                --arg consultant "$CONSULTANT_NAME" \
                --arg model "$OLLAMA_MODEL" \
                --arg persona "$OLLAMA_PERSONA" \
                --arg response "$INNER_RESPONSE" \
                --argjson eval_count "$EVAL_COUNT" \
                --argjson latency "$LATENCY_MS" \
                --arg timestamp "$(date -Iseconds)" \
                '{
                    consultant: $consultant,
                    model: $model,
                    persona: $persona,
                    response: {
                        summary: "See detailed response below",
                        detailed: $response,
                        approach: "local_inference",
                        pros: ["No API costs", "Full privacy", "No rate limits"],
                        cons: ["Limited by local hardware"],
                        caveats: ["Response format not structured"]
                    },
                    confidence: {
                        score: 6,
                        reasoning: "Local model response - confidence estimated",
                        uncertainty_factors: ["Unstructured output format"]
                    },
                    metadata: {
                        tokens_used: $eval_count,
                        latency_ms: $latency,
                        model_version: $model,
                        timestamp: $timestamp,
                        local: true,
                        cost: 0
                    }
                }' > "$OUTPUT_FILE"
        fi

        log_success "[Ollama] Response received (${EVAL_COUNT} tokens, ${LATENCY_MS}ms)"
        rm -f "$TEMP_OUTPUT"
        cat "$OUTPUT_FILE"
        exit 0
    fi
fi

# --- Error handling ---
ERROR_MSG="Query failed"
if [[ "$HTTP_CODE" == "000" ]]; then
    ERROR_MSG="Connection failed - is Ollama server running?"
elif [[ "$HTTP_CODE" != "200" ]]; then
    ERROR_MSG="HTTP error $HTTP_CODE"
fi

log_error "[Ollama] $ERROR_MSG"

jq -n \
    --arg consultant "$CONSULTANT_NAME" \
    --arg model "$OLLAMA_MODEL" \
    --arg persona "$OLLAMA_PERSONA" \
    --argjson latency "$LATENCY_MS" \
    --arg timestamp "$(date -Iseconds)" \
    --arg error "$ERROR_MSG" \
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
            local: true,
            cost: 0,
            error: $error
        }
    }' > "$OUTPUT_FILE"

rm -f "$TEMP_OUTPUT"
cat "$OUTPUT_FILE"
exit 1
