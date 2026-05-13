#!/bin/bash
# Sample bash script used by test_context_optimization.sh.
# Functions intentionally have substantial bodies so the AST/skeleton
# extractor has something to strip down to signatures + comments.

set -euo pipefail

# Default configuration — overridable via env.
DEFAULT_TIMEOUT="${DEFAULT_TIMEOUT:-30}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Emit a log line with a level prefix.
# Usage: log INFO "message"
log() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date +"%Y-%m-%dT%H:%M:%S%z")
    echo "[$ts] [$level] $msg" >&2
}

# Run a command with the configured timeout. Returns the command's exit code.
# Usage: run_with_timeout "label" "command args..."
run_with_timeout() {
    local label="$1"
    shift
    local cmd=("$@")

    log INFO "starting $label (timeout=${DEFAULT_TIMEOUT}s)"
    if command -v timeout >/dev/null 2>&1; then
        timeout "$DEFAULT_TIMEOUT" "${cmd[@]}"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$DEFAULT_TIMEOUT" "${cmd[@]}"
    else
        log WARN "no timeout binary available, running unbounded"
        "${cmd[@]}"
    fi
    local rc=$?
    log INFO "$label exited with $rc"
    return $rc
}

# Validate that all required tools are on PATH.
# Usage: check_deps tool1 tool2 ...
check_deps() {
    local missing=()
    for tool in "$@"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        log ERROR "missing dependencies: ${missing[*]}"
        return 1
    fi
    return 0
}

main() {
    check_deps jq curl
    run_with_timeout "demo" sleep 1
    log INFO "done"
}

main "$@"
