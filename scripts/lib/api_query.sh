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

    # Published for the caller in this shell after a successful response.
    # Never infer provider identity from the requested value when the response
    # omits it: callers record requested-only explicitly in that case.
    _API_RESPONSE_MODEL=""
    _API_MODEL_IDENTITY_SOURCE="requested-only"

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
            # Gemini 3.7 exposes low|medium|high thinking levels on the native
            # Google AI wire. The shared syntax validator is intentionally
            # broader for OpenAI-compatible providers, so fail before spending
            # a request when Google receives an unsupported level.
            local google_thinking_level=""
            if [[ -n "$effort" ]]; then
                case "$model" in
                    gemini-3.7-flash*)
                        case "$effort" in
                            low|medium|high) google_thinking_level="$effort" ;;
                            *)
                                log_error "[$consultant_name] $effort_var=$effort is unsupported for Gemini 3.7 on the 'google_ai' wire format (expected low|medium|high)"
                                return 1
                                ;;
                        esac
                        ;;
                    *)
                        log_warn "[$consultant_name] $effort_var is only transported to Gemini 3.7 on the 'google_ai' wire format and is ignored for $model."
                        ;;
                esac
            fi
            request_body=$(build_google_ai_request "$query" "$google_thinking_level")
            # Google AI appends model to URL; use x-goog-api-key header for security
            final_api_url="${api_url}/${model}:generateContent"
            auth_style="google_ai"
            ;;
        anthropic)
            if [[ -n "$effort" ]]; then
                log_warn "[$consultant_name] $effort_var is not supported on the 'anthropic' wire format and is ignored."
            fi
            local max_tokens_var api_max_tokens
            max_tokens_var="$(to_upper "$consultant_name")_API_MAX_TOKENS"
            api_max_tokens="${!max_tokens_var:-16384}"
            if ! [[ "$api_max_tokens" =~ ^[1-9][0-9]*$ ]]; then
                log_error "[$consultant_name] $max_tokens_var must be a positive integer (got: $api_max_tokens)"
                return 1
            fi
            request_body=$(build_anthropic_request "$query" "$model" "$api_max_tokens")
            auth_style="anthropic"
            ;;
        qwen)
            # The DashScope envelope has no reasoning_effort field. Say so
            # rather than accepting the setting and dropping it.
            if [[ -n "$effort" ]]; then
                local consultant_upper
                consultant_upper=$(to_upper "$consultant_name")
                log_warn "[$consultant_name] $effort_var is ignored on the '$api_format' wire format (no reasoning_effort field). Set ${consultant_upper}_FORMAT=openai and an OpenAI-compatible ${consultant_upper}_API_URL to use it."
            fi
            request_body=$(build_qwen_request "$query" "$model")
            ;;
        *)  # openai format
            local max_tokens_var api_max_tokens
            max_tokens_var="$(to_upper "$consultant_name")_API_MAX_TOKENS"
            api_max_tokens="${!max_tokens_var:-4096}"
            if ! [[ "$api_max_tokens" =~ ^[1-9][0-9]*$ ]]; then
                log_error "[$consultant_name] $max_tokens_var must be a positive integer (got: $api_max_tokens)"
                return 1
            fi
            if [[ -n "$effort" ]]; then
                request_body=$(build_openai_request "$query" "$model" "$api_max_tokens" "$effort")
            else
                request_body=$(build_openai_request "$query" "$model" "$api_max_tokens")
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

    # Publish measured usage before any parse/truncation return. A provider can
    # bill the entire completion budget and still return finish_reason=length;
    # that failed response must remain visible to cost and budget accounting.
    local _t_in _t_out
    read -r _t_in _t_out <<< "$(extract_token_split "$raw_response" "$api_format")"
    log_debug "[$consultant_name] Tokens used: $((_t_in + _t_out)) (in=$_t_in out=$_t_out)"
    set_api_token_split "$_t_in" "$_t_out"

    case "$api_format" in
        google_ai)
            _API_RESPONSE_MODEL=$(jq -r '.modelVersion // empty' <<<"$raw_response" 2>/dev/null || true)
            _API_RESPONSE_MODEL="${_API_RESPONSE_MODEL#models/}"
            ;;
        anthropic)
            _API_RESPONSE_MODEL=$(jq -r '.model // empty' <<<"$raw_response" 2>/dev/null || true)
            ;;
        qwen)
            _API_RESPONSE_MODEL=$(jq -r '.model // .output.model // empty' <<<"$raw_response" 2>/dev/null || true)
            ;;
        *)
            _API_RESPONSE_MODEL=$(jq -r '.model // empty' <<<"$raw_response" 2>/dev/null || true)
            ;;
    esac
    if [[ -n "$_API_RESPONSE_MODEL" && "$_API_RESPONSE_MODEL" != "null" \
        && "$_API_RESPONSE_MODEL" =~ ^[A-Za-z0-9._/-]{1,128}$ ]]; then
        _API_MODEL_IDENTITY_SOURCE="provider-reported"
    else
        if [[ -n "$_API_RESPONSE_MODEL" && "$_API_RESPONSE_MODEL" != "null" ]]; then
            log_warn "[$consultant_name] Provider returned an invalid model identifier; retaining requested-only identity"
        fi
        _API_RESPONSE_MODEL="$model"
    fi

    # Anthropic counts adaptive thinking and visible output against the same
    # max_tokens budget. A max_tokens stop is therefore an incomplete answer,
    # not a successful partial response suitable for synthesis.
    if [[ "$api_format" == "anthropic" ]] \
        && [[ "$(jq -r '.stop_reason // empty' <<<"$raw_response" 2>/dev/null)" == "max_tokens" ]]; then
        log_error "[$consultant_name] API response was truncated at ${api_max_tokens:-the configured} max tokens"
        rm -f "$temp_response"
        return 1
    fi

    # OpenAI-compatible reasoning models can spend the entire completion budget
    # in reasoning_content and return an empty visible answer with
    # finish_reason=length (observed live with DeepSeek V4 Pro/max). Never admit
    # that partial response into synthesis; callers can raise *_API_MAX_TOKENS.
    if [[ "$api_format" == "openai" ]] \
        && [[ "$(jq -r '.choices[0].finish_reason // empty' <<<"$raw_response" 2>/dev/null)" == "length" ]]; then
        log_error "[$consultant_name] API response was truncated at ${api_max_tokens:-the configured} max tokens"
        rm -f "$temp_response"
        return 1
    fi

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

    if [[ -z "$model" ]]; then
        log_error "[$consultant_name] API model is not configured: $model_var"
        build_error_response "$consultant_name" "unknown" "API Consultant" \
            "API model is not configured: $model_var" 0 "" "requested-only" > "$output_file"
        return 1
    fi

    # Build full query from query + context
    local full_query
    full_query=$(build_full_query "$query" "$context_file")

    if [[ -z "$full_query" ]]; then
        log_error "[$consultant_name] No query to send"
        return 1
    fi

    local start_time
    start_time=$(get_timestamp_ms)

    # Create temp file for API response
    local temp_response
    temp_response=$(mktemp)

    # Use run_api_mode_query which handles all the API format/auth logic
    local exit_code
    if run_api_mode_query "$consultant_name" "$model" "$full_query" "$temp_response" "$timeout_seconds"; then
        exit_code=0
    else
        exit_code=$?
    fi

    local end_time
    end_time=$(get_timestamp_ms)
    local latency=$((end_time - start_time))

    if [[ $exit_code -ne 0 ]]; then
        local _err_tok=0 _err_src=unknown _err_in="" _err_out=""
        if [[ -n "$_API_TOKEN_SPLIT" ]]; then
            read -r _err_tok _err_src _err_in _err_out <<< "$(resolve_response_tokens "$full_query" "")"
            clear_api_token_split
        fi
        build_error_response "$consultant_name" "${model:-unknown}" "API Consultant" \
            "API query failed (exit code: $exit_code)" "$latency" \
            "${model:-unknown}" "${_API_MODEL_IDENTITY_SOURCE:-requested-only}" \
            "$_err_tok" "$_err_src" "$_err_in" "$_err_out" > "$output_file"
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

    local normalized_content normalization_rc
    if normalized_content=$(normalize_consultant_response_text "$parsed_content"); then
        normalization_rc=0
    else
        normalization_rc=$?
    fi

    if [[ $normalization_rc -eq 0 ]]; then
        build_structured_response "$consultant_name" "${_API_RESPONSE_MODEL:-${model:-unknown}}" "API Consultant" \
            "$normalized_content" "$latency" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" "" "${model:-unknown}" "${_API_MODEL_IDENTITY_SOURCE:-requested-only}" > "$output_file"
    elif [[ $normalization_rc -eq 1 ]]; then
        build_fallback_response "$consultant_name" "${_API_RESPONSE_MODEL:-${model:-unknown}}" "API Consultant" \
            "$normalized_content" "$latency" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" "" "${model:-unknown}" "${_API_MODEL_IDENTITY_SOURCE:-requested-only}" > "$output_file"
    else
        log_error "[$consultant_name] Provider returned malformed, truncated, or schema-invalid JSON"
        build_error_response "$consultant_name" "${_API_RESPONSE_MODEL:-${model:-unknown}}" "API Consultant" \
            "Provider returned malformed, truncated, or schema-invalid JSON" "$latency" \
            "${model:-unknown}" "${_API_MODEL_IDENTITY_SOURCE:-requested-only}" \
            "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" > "$output_file"
        return 1
    fi

    log_success "[$consultant_name] Response generated"
    return 0
}
