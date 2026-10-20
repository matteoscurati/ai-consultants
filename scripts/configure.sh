#!/usr/bin/env bash
# configure.sh - Automatic and interactive persistent configuration
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_FILE="$PROJECT_ROOT/.env.example"

# shellcheck source=lib/user_config.sh
source "$SCRIPT_DIR/lib/user_config.sh"

MODE="auto"
ADVANCED=false
DRY_RUN=false
FORCE=false
SHOW_PARAMETERS=false
OUTPUT_FILE=""
SET_KEYS=()
SET_VALUES=()

usage() {
    cat <<'EOF'
Usage: ai-consultants configure [options]

Detect installed CLIs and available API keys, then write a complete persistent
configuration. Existing custom values and secrets are preserved; ENABLE_* flags
are refreshed from the detected availability unless overridden with --set.

Options:
  --auto, --non-interactive  Configure from detected CLIs and API keys (default)
  --interactive             Review consultant selection interactively
  --advanced                Review every supported parameter interactively
  --set KEY=VALUE           Override any supported parameter (repeatable)
  --output FILE             Write to FILE instead of the user config .env
  --dry-run                 Print the generated config without writing it
  --force                   Overwrite without creating a timestamped backup
  --show-parameters         List every parameter accepted by --set
  -h, --help                Show this help

Examples:
  ai-consultants configure
  ai-consultants configure --set DEFAULT_PRESET=balanced --set ENABLE_SYNTHESIS=true
  ai-consultants configure --interactive
  ai-consultants configure --advanced
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto|--non-interactive) MODE="auto"; shift ;;
        --interactive) MODE="interactive"; shift ;;
        --advanced) MODE="interactive"; ADVANCED=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --force) FORCE=true; shift ;;
        --show-parameters) SHOW_PARAMETERS=true; shift ;;
        --output)
            [[ $# -ge 2 ]] || die "--output requires a file path"
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --set)
            [[ $# -ge 2 ]] || die "--set requires KEY=VALUE"
            [[ "$2" == *=* ]] || die "--set requires KEY=VALUE"
            SET_KEYS+=("${2%%=*}")
            SET_VALUES+=("${2#*=}")
            shift 2
            ;;
        --set=*)
            assignment="${1#--set=}"
            [[ "$assignment" == *=* ]] || die "--set requires KEY=VALUE"
            SET_KEYS+=("${assignment%%=*}")
            SET_VALUES+=("${assignment#*=}")
            shift
            ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -r "$TEMPLATE_FILE" ]] || die "configuration template not found: $TEMPLATE_FILE"

list_parameters() {
    sed -nE 's/^[[:space:]]*#?[[:space:]]*([A-Z][A-Z0-9_]*)=.*/\1/p' "$TEMPLATE_FILE" | sort -u
}

is_supported_parameter() {
    local wanted="$1" key
    while IFS= read -r key; do
        [[ "$key" == "$wanted" ]] && return 0
    done < <(list_parameters)
    return 1
}

if [[ "$SHOW_PARAMETERS" == "true" ]]; then
    list_parameters
    exit 0
fi

if [[ -z "$OUTPUT_FILE" ]]; then
    USER_CONFIG_DIR=$(get_user_config_dir 2>/dev/null || true)
    [[ -n "$USER_CONFIG_DIR" ]] || die "cannot resolve the user config directory; set AI_CONSULTANTS_CONFIG_DIR"
    OUTPUT_FILE="$USER_CONFIG_DIR/.env"
fi

for key in "${SET_KEYS[@]+"${SET_KEYS[@]}"}"; do
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "invalid parameter name: $key"
    is_supported_parameter "$key" || die "unsupported parameter: $key (use --show-parameters)"
done

if [[ -L "$OUTPUT_FILE" ]]; then
    die "$OUTPUT_FILE is a symlink; refusing to write through it"
fi

OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
if [[ -L "$OUTPUT_DIR" ]]; then
    die "$OUTPUT_DIR is a symlink; set AI_CONSULTANTS_CONFIG_DIR to a real directory"
