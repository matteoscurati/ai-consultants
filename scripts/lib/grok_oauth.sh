#!/bin/bash
# grok_oauth.sh - Persistent, concurrency-safe Grok Build OAuth handoff.
#
# Shared mode keeps one runner-owned credential generation across invocations.
# Each invocation still receives its own HOME, workspace, prompt, and output;
# only GROK_HOME is shared so Grok Build's own auth.json.lock can coordinate a
# refresh. A short adapter lock protects generation adoption and publication.
# Serialized mode retains a per-run GROK_HOME and holds that adapter lock for
# the full CLI sequence as a diagnostic fallback.

GROK_OAUTH_SOURCE_HOME=""
GROK_OAUTH_SHARED_ROOT=""
GROK_OAUTH_ACTIVE_HOME=""
GROK_OAUTH_GENERATION=""
GROK_OAUTH_BASELINE_HASH=""
GROK_OAUTH_LOCK_PATH=""
GROK_OAUTH_LOCK_HELD=0
GROK_OAUTH_SYNC_STATUS="not_attempted"
GROK_OAUTH_ERROR=""
GROK_OAUTH_LOCK_WAIT_SECONDS=25
GROK_OAUTH_BOOTSTRAP_TIMEOUT_SECONDS=20

grok_oauth_digest() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}'
    else
        return 1
    fi
}

