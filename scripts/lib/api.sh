#!/bin/bash
# api.sh - HTTP/API abstraction layer for AI Consultants v2.0
#
# Provides functions for making HTTP API calls to external AI services
# with retry logic, error handling, and response parsing.
#
# Supported APIs: Qwen3 (DashScope), GLM (Zhipu), Grok (xAI)

# Load configuration (if not already loaded)
SCRIPT_DIR_API="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${AI_CONSULTANTS_VERSION:-}" ]]; then
    source "$SCRIPT_DIR_API/../config.sh"
fi

# =============================================================================
# SECURITY: ERROR MESSAGE SANITIZATION
# =============================================================================

# Sanitize error messages to prevent leaking sensitive data
# Removes API keys, tokens, and other sensitive patterns
# Usage: sanitize_error_message <message>
sanitize_error_message() {
    local message="$1"

    # Pattern list for sensitive data that should be redacted
    # - API keys (various formats)
    # - Bearer tokens
    # - Passwords in URLs
    # - Authorization headers

    echo "$message" | sed -E \
        -e 's/(api[_-]?key[[:space:]]*[:=][[:space:]]*)[^[:space:]"'\'']+/\1[REDACTED]/gi' \
        -e 's/(bearer[[:space:]]+)[^[:space:]"'\'']+/\1[REDACTED]/gi' \
        -e 's/(authorization[[:space:]]*:[[:space:]]*)[^[:space:]]+/\1[REDACTED]/gi' \
        -e 's/(password[[:space:]]*[:=][[:space:]]*)[^[:space:]"'\'']+/\1[REDACTED]/gi' \
        -e 's/(token[[:space:]]*[:=][[:space:]]*)[^[:space:]"'\'']+/\1[REDACTED]/gi' \
        -e 's/(sk-[a-zA-Z0-9]{20,})/[REDACTED_KEY]/g' \
        -e 's/([a-zA-Z0-9_-]{32,})/[POSSIBLE_KEY]/g'
}

# =============================================================================
# API KEY VALIDATION
# =============================================================================

# Check if an API key environment variable is set
# Usage: check_api_key "QWEN3_API_KEY" "Qwen3"
check_api_key() {
    local key_var_name="$1"
    local consultant_name="$2"

    # Get the value of the environment variable by name
    local key_value="${!key_var_name:-}"

    if [[ -z "$key_value" ]]; then
        log_error "[$consultant_name] API key not set: $key_var_name"
        log_info "Set the $key_var_name environment variable to use $consultant_name"
        return 1
    fi

    # Basic validation: key should be non-empty and not contain obvious placeholders
    if [[ "$key_value" == *"your_"* ]] || [[ "$key_value" == *"YOUR_"* ]] || [[ "$key_value" == "xxx"* ]]; then
        log_error "[$consultant_name] API key appears to be a placeholder: $key_var_name"
        return 1
    fi

    # Validate key format (minimum length, no whitespace)
    if [[ ${#key_value} -lt 10 ]]; then
        log_error "[$consultant_name] API key too short: $key_var_name"
        return 1
    fi

    if [[ "$key_value" =~ [[:space:]] ]]; then
        log_error "[$consultant_name] API key contains whitespace: $key_var_name"
        return 1
    fi

    log_debug "[$consultant_name] API key validated"
    return 0
}

# =============================================================================
# HTTP ERROR HANDLING
# =============================================================================

# Classify HTTP error codes
# Usage: classify_http_error <http_code>
# Returns: auth|rate_limit|server|client|success|unknown
classify_http_error() {
    local http_code="$1"

    case "$http_code" in
        200|201)
            echo "success"
            ;;
        400)
            echo "client"
            ;;
        401|403)
            echo "auth"
            ;;
        404)
            echo "not_found"
            ;;
        429)
            echo "rate_limit"
            ;;
        500|502|503|504)
            echo "server"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Calculate exponential backoff delay
# Usage: calculate_backoff <attempt_number>
calculate_backoff() {
    local attempt="$1"
    local base_delay="${API_BASE_BACKOFF:-2}"
    local max_delay="${API_MAX_BACKOFF:-60}"

    # Exponential backoff: base * 2^(attempt-1)
    local delay=$((base_delay * (1 << (attempt - 1))))

    # Cap at max delay
    if [[ $delay -gt $max_delay ]]; then
        delay=$max_delay
    fi

    echo "$delay"
}

