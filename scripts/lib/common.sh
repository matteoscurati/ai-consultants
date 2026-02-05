#!/bin/bash
# common.sh - Shared functions for consultation scripts
# Includes: logging, cross-platform timeout, retry logic, validation

# Guard against double-sourcing
if [[ -n "${_COMMON_SH_SOURCED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_COMMON_SH_SOURCED=1

# Load configuration
SCRIPT_DIR_COMMON="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_COMMON/../config.sh"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

_log() {
    local level=$1
    local color=$2
    local message=$3

    # Map levels to numbers for comparison (without associative arrays for compatibility)
    local current_level_num=1  # default INFO
    local message_level_num=1

    case "$LOG_LEVEL" in
        DEBUG) current_level_num=0 ;;
        INFO)  current_level_num=1 ;;
        WARN)  current_level_num=2 ;;
        ERROR) current_level_num=3 ;;
    esac

    case "$level" in
        DEBUG) message_level_num=0 ;;
        INFO)  message_level_num=1 ;;
        WARN)  message_level_num=2 ;;
        ERROR) message_level_num=3 ;;
    esac

    if [[ "$message_level_num" -ge "$current_level_num" ]]; then
        echo -e "${color}[$(date '+%H:%M:%S')] [$level]${C_RESET} ${message}" >&2
    fi
}

log_debug() { _log "DEBUG" "$C_DEBUG" "$1"; }
log_info() { _log "INFO" "$C_INFO" "$1"; }
log_success() { _log "INFO" "$C_SUCCESS" "$1"; }
log_warn() { _log "WARN" "$C_WARN" "$1"; }
log_error() { _log "ERROR" "$C_ERROR" "$1"; }

# =============================================================================
# CROSS-PLATFORM TIMEOUT
# =============================================================================

# Timeout function compatible with macOS and Linux
# Usage: run_with_timeout <seconds> <command> [args...]
run_with_timeout() {
    local timeout_seconds=$1
    shift
    local cmd=("$@")

    # Try first with timeout (Linux/GNU coreutils)
    if command -v timeout &> /dev/null; then
        timeout "$timeout_seconds" "${cmd[@]}"
        return $?
    fi

    # Try with gtimeout (macOS with coreutils installed)
    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_seconds" "${cmd[@]}"
        return $?
    fi

    # Fallback: implementation with background job and kill
    # Works on any POSIX system
    # Note: stdin must be captured before backgrounding
    local stdin_data
    stdin_data=$(cat)
    echo "$stdin_data" | "${cmd[@]}" &
    local pid=$!

    # Monitor in background
    (
        sleep "$timeout_seconds"
        kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" 2>/dev/null
    ) &
    local watchdog_pid=$!

    # Wait for the command
    wait "$pid" 2>/dev/null
    local exit_code=$?

    # Clean up the watchdog if the command finished first
    kill -0 "$watchdog_pid" 2>/dev/null && kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null

    # If the process was killed by timeout, return 124 (like GNU timeout)
    if [[ $exit_code -eq 143 ]] || [[ $exit_code -eq 137 ]]; then
        return 124
    fi

    return $exit_code
}

# =============================================================================
# COMMAND VERIFICATION
# =============================================================================

check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3

    if ! command -v "$cmd" &> /dev/null; then
        log_error "$name not found (command: $cmd)"
        if [[ -n "$install_hint" ]]; then
            log_info "Install with: $install_hint"
        fi
        return 1
    fi
    return 0
}

# =============================================================================
# MAIN QUERY EXECUTION FUNCTION
# =============================================================================