fi
if [[ "$DRY_RUN" == "true" ]]; then
    WORK_FILE=$(mktemp "${TMPDIR:-/tmp}/ai-consultants-configure.XXXXXX")
else
    mkdir -p "$OUTPUT_DIR"
    WORK_FILE=$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")
fi
trap 'rm -f "$WORK_FILE"' EXIT
cp "$TEMPLATE_FILE" "$WORK_FILE"
chmod 600 "$WORK_FILE"

read_value() {
    local file="$1" wanted="$2" line key value found="" seen=false
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi
        [[ "$line" == *=* ]] || continue
        key="${line%%=*}"
        key="${key//[[:space:]]/}"
        [[ "$key" == "$wanted" ]] || continue
        value=$(parse_env_value "${line#*=}")
        found="$value"
        seen=true
    done < "$file"
    [[ "$seen" == "true" ]] || return 1
    printf '%s' "$found"
}

set_value() {
    local key="$1" value="$2" tmp line replaced=false
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "$key cannot contain a newline"
    tmp=$(mktemp "${WORK_FILE}.edit.XXXXXX")
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*#?[[:space:]]*${key}= ]]; then
            if [[ "$replaced" == "false" ]]; then
                printf '%s=%s\n' "$key" "$value" >> "$tmp"
                replaced=true
            fi
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$WORK_FILE"
    if [[ "$replaced" == "false" ]]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp"
    fi
    mv "$tmp" "$WORK_FILE"
    chmod 600 "$WORK_FILE"
}

AUTO_MARKER="# ai-consultants:auto"
DEFAULT_MARKER="# ai-consultants:default"
PIN_MARKER="# ai-consultants:pin"

has_value_marker() {
    local file="$1" key="$2" marker="$3" line normalized
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        normalized="${line#"${line%%[![:space:]]*}"}"
        if [[ "$normalized" =~ ^export[[:space:]]+ ]]; then
            normalized="${normalized#export}"
            normalized="${normalized#"${normalized%%[![:space:]]*}"}"
        fi
        [[ "$normalized" == "$key="* ]] || continue
        [[ "$normalized" == *"$marker"* ]] && return 0
    done < "$file"
    return 1
}

is_auto_managed_value() {
    local file="$1" key="$2" line normalized raw="" seen=false
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        normalized="${line#"${line%%[![:space:]]*}"}"
        if [[ "$normalized" =~ ^export[[:space:]]+ ]]; then
            normalized="${normalized#export}"
            normalized="${normalized#"${normalized%%[![:space:]]*}"}"
        fi
        [[ "$normalized" == *=* ]] || continue
        [[ "${normalized%%=*}" == "$key" ]] || continue
        raw="$normalized"
        seen=true
    done < "$file"
    [[ "$seen" == "true" && "$raw" == *"$AUTO_MARKER"* ]]
}

has_explicit_value() {
    local key="$1" candidate
    for candidate in "${SET_KEYS[@]+"${SET_KEYS[@]}"}"; do
        [[ "$candidate" == "$key" ]] && return 0
    done
    [[ -n "${!key+x}" ]] && return 0
    if [[ -f "$OUTPUT_FILE" ]] && read_value "$OUTPUT_FILE" "$key" >/dev/null 2>&1; then
        is_auto_managed_value "$OUTPUT_FILE" "$key" || return 0
    fi
    return 1
}

