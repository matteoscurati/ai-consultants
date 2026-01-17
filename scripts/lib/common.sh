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
        if echo "$stdin_content" | run_with_timeout "$timeout_seconds" "${cmd[@]}" > "$output_file" 2> "$error_file"; then
            # Verify that the output is not empty
            if [[ -s "$output_file" ]]; then
                log_success "[$consultant_name] Response received ($(wc -c < "$output_file" | tr -d ' ') bytes)"
                rm -f "$error_file"
                return 0
            else
                log_warn "[$consultant_name] Empty response"
            fi
        fi

        # Error handling
        local exit_code=$?
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
KNOWN_CLI_AGENTS="GEMINI CODEX MISTRAL KILO CURSOR AIDER CLAUDE"
KNOWN_API_AGENTS="QWEN3 GLM GROK DEEPSEEK"
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
    local valid_agents="GEMINI CODEX MISTRAL KILO CURSOR QWEN3 GLM GROK"
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

# Set a value in a map
# Usage: map_set "MAPNAME" "key" "value"
map_set() {
    local map_name="$1"
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
    local map_name="$1"
    local safe_key
    safe_key=$(_map_sanitize_key "$2")
    eval "echo \"\${_MAP_${map_name}_${safe_key}:-}\""
}

# Check if a key exists in a map (returns 0 if exists, 1 otherwise)
# Usage: map_has "MAPNAME" "key" && echo "exists"
map_has() {
    local map_name="$1"
    local safe_key
    safe_key=$(_map_sanitize_key "$2")
    eval "[ -n \"\${_MAP_${map_name}_${safe_key}+x}\" ]"
}

# Get all keys from a map (space-separated)
# Usage: for key in $(map_keys "MAPNAME"); do ...; done
map_keys() {
    local map_name="$1"
    eval "echo \"\${_MAP_${map_name}__KEYS__:-}\""
}

# Clear all values from a map
# Usage: map_clear "MAPNAME"
map_clear() {
    local map_name="$1"
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