# Executes a query to an AI consultant with retry and timeout
#
# Usage: run_query <consultant_name> <output_file> <timeout_sec> <command...>
#
# The query is passed via stdin to the command.
# Example:
#   echo "$QUERY" | run_query "Gemini" "/tmp/out.json" 120 gemini -p - --output-format json
#
run_query() {
    local consultant_name="$1"
    local output_file="$2"
    local timeout_seconds="$3"
    shift 3
    local cmd=("$@")

    # File for stderr
    local error_file="${output_file}.err"

    # Read stdin into a variable so it can be reused in retries
    local stdin_content
    stdin_content=$(cat)

    log_info "Consulting $consultant_name (timeout: ${timeout_seconds}s, max retry: $MAX_RETRIES)..."

    local attempt=1
    while (( attempt <= MAX_RETRIES )); do
        log_debug "[$consultant_name] Attempt $attempt of $MAX_RETRIES..."

        # Execute the command with timeout, passing stdin
        echo "$stdin_content" | run_with_timeout "$timeout_seconds" "${cmd[@]}" > "$output_file" 2> "$error_file"
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            # Verify that the output is not empty
            if [[ -s "$output_file" ]]; then
                log_success "[$consultant_name] Response received ($(wc -c < "$output_file" | tr -d ' ') bytes)"
                rm -f "$error_file"
                return 0
            else
                log_warn "[$consultant_name] Empty response"
                exit_code=1  # Treat empty response as failure
            fi
        fi

        # Error handling
        local error_msg=""
        [[ -f "$error_file" ]] && error_msg=$(head -5 "$error_file" 2>/dev/null)

        if [[ $exit_code -eq 124 ]]; then
            log_warn "[$consultant_name] Timeout after ${timeout_seconds}s"
        else
            log_warn "[$consultant_name] Error (code: $exit_code)"
            [[ -n "$error_msg" ]] && log_debug "Details: $error_msg"
        fi

        ((attempt++))
        if (( attempt <= MAX_RETRIES )); then
            log_info "Waiting ${RETRY_DELAY_SECONDS}s before next attempt..."
            sleep "$RETRY_DELAY_SECONDS"
        fi
    done

    log_error "[$consultant_name] All $MAX_RETRIES attempts failed"
    return 1
}

# =============================================================================
# TIMESTAMP UTILITIES
# =============================================================================

# Detect timestamp method once at source time (avoid repeated detection)
if date +%s%3N 2>/dev/null | grep -qv 'N'; then
    _TIMESTAMP_METHOD="gnu"
elif command -v python3 &>/dev/null; then
    _TIMESTAMP_METHOD="python"
else
    _TIMESTAMP_METHOD="posix"
fi

# Get current timestamp in milliseconds (portable - works on macOS and Linux)
# Usage: get_timestamp_ms
get_timestamp_ms() {
    case "$_TIMESTAMP_METHOD" in
        gnu)    date +%s%3N ;;
        python) python3 -c 'import time; print(int(time.time()*1000))' ;;
        *)      echo "$(($(date +%s) * 1000))" ;;
    esac
}

# =============================================================================
# CASE NORMALIZATION HELPERS
# =============================================================================

# Convert string to uppercase (portable - works on Bash 3.2+)
# Usage: to_upper "string"
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr -d ' -'
}

# Convert string to lowercase (portable - works on Bash 3.2+)
# Usage: to_lower "string"
to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' -' '_'
}

# Convert to title case (first letter uppercase, rest lowercase)
# Usage: to_title "STRING" => "String"
to_title() {
    echo "$1" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}'
}

# =============================================================================
# KNOWN AGENTS REGISTRY
# =============================================================================

# Central list of known/predefined agents (to distinguish from custom ones)
# This list is used by discovery functions to identify custom agents
KNOWN_CLI_AGENTS="GEMINI CODEX MISTRAL KILO CURSOR AIDER AMP KIMI CLAUDE QWEN3"
KNOWN_API_AGENTS="GLM GROK DEEPSEEK"
KNOWN_FEATURE_FLAGS="PERSONA SYNTHESIS DEBATE REFLECTION CLASSIFICATION SMART_ROUTING COST_TRACKING PROGRESS_BARS EARLY_TERMINATION PREFLIGHT"

# Check if an agent name is a known predefined agent
# Usage: is_known_agent "AGENTNAME"
is_known_agent() {
    local agent_upper="$1"
    for known in $KNOWN_CLI_AGENTS $KNOWN_API_AGENTS $KNOWN_FEATURE_FLAGS; do
        [[ "$agent_upper" == "$known" ]] && return 0
    done
    return 1
}