# Extract Retry-After header value from response headers
# Usage: extract_retry_after <headers_file>
extract_retry_after() {
    local headers_file="$1"

    if [[ -f "$headers_file" ]]; then
        local retry_after
        retry_after=$(grep -i "^retry-after:" "$headers_file" 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' \r\n')
        if [[ -n "$retry_after" && "$retry_after" =~ ^[0-9]+$ ]]; then
            echo "$retry_after"
            return 0
        fi
    fi
    echo ""
    return 1
}

# =============================================================================
# REQUEST BUILDERS
# =============================================================================

# Build request body for Qwen3 (Alibaba DashScope format)
# Usage: build_qwen_request <prompt> <model>
build_qwen_request() {
    local prompt="$1"
    local model="${2:-qwen-max}"

    jq -n \
        --arg model "$model" \
        --arg prompt "$prompt" \
        '{
            model: $model,
            input: {
                messages: [
                    { role: "user", content: $prompt }
                ]
            },
            parameters: {
                result_format: "message"
            }
        }'
}

# Build request body for OpenAI-compatible APIs (GLM, Grok)
# Usage: build_openai_request <prompt> <model>
build_openai_request() {
    local prompt="$1"
    local model="${2:-gpt-4}"

    jq -n \
        --arg model "$model" \
        --arg prompt "$prompt" \
        '{
            model: $model,
            messages: [
                { role: "user", content: $prompt }
            ]
        }'
}

# =============================================================================
# RESPONSE PARSERS
# =============================================================================

# Parse Qwen3 response and extract content
# Usage: parse_qwen_response <response_json>
parse_qwen_response() {
    local response="$1"

    # Try different response paths (Qwen format varies)
    local content
    content=$(echo "$response" | jq -r '.output.choices[0].message.content // .output.text // empty' 2>/dev/null)

    if [[ -n "$content" && "$content" != "null" ]]; then
        echo "$content"
        return 0
    fi

    # Fallback: return raw output if structured parsing fails
    echo "$response" | jq -r '.output // empty' 2>/dev/null
}

# Parse OpenAI-compatible response (GLM, Grok)
# Usage: parse_openai_response <response_json>
parse_openai_response() {
    local response="$1"

    local content
    content=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -n "$content" && "$content" != "null" ]]; then
        echo "$content"
        return 0
    fi

    echo ""
    return 1
}

# Extract token usage from API response
# Usage: extract_token_usage <response_json> <format>
# format: "qwen" or "openai"
extract_token_usage() {
    local response="$1"
    local format="${2:-openai}"

    local input_tokens=0
    local output_tokens=0

    if [[ "$format" == "qwen" ]]; then
        input_tokens=$(echo "$response" | jq -r '.usage.input_tokens // 0' 2>/dev/null)
        output_tokens=$(echo "$response" | jq -r '.usage.output_tokens // 0' 2>/dev/null)
    else
        input_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)
        output_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
    fi

    local total=$((input_tokens + output_tokens))
    echo "$total"
}

# =============================================================================
# MAIN API QUERY FUNCTION
# =============================================================================