effective_input_value() {
    local key="$1" value i
    for ((i=${#SET_KEYS[@]}-1; i>=0; i--)); do
        if [[ "${SET_KEYS[$i]}" == "$key" ]]; then
            printf '%s' "${SET_VALUES[$i]}"
            return 0
        fi
    done
    if [[ -n "${!key+x}" ]]; then
        printf '%s' "${!key}"
        return 0
    fi
    if [[ -f "$OUTPUT_FILE" ]] && value=$(read_value "$OUTPUT_FILE" "$key"); then
        printf '%s' "$value"
        return 0
    fi
    read_value "$WORK_FILE" "$key"
}

set_auto_value() {
    set_value "$1" "$2 $AUTO_MARKER"
}

is_pin_managed_key() {
    [[ "$1" == *_MODEL ]]
}

# Pin wins over default, including hand-edited lines carrying both markers.
# Merge existing persistent values first, then current environment overrides.
while IFS= read -r key; do
    if [[ -f "$OUTPUT_FILE" ]] && value=$(read_value "$OUTPUT_FILE" "$key"); then
        if has_value_marker "$OUTPUT_FILE" "$key" "$PIN_MARKER"; then
            set_value "$key" "$value $PIN_MARKER"
        elif has_value_marker "$OUTPUT_FILE" "$key" "$DEFAULT_MARKER"; then
            provenance=$(awk -v key="$key" '
                { sub(/\r$/, ""); sub(/^[[:space:]]*(export[[:space:]]+)?/, "") }
                index($0, key "=") == 1 {
                    origin=""
                    if (match($0, /migrated-from=gpt-5[.]5|migrated-from=gpt-5[.]6-sol|migrated-from=gpt-6-astra/))
                        origin=substr($0, RSTART+14, RLENGTH-14)
                }
                END { printf "%s", origin }' "$OUTPUT_FILE")
            set_value "$key" "$value $DEFAULT_MARKER${provenance:+ migrated-from=$provenance}"
        else
            set_value "$key" "$value"
        fi
    fi
    if [[ -n "${!key+x}" ]]; then
        if is_pin_managed_key "$key"; then
            set_value "$key" "${!key} $PIN_MARKER"
        else
            set_value "$key" "${!key}"
        fi
    fi
done < <(list_parameters)

# Promote only the historical generated Claude defaults. Both the old unmarked
# Opus 4.8 scaffold and every unpinned Opus 5 value are managed defaults;
# explicit # ai-consultants:pin overrides always remain user-owned.
case "$(read_value "$WORK_FILE" CLAUDE_MODEL 2>/dev/null || true)" in
    claude-opus-4-8|claude-opus-5)
        if ! has_value_marker "$WORK_FILE" CLAUDE_MODEL "$PIN_MARKER"; then
            set_value CLAUDE_MODEL "claude-fable-5-1 $DEFAULT_MARKER"
            echo "Migrated managed Claude default to claude-fable-5-1" >&2
        fi
        ;;
esac

# Migrate exact unpinned persisted defaults; environment and --set remain pins.
# gpt-6-astra was the generated default from 5.1.0 to 5.1.2; it remains the
# max_quality target, so a pinned Astra is kept and max_quality still uses it.
old_codex_model=$(read_value "$WORK_FILE" CODEX_MODEL 2>/dev/null || true)
case "$old_codex_model" in
    gpt-5.5|gpt-5.6-sol|gpt-6-astra)
        if ! has_value_marker "$WORK_FILE" CODEX_MODEL "$PIN_MARKER"; then
            # Keep the earliest recorded origin across chained migrations.
            codex_origin=$(awk '
                { sub(/\r$/, ""); sub(/^[[:space:]]*(export[[:space:]]+)?/, "") }
                index($0, "CODEX_MODEL=") == 1 && match($0, /migrated-from=[^[:space:]]+/) {
                    origin = substr($0, RSTART + 14, RLENGTH - 14)
                }
                END { printf "%s", origin }' "$WORK_FILE")
            set_value CODEX_MODEL "gpt-6.1-sol $DEFAULT_MARKER migrated-from=${codex_origin:-$old_codex_model}"
            echo "Migrated managed Codex default: $old_codex_model -> gpt-6.1-sol" >&2
        fi
        ;;
esac

# Migrate only the exact catalog defaults previously generated by this tool.
# A # ai-consultants:pin marker is the durable escape hatch for users who want
# to keep an older target or a nonstandard binary name.
# Gemini 3.8 Flash (High) was the generated CLI default through 5.1.2; it now
# serves the standard tier only, so a pin keeps it as the default.
case "$(read_value "$WORK_FILE" GEMINI_MODEL 2>/dev/null || true)" in
    'Gemini 3.1 Pro (High)'|'Gemini 3.7 Flash (High)'|'Gemini 3.8 Flash (High)')
        if ! has_value_marker "$WORK_FILE" GEMINI_MODEL "$PIN_MARKER"; then
            set_value GEMINI_MODEL "Gemini 4 Argon (High) $DEFAULT_MARKER"
            echo "Migrated managed Gemini CLI default to Gemini 4 Argon (High)" >&2
        fi
        ;;
    'Gemini 3.7 Flash (Low)')
        if ! has_value_marker "$WORK_FILE" GEMINI_MODEL "$PIN_MARKER"; then
            set_value GEMINI_MODEL "Gemini 3.8 Flash (Low) $DEFAULT_MARKER"
            echo "Migrated managed Gemini CLI economy default to Gemini 3.8 Flash (Low)" >&2
        fi
        ;;
esac

# gemini-3.1-pro-preview was the generated API default through 5.1.2. The
# setting is API-only (agy reads GEMINI_MODEL), so CLI users are unaffected.
case "$(read_value "$WORK_FILE" GEMINI_API_MODEL 2>/dev/null || true)" in
    gemini-3.1-pro-preview)
        if ! has_value_marker "$WORK_FILE" GEMINI_API_MODEL "$PIN_MARKER"; then
            set_value GEMINI_API_MODEL "gemini-4-argon $DEFAULT_MARKER"
            echo "Migrated managed Gemini API default to gemini-4-argon" >&2
        fi
        ;;
