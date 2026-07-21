#!/bin/bash
# api_query.sh - API mode query execution for AI Consultants v2.6
#
# This module provides a unified API query function that handles the
# differences between API formats (OpenAI, Anthropic, Google AI).
#
# Used by query_*.sh scripts when they are in API mode instead of CLI mode.

# Guard against double-sourcing
if [[ -n "${_API_QUERY_SH_SOURCED:-}" ]]; then
    # shellcheck disable=SC2317  # exit 0 is the script-mode fallback for sourced double-load guard
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

    # Resolve the reasoning-effort knob BEFORE the format switch. Doing it
    # inside the openai arm meant a value set for a consultant on any other
    # wire format was silently dropped and never validated - and Qwen3's
    # DEFAULT format is `qwen`, so the one consultant the feature was built for
    # got exactly the silent no-op it exists to prevent.
    local effort_var effort=""
    effort_var="$(to_upper "$consultant_name")_REASONING_EFFORT"
    if [[ -n "${!effort_var:-}" ]]; then
        # Validate before spending a request: a rejected value should fail here,
        # not as a provider 400 after the call is billed.
        if ! effort=$(validate_reasoning_effort "${!effort_var}" "$consultant_name"); then
            return 1
        fi
    fi

    # Build request body based on format
    local request_body
    local final_api_url="$api_url"
    local auth_style="bearer"

    case "$api_format" in
        google_ai)
            if [[ -n "$effort" ]]; then
                log_warn "[$consultant_name] $effort_var is not supported on the 'google_ai' wire format and is ignored."
            fi
            request_body=$(build_google_ai_request "$query")
            # Google AI appends model to URL; use x-goog-api-key header for security
            final_api_url="${api_url}/${model}:generateContent"
            auth_style="google_ai"
            ;;
        anthropic)
            if [[ -n "$effort" ]]; then
                log_warn "[$consultant_name] $effort_var is not supported on the 'anthropic' wire format and is ignored."
            fi
            request_body=$(build_anthropic_request "$query" "$model")
            auth_style="anthropic"
            ;;
        qwen)
            # The DashScope envelope has no reasoning_effort field. Say so
            # rather than accepting the setting and dropping it.
            if [[ -n "$effort" ]]; then
                log_warn "[$consultant_name] $effort_var is ignored on the '$api_format' wire format (no reasoning_effort field). Set ${consultant_name^^}_FORMAT=openai and an OpenAI-compatible ${consultant_name^^}_API_URL to use it."
            fi
            request_body=$(build_qwen_request "$query" "$model")
            ;;
        *)  # openai format
            if [[ -n "$effort" ]]; then
                request_body=$(build_openai_request "$query" "$model" 4096 "$effort")
            else
                request_body=$(build_openai_request "$query" "$model")
            fi
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

    # Publish token usage for the response builder.
    #
    # These figures used to be logged and thrown away, so every response carried
    # the hardcoded tokens_used: 0 from build_response_metadata and every cost
    # report came out at $0.00. The provider's prompt/completion SPLIT is kept,
    # not just the total: output rates run several times input rates, so
    # re-splitting a total 60/40 overstates cost while still reading as
    # "measured".
    local _t_in _t_out
    read -r _t_in _t_out <<< "$(extract_token_split "$raw_response" "$api_format")"
    log_debug "[$consultant_name] Tokens used: $((_t_in + _t_out)) (in=$_t_in out=$_t_out)"
    set_api_token_split "$_t_in" "$_t_out"

    rm -f "$temp_response"
    return 0
}

# =============================================================================
# GENERIC API CONSULTANT FUNCTION (v2.6)
# =============================================================================

# Run a consultation using API mode for any API-based consultant
# This function is called by consult_all.sh for custom API agents and
# as a fallback when no dedicated query script exists.
#
# Usage: run_api_consultant <consultant_name> <query> <context_file> <output_file>
#
# Parameters:
#   consultant_name - Name of the consultant (e.g., "Qwen3", "DeepSeek")
#   query           - The query text (can be empty if context_file provides all content)
#   context_file    - Path to context file (can be empty)
#   output_file     - Path to write the JSON response
#
# Returns:
#   0 on success
#   1 on failure
run_api_consultant() {
    local consultant_name="$1"
    local query="$2"
    local context_file="$3"
    local output_file="$4"

    local consultant_upper
    consultant_upper=$(to_upper "$consultant_name")

    # Get configuration for this consultant
    local model_var="${consultant_upper}_MODEL"
    local timeout_var="${consultant_upper}_TIMEOUT_SECONDS"

    local model="${!model_var:-}"
    local timeout_seconds="${!timeout_var:-180}"

    # Build full query from query + context
    local full_query
    full_query=$(build_full_query "$query" "$context_file")

    if [[ -z "$full_query" ]]; then
        log_error "[$consultant_name] No query to send"
        return 1
    fi

    # Stance addendum (v2.21): API consultants don't pass through
    # build_query_with_persona (which wraps CLI prompts), so inject the shared
    # stance instruction here too -- otherwise they'd emit no stance and drop out
    # of the exact-match consensus count. Appended AFTER the empty-query guard so
    # a question-less run still errors cleanly instead of sending a stance-only prompt.
    [[ -n "${STANCE_OPTIONS_PROMPT:-}" ]] && full_query="${full_query}

${STANCE_OPTIONS_PROMPT}"

    local start_time
    start_time=$(get_timestamp_ms)

    # Create temp file for API response
    local temp_response
    temp_response=$(mktemp)

    # Use run_api_mode_query which handles all the API format/auth logic
    run_api_mode_query "$consultant_name" "$model" "$full_query" "$temp_response" "$timeout_seconds"
    local exit_code=$?

    local end_time
    end_time=$(get_timestamp_ms)
    local latency=$((end_time - start_time))

    if [[ $exit_code -ne 0 ]]; then
        build_error_response "$consultant_name" "${model:-unknown}" "API Consultant" \
            "API query failed (exit code: $exit_code)" "$latency" > "$output_file"
        rm -f "$temp_response"
        return 1
    fi

    # Read parsed content from temp file (run_api_mode_query already parsed it)
    local parsed_content
    parsed_content=$(cat "$temp_response")
    local _tok _tok_src _tok_in _tok_out
    read -r _tok _tok_src _tok_in _tok_out <<< "$(resolve_response_tokens "$full_query" "$parsed_content")"
    clear_api_token_split
    rm -f "$temp_response"

    if [[ -z "$parsed_content" ]]; then
        build_error_response "$consultant_name" "${model:-unknown}" "API Consultant" \
            "Empty response from API" "$latency" > "$output_file"
        return 1
    fi

    # Try to parse as structured JSON response
    if echo "$parsed_content" | jq -e '.response' >/dev/null 2>&1; then
        build_structured_response "$consultant_name" "${model:-unknown}" "API Consultant" \
            "$parsed_content" "$latency" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" > "$output_file"
    else
        build_fallback_response "$consultant_name" "${model:-unknown}" "API Consultant" \
            "$parsed_content" "$latency" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" > "$output_file"
    fi

    log_success "[$consultant_name] Response generated"
    return 0
}