# Execute an HTTP API query with retry and timeout
#
# Usage: run_api_query <consultant_name> <output_file> <timeout_sec> \
#                      <api_endpoint> <api_key_var> <request_body> [auth_style]
#
# Parameters:
#   consultant_name - Display name for logging (e.g., "Qwen3")
#   output_file     - Path to write response body
#   timeout_sec     - Request timeout in seconds
#   api_endpoint    - Full API URL
#   api_key_var     - Name of env var containing API key (not the value!)
#   request_body    - JSON request body
#   auth_style      - Optional: "bearer" (default) or "apikey"
#
# Returns:
#   0 on success
#   1 on auth failure (no retry)
#   2 on rate limit (after max retries)
#   3 on server error (after max retries)
#   124 on timeout
run_api_query() {
    local consultant_name="$1"
    local output_file="$2"
    local timeout_seconds="$3"
    local api_endpoint="$4"
    local api_key_var="$5"
    local request_body="$6"
    local auth_style="${7:-bearer}"

    # Check rate limiting before proceeding
    check_rate_limit "$consultant_name"

    # Resolve API key from env var name
    local api_key="${!api_key_var:-}"

    if [[ -z "$api_key" ]]; then
        log_error "[$consultant_name] API key not available: $api_key_var"
        return 1
    fi

    # Build authorization header
    local auth_header
    case "$auth_style" in
        apikey)
            auth_header="X-API-Key: $api_key"
            ;;
        *)  # Default to bearer token
            auth_header="Authorization: Bearer $api_key"
            ;;
    esac

    # Temporary files
    local temp_response=$(mktemp)
    local temp_headers=$(mktemp)
    local error_file="${output_file}.err"

    log_info "[$consultant_name] Querying API (timeout: ${timeout_seconds}s, max retry: $MAX_RETRIES)..."

    local attempt=1
    local last_http_code=0
    local success=false

    while (( attempt <= MAX_RETRIES )); do
        log_debug "[$consultant_name] Attempt $attempt of $MAX_RETRIES..."

        # Execute curl request
        local http_code
        http_code=$(curl -s -w "%{http_code}" \
            -o "$temp_response" \
            -D "$temp_headers" \
            -X POST "$api_endpoint" \
            -H "$auth_header" \
            -H "Content-Type: application/json" \
            -m "$timeout_seconds" \
            -d "$request_body" 2>"$error_file")

        local curl_exit=$?
        last_http_code="$http_code"

        # Handle curl-level errors
        if [[ $curl_exit -eq 28 ]]; then
            log_warn "[$consultant_name] Timeout after ${timeout_seconds}s"
            ((attempt++))
            if (( attempt <= MAX_RETRIES )); then
                local backoff=$(calculate_backoff "$attempt")
                log_info "[$consultant_name] Waiting ${backoff}s before retry..."
                sleep "$backoff"
            fi
            continue
        elif [[ $curl_exit -ne 0 ]]; then
            log_warn "[$consultant_name] Network error (curl exit: $curl_exit)"
            local error_msg=""
            [[ -f "$error_file" ]] && error_msg=$(head -3 "$error_file" 2>/dev/null)
            # Sanitize error message to avoid leaking sensitive data
            [[ -n "$error_msg" ]] && log_debug "[$consultant_name] Error: $(sanitize_error_message "$error_msg")"
            ((attempt++))
            if (( attempt <= MAX_RETRIES )); then
                sleep "$RETRY_DELAY_SECONDS"
            fi
            continue
        fi

        # Classify HTTP response
        local error_type=$(classify_http_error "$http_code")

        case "$error_type" in
            success)
                # Verify response is not empty
                if [[ -s "$temp_response" ]]; then
                    log_success "[$consultant_name] Response received (HTTP $http_code, $(wc -c < "$temp_response" | tr -d ' ') bytes)"
                    cp "$temp_response" "$output_file"
                    success=true
                    break
                else
                    log_warn "[$consultant_name] Empty response body"
                fi
                ;;
            auth)
                log_error "[$consultant_name] Authentication failed (HTTP $http_code)"
                log_error "[$consultant_name] Check that $api_key_var is correct"
                rm -f "$temp_response" "$temp_headers" "$error_file"
                return 1  # No retry for auth failures
                ;;
            rate_limit)
                # Try to get retry-after header
                local retry_after=$(extract_retry_after "$temp_headers")
                local backoff
                if [[ -n "$retry_after" ]]; then
                    backoff="$retry_after"
                    log_warn "[$consultant_name] Rate limited, server requests ${retry_after}s wait"
                else
                    backoff=$(calculate_backoff "$attempt")
                    log_warn "[$consultant_name] Rate limited (HTTP 429), backing off ${backoff}s"
                fi
                ((attempt++))
                if (( attempt <= MAX_RETRIES )); then
                    sleep "$backoff"
                fi
                ;;
            server)
                log_warn "[$consultant_name] Server error (HTTP $http_code)"
                ((attempt++))
                if (( attempt <= MAX_RETRIES )); then
                    local backoff=$(calculate_backoff "$attempt")
                    log_info "[$consultant_name] Waiting ${backoff}s before retry..."
                    sleep "$backoff"
                fi
                ;;
            client)
                log_error "[$consultant_name] Client error (HTTP $http_code)"
                # Log response body for debugging (sanitized to avoid leaking sensitive data)
                if [[ -s "$temp_response" ]]; then
                    local error_msg=$(jq -r '.error.message // .message // .' "$temp_response" 2>/dev/null | head -5)
                    log_debug "[$consultant_name] Response: $(sanitize_error_message "$error_msg")"
                fi
                rm -f "$temp_response" "$temp_headers" "$error_file"
                return 1  # No retry for client errors
                ;;
            *)
                log_warn "[$consultant_name] Unexpected response (HTTP $http_code)"
                ((attempt++))
                if (( attempt <= MAX_RETRIES )); then
                    sleep "$RETRY_DELAY_SECONDS"
                fi
                ;;
        esac
    done

    # Cleanup
    rm -f "$temp_response" "$temp_headers" "$error_file"

    if [[ "$success" == "true" ]]; then
        return 0
    else
        log_error "[$consultant_name] All $MAX_RETRIES attempts failed (last HTTP: $last_http_code)"
        return 3
    fi
}