esac

# Generation timeouts were generated as fixed limits through 5.1.2 (180 s per
# consultant, 240 s Claude and synthesis, 480 s synthesis total, 600 s for
# maximum-tier Qwen/DeepSeek). They now default to 0, no limit: the invoking
# host decides when to stop waiting. Pinned values remain hard limits.
migrated_timeouts=0
for timeout_spec in GEMINI_TIMEOUT:180 CODEX_TIMEOUT:180 MISTRAL_TIMEOUT:180 \
    QWEN3_TIMEOUT:180 GLM_TIMEOUT:180 GROK_TIMEOUT:180 DEEPSEEK_TIMEOUT:180 \
    MINIMAX_TIMEOUT:180 KIMI_TIMEOUT:180 CLAUDE_TIMEOUT:240 \
    QWEN3_MAX_QUALITY_TIMEOUT:600 DEEPSEEK_MAX_QUALITY_TIMEOUT:600 \
    SYNTHESIS_TIMEOUT:240 SYNTHESIS_TOTAL_TIMEOUT:480; do
    timeout_key="${timeout_spec%%:*}"
    if [[ "$(read_value "$WORK_FILE" "$timeout_key" 2>/dev/null || true)" == "${timeout_spec#*:}" ]] \
        && ! has_value_marker "$WORK_FILE" "$timeout_key" "$PIN_MARKER"; then
        set_value "$timeout_key" "0 $DEFAULT_MARKER"
        migrated_timeouts=$((migrated_timeouts + 1))
    fi
done
if [[ $migrated_timeouts -gt 0 ]]; then
    echo "Migrated $migrated_timeouts managed timeout default(s) to 0 (no limit)" >&2
fi
unset migrated_timeouts timeout_spec timeout_key

# Qwen 3.7 Max was the generated default through 5.1.2; the 3.8-max-preview
# Token Plan ID is no longer listed by the provider.
case "$(read_value "$WORK_FILE" QWEN3_MODEL 2>/dev/null || true)" in
    qwen3.7-max|qwen3.8-max-preview)
        if ! has_value_marker "$WORK_FILE" QWEN3_MODEL "$PIN_MARKER"; then
            set_value QWEN3_MODEL "qwen3.8-max $DEFAULT_MARKER"
            echo "Migrated managed Qwen default to qwen3.8-max" >&2
        fi
        ;;
esac