# =============================================================================
# CLI/API MODE SWITCHING (v2.6)
# =============================================================================

# Check if an agent is configured to use API mode instead of CLI
# Usage: is_api_mode <agent_name>
# Returns: 0 (true) if API mode, 1 (false) if CLI mode
is_api_mode() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")

    local var_name="${agent_upper}_USE_API"
    [[ "${!var_name:-false}" == "true" ]]
}

# Validate API mode configuration for an agent
# Checks if the required API key is set
# Usage: validate_api_mode <agent_name>
# Returns: 0 if valid, 1 if API key missing
validate_api_mode() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")

    local api_key_var
    case "$agent_upper" in
        GEMINI)     api_key_var="GEMINI_API_KEY" ;;
        CODEX)      api_key_var="OPENAI_API_KEY" ;;
        CLAUDE)     api_key_var="ANTHROPIC_API_KEY" ;;
        MISTRAL)    api_key_var="MISTRAL_API_KEY" ;;
        QWEN3)      api_key_var="QWEN3_API_KEY" ;;
        *)
            log_error "Unknown agent for API mode: $agent"
            return 1
            ;;
    esac

    if [[ -z "${!api_key_var:-}" ]]; then
        log_error "[$agent] API mode enabled but $api_key_var is not set"
        return 1
    fi

    log_debug "[$agent] API mode validated with $api_key_var"
    return 0
}

# Get the API key variable name for an agent
# Usage: get_api_key_var <agent_name>
get_api_key_var() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")

    case "$agent_upper" in
        GEMINI)     echo "GEMINI_API_KEY" ;;
        CODEX)      echo "OPENAI_API_KEY" ;;
        CLAUDE)     echo "ANTHROPIC_API_KEY" ;;
        MISTRAL)    echo "MISTRAL_API_KEY" ;;
        QWEN3)      echo "QWEN3_API_KEY" ;;
        GLM)        echo "GLM_API_KEY" ;;
        GROK)       echo "GROK_API_KEY" ;;
        DEEPSEEK)   echo "DEEPSEEK_API_KEY" ;;
        *)          echo "" ;;
    esac
}

# Get the API URL for an agent
# Usage: get_api_url <agent_name>
get_api_url() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")

    case "$agent_upper" in
        GEMINI)     echo "${GEMINI_API_URL:-https://generativelanguage.googleapis.com/v1beta/models}" ;;
        CODEX)      echo "${CODEX_API_URL:-https://api.openai.com/v1/chat/completions}" ;;
        CLAUDE)     echo "${CLAUDE_API_URL:-https://api.anthropic.com/v1/messages}" ;;
        MISTRAL)    echo "${MISTRAL_API_URL:-https://api.mistral.ai/v1/chat/completions}" ;;
        QWEN3)      echo "${QWEN3_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation}" ;;
        GLM)        echo "${GLM_API_URL:-https://open.bigmodel.cn/api/paas/v4/chat/completions}" ;;
        GROK)       echo "${GROK_API_URL:-https://api.x.ai/v1/chat/completions}" ;;
        DEEPSEEK)   echo "${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}" ;;
        *)          echo "" ;;
    esac
}

# Get the API response format for an agent
# Usage: get_api_format <agent_name>
get_api_format() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")

    case "$agent_upper" in
        GEMINI)     echo "google_ai" ;;
        CLAUDE)     echo "anthropic" ;;
        CODEX|MISTRAL|GLM|GROK|DEEPSEEK)  echo "openai" ;;
        QWEN3)      echo "qwen" ;;
        *)          echo "openai" ;;
    esac
}

# Log API mode status for debugging
log_api_mode_status() {
    local agent="$1"
    if is_api_mode "$agent"; then
        log_debug "[$agent] Mode: API"
    else
        log_debug "[$agent] Mode: CLI"
    fi
}

# =============================================================================
# SELF-EXCLUSION LOGIC (v2.2)
# =============================================================================