# =============================================================================
# API CONFIGURATION DEFAULTS
# =============================================================================

# Base backoff delay in seconds
API_BASE_BACKOFF="${API_BASE_BACKOFF:-2}"

# Maximum backoff delay in seconds
API_MAX_BACKOFF="${API_MAX_BACKOFF:-60}"

# =============================================================================
# RATE LIMITING
# =============================================================================

# Rate limiting configuration
# Requests per minute limit per consultant
API_RATE_LIMIT="${API_RATE_LIMIT:-30}"

# Rate limit state file (per consultant)
RATE_LIMIT_DIR="${RATE_LIMIT_DIR:-/tmp/ai_consultants_ratelimit}"

# Initialize rate limit directory
_init_rate_limit_dir() {
    if [[ ! -d "$RATE_LIMIT_DIR" ]]; then
        mkdir -p "$RATE_LIMIT_DIR"
        chmod 700 "$RATE_LIMIT_DIR"
    fi
}

# Check and enforce rate limit for a consultant
# Returns 0 if request can proceed, 1 if rate limited (with delay)
# Usage: check_rate_limit <consultant_name>
check_rate_limit() {
    local consultant_name="$1"
    local limit="${API_RATE_LIMIT:-30}"
    local window=60  # 1 minute window

    _init_rate_limit_dir

    # Normalize consultant name for filename
    local safe_name=$(echo "$consultant_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '_')
    local state_file="${RATE_LIMIT_DIR}/${safe_name}_ratelimit"

    local now=$(date +%s)
    local window_start=$((now - window))

    # Create state file if it doesn't exist
    if [[ ! -f "$state_file" ]]; then
        touch "$state_file"
        chmod 600 "$state_file"
    fi

    # Read timestamps from state file and count requests in current window
    local count=0
    local new_timestamps=""

    while IFS= read -r timestamp; do
        if [[ -n "$timestamp" ]] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
            if [[ $timestamp -ge $window_start ]]; then
                ((count++)) || true
                new_timestamps+="$timestamp"$'\n'
            fi
        fi
    done < "$state_file"

    # Check if we're at the limit
    if [[ $count -ge $limit ]]; then
        # Calculate wait time until oldest request expires
        local oldest=$(echo "$new_timestamps" | head -1)
        if [[ -n "$oldest" ]]; then
            local wait_time=$((oldest + window - now + 1))
            if [[ $wait_time -gt 0 ]]; then
                log_warn "[$consultant_name] Rate limit reached ($count/$limit requests/min), waiting ${wait_time}s..."
                sleep "$wait_time"
            fi
        fi
    fi

    # Record this request
    new_timestamps+="$now"$'\n'
    echo "$new_timestamps" > "$state_file"

    return 0
}

# Clear rate limit state for a consultant (useful for testing)
# Usage: clear_rate_limit <consultant_name>
clear_rate_limit() {
    local consultant_name="$1"
    local safe_name=$(echo "$consultant_name" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '_')
    local state_file="${RATE_LIMIT_DIR}/${safe_name}_ratelimit"

    rm -f "$state_file" 2>/dev/null || true
}

# Clear all rate limit state
clear_all_rate_limits() {
    rm -rf "$RATE_LIMIT_DIR" 2>/dev/null || true
}
