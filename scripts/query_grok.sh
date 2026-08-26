#!/bin/bash
# query_grok.sh - Query Grok Build CLI, with xAI API fallback
#
# Usage: ./query_grok.sh "question" [context_file] [output_file]
#
# Environment variables:
#   GROK_CMD        - Grok Build command (default: grok)
#   GROK_MODEL      - Model to use in both transports (default: grok-4.6)
#   GROK_TIMEOUT    - Timeout in seconds (default: 180)
#   GROK_MAX_TURNS  - Bounded advisory turns (default: 4)
#   GROK_USE_API    - Force the API path when true (default: CLI-first auto)
#   GROK_API_KEY    - xAI API key used by the fallback
#   XAI_API_KEY     - Official xAI key name; accepted as a GROK_API_KEY alias
#   GROK_REASONING_EFFORT - Optional CLI/API effort; max_quality sets xhigh
#   GROK_OAUTH_MODE - shared (default, concurrent) or serialized (diagnostic)
#   ENABLE_PERSONA  - Enable "The Provocateur" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"
source "$SCRIPT_DIR/lib/grok_oauth.sh"

QUERY="${1:-}"
CONTEXT_FILE="${2:-}"
OUTPUT_FILE="${3:-/tmp/grok_response.json}"

ENABLE_PERSONA="${ENABLE_PERSONA:-true}"
CONSULTANT_NAME="Grok"

FULL_QUERY=$(build_full_query "$QUERY" "$CONTEXT_FILE")
validate_query "$FULL_QUERY" "$CONSULTANT_NAME" || exit 1

if [[ "$ENABLE_PERSONA" == "true" ]]; then
    FULL_QUERY=$(build_query_with_persona "$CONSULTANT_NAME" "$FULL_QUERY")
fi

START_TIME=$(get_timestamp_ms)
TEMP_OUTPUT=$(mktemp)
GROK_RUNTIME_DIR=""
TRANSPORT="cli"
GROK_CLI_VERSION=""
GROK_CLI_COMPATIBILITY=""
GROK_SUPPORTS_NO_AUTO_UPDATE=false
GROK_SUPPORTS_REASONING_EFFORT=false
GROK_CLI_EFFORT=""
_GROK_CAPABILITY_ERROR=""
_GROK_REQUEST_LAUNCHED=false
_GROK_MODEL_PROBE_ERROR=""
_GROK_OAUTH_PREPARED=false
_GROK_OAUTH_FAILURE=false
exit_code=1

if ! [[ "$GROK_MAX_TURNS" =~ ^[1-9][0-9]*$ ]]; then
    log_error "[$CONSULTANT_NAME] GROK_MAX_TURNS must be a positive integer (got: $GROK_MAX_TURNS)"
    build_error_response "$CONSULTANT_NAME" "$GROK_MODEL" "$(get_persona_name "$CONSULTANT_NAME")" \
        "Invalid GROK_MAX_TURNS" 0 "$GROK_MODEL" requested-only > "$OUTPUT_FILE"
    cat "$OUTPUT_FILE"
    exit 1
fi

cleanup() {
    grok_oauth_release_lock
    rm -f "$TEMP_OUTPUT" "${TEMP_OUTPUT}.err"

    # GROK_RUNTIME_DIR is always created by this script under the system temp
    # directory. Validate the prefix before recursive cleanup so an unexpected
    # empty or overridden value can never widen the deletion target.
    local temp_prefix="${TMPDIR:-/tmp}"
    temp_prefix="${temp_prefix%/}/ai-consultants-grok."
    if [[ -n "$GROK_RUNTIME_DIR" && "$GROK_RUNTIME_DIR" == "$temp_prefix"* ]]; then
        rm -rf -- "$GROK_RUNTIME_DIR"
    fi
}
trap cleanup EXIT

run_grok_api() {
    source "$SCRIPT_DIR/lib/api_query.sh"
    : > "$TEMP_OUTPUT"
    if run_api_mode_query \
            "$CONSULTANT_NAME" \
            "$GROK_MODEL" \
            "$FULL_QUERY" \
            "$TEMP_OUTPUT" \
            "$GROK_TIMEOUT_SECONDS"; then
        return 0
    else
        return $?
    fi
}