# Maps invoking agent identifier to the consultant name that should be excluded.
# Prevents an agent from consulting itself (e.g., Claude Code shouldn't query Claude).
#
# Usage: excluded=$(get_self_consultant_name)
# Returns: Uppercase consultant name (e.g., "CLAUDE", "CODEX") or empty string
get_self_consultant_name() {
    local invoking
    invoking=$(to_lower "${INVOKING_AGENT:-unknown}")

    # Normalize aliases to canonical names
    case "$invoking" in
        claude|claude_code|claudecode)  echo "CLAUDE" ;;
        codex|codex_cli|codexcli)       echo "CODEX" ;;
        gemini|gemini_cli|geminicli)    echo "GEMINI" ;;
        mistral|vibe|mistral_vibe)      echo "MISTRAL" ;;
        kilo|kilocode|kilo_code)        echo "KILO" ;;
        amp|amp_code|ampcode)           echo "AMP" ;;
        kimi|kimi_code|kimicode)        echo "KIMI" ;;
        qwen|qwen3|qwen_code|qwencode)  echo "QWEN3" ;;
        cursor|aider)                   echo "$(to_upper "$invoking")" ;;
        *)                              echo "" ;;
    esac
}

# Check if a consultant should be skipped due to self-exclusion
# Usage: should_skip_consultant "CONSULTANTNAME"
# Returns: 0 (true) if should skip, 1 (false) if should include
should_skip_consultant() {
    local self_name
    self_name=$(get_self_consultant_name)
    [[ -n "$self_name" && "$(to_upper "$1")" == "$self_name" ]]
}

# Log self-exclusion status for debugging
log_self_exclusion_status() {
    local self_name
    self_name=$(get_self_consultant_name)
    if [[ -n "$self_name" ]]; then
        log_debug "Self-exclusion: excluding $self_name (invoking: ${INVOKING_AGENT:-unknown})"
    fi
}

# =============================================================================
# SECURITY: INPUT VALIDATION
# =============================================================================