grok_oauth_credential_valid() {
    local credential="$1"
    [[ -f "$credential" && ! -L "$credential" ]] || return 1
    jq -e '
        type == "object" and
        ([.[]? | objects |
          select(((.key // "") | type == "string" and length > 0) and
                 ((.refresh_token // "") | type == "string" and length > 0))] |
         length > 0)
    ' "$credential" >/dev/null 2>&1
}

grok_oauth_release_lock() {
    local owner_pid=""
    [[ "$GROK_OAUTH_LOCK_HELD" -eq 1 ]] || return 0
    if [[ -d "$GROK_OAUTH_LOCK_PATH" && ! -L "$GROK_OAUTH_LOCK_PATH" &&
          -f "$GROK_OAUTH_LOCK_PATH/owner" && ! -L "$GROK_OAUTH_LOCK_PATH/owner" ]]; then
        owner_pid=$(<"$GROK_OAUTH_LOCK_PATH/owner")
        if [[ "$owner_pid" == "$$" ]]; then
            rm -f -- "$GROK_OAUTH_LOCK_PATH/owner"
            rmdir "$GROK_OAUTH_LOCK_PATH" >/dev/null 2>&1 || true
        fi
    fi
    GROK_OAUTH_LOCK_HELD=0
}

grok_oauth_acquire_lock() {
    local owner_pid=""
    [[ -d "$GROK_OAUTH_SOURCE_HOME" && ! -L "$GROK_OAUTH_SOURCE_HOME" ]] || return 1
    GROK_OAUTH_LOCK_PATH="$GROK_OAUTH_SOURCE_HOME/.ai-consultants-oauth.lock.d"
    [[ ! -L "$GROK_OAUTH_LOCK_PATH" ]] || return 1

    if ! mkdir "$GROK_OAUTH_LOCK_PATH" 2>/dev/null; then
        if [[ -f "$GROK_OAUTH_LOCK_PATH/owner" && ! -L "$GROK_OAUTH_LOCK_PATH/owner" ]]; then
            owner_pid=$(<"$GROK_OAUTH_LOCK_PATH/owner")
        fi
        if [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
            rm -f -- "$GROK_OAUTH_LOCK_PATH/owner"
            rmdir "$GROK_OAUTH_LOCK_PATH" >/dev/null 2>&1 || return 2
            mkdir "$GROK_OAUTH_LOCK_PATH" 2>/dev/null || return 2
        else
            return 2
        fi
    fi

    if ! printf '%s\n' "$$" > "$GROK_OAUTH_LOCK_PATH/owner" ||
       ! chmod 700 "$GROK_OAUTH_LOCK_PATH" ||
       ! chmod 600 "$GROK_OAUTH_LOCK_PATH/owner"; then
        rm -f -- "$GROK_OAUTH_LOCK_PATH/owner"
        rmdir "$GROK_OAUTH_LOCK_PATH" >/dev/null 2>&1 || true
        return 1
    fi
    GROK_OAUTH_LOCK_HELD=1
}

grok_oauth_acquire_lock_wait() {
    local deadline rc
    deadline=$(( $(date +%s) + GROK_OAUTH_LOCK_WAIT_SECONDS ))
    while :; do
        rc=0
        grok_oauth_acquire_lock || rc=$?
        [[ "$rc" -eq 2 ]] || return "$rc"
        [[ "$(date +%s)" -lt "$deadline" ]] || return 2
        sleep 1
    done
}

grok_oauth_write_controlled_config() {
    local grok_home="$1" config_path candidate
    [[ -d "$grok_home" && ! -L "$grok_home" ]] || return 1
    config_path="$grok_home/config.toml"
    candidate=$(mktemp "$grok_home/.config.toml.ai-consultants.XXXXXX") || return 1
    if ! cat > "$candidate" <<'EOF'
[compat.claude]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false

[compat.cursor]
skills = false
rules = false
agents = false
mcps = false
hooks = false
sessions = false

[compat.codex]
sessions = false

[workflows]
enabled = false
EOF
    then
        rm -f -- "$candidate"
        return 1
    fi
    if ! chmod 600 "$candidate" || ! mv -f "$candidate" "$config_path"; then
        rm -f -- "$candidate"
        return 1
    fi
}

grok_oauth_read_marker() {
    local marker="$GROK_OAUTH_SHARED_ROOT/sync-marker.json"
    [[ -f "$marker" && ! -L "$marker" ]] || return 1
    jq -re '
        select(.schema == "ai_consultants_grok_shared_oauth_marker_v1") |
        select((.generation | type == "string" and test("^gen-[0-9]+-[0-9]+$")) and
               (.synced_sha256 | type == "string" and test("^[0-9a-f]{64}$"))) |
        "\(.generation) \(.synced_sha256)"
    ' "$marker" 2>/dev/null
}

grok_oauth_write_marker() {
    local generation="$1" synced_sha256="$2" candidate
    candidate=$(mktemp "$GROK_OAUTH_SHARED_ROOT/.sync-marker.json.XXXXXX") || return 1
    if ! jq -n --arg generation "$generation" --arg synced_sha256 "$synced_sha256" '
        {schema:"ai_consultants_grok_shared_oauth_marker_v1",
         generation:$generation,synced_sha256:$synced_sha256}
    ' > "$candidate" || ! chmod 600 "$candidate" ||
       ! mv -f "$candidate" "$GROK_OAUTH_SHARED_ROOT/sync-marker.json"; then
        rm -f -- "$candidate"
        return 1
    fi
}

grok_oauth_init() {
    local source_home="$1"
    GROK_OAUTH_ERROR=""
    GROK_OAUTH_ACTIVE_HOME=""
    GROK_OAUTH_GENERATION=""
    GROK_OAUTH_BASELINE_HASH=""
    GROK_OAUTH_SYNC_STATUS="not_attempted"
    case "$GROK_OAUTH_MODE" in
        shared|serialized) ;;
        *) GROK_OAUTH_ERROR="Invalid GROK_OAUTH_MODE (expected shared or serialized)"; return 1 ;;
    esac
    if [[ ! -d "$source_home" ]]; then
        GROK_OAUTH_ERROR="Grok OAuth home is missing"
        return 2
    elif [[ -L "$source_home" ]]; then
        GROK_OAUTH_ERROR="Grok OAuth home is unsafe"
        return 1
    fi
    GROK_OAUTH_SOURCE_HOME=$(cd "$source_home" && pwd -P) || {
        GROK_OAUTH_ERROR="Could not resolve the Grok OAuth home"
        return 1
    }
    GROK_OAUTH_SHARED_ROOT="${_AI_CONSULTANTS_XDG_DATA}/grok-shared-oauth"
    if [[ ! -f "$GROK_OAUTH_SOURCE_HOME/auth.json" ]]; then
        GROK_OAUTH_ERROR="Grok OAuth credential is missing"
        return 2
    elif ! grok_oauth_credential_valid "$GROK_OAUTH_SOURCE_HOME/auth.json"; then
        GROK_OAUTH_ERROR="Grok OAuth credential is malformed"
        return 1
    fi
    grok_oauth_digest "$GROK_OAUTH_SOURCE_HOME/auth.json" >/dev/null || {
        GROK_OAUTH_ERROR="SHA-256 support is required for Grok OAuth reconciliation"
        return 1
    }
}

grok_oauth_seed_shared() {
    local marker="" marker_generation="" marker_sha="" ambient_hash generation generation_dir
    local lock_rc=0
    if [[ -e "$GROK_OAUTH_SHARED_ROOT" &&
          ( ! -d "$GROK_OAUTH_SHARED_ROOT" || -L "$GROK_OAUTH_SHARED_ROOT" ) ]]; then
        GROK_OAUTH_ERROR="Shared Grok OAuth root is unsafe"
        return 1
    fi
    if ! mkdir -p "$GROK_OAUTH_SHARED_ROOT" || ! chmod 700 "$GROK_OAUTH_SHARED_ROOT"; then
        GROK_OAUTH_ERROR="Could not create the shared Grok OAuth root"
        return 1
    fi
    grok_oauth_acquire_lock_wait || lock_rc=$?
    if [[ "$lock_rc" -eq 2 ]]; then
        GROK_OAUTH_ERROR="Another Grok invocation is reconciling OAuth state"
        return 2
    elif [[ "$lock_rc" -ne 0 ]]; then
        GROK_OAUTH_ERROR="Could not secure Grok OAuth state"
        return 1
    fi

    if ! grok_oauth_credential_valid "$GROK_OAUTH_SOURCE_HOME/auth.json"; then
        GROK_OAUTH_ERROR="Ambient Grok OAuth credential changed or became malformed during adoption"
        grok_oauth_release_lock
        return 1
    fi
    ambient_hash=$(grok_oauth_digest "$GROK_OAUTH_SOURCE_HOME/auth.json") || {
        GROK_OAUTH_ERROR="Could not fingerprint the ambient Grok OAuth credential"
        grok_oauth_release_lock
        return 1
    }
    if marker=$(grok_oauth_read_marker); then
        marker_generation=${marker%% *}
        marker_sha=${marker##* }
    fi

    generation_dir="$GROK_OAUTH_SHARED_ROOT/$marker_generation"
    if [[ -n "$marker_generation" && "$marker_sha" == "$ambient_hash" &&
          -d "$generation_dir" && ! -L "$generation_dir" ]] &&
       grok_oauth_credential_valid "$generation_dir/auth.json"; then
        GROK_OAUTH_GENERATION="$marker_generation"
        if ! grok_oauth_write_controlled_config "$generation_dir"; then
            GROK_OAUTH_ERROR="Could not reconcile shared Grok configuration"
            grok_oauth_release_lock
            return 1
        fi
    else
        generation="gen-$(date +%s)-$$"
        generation_dir="$GROK_OAUTH_SHARED_ROOT/$generation"
        if [[ -e "$generation_dir" || -L "$generation_dir" ]] ||
           ! mkdir "$generation_dir" || ! chmod 700 "$generation_dir"; then
            GROK_OAUTH_ERROR="Could not create a shared Grok OAuth generation"
            grok_oauth_release_lock
            return 1
        fi
        if ! cp "$GROK_OAUTH_SOURCE_HOME/auth.json" "$generation_dir/auth.json" ||
           ! chmod 600 "$generation_dir/auth.json" ||
           ! grok_oauth_credential_valid "$generation_dir/auth.json" ||
           ! grok_oauth_write_controlled_config "$generation_dir" ||
           ! grok_oauth_write_marker "$generation" "$ambient_hash"; then
            GROK_OAUTH_ERROR="Could not seed a shared Grok OAuth generation"
            grok_oauth_release_lock
            return 1
        fi
        GROK_OAUTH_GENERATION="$generation"
    fi
    grok_oauth_release_lock
    GROK_OAUTH_ACTIVE_HOME=$(cd "$GROK_OAUTH_SHARED_ROOT/$GROK_OAUTH_GENERATION" && pwd -P) || {
        GROK_OAUTH_ERROR="Could not resolve the shared Grok OAuth generation"
        return 1
    }
}

grok_oauth_seed_serialized() {
    local isolated_grok_home="$1" lock_rc=0
    grok_oauth_acquire_lock_wait || lock_rc=$?
    if [[ "$lock_rc" -eq 2 ]]; then
        GROK_OAUTH_ERROR="Another Grok invocation is using serialized OAuth mode"
        return 2
    elif [[ "$lock_rc" -ne 0 ]]; then
        GROK_OAUTH_ERROR="Could not secure Grok OAuth state"
        return 1
    fi
    if ! grok_oauth_credential_valid "$GROK_OAUTH_SOURCE_HOME/auth.json" ||
       ! mkdir -p "$isolated_grok_home" || ! chmod 700 "$isolated_grok_home" ||
       ! cp "$GROK_OAUTH_SOURCE_HOME/auth.json" "$isolated_grok_home/auth.json" ||
       ! chmod 600 "$isolated_grok_home/auth.json" ||
       ! grok_oauth_credential_valid "$isolated_grok_home/auth.json" ||
       ! grok_oauth_write_controlled_config "$isolated_grok_home"; then
        GROK_OAUTH_ERROR="Could not seed serialized Grok OAuth state"
        grok_oauth_release_lock
        return 1
    fi
    GROK_OAUTH_BASELINE_HASH=$(grok_oauth_digest "$GROK_OAUTH_SOURCE_HOME/auth.json") || {
        GROK_OAUTH_ERROR="Could not fingerprint serialized Grok OAuth state"
        grok_oauth_release_lock
        return 1
    }
    GROK_OAUTH_ACTIVE_HOME="$isolated_grok_home"
}

grok_oauth_prepare() {
    local isolated_grok_home="$1"
    if [[ "$GROK_OAUTH_MODE" == "shared" ]]; then
        grok_oauth_seed_shared
    else
        grok_oauth_seed_serialized "$isolated_grok_home"
    fi
}

# Grok 1.0.4 lazily creates metadata, caches, DBs, and managed config the first
# time a new GROK_HOME reaches the authenticated inventory. Its own locks cover
# individual files but two pristine homes entering that bootstrap concurrently
# can both report authentication unavailable. Serialize this one-time seed
# only; the sentinel keeps every later capability probe and inference parallel.
grok_oauth_bootstrap_shared() {
    local probe_home="$1" grok_cmd="$2"
    local sentinel="$GROK_OAUTH_ACTIVE_HOME/.ai-consultants-ready.json"
    local candidate models lock_rc=0
    [[ "$GROK_OAUTH_MODE" == "shared" ]] || return 0
    if [[ -f "$sentinel" && ! -L "$sentinel" ]] &&
       jq -e --arg generation "$GROK_OAUTH_GENERATION" '
         .schema == "ai_consultants_grok_home_ready_v1" and
         .generation == $generation
       ' "$sentinel" >/dev/null 2>&1; then
        return 0
    fi

    grok_oauth_acquire_lock_wait || lock_rc=$?
    if [[ "$lock_rc" -eq 2 ]]; then
        GROK_OAUTH_ERROR="Another Grok invocation is bootstrapping shared OAuth state"
        return 2
    elif [[ "$lock_rc" -ne 0 ]]; then
        GROK_OAUTH_ERROR="Could not secure shared Grok OAuth bootstrap"
        return 1
    fi
    if [[ -f "$sentinel" && ! -L "$sentinel" ]] &&
       jq -e --arg generation "$GROK_OAUTH_GENERATION" '
         .schema == "ai_consultants_grok_home_ready_v1" and
         .generation == $generation
       ' "$sentinel" >/dev/null 2>&1; then
        grok_oauth_release_lock
        return 0
    fi

    if ! models=$(run_with_timeout "$GROK_OAUTH_BOOTSTRAP_TIMEOUT_SECONDS" \
        env HOME="$probe_home" GROK_HOME="$GROK_OAUTH_ACTIVE_HOME" \
        "$grok_cmd" models 2>&1); then
        if grep -Eiq 'not logged in|logged out|login required|authentication required|unauthorized|run .?grok login|status.?401' <<< "$models"; then
            GROK_OAUTH_ERROR="Grok Build authentication unavailable"
            grok_oauth_release_lock
            return 4
        fi
        GROK_OAUTH_ERROR="Shared Grok OAuth bootstrap could not authenticate"
        grok_oauth_release_lock
        return 1
    fi
    # This call exists only to let a pristine provider home finish its lazy
    # initialization. The adapter's normal model probe immediately follows and
    # remains the single authority for authenticated inventory/model identity;
    # first-run provider output is not stable enough to validate twice here.
    if ! grok_oauth_credential_valid "$GROK_OAUTH_ACTIVE_HOME/auth.json"; then
        GROK_OAUTH_ERROR="Shared Grok OAuth bootstrap returned invalid state"
        grok_oauth_release_lock
        return 1
    fi
    candidate=$(mktemp "$GROK_OAUTH_ACTIVE_HOME/.ai-consultants-ready.json.XXXXXX") || {
        GROK_OAUTH_ERROR="Could not stage shared Grok OAuth readiness"
        grok_oauth_release_lock
        return 1
    }
    if ! jq -n --arg generation "$GROK_OAUTH_GENERATION" '
        {schema:"ai_consultants_grok_home_ready_v1",generation:$generation}
      ' > "$candidate" || ! chmod 600 "$candidate" || ! mv -f "$candidate" "$sentinel"; then
        rm -f -- "$candidate"
        GROK_OAUTH_ERROR="Could not record shared Grok OAuth readiness"
        grok_oauth_release_lock
        return 1
    fi
    grok_oauth_release_lock
}

grok_oauth_publish_shared() {
    local marker marker_generation marker_sha shared_hash ambient_hash candidate lock_rc=0 rc=0
    grok_oauth_acquire_lock_wait || lock_rc=$?
    [[ "$lock_rc" -ne 2 ]] || return 3
    [[ "$lock_rc" -eq 0 ]] || return 1

    if ! marker=$(grok_oauth_read_marker); then
        rc=1
    else
        marker_generation=${marker%% *}
        marker_sha=${marker##* }
        if [[ "$marker_generation" != "$GROK_OAUTH_GENERATION" ]]; then
            rc=2
        elif ! grok_oauth_credential_valid "$GROK_OAUTH_ACTIVE_HOME/auth.json" ||
             ! shared_hash=$(grok_oauth_digest "$GROK_OAUTH_ACTIVE_HOME/auth.json"); then
            rc=1
        elif ! grok_oauth_credential_valid "$GROK_OAUTH_SOURCE_HOME/auth.json" ||
             ! ambient_hash=$(grok_oauth_digest "$GROK_OAUTH_SOURCE_HOME/auth.json"); then
            rc=2
        elif [[ "$ambient_hash" != "$marker_sha" ]]; then
            rc=2
        elif [[ "$shared_hash" == "$marker_sha" ]]; then
            rc=0
        else
            candidate=$(mktemp "$GROK_OAUTH_SOURCE_HOME/.auth.json.ai-consultants.XXXXXX") || rc=1
            if [[ "$rc" -eq 0 ]]; then
                if cp "$GROK_OAUTH_ACTIVE_HOME/auth.json" "$candidate" &&
                   chmod 600 "$candidate" &&
                   mv -f "$candidate" "$GROK_OAUTH_SOURCE_HOME/auth.json" &&
                   grok_oauth_write_marker "$GROK_OAUTH_GENERATION" "$shared_hash"; then
                    rc=0
                else
                    rm -f -- "$candidate"
                    rc=1
                fi
            fi
        fi
    fi
    grok_oauth_release_lock
    return "$rc"
}

grok_oauth_publish_serialized() {
    local scratch_hash ambient_hash candidate
    grok_oauth_credential_valid "$GROK_OAUTH_ACTIVE_HOME/auth.json" || return 1
    scratch_hash=$(grok_oauth_digest "$GROK_OAUTH_ACTIVE_HOME/auth.json") || return 1
    grok_oauth_credential_valid "$GROK_OAUTH_SOURCE_HOME/auth.json" || return 2
    ambient_hash=$(grok_oauth_digest "$GROK_OAUTH_SOURCE_HOME/auth.json") || return 1
    [[ "$ambient_hash" == "$GROK_OAUTH_BASELINE_HASH" ]] || return 2
    [[ "$scratch_hash" != "$GROK_OAUTH_BASELINE_HASH" ]] || return 0
    candidate=$(mktemp "$GROK_OAUTH_SOURCE_HOME/.auth.json.ai-consultants.XXXXXX") || return 1
    if ! cp "$GROK_OAUTH_ACTIVE_HOME/auth.json" "$candidate" ||
       ! chmod 600 "$candidate" ||
       ! mv -f "$candidate" "$GROK_OAUTH_SOURCE_HOME/auth.json"; then
        rm -f -- "$candidate"
        return 1
    fi
}

grok_oauth_sync() {
    local rc=0
    if [[ "$GROK_OAUTH_MODE" == "shared" ]]; then
        grok_oauth_publish_shared || rc=$?
    else
        grok_oauth_publish_serialized || rc=$?
    fi
    grok_oauth_release_lock
    case "$rc" in
        0) GROK_OAUTH_SYNC_STATUS="ok" ;;
        2) GROK_OAUTH_SYNC_STATUS="conflict" ;;
        3) GROK_OAUTH_SYNC_STATUS="lock_busy" ;;
        *) GROK_OAUTH_SYNC_STATUS="failed" ;;
    esac
    return "$rc"
}
