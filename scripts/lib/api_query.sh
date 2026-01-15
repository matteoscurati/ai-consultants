#!/bin/bash
# api_query.sh - Shared library for API-based consultant queries
#
# Provides a unified function to query API-based consultants (Qwen3, GLM, Grok)
# with proper error handling, persona support, and JSON schema formatting.
#
# Usage in query scripts:
#   source "$SCRIPT_DIR/lib/api_query.sh"
#   run_api_consultant "Qwen3" "$@"

# Load dependencies
SCRIPT_DIR_API_QUERY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_API_QUERY/../config.sh"
source "$SCRIPT_DIR_API_QUERY/common.sh"
source "$SCRIPT_DIR_API_QUERY/api.sh"
source "$SCRIPT_DIR_API_QUERY/personas.sh"

# =============================================================================
# CONSULTANT CONFIGURATION LOOKUP
# =============================================================================

# Get configuration for a specific API consultant
# Usage: get_api_config <consultant_name> <config_key>
# Returns: The configuration value
#
# Supports all API consultants via environment variable convention:
#   {NAME}_MODEL, {NAME}_API_URL, {NAME}_API_KEY, {NAME}_FORMAT, {NAME}_TIMEOUT
#
# Predefined agents (Qwen3, GLM, Grok) have defaults set in config.sh
get_api_config() {
    local consultant="$1"
    local key="$2"

    # Use helper functions from common.sh for case normalization
    local upper
    upper=$(to_upper "$consultant")
    local lower
    lower=$(to_lower "$consultant")

    case "$key" in
        model)
            local var="${upper}_MODEL"
            echo "${!var:-gpt-4}"
            ;;
        timeout)
            local var="${upper}_TIMEOUT"
            echo "${!var:-180}"
            ;;
        api_url)
            local var="${upper}_API_URL"
            local url="${!var:-}"
            if [[ -z "$url" ]]; then
                log_error "[$consultant] API URL not configured: ${var}"
                return 1
            fi
            echo "$url"
            ;;
        api_key_var)
            echo "${upper}_API_KEY"
            ;;
        response_format)
            local var="${upper}_FORMAT"
            echo "${!var:-openai}"
            ;;
        default_output)
            echo "/tmp/${lower}_response.json"
            ;;
    esac
}

# =============================================================================
# MAIN QUERY FUNCTION
# =============================================================================

# Run a query against an API-based consultant
# Usage: run_api_consultant <consultant_name> [query] [context_file] [output_file]
run_api_consultant() {
    local consultant_name="$1"
    local query="${2:-}"
    local context_file="${3:-}"
    local output_file="${4:-$(get_api_config "$consultant_name" "default_output")}"

    # Get consultant-specific configuration
    local model=$(get_api_config "$consultant_name" "model")
    local timeout=$(get_api_config "$consultant_name" "timeout")
    local api_url=$(get_api_config "$consultant_name" "api_url")
    local api_key_var=$(get_api_config "$consultant_name" "api_key_var")
    local response_format=$(get_api_config "$consultant_name" "response_format")

    # Check prerequisites
    check_api_key "$api_key_var" "$consultant_name" || exit 1
    check_command "curl" "curl" "apt install curl / brew install curl" || exit 1
    check_command "jq" "jq" "apt install jq / brew install jq" || exit 1

    # Build query
    local full_query=$(build_full_query "$query" "$context_file")
    validate_query "$full_query" "$consultant_name" || exit 1

    # Add persona if enabled
    local enable_persona="${ENABLE_PERSONA:-true}"
    if [[ "$enable_persona" == "true" ]]; then
        full_query=$(build_query_with_persona "$consultant_name" "$full_query")
    fi

    # Build request body based on format
    local request_body
    if [[ "$response_format" == "qwen" ]]; then
        request_body=$(build_qwen_request "$full_query" "$model")
    else
        request_body=$(build_openai_request "$full_query" "$model")
    fi

    # Timestamp for latency calculation
    local start_time=$(date +%s%3N 2>/dev/null || date +%s000)

    # Execute API query
    local temp_output=$(mktemp)
    run_api_query \
        "$consultant_name" \
        "$temp_output" \
        "$timeout" \
        "$api_url" \
        "$api_key_var" \
        "$request_body" \
        "bearer"

    local exit_code=$?

    # Calculate latency
    local end_time=$(date +%s%3N 2>/dev/null || date +%s000)
    local latency_ms=$((end_time - start_time))

    # Process response
    if [[ $exit_code -eq 0 && -f "$temp_output" && -s "$temp_output" ]]; then
        _format_success_response "$consultant_name" "$model" "$temp_output" "$output_file" "$latency_ms" "$response_format"
    else
        _format_error_response "$consultant_name" "$model" "$output_file" "$latency_ms" "$exit_code"
    fi

    rm -f "$temp_output"
    cat "$output_file"
    exit $exit_code
}

# =============================================================================
# RESPONSE FORMATTING (INTERNAL)
# =============================================================================

_format_success_response() {
    local consultant_name="$1"
    local model="$2"
    local temp_output="$3"
    local output_file="$4"
    local latency_ms="$5"
    local response_format="$6"

    # Parse API response
    local raw_api_response=$(cat "$temp_output")
    local raw_response
    local tokens_used

    if [[ "$response_format" == "qwen" ]]; then
        raw_response=$(parse_qwen_response "$raw_api_response")
        tokens_used=$(extract_token_usage "$raw_api_response" "qwen")
    else
        raw_response=$(parse_openai_response "$raw_api_response")
        tokens_used=$(extract_token_usage "$raw_api_response" "openai")
    fi

    local persona_name=$(get_persona_name "$consultant_name")
    local timestamp=$(date -Iseconds)

    # Check if response is already structured JSON
    if echo "$raw_response" | jq -e '.response.summary' > /dev/null 2>&1; then
        # Structured response - wrap with metadata
        jq -n \
            --arg consultant "$consultant_name" \
            --arg model "$model" \
            --arg persona "$persona_name" \
            --argjson inner "$raw_response" \
            --argjson latency "$latency_ms" \
            --argjson tokens "$tokens_used" \
            --arg timestamp "$timestamp" \
            '{
                consultant: $consultant,
                model: $model,
                persona: $persona,
                response: $inner.response,
                confidence: $inner.confidence,
                metadata: {
                    tokens_used: $tokens,
                    latency_ms: $latency,
                    model_version: $model,
                    timestamp: $timestamp
                }
            }' > "$output_file"
    else
        # Unstructured response - create base structure
        jq -n \
            --arg consultant "$consultant_name" \
            --arg model "$model" \
            --arg persona "$persona_name" \
            --arg response "$raw_response" \
            --argjson latency "$latency_ms" \
            --argjson tokens "$tokens_used" \
            --arg timestamp "$timestamp" \
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
                    tokens_used: $tokens,
                    latency_ms: $latency,
                    model_version: $model,
                    timestamp: $timestamp
                }
            }' > "$output_file"
    fi
}

_format_error_response() {
    local consultant_name="$1"
    local model="$2"
    local output_file="$3"
    local latency_ms="$4"
    local exit_code="$5"

    local persona_name=$(get_persona_name "$consultant_name")
    local timestamp=$(date -Iseconds)
    local error_msg="Query failed with exit code $exit_code"

    jq -n \
        --arg consultant "$consultant_name" \
        --arg model "$model" \
        --arg persona "$persona_name" \
        --argjson latency "$latency_ms" \
        --arg timestamp "$timestamp" \
        --arg error "$error_msg" \
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
        }' > "$output_file"
}