# Mistral Large 3 was the generated API default through 5.1.2. The setting is
# API-only (Vibe reads MISTRAL_CLI_MODEL), so CLI users are unaffected.
case "$(read_value "$WORK_FILE" MISTRAL_MODEL 2>/dev/null || true)" in
    mistral-large-3)
        if ! has_value_marker "$WORK_FILE" MISTRAL_MODEL "$PIN_MARKER"; then
            set_value MISTRAL_MODEL "mistral-large-4 $DEFAULT_MARKER"
            echo "Migrated managed Mistral API default to mistral-large-4" >&2
        fi
        ;;
esac

case "$(read_value "$WORK_FILE" GLM_MODEL 2>/dev/null || true)" in
    glm-5.2|glm-5.3)
        if ! has_value_marker "$WORK_FILE" GLM_MODEL "$PIN_MARKER"; then
            set_value GLM_MODEL "glm-5.3-flash $DEFAULT_MARKER"
            echo "Migrated managed GLM default to glm-5.3-flash" >&2
        fi
        ;;
esac

case "$(read_value "$WORK_FILE" GROK_MODEL 2>/dev/null || true)" in
    grok-4.5|grok-4.6)
        if ! has_value_marker "$WORK_FILE" GROK_MODEL "$PIN_MARKER"; then
            set_value GROK_MODEL "grok-4.7 $DEFAULT_MARKER"
            echo "Migrated managed Grok default to grok-4.7" >&2
        fi
        ;;
esac

# MiniMax-M2.5 (through 2.x) and MiniMax-M2.7 (through 5.2.0) were the
# generated defaults; MiniMax-M3.1-Flash now serves every tier. It always
# reasons and its reasoning shares the completion budget, so the generated
# 4096/4096/16384 budgets move to 16384/16384/32768. Pins are kept.
case "$(read_value "$WORK_FILE" MINIMAX_MODEL 2>/dev/null || true)" in
    MiniMax-M2.5|MiniMax-M2.7)
        if ! has_value_marker "$WORK_FILE" MINIMAX_MODEL "$PIN_MARKER"; then
            set_value MINIMAX_MODEL "MiniMax-M3.1-Flash $DEFAULT_MARKER"
            echo "Migrated managed MiniMax default to MiniMax-M3.1-Flash" >&2
        fi
        ;;
esac
migrated_budgets=0
for budget_spec in MINIMAX_MAX_TOKENS:4096:16384 MINIMAX_API_MAX_TOKENS:4096:16384 \
    MINIMAX_MAX_QUALITY_TOKENS:16384:32768; do
    budget_key="${budget_spec%%:*}"
    budget_old="${budget_spec#*:}"; budget_new="${budget_old#*:}"; budget_old="${budget_old%%:*}"
    if [[ "$(read_value "$WORK_FILE" "$budget_key" 2>/dev/null || true)" == "$budget_old" ]] \
        && ! has_value_marker "$WORK_FILE" "$budget_key" "$PIN_MARKER"; then
        set_value "$budget_key" "$budget_new $DEFAULT_MARKER"
        migrated_budgets=$((migrated_budgets + 1))
    fi
done
if [[ $migrated_budgets -gt 0 ]]; then
    echo "Migrated $migrated_budgets managed MiniMax token budget(s) for MiniMax-M3.1-Flash" >&2
fi
unset migrated_budgets budget_spec budget_key budget_old budget_new

# Refresh only exact unpinned historical DeepSeek defaults. Environment and
# --set selections carry pin markers and remain user-owned.
case "$(read_value "$WORK_FILE" DEEPSEEK_MODEL 2>/dev/null || true)" in
    deepseek-v4-pro|deepseek-v4-flash)
        if ! has_value_marker "$WORK_FILE" DEEPSEEK_MODEL "$PIN_MARKER"; then
            set_value DEEPSEEK_MODEL "deepseek-flash $DEFAULT_MARKER"
            echo "Migrated managed DeepSeek default to deepseek-flash (V4.1 Flash)" >&2
        fi
        ;;
esac