observe_grok_cli_version() {
    local version
    version=$("$GROK_CMD" --version 2>/dev/null | head -1 || true)
    if [[ "$version" =~ ^grok[[:space:]]+([^[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ -n "$version" ]]; then
        printf '%s\n' "$version"
    else
        printf 'unknown\n'
    fi
}

grok_cli_supports_required_interface() {
    local probe_home="$1"
    local probe_grok_home="$2"
    local probe_workspace="$3"
    local help flag

    help=$(env HOME="$probe_home" GROK_HOME="$probe_grok_home" \
        "$GROK_CMD" --help 2>&1 || true)
    for flag in \
        --prompt-file --model --cwd --output-format --no-plan --no-subagents \
        --no-memory --disable-web-search --max-turns --permission-mode \
        --sandbox --tools --deny --verbatim; do
        grep -q -- "$flag" <<< "$help" || return 1
    done
    grep -Eq '^[[:space:]]+models([[:space:]]|$)' <<< "$help" || return 1

    local probe_args=(
        env HOME="$probe_home" GROK_HOME="$probe_grok_home"
        "$GROK_CMD"
        --prompt-file /dev/null \
        -m "$GROK_MODEL" \
        --cwd "$probe_workspace" \
        --output-format plain \
        --no-plan \
        --no-subagents \
        --no-memory \
        --disable-web-search \
        --max-turns 1 \
        --permission-mode dontAsk \
        --sandbox strict \
        --tools "" \
        --deny Bash \
        --deny Edit \
        --deny Read \
        --deny Grep \
        --deny MCPTool \
        --deny WebFetch \
        --deny WebSearch \
        --verbatim
    )

    if grep -q -- '--reasoning-effort' <<< "$help"; then
        GROK_SUPPORTS_REASONING_EFFORT=true
    fi
    if [[ -n "${GROK_REASONING_EFFORT:-}" ]]; then
        if [[ "$GROK_SUPPORTS_REASONING_EFFORT" != "true" ]]; then
            _GROK_CAPABILITY_ERROR="Grok Build CLI does not expose --reasoning-effort"
            return 1
        fi
        source "$SCRIPT_DIR/lib/api.sh"
        if ! GROK_CLI_EFFORT=$(validate_reasoning_effort "$GROK_REASONING_EFFORT" "$CONSULTANT_NAME"); then
            _GROK_CAPABILITY_ERROR="Invalid Grok Build reasoning effort: $GROK_REASONING_EFFORT"
            return 1
        fi
        probe_args+=(--reasoning-effort "$GROK_CLI_EFFORT")
    fi

    # Exercise the complete headless argument surface under --help. This checks
    # parser compatibility without starting a session or sending a prompt.
    "${probe_args[@]}" --help >/dev/null 2>&1 || return 1

    if grep -q -- '--no-auto-update' <<< "$help"; then
        GROK_SUPPORTS_NO_AUTO_UPDATE=true
    else
        GROK_SUPPORTS_NO_AUTO_UPDATE=false
    fi
    GROK_CLI_COMPATIBILITY="capability-probed"
}

grok_cli_exposes_requested_model() {
    local isolated_home="$1"
    local isolated_grok_home="$2"
    local models

    if ! models=$(env HOME="$isolated_home" GROK_HOME="$isolated_grok_home" \
            "$GROK_CMD" models 2>&1); then
        if grep -Eiq 'auth|log ?in|credential|token|401|unauthor' <<<"$models"; then
            _GROK_MODEL_PROBE_ERROR="Grok Build CLI authentication unavailable"
        else
            _GROK_MODEL_PROBE_ERROR="Grok Build CLI model inventory failed"
        fi
        return 1
    fi
    grep -Fq "You are logged in with grok.com." <<< "$models" || {
        _GROK_MODEL_PROBE_ERROR="Grok Build CLI authentication unavailable"
        return 1
    }
    if ! awk -v requested="$GROK_MODEL" '
        {
            line = $0
            sub(/^[[:space:]*]+/, "", line)
            split(line, fields, /[[:space:]]+/)
            if (fields[1] == requested) found = 1
        }
        END { exit(found ? 0 : 1) }
    ' <<< "$models"; then
        _GROK_MODEL_PROBE_ERROR="Grok Build CLI does not expose the requested model $GROK_MODEL"
        return 1
    fi
    return 0
}

grok_shared_oauth_bootstrap_ready() {
    oauth_rc=0
    grok_oauth_bootstrap_shared "$1" "$GROK_CMD" || oauth_rc=$?
    [[ "$oauth_rc" -eq 0 ]]
}

grok_cli_is_unavailable() {
    local cli_exit_code="$1"
    local error_file="$2"

    # A missing command is detected before execution. 126/127 cover a binary
    # that was resolved but cannot be executed (bad interpreter, permissions,
    # or a race with an uninstall).
    case "$cli_exit_code" in
        126|127) return 0 ;;
    esac

    [[ -s "$error_file" ]] || return 1

    # Authentication is part of CLI availability: without a usable Grok Build
    # login the subscription transport cannot start a request. Do not classify
    # model errors, timeouts, empty output, or other post-launch failures here;
    # those must surface instead of silently creating a billable API request.
    grep -Eiq \
        'not authenticated|authentication( is)? (required|unavailable)|authentication failed|unauthorized|run .?grok login|please .*log ?in|no (valid )?(credentials|access token)|missing .*credential|token.*expired|(^|[^0-9])401([^0-9]|$)|permission denied|cannot execute|exec format error|no such file or directory|failed to (start|launch|spawn)|could not (start|launch|spawn)' \
        "$error_file"
}

if is_api_mode "grok"; then
    log_api_mode_status "grok"
    TRANSPORT="api"
    if run_grok_api; then
        exit_code=0
    else
        exit_code=$?
    fi
else
    log_api_mode_status "grok"

    if command -v "$GROK_CMD" >/dev/null 2>&1; then
        runtime_base="${TMPDIR:-/tmp}"
        runtime_base="${runtime_base%/}"
        GROK_RUNTIME_DIR=$(mktemp -d "$runtime_base/ai-consultants-grok.XXXXXX")
        chmod 700 "$GROK_RUNTIME_DIR"

        isolated_home="$GROK_RUNTIME_DIR/home"
        isolated_grok_home="$isolated_home/.grok"
        isolated_workspace="$GROK_RUNTIME_DIR/workspace"
        prompt_file="$GROK_RUNTIME_DIR/prompt.txt"
        mkdir -p "$isolated_home" "$isolated_workspace"
        chmod 700 "$isolated_home" "$isolated_workspace"
        printf '%s' "$FULL_QUERY" > "$prompt_file"
        chmod 600 "$prompt_file"

        # Preserve a rotating subscription credential without sharing agent
        # state. HOME/CWD/prompt/output remain per invocation. In shared mode,
        # concurrent processes use one runner-owned GROK_HOME so Grok Build's
        # native auth lock can coordinate refresh. Serialized mode keeps the
        # previous per-run GROK_HOME shape under a full diagnostic lock.
        source_grok_home=$(printenv GROK_HOME 2>/dev/null || true)
        [[ -n "$source_grok_home" ]] || source_grok_home="${HOME}/.grok"
        oauth_rc=0
        grok_oauth_init "$source_grok_home" || oauth_rc=$?
        if [[ "$oauth_rc" -eq 2 ]]; then
            printf '%s\n' "Grok Build authentication unavailable; run grok login" > "${TEMP_OUTPUT}.err"
            log_warn "[$CONSULTANT_NAME] Grok Build authentication unavailable"
            exit_code=69
        elif [[ "$oauth_rc" -ne 0 ]]; then
            _GROK_OAUTH_FAILURE=true
            printf '%s\n' "Grok OAuth state failed validation" > "${TEMP_OUTPUT}.err"
            log_warn "[$CONSULTANT_NAME] $GROK_OAUTH_ERROR"
            exit_code=70
        else
            oauth_rc=0
            grok_oauth_prepare "$isolated_grok_home" || oauth_rc=$?
            if [[ "$oauth_rc" -ne 0 ]]; then
                _GROK_OAUTH_FAILURE=true
                printf '%s\n' "Grok OAuth state could not be prepared" > "${TEMP_OUTPUT}.err"
                log_warn "[$CONSULTANT_NAME] $GROK_OAUTH_ERROR"
                [[ "$oauth_rc" -eq 2 ]] && exit_code=75 || exit_code=70
            else
                _GROK_OAUTH_PREPARED=true
            fi
        fi

        GROK_CLI_VERSION=$(observe_grok_cli_version)
        if [[ "$_GROK_OAUTH_PREPARED" != "true" ]]; then
            :
        elif ! grok_cli_supports_required_interface \
                "$isolated_home" "$GROK_OAUTH_ACTIVE_HOME" "$isolated_workspace"; then
            GROK_CLI_COMPATIBILITY="incompatible"
            printf '%s\n' "${_GROK_CAPABILITY_ERROR:-Grok Build CLI lacks the required capabilities}" > "${TEMP_OUTPUT}.err"
            log_warn "[$CONSULTANT_NAME] ${_GROK_CAPABILITY_ERROR:-Grok Build CLI lacks the required capabilities} (reported version: $GROK_CLI_VERSION)"
            exit_code=69
        elif [[ "$GROK_OAUTH_MODE" == "shared" ]] &&
             ! grok_shared_oauth_bootstrap_ready "$isolated_home"; then
            _GROK_OAUTH_PREPARED=false
            if [[ "$oauth_rc" -eq 4 ]]; then
                printf '%s\n' "Grok Build authentication unavailable; run grok login" > "${TEMP_OUTPUT}.err"
                log_warn "[$CONSULTANT_NAME] Grok Build authentication unavailable"
                exit_code=69
            else
                _GROK_OAUTH_FAILURE=true
                printf '%s\n' "Grok shared OAuth bootstrap failed" > "${TEMP_OUTPUT}.err"
                log_warn "[$CONSULTANT_NAME] $GROK_OAUTH_ERROR"
                [[ "$oauth_rc" -eq 2 ]] && exit_code=75 || exit_code=70
            fi
        elif ! grok_cli_exposes_requested_model \
                "$isolated_home" "$GROK_OAUTH_ACTIVE_HOME" > "${TEMP_OUTPUT}.err"; then
            printf '%s\n' "${_GROK_MODEL_PROBE_ERROR:-Grok Build CLI model inventory failed}" > "${TEMP_OUTPUT}.err"
            log_warn "[$CONSULTANT_NAME] ${_GROK_MODEL_PROBE_ERROR:-Grok Build CLI model inventory failed}"
            exit_code=69
        else
            # Official Grok Build headless contract:
            #   --prompt-file avoids argv size/process-list exposure, -m pins the
            #   model, and plain output contains the final assistant text.
            #   dontAsk + strict sandbox make every unapproved tool fail closed.
            GROK_ARGS=(
                env
                HOME="$isolated_home"
                GROK_HOME="$GROK_OAUTH_ACTIVE_HOME"
                "$GROK_CMD"
                --prompt-file "$prompt_file"
                -m "$GROK_MODEL"
                --cwd "$isolated_workspace"
                --output-format plain
                --no-plan
                --no-subagents
                --no-memory
                --disable-web-search
                --max-turns "$GROK_MAX_TURNS"
                --permission-mode dontAsk
                --sandbox strict
                --tools ""
                --deny Bash
                --deny Edit
                --deny Read
                --deny Grep
                --deny MCPTool
                --deny WebFetch
                --deny WebSearch
                --verbatim
            )

            # --no-auto-update is a useful optional capability, not a version
            # requirement. Compatible older or vendor-custom builds may omit it.
            if [[ "$GROK_SUPPORTS_NO_AUTO_UPDATE" == "true" ]]; then
                GROK_ARGS+=("--no-auto-update")
            fi
            if [[ -n "$GROK_CLI_EFFORT" ]]; then
                GROK_ARGS+=("--reasoning-effort" "$GROK_CLI_EFFORT")
            fi

            _GROK_REQUEST_LAUNCHED=true
            if RUN_QUERY_REDACT_ERRORS=true run_query \
                    "$CONSULTANT_NAME" \
                    "$TEMP_OUTPUT" \
                    "$GROK_TIMEOUT_SECONDS" \
                    "${GROK_ARGS[@]}" </dev/null; then
                exit_code=0
            else
                exit_code=$?
            fi
        fi

        # Publish refreshes before considering fallback or publishing output.
        # A concurrent external `grok login` changes the ambient digest, wins
        # the CAS, and makes this run fail temporarily without overwriting it.
        if [[ "$_GROK_OAUTH_PREPARED" == "true" ]]; then
            oauth_rc=0
            grok_oauth_sync || oauth_rc=$?
            if [[ "$oauth_rc" -ne 0 ]]; then
                _GROK_OAUTH_FAILURE=true
                : > "$TEMP_OUTPUT"
                case "$oauth_rc" in
                    2)
                        printf '%s\n' "Grok OAuth changed concurrently; retry" > "${TEMP_OUTPUT}.err"
                        log_warn "[$CONSULTANT_NAME] External Grok login superseded this run"
                        exit_code=75
                        ;;
                    3)
                        printf '%s\n' "Grok OAuth reconciliation lock is busy; retry" > "${TEMP_OUTPUT}.err"
                        log_warn "[$CONSULTANT_NAME] Grok OAuth reconciliation is temporarily busy"
                        exit_code=75
                        ;;
                    *)
                        printf '%s\n' "Grok OAuth refresh could not be persisted" > "${TEMP_OUTPUT}.err"
                        log_warn "[$CONSULTANT_NAME] Grok OAuth refresh could not be persisted"
                        exit_code=70
                        ;;
                esac
            fi
        fi
    else
        log_warn "[$CONSULTANT_NAME] Grok Build CLI not found: $GROK_CMD"
        exit_code=127
    fi

    # Fall back only when the CLI transport is genuinely unavailable. A timeout,
    # model error, empty reply, or other post-launch failure is returned as-is so
    # it cannot silently turn into a separately billed API request.
    if [[ $exit_code -ne 0 ]] \
            && [[ "$_GROK_REQUEST_LAUNCHED" != "true" ]] \
            && [[ "$_GROK_OAUTH_FAILURE" != "true" ]] \
            && grok_cli_is_unavailable "$exit_code" "${TEMP_OUTPUT}.err" \
            && [[ -n "${GROK_API_KEY:-}" ]]; then
        log_warn "[$CONSULTANT_NAME] Grok Build CLI unavailable (exit $exit_code); falling back to the xAI API"
        TRANSPORT="api_fallback"
        if run_grok_api; then
            exit_code=0
        else
            exit_code=$?
        fi
    elif [[ $exit_code -ne 0 && -n "${GROK_API_KEY:-}" ]]; then
        if [[ "$_GROK_REQUEST_LAUNCHED" == "true" ]]; then
            log_warn "[$CONSULTANT_NAME] Grok Build request failed after launch; API fallback suppressed"
        else
            log_warn "[$CONSULTANT_NAME] Grok Build configuration/capability check failed; API fallback suppressed"
        fi
    fi
