#!/bin/bash
# common.sh - Shared functions for consultation scripts
# Includes: logging, cross-platform timeout, retry logic, validation

# Guard against double-sourcing
if [[ -n "${_COMMON_SH_SOURCED:-}" ]]; then
    # shellcheck disable=SC2317  # exit 0 is the script-mode fallback for sourced double-load guard
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

# Random stagger delay to avoid rate-limit bursts on parallel launch.
# Usage: apply_launch_stagger
# Sleeps for a random duration between 0 and LAUNCH_STAGGER_MAX_SECONDS.
# No-op if LAUNCH_STAGGER_MAX_SECONDS is 0 or unset.
apply_launch_stagger() {
    local max="${LAUNCH_STAGGER_MAX_SECONDS:-0}"
    if [[ "$max" -gt 0 ]] 2>/dev/null; then
        local delay_ms=$(( RANDOM % (max * 1000) ))
        # Pure-bash second.millisecond formatting (avoids 14× awk forks per consultation).
        local delay_s
        delay_s=$(printf '%d.%03d' "$((delay_ms / 1000))" "$((delay_ms % 1000))")
        log_debug "Stagger delay: ${delay_s}s"
        sleep "$delay_s"
    fi
}

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
    local cmd_name=$1
    local name=$2
    local install_hint=$3

    if ! command -v "$cmd_name" &> /dev/null; then
        log_error "$name not found (command: $cmd_name)"
        if [[ -n "$install_hint" ]]; then
            log_info "Install with: $install_hint"
        fi
        return 1
    fi
    return 0
}

# Run a command with SSH session markers stripped from the environment.
#
# WHY (do not "simplify" this away): the Antigravity CLI (`agy`, our Gemini
# transport) picks its credential store from the environment. When it sees any
# of SSH_CLIENT, SSH_CONNECTION, or SSH_TTY it switches to a file-based token
# store and never consults the macOS Keychain. A user who signed in locally has
# credentials only in the Keychain, so every `agy` call from an SSH session
# fails auth — and re-signing-in does not help, because the new login also lands
# in the Keychain the CLI has already decided to ignore. Clearing the three
# markers for the `agy` process restores Keychain lookup. On a local (non-SSH)
# session they are already unset, so this is a pure no-op there. It grants no
# extra tools or filesystem access; it only changes which credential store the
# CLI consults.
#
# AGY_ENV_PREFIX is the exec-safe form (external `env` binary) for use under
# run_with_timeout / GNU timeout, which cannot invoke shell functions. agy_env
# is the same-shell convenience wrapper. Keep both in lockstep via this array.
#
# Usage (same shell):  agy_env <command> [args...]
# Usage (under timeout / command arrays):  "${AGY_ENV_PREFIX[@]}" <command> [args...]
AGY_ENV_PREFIX=(env -u SSH_CLIENT -u SSH_CONNECTION -u SSH_TTY)
agy_env() { "${AGY_ENV_PREFIX[@]}" "$@"; }

# =============================================================================
# MAIN QUERY EXECUTION FUNCTION
# =============================================================================

# Executes a query to an AI consultant with retry and timeout
#
# Usage: run_query <consultant_name> <output_file> <timeout_sec> <command...>
#
# The query is passed via stdin to the command.
# Use the exec-safe array form under run_query (agy_env is same-shell only).
# Example:
#   echo "$QUERY" | run_query "Gemini" "/tmp/out.json" 120 "${AGY_ENV_PREFIX[@]}" agy -p "..." --model "Gemini 3.1 Pro (High)"
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
        # Keep failures inside an explicit conditional. Without this guard,
        # callers running with `set -e` can exit here before retry handling and
        # the final diagnostic are emitted (observed with several CLIs).
        local exit_code
        if echo "$stdin_content" | run_with_timeout "$timeout_seconds" "${cmd[@]}" > "$output_file" 2> "$error_file"; then
            exit_code=0
        else
            exit_code=$?
        fi

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
        if [[ "${RUN_QUERY_REDACT_ERRORS:-false}" != "true" && -f "$error_file" ]]; then
            error_msg=$(head -5 "$error_file" 2>/dev/null)
        fi

        # First line of the CLI's own stderr — the actual reason (auth error,
        # command not found, etc.). Kept for the final failure message so it
        # reaches the orchestrator's captured stderr (the per-CLI error_file is a
        # mktemp path the caller can't locate).
        local error_first=""
        [[ -n "$error_msg" ]] && error_first=$(printf '%s\n' "$error_msg" | grep -v '^[[:space:]]*$' | head -1 | cut -c1-200)

        if [[ $exit_code -eq 124 ]]; then
            log_warn "[$consultant_name] Timeout after ${timeout_seconds}s"
        else
            log_warn "[$consultant_name] Error (code: $exit_code)${error_first:+: $error_first}"
        fi

        ((attempt++)) || true
        if (( attempt <= MAX_RETRIES )); then
            log_info "Waiting ${RETRY_DELAY_SECONDS}s before next attempt..."
            sleep "$RETRY_DELAY_SECONDS"
        fi
    done

    log_error "[$consultant_name] All $MAX_RETRIES attempts failed${error_first:+: $error_first}"
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
KNOWN_CLI_AGENTS="GEMINI CODEX MISTRAL KIMI CLAUDE QWEN3 GROK MINIMAX"
KNOWN_API_AGENTS="GLM DEEPSEEK"