configure_cli_only() {
    local enable_key="$1" cmd_key="$2" cmd enabled=false
    cmd=$(effective_input_value "$cmd_key")
    command -v "$cmd" >/dev/null 2>&1 && enabled=true
    set_value "$enable_key" "$enabled"
}

configure_switchable() {
    local enable_key="$1" cmd_key="$2" mode_key="$3" api_key="$4"
    local cmd api_secret explicit_mode="" enabled=false mode=false
    cmd=$(effective_input_value "$cmd_key")
    api_secret=$(effective_input_value "$api_key" 2>/dev/null || true)
    if has_explicit_value "$mode_key"; then
        explicit_mode=$(effective_input_value "$mode_key" || true)
        case "$explicit_mode" in
            true|false) ;;
            *) echo "Warning: ignoring invalid $mode_key=$explicit_mode (expected true or false)" >&2; explicit_mode="" ;;
        esac
    fi

    if [[ "$explicit_mode" == "true" ]]; then
        mode=true
        [[ -n "$api_secret" ]] && enabled=true
    elif [[ "$explicit_mode" == "false" ]]; then
        mode=false
        command -v "$cmd" >/dev/null 2>&1 && enabled=true
    elif command -v "$cmd" >/dev/null 2>&1; then
        mode=false
        enabled=true
    elif [[ -n "$api_secret" ]]; then
        mode=true
        enabled=true
    fi

    if [[ -n "$explicit_mode" ]]; then
        set_value "$mode_key" "$mode"
    else
        set_auto_value "$mode_key" "$mode"
    fi
    set_value "$enable_key" "$enabled"
}

configure_api_only() {
    local enable_key="$1" api_key="$2" secret
    secret=$(effective_input_value "$api_key" 2>/dev/null || true)
    if [[ -n "$secret" ]]; then
        set_value "$enable_key" true
    else
        set_value "$enable_key" false
    fi
}

run_auto_detection() {
    # CLI-first auto-detection. An explicitly configured *_USE_API value wins.
    configure_switchable ENABLE_GEMINI GEMINI_CMD GEMINI_USE_API GEMINI_API_KEY
    configure_switchable ENABLE_CODEX CODEX_CMD CODEX_USE_API OPENAI_API_KEY
    configure_switchable ENABLE_MISTRAL MISTRAL_CMD MISTRAL_USE_API MISTRAL_API_KEY
    configure_cli_only ENABLE_KIMI KIMI_CMD
    configure_switchable ENABLE_CLAUDE CLAUDE_CMD CLAUDE_USE_API ANTHROPIC_API_KEY
    configure_switchable ENABLE_QWEN3 QWEN3_CMD QWEN3_USE_API QWEN3_API_KEY
    configure_switchable ENABLE_GROK GROK_CMD GROK_USE_API GROK_API_KEY
    configure_switchable ENABLE_MINIMAX MINIMAX_CMD MINIMAX_USE_API MINIMAX_API_KEY
    configure_api_only ENABLE_GLM GLM_API_KEY
    configure_api_only ENABLE_DEEPSEEK DEEPSEEK_API_KEY
}

run_auto_detection

prompt_value() {
    local key="$1" current reply
    current=$(read_value "$WORK_FILE" "$key" || true)
    if [[ "$key" == *_API_KEY ]]; then
        read -r -s -p "$key [keep current]: " reply
        echo ""
        if [[ -n "$reply" ]]; then
            set_value "$key" "$reply"
        fi
    else
        read -r -p "$key [$current]: " reply
        if [[ -n "$reply" ]]; then
            if is_pin_managed_key "$key"; then
                set_value "$key" "$reply $PIN_MARKER"
            else
                set_value "$key" "$reply"
            fi
        fi
    fi
}

