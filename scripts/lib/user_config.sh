#!/bin/bash
# user_config.sh - Persistent user-level configuration loader
#
# Looks for configuration in (first found wins per file type):
#   $AI_CONSULTANTS_CONFIG_DIR/{config.sh,.env,affinity.json}    (highest priority)
#   $XDG_CONFIG_HOME/ai-consultants/{config.sh,.env,affinity.json}
#   $HOME/.config/ai-consultants/{config.sh,.env,affinity.json}  (default)
#
# Precedence (highest wins):
#   1. CLI flags (--preset, --strategy, etc.)
#   2. Existing environment variables (export FOO=bar before invocation)
#   3. User config: ~/.config/ai-consultants/{config.sh,.env}
#   4. config.sh defaults (the ${VAR:-default} pattern)
#   5. Hardcoded defaults inside individual scripts
#
# The .env file uses KEY=value lines and only sets variables that are NOT
# already in the environment — so existing env vars always win.
# config.sh is fully sourced (write any bash you want); to defer to env,
# use `export VAR="${VAR:-value}"`.

# Resolve the user config directory using the standard search path.
# Idempotent and side-effect-free.
# Returns empty string + exit 1 when HOME and XDG_CONFIG_HOME are both unset
# (e.g. in a distroless container without HOME) so callers can degrade
# gracefully instead of computing the broken path "/.config/ai-consultants".
get_user_config_dir() {
    if [[ -n "${AI_CONSULTANTS_CONFIG_DIR:-}" ]]; then
        echo "$AI_CONSULTANTS_CONFIG_DIR"
        return 0
    fi
    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        echo "$XDG_CONFIG_HOME/ai-consultants"
        return 0
    fi
    if [[ -z "${HOME:-}" ]]; then
        echo ""
        return 1
    fi
    echo "$HOME/.config/ai-consultants"
}

# Resolve an XDG base directory for cache / state / data.
# Returns "$XDG_<KIND>_HOME/ai-consultants" if the spec var is set, else
# the freedesktop.org default ($HOME/.cache, $HOME/.local/state,
# $HOME/.local/share). Falls back to /tmp if HOME is also unset (container).
# Usage: get_xdg_dir cache | get_xdg_dir state | get_xdg_dir data
get_xdg_dir() {
    local kind="$1"
    local var default
    case "$kind" in
        cache) var="XDG_CACHE_HOME"; default=".cache" ;;
        state) var="XDG_STATE_HOME"; default=".local/state" ;;
        data)  var="XDG_DATA_HOME";  default=".local/share" ;;
        *) echo ""; return 1 ;;
    esac
    local base="${!var:-}"
    if [[ -n "$base" ]]; then
        echo "$base/ai-consultants"
    elif [[ -n "${HOME:-}" ]]; then
        echo "$HOME/$default/ai-consultants"
    else
        # Last-resort fallback for distroless containers etc. — better than
        # writing to /<default>/ai-consultants which is usually unwritable.
        echo "/tmp/ai-consultants-${kind}"
    fi
}

# Returns the first existing path for a config artifact, or empty string.
# Usage: find_user_config_file <basename>     e.g. find_user_config_file .env
find_user_config_file() {
    local basename="$1"
    local dir
    dir=$(get_user_config_dir 2>/dev/null) || true
    if [[ -n "$dir" && -f "$dir/$basename" ]]; then
        echo "$dir/$basename"
        return 0
    fi
    echo ""
    return 1
}

# Parse a .env-style file: KEY=value, KEY="value", # comments, blank lines.
# A leading `export` is permitted (and ignored). Variables already set in
# the calling environment are preserved (user export wins over .env file).
_apply_env_file() {
    local file="$1"
    [[ -r "$file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip a trailing CR (Windows CR-LF line endings). Without this,
        # values like `ENABLE_DEBATE=true\r` silently fail every downstream
        # `[[ "$X" == "true" ]]` comparison.
        line="${line%$'\r'}"

        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue

        # Strip optional leading `export `
        line="${line#"${line%%[![:space:]]*}"}"   # ltrim
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export }"
            line="${line#"${line%%[![:space:]]*}"}"
        fi

        # Split on first =
        if [[ "$line" != *=* ]]; then
            continue
        fi
        key="${line%%=*}"
        value="${line#*=}"

        # Trim whitespace from key
        key="${key//[[:space:]]/}"

        # Validate key (alphanumeric + underscore, must start with letter/_)
        if ! [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            continue
        fi

        # Skip if already in environment (env wins over .env file)
        if [[ -n "${!key+set}" ]]; then
            continue
        fi

        # Strip optional surrounding quotes
        if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
            value="${value:1:${#value}-2}"
        fi

        # Strip trailing whitespace and an inline comment if value is unquoted
        # (we already stripped quotes if present)
        # Note: we intentionally do NOT do shell expansion here for safety.
        export "$key=$value"
    done < "$file"
}

# Load user-level configuration. Call once early — config.sh sources this
# before applying any ${VAR:-default} fallbacks, so user config behaves as
# a defaults layer that env vars and CLI flags can still override.
#
# Idempotent: a process-wide guard ensures a single load even when config.sh
# is sourced repeatedly (consult_all.sh transitively sources it 15-30 times
# per consultation via lib/common.sh and every query_*.sh). Without this
# guard, a user config.sh containing PATH-appends, counters, log-appends,
# or any non-idempotent statement would compound silently across sources.
load_user_config() {
    [[ -n "${_AI_CONSULTANTS_USER_CONFIG_LOADED:-}" ]] && return 0
    export _AI_CONSULTANTS_USER_CONFIG_LOADED=1

    local env_file config_file
    env_file=$(find_user_config_file ".env" || true)
    config_file=$(find_user_config_file "config.sh" || true)

    [[ -n "$env_file" ]] && _apply_env_file "$env_file"
    if [[ -n "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
    fi
}