# Every non-consultant ENABLE_* flag declared in config.sh. This is a denylist
# guarding _discover_custom_api_agents (consult_all.sh): that function walks
# `env`, and any ENABLE_X=true whose X is absent here is enrolled as a custom
# consultant once an X_API_URL is also present. A flag missing from this list is
# therefore a latent phantom-consultant bug, not a cosmetic omission -- it had
# drifted 18 flags out of date before the pin below existed.
# KEEP IN SYNC with the top-level ENABLE_* declarations in config.sh;
# test_common.sh::test_known_feature_flags_in_sync fails the build otherwise.
KNOWN_FEATURE_FLAGS="PERSONA SYNTHESIS CLASSIFICATION SMART_ROUTING \
COST_TRACKING PROGRESS_BARS EARLY_TERMINATION PREFLIGHT \
AST_EXTRACTION BUDGET_LIMIT \
COMPACT_REPORT COST_AWARE_ROUTING HEALTH_GATE \
RELIABILITY_TRACKING RESPONSE_LIMITS SELECTIVE_CONTEXT \
SEMANTIC_CACHE SEMANTIC_CHUNKING SYMBOL_COMPRESSION"

# Check if an agent name is a known predefined agent
# Usage: is_known_agent "AGENTNAME"
is_known_agent() {
    local agent_upper="$1"
    for known in $KNOWN_CLI_AGENTS $KNOWN_API_AGENTS $KNOWN_FEATURE_FLAGS; do
        [[ "$agent_upper" == "$known" ]] && return 0
    done
    return 1
}

# List enabled custom API consultants discovered from the environment.
# Convention: ENABLE_AGENTNAME=true plus AGENTNAME_API_URL. Known consultants
# and non-consultant feature flags are excluded by the shared registry.
_list_custom_api_agents() {
    local var value agent_upper url_var agent_name
    while IFS='=' read -r var value; do
        [[ "$var" == ENABLE_* && "$value" == "true" ]] || continue
        agent_upper="${var#ENABLE_}"
        is_known_agent "$agent_upper" && continue

        url_var="${agent_upper}_API_URL"
        [[ -n "${!url_var:-}" ]] || continue
        agent_name=$(to_title "$agent_upper")
        printf '%s\n' "$agent_name"
    done < <(env)
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
        GROK)       api_key_var="GROK_API_KEY" ;;
        MINIMAX)    api_key_var="MINIMAX_API_KEY" ;;
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
        MINIMAX)    echo "MINIMAX_API_KEY" ;;
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
        GLM)        echo "${GLM_API_URL:-https://api.z.ai/api/coding/paas/v4/chat/completions}" ;;
        GROK)       echo "${GROK_API_URL:-https://api.x.ai/v1/chat/completions}" ;;
        DEEPSEEK)   echo "${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}" ;;
        MINIMAX)    echo "${MINIMAX_API_URL:-https://api.minimax.io/v1/chat/completions}" ;;
        *)          echo "" ;;
    esac
}

# Get the API response format for an agent
# Usage: get_api_format <agent_name>
#
# The per-agent default below is overridable with ${AGENT}_FORMAT (e.g.
# QWEN3_FORMAT=openai), which is what lets a consultant be pointed at an
# endpoint speaking a different wire protocol than its provider's own — Qwen
# Cloud Token Plan, for instance, is OpenAI-compatible while DashScope is not.
# Those variables have been declared in config.sh and documented in
# .env.example since v2.6 but were never read: this function hardcoded the
# mapping, so setting one silently did nothing.
#
# An unrecognized value falls back to the default with a warning rather than
# failing. There is always a correct per-agent default to fall back to, so a
# typo degrades to today's behavior instead of building a malformed body. (The
# reasoning-effort knob deliberately does the opposite — see
# validate_reasoning_effort: substituting a default there would silently ignore
# what the user asked for.)
get_api_format() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")

    local default_format
    case "$agent_upper" in
        GEMINI)     default_format="google_ai" ;;
        CLAUDE)     default_format="anthropic" ;;
        CODEX|MISTRAL|GLM|GROK|DEEPSEEK|MINIMAX)  default_format="openai" ;;
        QWEN3)      default_format="qwen" ;;
        *)          default_format="openai" ;;
    esac

    local override_var="${agent_upper}_FORMAT"
    local override="${!override_var:-}"
    # Lowercase like validate_reasoning_effort does: these are hand-typed .env
    # values, and a capitalized one silently falling back to the provider
    # default sends the wrong envelope to the configured endpoint.
    override=$(echo "$override" | tr '[:upper:]' '[:lower:]')

    if [[ -z "$override" || "$override" == "$default_format" ]]; then
        echo "$default_format"
        return 0
    fi

    case "$override" in
        google_ai|anthropic|qwen|openai)
            echo "$override"
            ;;
        *)
            log_warn "[$agent] $override_var='$override' is not a known API format (google_ai|anthropic|qwen|openai) - using '$default_format'"
            echo "$default_format"
            ;;
    esac
}