if [[ "$MODE" == "interactive" ]]; then
    read -r -p "Configure or update API credentials? [y/N]: " configure_keys
    if [[ "$configure_keys" =~ ^[Yy]$ ]]; then
        for key in GEMINI_API_KEY OPENAI_API_KEY MISTRAL_API_KEY ANTHROPIC_API_KEY QWEN3_API_KEY MINIMAX_API_KEY GLM_API_KEY GROK_API_KEY DEEPSEEK_API_KEY; do
            prompt_value "$key"
        done
        # Re-evaluate transports now that new credentials are available.
        run_auto_detection
    fi

    echo "Detected configuration (press Enter to keep each value):"
    for key in ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_KIMI ENABLE_CLAUDE ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK ENABLE_MINIMAX; do
        prompt_value "$key"
    done
    for key in GEMINI_USE_API CODEX_USE_API MISTRAL_USE_API CLAUDE_USE_API QWEN3_USE_API GROK_USE_API MINIMAX_USE_API; do
        prompt_value "$key"
    done

    if [[ "$ADVANCED" == "true" ]]; then
        echo ""
        echo "Advanced review: every supported persistent parameter"
        # Read the parameter list on fd 3, not stdin (fd 0) — prompt_value's
        # nested `read -r -p` needs the real stdin for the interactive reply;
        # redirecting the loop itself on fd 0 would make it consume the next
        # parameter name as the user's answer instead.
        while IFS= read -r key <&3; do
            case "$key" in
                ENABLE_GEMINI|ENABLE_CODEX|ENABLE_MISTRAL|ENABLE_KIMI|ENABLE_CLAUDE|ENABLE_QWEN3|ENABLE_GLM|ENABLE_GROK|ENABLE_DEEPSEEK|ENABLE_MINIMAX|GEMINI_USE_API|CODEX_USE_API|MISTRAL_USE_API|CLAUDE_USE_API|QWEN3_USE_API|GROK_USE_API|MINIMAX_USE_API|GEMINI_API_KEY|OPENAI_API_KEY|MISTRAL_API_KEY|ANTHROPIC_API_KEY|QWEN3_API_KEY|MINIMAX_API_KEY|GLM_API_KEY|GROK_API_KEY|DEEPSEEK_API_KEY) continue ;;
            esac
            prompt_value "$key"
        done 3< <(list_parameters)
    fi
fi

# Explicit command-line overrides have final precedence.
for ((i=0; i<${#SET_KEYS[@]}; i++)); do
    if is_pin_managed_key "${SET_KEYS[$i]}"; then
        set_value "${SET_KEYS[$i]}" "${SET_VALUES[$i]} $PIN_MARKER"
    else
        set_value "${SET_KEYS[$i]}" "${SET_VALUES[$i]}"
    fi
done

enabled_count=0
for key in ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_KIMI ENABLE_CLAUDE ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK ENABLE_MINIMAX; do
    [[ "$(read_value "$WORK_FILE" "$key" || true)" == "true" ]] && enabled_count=$((enabled_count + 1))
done

if [[ "$DRY_RUN" == "true" ]]; then
    # Never print secrets in dry-run output.
    sed -E 's/^([A-Z][A-Z0-9_]*_API_KEY)=.*$/\1=<redacted>/' "$WORK_FILE"
    echo "" >&2
    echo "Detected $enabled_count usable consultant(s); no files written." >&2
    exit 0
fi

if [[ -f "$OUTPUT_FILE" && "$FORCE" != "true" ]]; then
    # mktemp, not a bare timestamp: the name is only second-precise, so two runs
    # landing in the same second would resolve to one path and the second cp
    # would clobber the first run's backup. mktemp claims the name atomically,
    # which also makes concurrent runs safe.
    backup=$(mktemp "${OUTPUT_FILE}.backup.$(date +%Y%m%d_%H%M%S).XXXXXX")
    cp "$OUTPUT_FILE" "$backup"
    chmod 600 "$backup"
    echo "Backup: $backup"
fi

mv "$WORK_FILE" "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"
trap - EXIT

echo "Configuration saved to: $OUTPUT_FILE"
echo "Enabled consultants: $enabled_count/10"
if [[ $enabled_count -lt 2 ]]; then
    echo "Warning: fewer than 2 consultants are currently usable." >&2
    echo "Install another CLI or add an API key, then run configure again." >&2
fi
echo "Next: ai-consultants doctor"
