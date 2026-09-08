#!/bin/bash
# Passive checks only. No Docker operations and no sandbox policy changes.
# Arguments inject candidate paths for tests; runtime uses the known locations.
grok_sandbox_preflight() {
    local candidate
    if [[ $# -eq 0 ]]; then
        set -- /var/run/docker.sock /run/docker.sock /run/podman/podman.sock /var/run/podman/podman.sock \
            /run/containerd/containerd.sock /var/run/containerd/containerd.sock \
            "$HOME/.docker/run/docker.sock" "$HOME/.docker/desktop/docker.sock" \
            "$HOME/Library/Containers/com.docker.docker/Data/docker.sock"
    fi
    for candidate in "$@"; do
        if [[ -L "$candidate" ]]; then
            printf 'sandbox_runtime_socket_symlink: %s\n' "$candidate"
            return 1
        fi
    done
}

# Scan both streams before success/retry handling, including zero-exit warnings.
grok_sandbox_failure() {
    if grep -Eiq 'sandbox could not be applied|could not apply the .* sandbox profile|runtime-socket deny resolution failed|sandbox_profile_refused|sandbox[-_ ]profile.*(refus|denied)|sandbox-exec:.*(denied|not permitted)|failed to (apply|initialize|enable).*sandbox' "$@" 2>/dev/null; then
        printf '%s\n' sandbox_profile_refused
        return 0
    fi
    if grep -Eiq '^[[:space:]]*((\[[^]]+\]|warning|warn|error)[[:space:]:]*)?(sandbox.*(not applied|not enforced|disabled|unavailable)|running without.*sandbox|running unsandboxed|could not apply.*sandbox)' "$@" 2>/dev/null; then
        printf '%s\n' sandbox_not_applied
        return 0
    fi
    return 1
}