# Warn when a reasoning-effort setting cannot be delivered on the CLI transport.
# Usage: warn_effort_ignored_in_cli <agent_name>
#
# api_query.sh reads ${AGENT}_REASONING_EFFORT generically for API transports,
# accept the variable in API mode. CLI adapters that cannot express the setting
# use this diagnostic instead of silently ignoring it.
warn_effort_ignored_in_cli() {
    local agent="$1"
    local agent_upper
    agent_upper=$(to_upper "$agent")
    local var="${agent_upper}_REASONING_EFFORT"
    [[ -n "${!var:-}" ]] || return 0
    # Self-guarding, so call sites do not have to be placed inside the CLI
    # branch: in API mode the setting is honored and must not be warned about.
    #
    # Explicit `if`, not `is_api_mode "$agent" && return 0`: an &&-list that
    # short-circuits returns non-zero as a statement, and under `set -e` that
    # kills the caller. Same shape as the v2.22.0 prompt_value bug.
    if is_api_mode "$agent"; then
        return 0
    fi
    log_warn "[$agent] $var is ignored in CLI mode - this consultant's CLI does not expose a reasoning-effort flag. Set it in the CLI's own configuration, or switch this consultant to API mode."
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
        kimi|kimi_code|kimicode)        echo "KIMI" ;;
        qwen|qwen3|qwen_code|qwencode)  echo "QWEN3" ;;
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

# Return success when a known consultant has a transport configured locally.
# This is intentionally a static check: it only examines a selected API key or
# whether the configured CLI resolves on PATH.  It must not invoke a CLI, ping
# a provider, or otherwise make a network request.
#
# Usage: is_consultant_statically_configured <consultant_name>
is_consultant_statically_configured() {
    local consultant_upper="$1" use_api_var cmd_var api_key_var cmd
    consultant_upper=$(to_upper "$consultant_upper")

    case "$consultant_upper" in
        GLM|DEEPSEEK)
            api_key_var=$(get_api_key_var "$consultant_upper")
            [[ -n "$api_key_var" && -n "${!api_key_var:-}" ]]
            return
            ;;
        GEMINI|CODEX|MISTRAL|KIMI|CLAUDE|QWEN3|GROK|MINIMAX)
            ;;
        *)
            return 1
            ;;
    esac

    use_api_var="${consultant_upper}_USE_API"
    if [[ "${!use_api_var:-false}" == "true" ]]; then
        api_key_var=$(get_api_key_var "$consultant_upper")
        [[ -n "$api_key_var" && -n "${!api_key_var:-}" ]]
        return
    fi

    cmd_var="${consultant_upper}_CMD"
    cmd="${!cmd_var:-}"
    [[ -n "$cmd" ]] && command -v "$cmd" >/dev/null 2>&1
}

