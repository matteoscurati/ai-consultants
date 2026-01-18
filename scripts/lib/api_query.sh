#!/bin/bash
# api_query.sh - API mode query execution for AI Consultants v2.6
#
# This module provides a unified API query function that handles the
# differences between API formats (OpenAI, Anthropic, Google AI).
#
# Used by query_*.sh scripts when they are in API mode instead of CLI mode.

# Guard against double-sourcing
if [[ -n "${_API_QUERY_SH_SOURCED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_API_QUERY_SH_SOURCED=1

# Load dependencies
SCRIPT_DIR_API_QUERY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_API_QUERY/common.sh"
source "$SCRIPT_DIR_API_QUERY/api.sh"

# =============================================================================
# API QUERY EXECUTION
# =============================================================================

# Execute an API query for a consultant in API mode
#
# Usage: run_api_mode_query <consultant_name> <model> <query> <output_file> <timeout_sec>
#
# This function:
# 1. Determines the correct API format based on consultant name
# 2. Builds the appropriate request body
# 3. Executes the API call with retry logic
# 4. Parses the response
# 5. Returns the raw text response
#
# Returns:
#   0 on success (response written to output_file)
#   1 on auth failure
#   2 on rate limit
#   3 on server error
#   124 on timeout
run_api_mode_query() {
    local consultant_name="$1"
    local model="$2"
    local query="$3"
    local output_file="$4"
    local timeout_seconds="${5:-180}"

    # Get API configuration
    local api_format
    api_format=$(get_api_format "$consultant_name")
    local api_key_var
    api_key_var=$(get_api_key_var "$consultant_name")
    local api_url
    api_url=$(get_api_url "$consultant_name")

    # Validate API key (except for Google AI where key is in URL)
    if [[ "$api_format" != "google_ai" && -z "${!api_key_var:-}" ]]; then
        log_error "[$consultant_name] API key not set: $api_key_var"
        return 1
    fi

    # Build request body based on format
    local request_body
    local final_api_url="$api_url"
    local auth_style="bearer"

    case "$api_format" in
        google_ai)
            request_body=$(build_google_ai_request "$query")
            # Google AI appends model to URL and uses API key in URL
            local api_key_value="${!api_key_var:-}"
            final_api_url="${api_url}/${model}:generateContent?key=${api_key_value}"
            auth_style="none"
            api_key_var=""  # No separate auth header needed
            ;;
        anthropic)
            request_body=$(build_anthropic_request "$query" "$model")
            auth_style="anthropic"
            ;;
        qwen)
            request_body=$(build_qwen_request "$query" "$model")
            ;;
        *)  # openai format
            request_body=$(build_openai_request "$query" "$model")
            ;;
    esac

    log_debug "[$consultant_name] API format: $api_format"
    log_debug "[$consultant_name] API URL: $final_api_url"

    # Create temp file for raw API response
    local temp_response
    temp_response=$(mktemp)

    # Execute API call using unified run_api_query with auth_style
    run_api_query "$consultant_name" "$temp_response" "$timeout_seconds" "$final_api_url" "$api_key_var" "$request_body" "$auth_style"
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        rm -f "$temp_response"
        return $exit_code
    fi

    # Parse response based on format
    local raw_response
    raw_response=$(cat "$temp_response")

    local parsed_content
    case "$api_format" in
        google_ai)
            parsed_content=$(parse_google_ai_response "$raw_response")
            ;;
        anthropic)
            parsed_content=$(parse_anthropic_response "$raw_response")
            ;;
        qwen)
            parsed_content=$(parse_qwen_response "$raw_response")
            ;;
        *)  # openai format
            parsed_content=$(parse_openai_response "$raw_response")
            ;;
    esac

    if [[ -z "$parsed_content" ]]; then
        log_error "[$consultant_name] Failed to parse API response"
        rm -f "$temp_response"
        return 1
    fi

    # Write parsed content to output
    echo "$parsed_content" > "$output_file"

    # Extract and log token usage
    local tokens
    tokens=$(extract_token_usage "$raw_response" "$api_format")
    log_debug "[$consultant_name] Tokens used: $tokens"

    rm -f "$temp_response"
    return 0
}
