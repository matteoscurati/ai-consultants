#!/bin/bash
# common.sh - Shared functions for consultation scripts
# Includes: logging, cross-platform timeout, retry logic, validation

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
    "${cmd[@]}" &
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
KNOWN_CLI_AGENTS="GEMINI CODEX MISTRAL KILO CURSOR"
KNOWN_API_AGENTS="QWEN3 GLM GROK"
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
    if [[ "$path" == *$'\0'* ]]; then
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