fi

END_TIME=$(get_timestamp_ms)
LATENCY_MS=$((END_TIME - START_TIME))
PERSONA_NAME=$(get_persona_name "$CONSULTANT_NAME")
MODEL_IDENTITY_SOURCE="${_API_MODEL_IDENTITY_SOURCE:-requested-only}"
EFFECTIVE_MODEL="${_API_RESPONSE_MODEL:-$GROK_MODEL}"
if [[ "$TRANSPORT" == "cli" && "$GROK_CLI_COMPATIBILITY" == "capability-probed" ]]; then
    MODEL_IDENTITY_SOURCE="capability-probed"
    EFFECTIVE_MODEL="$GROK_MODEL"
fi

# The response builder intentionally returns the consultant exit code. Keep it
# inside a conditional so `set -e` cannot skip transport metadata and cleanup
# on the failure path.
if process_consultant_response "$CONSULTANT_NAME" "$GROK_MODEL" "$PERSONA_NAME" \
        "$TEMP_OUTPUT" "$OUTPUT_FILE" "$exit_code" "$LATENCY_MS" "" "$FULL_QUERY" \
        "$GROK_MODEL" "$MODEL_IDENTITY_SOURCE" "$EFFECTIVE_MODEL" \
        "$((GROK_MAX_TURNS * MAX_RETRIES))"; then
    :
else
    response_rc=$?
    [[ $exit_code -ne 0 ]] || exit_code=$response_rc
fi

# Preserve which route actually answered without changing the shared schema.
if [[ -s "$OUTPUT_FILE" ]]; then
    response_tmp=$(mktemp)
    if jq --arg transport "$TRANSPORT" \
            --arg cli_version "$GROK_CLI_VERSION" \
            --arg cli_compatibility "$GROK_CLI_COMPATIBILITY" '
            .metadata.transport = $transport |
            if $transport == "cli" and $cli_version != "" then
                .metadata.cli_version = $cli_version |
                .metadata.cli_compatibility = $cli_compatibility
            else
                .
            end
        ' \
            "$OUTPUT_FILE" > "$response_tmp"; then
        mv "$response_tmp" "$OUTPUT_FILE"
    else
        rm -f "$response_tmp"
    fi
fi

cat "$OUTPUT_FILE"
exit $exit_code