# Print canonical preset consultants that are statically configured and not
# the invoking host.  Keep the preset's enabled consultants first, then fill
# any lost slot from ALL_CONSULTANTS in its canonical order.  The caller owns
# the promised-cardinality check so the helper remains useful to offline tests.
#
# Usage: select_preset_consultants <preset_name>
select_preset_consultants() {
    local preset="$1" promised consultant consultant_upper enable_var
    local -a selected=()

    promised=$(get_effective_preset_panel_size "$preset") || return 1

    # Preserve the preset's existing primary panel and its ordering.
    for consultant in "${ALL_CONSULTANTS[@]}"; do
        consultant_upper=$(to_upper "$consultant")
        enable_var="ENABLE_${consultant_upper}"
        [[ "${!enable_var:-false}" == "true" ]] || continue
        should_skip_consultant "$consultant_upper" && continue
        is_consultant_statically_configured "$consultant_upper" || continue
        selected+=("$consultant")
    done

    # Refill host-excluded or unavailable primary slots from the canonical
    # roster.  The first pass above prevents a configured primary consultant
    # from moving behind a fallback.
    if [[ ${#selected[@]} -lt $promised ]]; then
        for consultant in "${ALL_CONSULTANTS[@]}"; do
            [[ ${#selected[@]} -ge $promised ]] && break
            consultant_upper=$(to_upper "$consultant")
            should_skip_consultant "$consultant_upper" && continue
            is_consultant_statically_configured "$consultant_upper" || continue

            case " ${selected[*]-} " in
                *" $consultant "*) continue ;;
            esac
            selected+=("$consultant")
        done
    fi

    printf '%s\n' "${selected[@]+"${selected[@]}"}"
}

# Render the actionable failure used when a preset's static transports cannot
# fulfill its documented panel size.  Do not replace this with a health check:
# availability here is purposely local and side-effect free.
# Usage: log_preset_capacity_diagnostic <preset> <raw_promised> <effective_target> <selected_count>
log_preset_capacity_diagnostic() {
    local preset="$1" raw_promised="$2" effective_target="$3" selected_count="$4" missing
    missing=$((effective_target - selected_count))
    log_error "Preset '$preset' promises $raw_promised consultants (effective target: $effective_target after host self-exclusion), but static transport selection found $selected_count; missing capacity: $missing."
    log_info "Install or configure $missing additional eligible consultant transport(s) (CLI on PATH or API mode with its API key), then rerun the preset."
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
    local valid_agents="GEMINI CODEX MISTRAL KIMI CLAUDE QWEN3 GLM GROK DEEPSEEK MINIMAX"
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
    if [[ " $current_keys " != *" $safe_key "* ]]; then
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
# TOKEN ESTIMATION (v2.1)
# =============================================================================

# Estimate token count from text
# Uses ~4 characters per token approximation for English text
# Usage: estimate_tokens "text" or echo "text" | estimate_tokens
estimate_tokens() {
    local text
    # Decide by argument COUNT, not emptiness: `estimate_tokens ""` is an
    # explicit empty string (0 tokens), not a request to read stdin. Keying on
    # `-z` made the two indistinguishable, so an empty-string call fell through
    # to `cat` and blocked forever whenever stdin was an open pipe rather than
    # closed/EOF — a hang that passed in CI (stdin is /dev/null there) and wedged
    # local gate runs. Only a genuinely arg-less call reads stdin.
    if [[ $# -gt 0 ]]; then
        text="$1"
    else
        text=$(cat)
    fi
    local chars
    chars=$(echo -n "$text" | wc -c | tr -d ' ')
    echo $((chars / 4))
}

# =============================================================================
# RESPONSE BUILDERS (v2.4)
# =============================================================================
# Shared helpers for building standardized JSON responses in query scripts

# Token counts published by the API layer for the response it just wrote, as
# "<input> <output>". Consumed and cleared by resolve_response_tokens.
#
# A plain variable, not a file: every caller of run_api_mode_query invokes it as
# a plain statement in the current shell (verified across all six call sites),
# so an assignment propagates. An earlier cut of this change used a temp-file
# sidecar, justified by a claim that some callers run in a command
# substitution - that claim was false, and it bought a cross-function file
# lifecycle with five cleanup sites for nothing. The real subshell constraint
# applies to calculate_session_cost / format_cost_caveats, which ARE always
# called as $(...) and therefore take their input as arguments.
_API_TOKEN_SPLIT=""

# Publish the API layer's measured split. Usage: set_api_token_split <in> <out>
set_api_token_split() {
    _API_TOKEN_SPLIT="${1:-0} ${2:-0}"
}

# Clear a published split once it has been consumed, so a CLI-mode response
# later in the same shell cannot inherit an earlier API call's figures.
# Callers do this, not resolve_response_tokens: that runs inside $(...) and an
# assignment there dies with the subshell - it can read the variable (subshells
# inherit) but never clear it.
clear_api_token_split() {
    _API_TOKEN_SPLIT=""
}

# Determine the token counts for a response and where they came from.
# Usage: resolve_response_tokens <input_text> <response_text>
# Echoes: "<total> <source> <input> <output>", source = measured|estimated
#
# API mode gets the provider's own usage figures; CLI mode has no such data, so
# it falls back to the 4-chars-per-token approximation over prompt + reply. The
# source is recorded alongside the numbers so cost reports can say which they
# are built on instead of presenting an approximation as a measurement.
#
# Both halves are measured in BYTES via estimate_tokens. Passing a bash
# character count for one and a byte count for the other under-counted
# multibyte input roughly threefold.
resolve_response_tokens() {
    local input_text="${1:-}"
    local response_text="${2:-}"
    local input_multiplier="${3:-1}"
    [[ "$input_multiplier" =~ ^[1-9][0-9]*$ ]] || input_multiplier=1

    if [[ -n "$_API_TOKEN_SPLIT" ]]; then
        local m_in m_out
        read -r m_in m_out <<< "$_API_TOKEN_SPLIT"
        [[ "$m_in"  =~ ^[0-9]+$ ]] || m_in=0
        [[ "$m_out" =~ ^[0-9]+$ ]] || m_out=0
        if (( m_in + m_out > 0 )); then
            echo "$(( m_in + m_out )) measured $m_in $m_out"
            return 0
        fi
    fi

    local in_tokens=0 out_tokens=0
    [[ -n "$input_text" ]]    && in_tokens=$(estimate_tokens "$input_text")
    [[ -n "$response_text" ]] && out_tokens=$(estimate_tokens "$response_text")
    [[ "$in_tokens"  =~ ^[0-9]+$ ]] || in_tokens=0
    [[ "$out_tokens" =~ ^[0-9]+$ ]] || out_tokens=0
    in_tokens=$((in_tokens * input_multiplier))
    echo "$(( in_tokens + out_tokens )) estimated $in_tokens $out_tokens"
}

# Build metadata JSON for responses
# Usage: build_response_metadata <latency_ms> <model> [error_msg] [tokens] [source]
#        [tokens_input] [tokens_output] [provider_cost_usd]
#
# tokens_used was hardcoded to 0 until v2.25, which made every session's cost
# report read $0.00 regardless of what was actually spent (calculate_session_cost
# multiplies this field by the model rate). tokens_source records whether the
# figure is the provider's own or a local approximation.
build_response_metadata() {
    local latency="$1"
    local model="$2"
    local error="${3:-}"
    local tokens="${4:-0}"
    local source="${5:-unknown}"
    local tokens_in="${6:-}"
    local tokens_out="${7:-}"
    local provider_cost="${8:-}"
    local requested_model="${9:-$model}"
    local model_identity_source="${10:-requested-only}"
    local response_quality="${11:-unknown}"

    jq -n \
        --argjson latency "$latency" \
        --arg model "$model" \
        --arg timestamp "$(date -Iseconds)" \
        --arg error "$error" \
        --argjson tokens "${tokens:-0}" \
        --arg source "$source" \
        --arg t_in "$tokens_in" \
        --arg t_out "$tokens_out" \
        --arg provider_cost "$provider_cost" \
        --arg requested_model "$requested_model" \
        --arg model_identity_source "$model_identity_source" \
        --arg response_quality "$response_quality" \
        '{tokens_used: $tokens, tokens_source: $source, latency_ms: $latency, model_version: $model,
          requested_model: $requested_model, model_identity_source: $model_identity_source,
          response_quality: $response_quality, timestamp: $timestamp}
         + (if $t_in  != "" then {tokens_input:  ($t_in  | tonumber)} else {} end)
         + (if $t_out != "" then {tokens_output: ($t_out | tonumber)} else {} end)
         + (if $provider_cost != "" then {provider_cost_usd: ($provider_cost | tonumber)} else {} end)
         + (if $error != "" then {error: $error} else {} end)'
}

# Build a complete structured response JSON
# Usage: build_structured_response <consultant> <model> <persona> <inner_json> <latency_ms>
build_structured_response() {
    local consultant="$1"
    local model="$2"
    local persona="$3"
    local inner_json="$4"
    local latency="$5"
    local tokens="${6:-0}"
    local tokens_source="${7:-unknown}"
    local tokens_in="${8:-}"
    local tokens_out="${9:-}"
    local provider_cost="${10:-}"
    local requested_model="${11:-$model}"
    local model_identity_source="${12:-requested-only}"

    jq -n \
        --arg consultant "$consultant" \
        --arg model "$model" \
        --arg persona "$persona" \
        --argjson inner "$inner_json" \
        --argjson metadata "$(build_response_metadata "$latency" "$model" "" "$tokens" "$tokens_source" "$tokens_in" "$tokens_out" "$provider_cost" "$requested_model" "$model_identity_source" structured)" \
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
    local tokens="${6:-0}"
    local tokens_source="${7:-unknown}"
    local tokens_in="${8:-}"
    local tokens_out="${9:-}"
    local provider_cost="${10:-}"
    local requested_model="${11:-$model}"
    local model_identity_source="${12:-requested-only}"
    local summary
    summary=$(printf '%s\n' "$response_text" | awk 'NF {print; exit}' | sed -E 's/^[[:space:]#>*-]+//' | cut -c1-500)
    [[ -n "$summary" ]] || summary="Unstructured provider response"

    jq -n \
        --arg consultant "$consultant" \
        --arg model "$model" \
        --arg persona "$persona" \
        --arg response "$response_text" \
        --arg summary "$summary" \
        --argjson metadata "$(build_response_metadata "$latency" "$model" "" "$tokens" "$tokens_source" "$tokens_in" "$tokens_out" "$provider_cost" "$requested_model" "$model_identity_source" fallback)" \
        '{consultant: $consultant, model: $model, persona: $persona,
          response: {summary: $summary, detailed: $response, approach: "unstructured-provider-response", pros: [], cons: [], caveats: ["Provider returned valid text outside the requested JSON schema"]},
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
    local requested_model="${6:-$model}"
    local model_identity_source="${7:-requested-only}"
    local tokens="${8:-0}"
    local tokens_source="${9:-unknown}"
    local tokens_in="${10:-}"
    local tokens_out="${11:-}"
    local provider_cost="${12:-}"

    jq -n \
        --arg consultant "$consultant" \
        --arg model "$model" \
        --arg persona "$persona" \
        --arg error "$error_msg" \
        --argjson metadata "$(build_response_metadata "$latency" "$model" "$error_msg" "$tokens" "$tokens_source" "$tokens_in" "$tokens_out" "$provider_cost" "$requested_model" "$model_identity_source" error)" \
        '{consultant: $consultant, model: $model, persona: $persona,
          response: {summary: "ERROR: Consultation failed", detailed: $error, approach: "error", pros: [], cons: [], caveats: []},
          confidence: {score: 0, reasoning: "Consultation failed", uncertainty_factors: ["Execution error"]},
          metadata: $metadata}'
}

# Process consultant response and write to output file
# Strip a markdown code fence wrapping a JSON payload.
# Some CLIs print the model's JSON inside a ```json ... ``` fence instead of raw
# JSON (e.g. agy / Gemini 3.1 Pro), which breaks downstream jq parsing. This is
# fallback-only: if the input already parses as JSON it is returned unchanged
# (a real fence makes the text invalid JSON, so the gate reliably detects it).
# Usage: cleaned=$(strip_json_fence "$raw")
# Extract the model's response from kimi's --output-format stream-json output
# (JSONL, one object per line). The real answer is the LAST {"role":"assistant"}
# line's .content; the {"role":"meta",...} session-resume line is dropped. Handles
# .content as a string OR a block-array ([{type,text},...]); tolerates non-object
# and non-JSON lines. Echoes the content (empty if none, so the caller keeps the
# raw output for its fallback path).
# Usage: content=$(_kimi_extract_content <stream-json-file>)
_kimi_extract_content() {
    jq -sRr '
        [ splits("\n") | fromjson? | select(type=="object" and .role=="assistant") | .content ] | last as $c
        | if   $c == null          then ""
          elif ($c|type) == "array"  then ($c | map(if type=="object" then (.text // .content // "") else tostring end) | join(""))
          elif ($c|type) == "string" then $c
          else ($c | tostring) end
    ' "$1" 2>/dev/null
}

# Validate the response envelope rather than guessing from filenames. Pipeline
# metadata and peer-review artifacts can use arbitrary names, while anonymous
# copies deliberately remove the consultant identity. Every loop that consumes
# consultant responses must gate on the actual shape. Shared by voting.sh,
# peer_review.sh, synthesize.sh, and costs.sh.
_is_consultant_response_file() {
    local f="$1"
    [[ -f "$f" && -s "$f" ]] || return 1
    jq -e '
        type == "object" and
        (.consultant | type == "string" and length > 0) and
        (.response | type == "object")
    ' "$f" >/dev/null 2>&1
}

# A syntactically valid consultant envelope is not necessarily a usable answer:
# error envelopes share the same outer shape. Synthesis and fallback statistics
# must consume only provider responses that completed successfully.
_is_successful_consultant_response_file() {
    local f="$1"
    _is_consultant_response_file "$f" || return 1
    jq -e '
        (.response.approach // "") != "error" and
        (.metadata.response_quality // "unknown") != "error" and
        ((.metadata.error // "") == "") and
        ((.confidence.score // 0) > 0)
    ' "$f" >/dev/null 2>&1
}

# Extract a concise, ANSI-stripped failure reason from a consultant's captured
# stderr (.err) file, for surfacing WHY a consultant produced no output (auth
# error, CLI not installed, transient init failure, ...) instead of a bare
# "Failed". Prefers an explicit error-ish line; falls back to the last non-empty
# line. Returns empty string if the file is missing/empty.
# Usage: reason=$(get_consultant_error_reason "$err_file")
get_consultant_error_reason() {
    local ef="$1"
    [[ -s "$ef" ]] || return 0
    local esc cleaned line
    esc=$(printf '\033')
    # Strip ANSI, blank lines, AND our own orchestration status logs first — those
    # carry no failure info and would otherwise be mis-picked (e.g. the
    # "Consulting X (timeout: 180s...)" header matches the 'timeout' pattern below).
    cleaned=$(sed "s/${esc}\[[0-9;]*m//g" "$ef" 2>/dev/null \
        | grep -v '^[[:space:]]*$' \
        | grep -ivE '\[INFO\].*(Consulting|Response received|Waiting .* before|Attempt [0-9]|Querying)')
    # Prefer a line that names an actual error; else the last remaining line.
    line=$(printf '%s\n' "$cleaned" | grep -iE 'error|fail|not found|no such|denied|unauthor|invalid|timed? ?out|missing|command not found|exit code' | tail -1)
    [[ -z "$line" ]] && line=$(printf '%s\n' "$cleaned" | tail -1)
    # Strip our own log_error() wrapper boilerplate ("[HH:MM:SS] [LEVEL] [Consultant]
    # All N attempts failed:") so only the underlying CLI error remains -- the
    # consultant name is already a separate report column and the retry count
    # carries no diagnostic signal. Anchored on the full shape (only ever emitted
    # together by run_query's final log_error) so it stays generic + non-regressing.
    line=$(printf '%s' "$line" | sed -E 's/^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] \[(DEBUG|INFO|WARN|ERROR)\] \[[^]]+\] All [0-9]+ attempts failed:?[[:space:]]*//')
    # If stripping the "All N attempts failed:" boilerplate emptied the line (a
    # bare timeout / no-stderr summary carries no trailing reason), fall back to
    # the last real line that ISN'T that boilerplate -- otherwise a plain timeout
    # surfaces as empty -> the "CLI missing/unauth" mis-attribution (v2.18.0 class).
    if [[ -z "$line" ]]; then
        line=$(printf '%s\n' "$cleaned" \
            | grep -ivE '\] \[[^]]+\] All [0-9]+ attempts failed' \
            | grep -iE 'error|fail|not found|no such|denied|unauthor|invalid|timed? ?out|missing|command not found|exit code' \
            | tail -1)
    fi
    printf '%s' "$line" | cut -c1-200
}

# Render one DIAGNOSED_FAILURES entry ("name|reason") for a given surface.
# Single source of the "name|reason" decode (used by both the console log and the
# report table), and the table mode escapes any '|' in the reason so a CLI error
# containing a pipe doesn't mangle the markdown row.
# Usage: render_diagnosed_failure "<name>|<reason>" [console|table]
render_diagnosed_failure() {
    local entry="$1" mode="${2:-console}" name reason
    name="${entry%%|*}"
    reason="${entry#*|}"
    if [[ "$mode" == "table" ]]; then
        printf '| %s | %s |' "$name" "${reason//|/\\|}"
    else
        printf '  - %s: %s' "$name" "$reason"
    fi
}

# Grade a consultation by how many consultants responded (v2.19.0).
# Usage: grade_quorum <success_count> <attempted_count> <min_quorum>
# Echoes: FAILED (< min) | DEGRADED (>= min but some failed) | MET (all responded)
grade_quorum() {
    local success="$1" attempted="$2" min="$3"
    if [[ "$success" -lt "$min" ]]; then
        echo "FAILED"
    elif [[ "$success" -lt "$attempted" ]]; then
        echo "DEGRADED"
    else
        echo "MET"
    fi
}

# Send a trivial real "ping" query to a consultant's query script and report
# whether it produced a structurally valid response. Shared by `doctor --live`
# and the consult_all health gate. Persona is disabled (we only need a parseable
# envelope, not a full analysis). Caller provides scratch out/err paths.
# <id> is the ALREADY-lowercased consultant id. Callers compute the lowercase
# form anyway (for the out/err paths), so we take it directly instead of forking
# to_lower again per consultant.
# Usage: ping_consultant <id> <scripts_dir> <timeout_s> <out_file> <err_file>
# Returns: 0 = responded, 1 = failed/empty, 2 = no query script (not probeable)
ping_consultant() {
    local id="$1" scripts_dir="$2" timeout_s="$3" out="$4" err="$5"
    local qs="$scripts_dir/query_${id}.sh"
    [[ -x "$qs" ]] || return 2
    ENABLE_PERSONA=false run_with_timeout "$timeout_s" "$qs" "Reply with exactly: OK" "" "$out" >/dev/null 2>"$err" || true
    [[ -s "$out" ]] && jq -e '.response' "$out" >/dev/null 2>&1
}

strip_json_fence() {
    local text="$1"
    if echo "$text" | jq -e '.' > /dev/null 2>&1; then
        printf '%s' "$text"
        return 0
    fi
    # Drop lines that are purely a fence marker (```), optionally with a language
    # tag (```json). A valid JSON string value can never be such a line (JSON
    # strings cannot contain a raw newline), so this never corrupts valid JSON.
    printf '%s\n' "$text" | sed '/^[[:space:]]*```[[:alnum:]]*[[:space:]]*$/d'
}

# Normalize a provider's textual payload into the required response envelope.
# Returns 0 for structured JSON, 1 for valid non-JSON text, and 2 for a JSON-like
# payload that is malformed/truncated or uses the wrong schema. Valid JSON string
# wrappers are unwrapped twice (observed with CLI envelopes that double-encode
# the model response).
normalize_consultant_response_text() {
    local text="$1" decoded depth=0 first_char
    text=$(strip_json_fence "$text")

    while (( depth < 2 )) && printf '%s' "$text" | jq -e 'type == "string"' >/dev/null 2>&1; do
        decoded=$(printf '%s' "$text" | jq -r '.') || break
        text="$decoded"
        depth=$((depth + 1))
    done

    printf '%s' "$text"
    if printf '%s' "$text" | jq -e \
            'type == "object" and (.response | type == "object") and
             (.response.summary | type == "string") and
             (.confidence | type == "object")' >/dev/null 2>&1; then
        return 0
    fi

    first_char=$(printf '%s' "$text" | sed -E 's/^[[:space:]]*//' | cut -c1)
    if printf '%s' "$text" | jq -e '.' >/dev/null 2>&1 \
        || [[ "$first_char" == "{" || "$first_char" == "[" ]]; then
        return 2
    fi
    return 1
}

# This encapsulates the common post-processing pattern found in all query scripts
# Usage: process_consultant_response <consultant> <model> <persona> <temp_output> <output_file> <exit_code> <latency_ms> [native_json_field]
# Parameters:
#   consultant       - Consultant name (e.g., "Gemini")
#   model            - Model used (e.g., "gemini-3.1-pro-preview")
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
    local input_text="${9:-}"
    local requested_model="${10:-$model}"
    local model_identity_source="${11:-requested-only}"
    local effective_model="${12:-$model}"
    local input_multiplier="${13:-1}"

    if [[ $exit_code -eq 0 && -f "$temp_output" && -s "$temp_output" ]]; then
        local raw_response inner_response
        raw_response=$(cat "$temp_output")

        local _tok _tok_src _tok_in _tok_out
        read -r _tok _tok_src _tok_in _tok_out <<< "$(resolve_response_tokens "$input_text" "$raw_response" "$input_multiplier")"
        clear_api_token_split

        # Try to extract from native JSON format if field specified
        if [[ -n "$native_json_field" ]] && echo "$raw_response" | jq -e ".$native_json_field" > /dev/null 2>&1; then
            inner_response=$(echo "$raw_response" | jq -r ".$native_json_field")
        else
            inner_response="$raw_response"
        fi

        rm -f "$temp_output"

        local normalization_rc
        if inner_response=$(normalize_consultant_response_text "$inner_response"); then
            normalization_rc=0
        else
            normalization_rc=$?
        fi

        if [[ $normalization_rc -eq 0 ]]; then
            build_structured_response "$consultant" "$effective_model" "$persona" "$inner_response" "$latency_ms" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" "" "$requested_model" "$model_identity_source" > "$output_file"
        elif [[ $normalization_rc -eq 1 ]]; then
            build_fallback_response "$consultant" "$effective_model" "$persona" "$inner_response" "$latency_ms" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" "" "$requested_model" "$model_identity_source" > "$output_file"
        else
            log_error "[$consultant] Provider returned malformed, truncated, or schema-invalid JSON"
            build_error_response "$consultant" "$effective_model" "$persona" \
                "Provider returned malformed, truncated, or schema-invalid JSON" "$latency_ms" \
                "$requested_model" "$model_identity_source" "$_tok" "$_tok_src" "$_tok_in" "$_tok_out" > "$output_file"
            return 1
        fi
    else
        rm -f "$temp_output"
        local _err_tok=0 _err_src=unknown _err_in="" _err_out=""
        if [[ -n "$_API_TOKEN_SPLIT" ]]; then
            read -r _err_tok _err_src _err_in _err_out <<< "$(resolve_response_tokens "$input_text" "")"
            clear_api_token_split
        fi
        build_error_response "$consultant" "$effective_model" "$persona" \
            "Query failed with exit code $exit_code" "$latency_ms" \
            "$requested_model" "$model_identity_source" \
            "$_err_tok" "$_err_src" "$_err_in" "$_err_out" > "$output_file"
    fi

    return $exit_code
}

# =============================================================================
# SYNTHESIS CLI RESOLUTION (v2.10.1)
# =============================================================================

# Map a canonical consultant name (from get_self_consultant_name) to its CLI command name.
# Usage: cli=$(_consultant_to_cli "CLAUDE")
_consultant_to_cli() {
    case "$1" in
        CLAUDE)  echo "claude" ;;
        GEMINI)  echo "gemini" ;;
        CODEX)   echo "codex" ;;
        MISTRAL) echo "mistral" ;;
        KIMI)    echo "kimi" ;;
        QWEN3)   echo "qwen" ;;
        *)       echo "" ;;
    esac
}

# Resolve which CLI to use for synthesis.
# Avoids using the invoking agent's CLI (self-consultation prevention).
# Walks a fallback chain: configured SYNTHESIS_CMD → gemini → codex → claude.
#
# Usage: SYNTH_CLI=$(resolve_synthesis_cli)
# Returns: CLI type name (gemini, codex, claude) or empty string on failure
_synthesis_cli_ready() {
    local candidate="$1" cmd help status
    case "$candidate" in
        claude)
            cmd="${CLAUDE_CMD:-claude}"
            command -v "$cmd" >/dev/null 2>&1 || return 1
            help=$(run_with_timeout 8 "$cmd" --help 2>&1) || return 1
            for flag in --print --no-session-persistence --setting-sources --tools; do
                grep -q -- "$flag" <<<"$help" || return 1
            done
            if grep -Eq '^[[:space:]]+auth([[:space:]]|$)' <<<"$help"; then
                status=$(run_with_timeout 12 "$cmd" auth status 2>&1) || return 1
                printf '%s' "$status" | jq -e '.loggedIn == true' >/dev/null 2>&1
            else
                return 0
            fi
            ;;
        gemini)
            cmd="${GEMINI_CMD:-agy}"
            command -v "$cmd" >/dev/null 2>&1 || return 1
            run_with_timeout 12 "${AGY_ENV_PREFIX[@]}" "$cmd" models >/dev/null 2>&1
            ;;
        codex)
            cmd="${CODEX_CMD:-codex}"
            command -v "$cmd" >/dev/null 2>&1 || return 1
            run_with_timeout 8 "$cmd" --version >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

resolve_synthesis_cli() {
    # Reuse get_self_consultant_name for complete alias coverage
    local avoid_cmd
    avoid_cmd=$(_consultant_to_cli "$(get_self_consultant_name)")

    # 1. Check if SYNTHESIS_CMD is configured and is not the invoking agent
    local configured="${SYNTHESIS_CMD:-}"
    if [[ -n "$configured" && "$configured" != "$avoid_cmd" ]]; then
        if _synthesis_cli_ready "$configured"; then
            echo "$configured"
            return 0
        fi
    fi

    # 2. Walk fallback chain: pick first available CLI that isn't the invoking agent
    local candidate
    for candidate in gemini codex claude; do
        [[ "$candidate" == "$avoid_cmd" ]] && continue
        if _synthesis_cli_ready "$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
    return 1
}

# Build synthesis command arguments for a resolved CLI type.
# Sets the global SYNTHESIS_ARGS array directly (no eval needed).
# Usage: build_synthesis_args <cli_type> [prompt] [codex_payload_file]
build_synthesis_args() {
    local cli_type="$1"
    local prompt="${2:-}"   # agy takes the prompt inline (-p arg); others read stdin
    local codex_payload_file="${3:-}"

    case "$cli_type" in
        claude)
            SYNTHESIS_ARGS=("${CLAUDE_CMD:-claude}" "--print" \
                "--no-session-persistence" "--setting-sources" "" "--tools" "" \
                "--strict-mcp-config" "--mcp-config" '{"mcpServers":{}}' \
                "--permission-mode" "plan")
            local model="${SYNTHESIS_MODEL:-${CLAUDE_MODEL:-}}"
            [[ -n "$model" ]] && SYNTHESIS_ARGS+=("--model" "$model")
            ;;
        gemini)
            # agy's -p takes the prompt as its ARGUMENT value; it does NOT read
            # stdin and "-" is not a stdin sentinel. A prior `-p -` made agy answer
            # a literal "-" with a generic greeting -> unparseable synthesis ->
            # manual_review. Pass the prompt directly, mirroring query_gemini.sh.
            # AGY_ENV_PREFIX is exec-safe under timeout (see agy_env above).
            SYNTHESIS_ARGS=("${AGY_ENV_PREFIX[@]}" "${GEMINI_CMD:-agy}" "-p" "$prompt")
            local model="${SYNTHESIS_MODEL:-${GEMINI_MODEL:-}}"
            [[ -n "$model" ]] && SYNTHESIS_ARGS+=("--model" "$model")
            ;;
        codex)
            [[ -n "$codex_payload_file" ]] || {
                log_warn "Codex synthesis requires an output payload path"
                return 1
            }
            SYNTHESIS_ARGS=("${CODEX_CMD:-codex}" exec --ephemeral \
                --ignore-user-config --ignore-rules --skip-git-repo-check \
                -s read-only --color never -o "$codex_payload_file")
            local model="${SYNTHESIS_MODEL:-${CODEX_MODEL:-}}"
            [[ -n "$model" ]] && SYNTHESIS_ARGS+=(-m "$model")
            SYNTHESIS_ARGS+=(-)
            ;;
        *)
            log_warn "Unknown synthesis CLI type: $cli_type"
            return 1
            ;;
    esac
    return 0
}