# Validate a file path to prevent path traversal attacks
# - Rejects paths containing ".."
# - Rejects absolute paths starting with / (unless in allowed dirs)
# - Returns 0 if valid, 1 if invalid
# Usage: validate_file_path "path" [allow_absolute]
validate_file_path() {
    local path="$1"
    local allow_absolute="${2:-false}"

    # Check for empty path
    if [[ -z "$path" ]]; then
        log_error "Empty file path provided"
        return 1
    fi

    # Check for path traversal attempts
    if [[ "$path" == *".."* ]]; then
        log_error "Path traversal detected in: $path"
        return 1
    fi

    # Check for null bytes (common injection technique)
    # Bash 3.2 can't reliably detect null bytes in variables, but command-line
    # arguments with null bytes are truncated anyway, so this is a best-effort check
    local path_len=${#path}
    local printf_len
    printf_len=$(printf '%s' "$path" | wc -c | tr -d ' ')
    if [[ "$path_len" != "$printf_len" ]]; then
        log_error "Null byte injection detected in path"
        return 1
    fi

    # Check absolute paths
    if [[ "$path" == /* ]] && [[ "$allow_absolute" != "true" ]]; then
        log_warn "Absolute path not allowed: $path"
        return 1
    fi

    # Reject paths to sensitive system directories
    local sensitive_paths="/etc /root /var/log /proc /sys /dev"
    for sensitive in $sensitive_paths; do
        if [[ "$path" == "$sensitive"* ]]; then
            log_error "Access to sensitive path denied: $path"
            return 1
        fi
    done

    return 0
}

# Sanitize a string for safe use in filenames
# Removes or replaces dangerous characters
# Usage: sanitize_filename "string"
sanitize_filename() {
    local input="$1"
    # Remove null bytes, newlines, and other control characters
    # Replace spaces and special chars with underscores
    echo "$input" | tr -d '\0\n\r' | tr -cs '[:alnum:]._-' '_' | head -c 255
}

# Validate consultant name against known valid names
# Usage: validate_consultant_name "name"
validate_consultant_name() {
    local name="$1"
    local upper
    upper=$(to_upper "$name")

    # Check against known agents
    local valid_agents="GEMINI CODEX MISTRAL KILO CURSOR AIDER AMP KIMI CLAUDE QWEN3 GLM GROK DEEPSEEK OLLAMA"
    for agent in $valid_agents; do
        if [[ "$upper" == "$agent" ]]; then
            return 0
        fi
    done

    # Check if it looks like a custom agent (alphanumeric only)
    if [[ ! "$upper" =~ ^[A-Z0-9_]+$ ]]; then
        log_error "Invalid consultant name: $name"
        return 1
    fi

    return 0
}

# =============================================================================
# UTILITY
# =============================================================================

# Builds the complete query from arguments and context file
# Usage: build_full_query "query" "context_file"
build_full_query() {
    local query="$1"
    local context_file="$2"
    local full_query=""

    # Add context if provided
    if [[ -n "$context_file" && -f "$context_file" ]]; then
        full_query=$(cat "$context_file")
    fi

    # Add query if provided
    if [[ -n "$query" ]]; then
        if [[ -n "$full_query" ]]; then
            full_query="${full_query}

# Additional Question
${query}"
        else
            full_query="$query"
        fi
    fi

    echo "$full_query"
}

# Verifies that there is something to send
validate_query() {
    local full_query="$1"
    local consultant="$2"

    if [[ -z "$full_query" ]]; then
        log_error "No query to send to $consultant. Specify a query or a context file."
        return 1
    fi
    return 0
}

# =============================================================================
# BASH 3.2 COMPATIBLE MAP FUNCTIONS
# =============================================================================
# These functions emulate associative arrays for compatibility with macOS
# default bash (3.2). They use dynamic variable names with eval.
#
# IMPORTANT: Keys must be alphanumeric (letters, numbers, underscore).
# Special characters in keys will be stripped.
#
# Usage:
#   map_set "MYMAP" "key" "value"
#   value=$(map_get "MYMAP" "key")
#   map_has "MYMAP" "key" && echo "exists"
#   map_keys "MYMAP"  # prints space-separated keys
#   map_clear "MYMAP"

# Sanitize key for use as variable name (keep only alphanumeric and underscore)
_map_sanitize_key() {
    echo "$1" | tr -cd '[:alnum:]_'
}

# Validate map name to prevent eval injection
# Only allows alphanumeric characters and underscores
_map_validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        log_error "Invalid map name: $name (must be alphanumeric with underscores)"
        return 1
    fi
    echo "$name"
}

# Set a value in a map
# Usage: map_set "MAPNAME" "key" "value"
map_set() {
    local map_name
    map_name=$(_map_validate_name "$1") || return 1
    local safe_key
    safe_key=$(_map_sanitize_key "$2")
    local value="$3"

    eval "_MAP_${map_name}_${safe_key}=\"\$value\""

    # Track keys for iteration (only add if not already present)
    local keys_var="_MAP_${map_name}__KEYS__"
    local current_keys
    eval "current_keys=\"\${$keys_var:-}\""
    if [[ ! " $current_keys " =~ " $safe_key " ]]; then
        if [[ -z "$current_keys" ]]; then
            eval "$keys_var=\"\$safe_key\""
        else
            eval "$keys_var=\"\$current_keys \$safe_key\""
        fi
    fi
}

# Get a value from a map
# Usage: value=$(map_get "MAPNAME" "key")
map_get() {
    local map_name
    map_name=$(_map_validate_name "$1") || return 1
    local safe_key
    safe_key=$(_map_sanitize_key "$2")
    eval "echo \"\${_MAP_${map_name}_${safe_key}:-}\""
}

# Check if a key exists in a map (returns 0 if exists, 1 otherwise)
# Usage: map_has "MAPNAME" "key" && echo "exists"
map_has() {
    local map_name
    map_name=$(_map_validate_name "$1") || return 1
    local safe_key
    safe_key=$(_map_sanitize_key "$2")
    eval "[ -n \"\${_MAP_${map_name}_${safe_key}+x}\" ]"
}

# Get all keys from a map (space-separated)
# Usage: for key in $(map_keys "MAPNAME"); do ...; done
map_keys() {
    local map_name
    map_name=$(_map_validate_name "$1") || return 1
    eval "echo \"\${_MAP_${map_name}__KEYS__:-}\""
}

# Clear all values from a map
# Usage: map_clear "MAPNAME"
map_clear() {
    local map_name
    map_name=$(_map_validate_name "$1") || return 1
    local keys_var="_MAP_${map_name}__KEYS__"
    local keys key
    eval "keys=\"\${$keys_var:-}\""
    for key in $keys; do
        eval "unset _MAP_${map_name}_${key}"
    done
    eval "unset $keys_var"
}

# =============================================================================
# MODULE SOURCING HELPER
# =============================================================================

# Source common.sh from a library module with automatic path detection
# This is called by other lib/*.sh files to source common.sh reliably
# Usage: source_common (call from within the module's directory context)
# Note: This function exists primarily for documentation - modules should
# use the pattern below directly since this function may not exist yet.
#
# Standard pattern for lib modules:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/common.sh" 2>/dev/null || source "${SCRIPT_DIR%/*}/lib/common.sh" 2>/dev/null || true

# =============================================================================
# PANIC MODE DETECTION (v2.2)
# =============================================================================

# Check if panic mode should be triggered based on responses
# Usage: should_trigger_panic <responses_dir>
# Returns: 0 if panic mode should trigger, 1 otherwise
should_trigger_panic() {
    local responses_dir="$1"
    local panic_mode="${ENABLE_PANIC_MODE:-auto}"

    # Never trigger if disabled
    [[ "$panic_mode" == "never" ]] && return 1

    # Always trigger if set to always
    [[ "$panic_mode" == "always" ]] && return 0

    # Auto-detect mode
    local total_confidence=0
    local response_count=0
    local has_uncertainty_keywords=false

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            # Check confidence score
            local confidence
            confidence=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)
            total_confidence=$((total_confidence + confidence))
            ((response_count++))

            # Check for uncertainty keywords in summary/detailed response
            local keywords="${PANIC_KEYWORDS:-uncertain|maybe|not sure|possibly}"
            local text
            text=$(jq -r '(.response.summary // "") + " " + (.response.detailed // "")' "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]')

            if echo "$text" | grep -qiE "$keywords"; then
                has_uncertainty_keywords=true
            fi
        fi
    done

    # Calculate average confidence
    if [[ $response_count -gt 0 ]]; then
        local avg_confidence=$((total_confidence / response_count))
        local threshold="${PANIC_CONFIDENCE_THRESHOLD:-5}"

        # Trigger if average confidence is below threshold
        if [[ $avg_confidence -lt $threshold ]]; then
            return 0
        fi
    fi

    # Trigger if uncertainty keywords found
    if [[ "$has_uncertainty_keywords" == "true" ]]; then
        return 0
    fi

    return 1
}

# Get panic mode diagnosis (for reporting)
# Usage: get_panic_diagnosis <responses_dir>
# Output: JSON with diagnosis details
get_panic_diagnosis() {
    local responses_dir="$1"

    local total_confidence=0
    local response_count=0
    local uncertainty_found=()

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local confidence consultant
            confidence=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)
            consultant=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            total_confidence=$((total_confidence + confidence))
            ((response_count++))

            # Check for keywords
            local keywords="${PANIC_KEYWORDS:-uncertain|maybe|not sure|possibly}"
            local text
            text=$(jq -r '(.response.summary // "") + " " + (.response.detailed // "")' "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]')

            if echo "$text" | grep -qiE "$keywords"; then
                uncertainty_found+=("$consultant")
            fi
        fi
    done

    local avg_confidence=5
    if [[ $response_count -gt 0 ]]; then
        avg_confidence=$((total_confidence / response_count))
    fi

    local threshold="${PANIC_CONFIDENCE_THRESHOLD:-5}"
    local triggers=()

    [[ $avg_confidence -lt $threshold ]] && triggers+=("low_confidence")
    [[ ${#uncertainty_found[@]} -gt 0 ]] && triggers+=("uncertainty_keywords")

    jq -n \
        --argjson avg_confidence "$avg_confidence" \
        --argjson threshold "$threshold" \
        --argjson response_count "$response_count" \
        --arg uncertainty_consultants "$(IFS=','; echo "${uncertainty_found[*]:-}")" \
        --arg triggers "$(IFS=','; echo "${triggers[*]:-}")" \
        '{
            average_confidence: $avg_confidence,
            threshold: $threshold,
            responses_analyzed: $response_count,
            consultants_with_uncertainty: ($uncertainty_consultants | split(",") | map(select(. != ""))),
            triggers: ($triggers | split(",") | map(select(. != ""))),
            triggered: (($triggers | length) > 0)
        }'
}

# =============================================================================
# TOKEN ESTIMATION (v2.1)
# =============================================================================

# Estimate token count from text
# Uses ~4 characters per token approximation for English text
# Usage: estimate_tokens "text" or echo "text" | estimate_tokens
estimate_tokens() {
    local text="${1:-}"
    if [[ -z "$text" ]]; then
        # Read from stdin if no argument
        text=$(cat)
    fi
    local chars
    chars=$(echo -n "$text" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

# Estimate tokens from a file
# Usage: estimate_tokens_file "/path/to/file"
estimate_tokens_file() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        local chars
        chars=$(wc -c < "$file_path" | tr -d ' ')
        echo $((chars / 4))
    else
        echo 0
    fi
}

# Log token estimate with label
# Usage: log_token_estimate "Prompt" "$prompt_text"
log_token_estimate() {
    local label="$1"
    local text="$2"
    local tokens
    tokens=$(estimate_tokens "$text")
    log_debug "$label: ~$tokens tokens (~$((tokens * 4)) chars)"
}

# =============================================================================
# RESPONSE BUILDERS (v2.4)
# =============================================================================
# Shared helpers for building standardized JSON responses in query scripts

# Build metadata JSON for responses
# Usage: build_response_metadata <latency_ms> <model> [error_msg]
build_response_metadata() {
    local latency="$1"
    local model="$2"
    local error="${3:-}"

    jq -n \
        --argjson latency "$latency" \
        --arg model "$model" \
        --arg timestamp "$(date -Iseconds)" \
        --arg error "$error" \
        '{tokens_used: 0, latency_ms: $latency, model_version: $model, timestamp: $timestamp} + (if $error != "" then {error: $error} else {} end)'
}

# Build a complete structured response JSON
# Usage: build_structured_response <consultant> <model> <persona> <inner_json> <latency_ms>
build_structured_response() {
    local consultant="$1"
    local model="$2"
    local persona="$3"
    local inner_json="$4"
    local latency="$5"

    jq -n \
        --arg consultant "$consultant" \
        --arg model "$model" \
        --arg persona "$persona" \
        --argjson inner "$inner_json" \
        --argjson metadata "$(build_response_metadata "$latency" "$model")" \
        '{consultant: $consultant, model: $model, persona: $persona, response: $inner.response, confidence: $inner.confidence, metadata: $metadata}'
}

# Build a fallback response from unstructured text
# Usage: build_fallback_response <consultant> <model> <persona> <response_text> <latency_ms>
build_fallback_response() {
    local consultant="$1"
    local model="$2"
    local persona="$3"
    local response_text="$4"
    local latency="$5"

    jq -n \
        --arg consultant "$consultant" \
        --arg model "$model" \
        --arg persona "$persona" \
        --arg response "$response_text" \
        --argjson metadata "$(build_response_metadata "$latency" "$model")" \
        '{consultant: $consultant, model: $model, persona: $persona,
          response: {summary: "Unstructured response - see detailed", detailed: $response, approach: "unknown", pros: [], cons: [], caveats: ["Unstructured output from consultant"]},
          confidence: {score: 5, reasoning: "Confidence not provided by consultant", uncertainty_factors: ["Non-standard response format"]},
          metadata: $metadata}'
}

# Build an error response
# Usage: build_error_response <consultant> <model> <persona> <error_msg> <latency_ms>
build_error_response() {
    local consultant="$1"
    local model="$2"
    local persona="$3"
    local error_msg="$4"
    local latency="$5"

    jq -n \
        --arg consultant "$consultant" \
        --arg model "$model" \
        --arg persona "$persona" \
        --arg error "$error_msg" \
        --argjson metadata "$(build_response_metadata "$latency" "$model" "$error_msg")" \
        '{consultant: $consultant, model: $model, persona: $persona,
          response: {summary: "ERROR: Consultation failed", detailed: $error, approach: "error", pros: [], cons: [], caveats: []},
          confidence: {score: 0, reasoning: "Consultation failed", uncertainty_factors: ["Execution error"]},
          metadata: $metadata}'
}

# Process consultant response and write to output file
# This encapsulates the common post-processing pattern found in all query scripts
# Usage: process_consultant_response <consultant> <model> <persona> <temp_output> <output_file> <exit_code> <latency_ms> [native_json_field]
# Parameters:
#   consultant       - Consultant name (e.g., "Gemini")
#   model            - Model used (e.g., "gemini-3.0-pro")
#   persona          - Persona name (e.g., "The Architect")
#   temp_output      - Path to temporary output file from CLI/API
#   output_file      - Path to final output file
#   exit_code        - Exit code from CLI/API call
#   latency_ms       - Latency in milliseconds
#   native_json_field - Optional field name to extract from native JSON (e.g., "response" for Gemini)
# Returns: The same exit code passed in
process_consultant_response() {
    local consultant="$1"
    local model="$2"
    local persona="$3"
    local temp_output="$4"
    local output_file="$5"
    local exit_code="$6"
    local latency_ms="$7"
    local native_json_field="${8:-}"

    if [[ $exit_code -eq 0 && -f "$temp_output" && -s "$temp_output" ]]; then
        local raw_response inner_response
        raw_response=$(cat "$temp_output")

        # Try to extract from native JSON format if field specified
        if [[ -n "$native_json_field" ]] && echo "$raw_response" | jq -e ".$native_json_field" > /dev/null 2>&1; then
            inner_response=$(echo "$raw_response" | jq -r ".$native_json_field")
        else
            inner_response="$raw_response"
        fi

        rm -f "$temp_output"

        # Use shared helpers for response building
        if echo "$inner_response" | jq -e '.response.summary' > /dev/null 2>&1; then
            build_structured_response "$consultant" "$model" "$persona" "$inner_response" "$latency_ms" > "$output_file"
        else
            build_fallback_response "$consultant" "$model" "$persona" "$inner_response" "$latency_ms" > "$output_file"
        fi
    else
        rm -f "$temp_output"
        build_error_response "$consultant" "$model" "$persona" "Query failed with exit code $exit_code" "$latency_ms" > "$output_file"
    fi

    return $exit_code
}

# Check if a consultant is enabled
# Usage: is_consultant_enabled <consultant_name>
# Returns: 0 if enabled, 1 if disabled
is_consultant_enabled() {
    local name="$1"
    local name_upper
    name_upper=$(to_upper "$name")
    local var_name="ENABLE_${name_upper}"

    # Get default based on consultant type
    local default="true"
    case "$name_upper" in
        AIDER|AMP|KIMI|CLAUDE|QWEN3|GLM|GROK|DEEPSEEK|OLLAMA)
            default="false"
            ;;
    esac

    [[ "${!var_name:-$default}" == "true" ]]
}

# Get list of enabled consultants
# Usage: get_enabled_consultants
# Output: Space-separated list of enabled consultant names
get_enabled_consultants() {
    local enabled=()
    for consultant in "${ALL_CONSULTANTS[@]}"; do
        if is_consultant_enabled "$consultant"; then
            enabled+=("$consultant")
        fi
    done
    echo "${enabled[@]}"
}
