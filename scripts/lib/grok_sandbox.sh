#!/bin/bash
# Capture private test-harness input before common.sh loads user configuration.
# This is not a configure/.env option and never changes --sandbox strict.
if declare -F grok_sandbox_preflight >/dev/null 2>&1; then return 0; fi
_grok_test_paths_set="${_AI_CONSULTANTS_GROK_TEST_SOCKET_PATHS+x}"
_grok_test_paths="${_AI_CONSULTANTS_GROK_TEST_SOCKET_PATHS-}"
# Passive checks only. No Docker operations and no sandbox policy changes.
# Arguments inject candidate paths for tests; runtime uses the known locations.
grok_sandbox_preflight() {
    local candidate
    if [[ $# -eq 0 && "$_grok_test_paths_set" == x ]]; then
        while IFS= read -r candidate; do
            [[ -z "$candidate" ]] || set -- "$@" "$candidate"
        done <<< "$_grok_test_paths"
        [[ $# -gt 0 ]] || return 0
    fi
    if [[ $# -eq 0 ]]; then
        set -- /var/run/docker.sock /run/docker.sock /run/podman/podman.sock /var/run/podman/podman.sock \
            /run/containerd/containerd.sock /var/run/containerd/containerd.sock
        if [[ -n "${HOME:-}" ]]; then
            set -- "$@" "$HOME/.docker/run/docker.sock" "$HOME/.docker/desktop/docker.sock" \
                "$HOME/Library/Containers/com.docker.docker/Data/docker.sock"
        fi
    fi
    for candidate in "$@"; do
        if [[ -L "$candidate" ]]; then
            printf 'sandbox_runtime_socket_symlink: %s\n' "$candidate"
            return 1
        fi
    done
}

# Parse CLI diagnostics (never model-authored answer text), including zero-exit warnings.
grok_sandbox_failure() {
    # Snapshot once: /dev/stdin may be a pipe and cannot be read twice.
    local diagnostics explicit_only=false
    if [[ "${1:-}" == --explicit ]]; then explicit_only=true; shift; fi
    diagnostics=$(cat "$@" 2>/dev/null) || true
    if grep -Eiq '(^|[^[:alnum:]_])sandbox_not_applied([^[:alnum:]_]|$)' <<< "$diagnostics"; then
        printf '%s\n' sandbox_not_applied
        return 0
    fi
    if grep -Eiq 'sandbox could not be applied|could not apply the .* sandbox profile|runtime-socket deny resolution failed|sandbox_profile_refused|sandbox[-_ ]profile.*(refus|denied)|sandbox-exec:.*(denied|not permitted)|failed to (apply|initialize|enable).*sandbox' <<< "$diagnostics"; then
        printf '%s\n' sandbox_profile_refused
        return 0
    fi
    [[ "$explicit_only" != true ]] || return 1
    if grep -Eiq '^[[:space:]]*((\[[^]]+\]|warning|warn|error)[[:space:]:]*)?(sandbox.*(not applied|not enforced|disabled|unavailable)|running without.*sandbox|running unsandboxed|could not apply.*sandbox)' <<< "$diagnostics"; then
        printf '%s\n' sandbox_not_applied
        return 0
    fi
    return 1
}
