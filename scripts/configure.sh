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
  ai-consultants configure --set DEFAULT_PRESET=balanced --set ENABLE_DEBATE=true
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
        value="${line#*=}"
        if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
            value="${value:1:${#value}-2}"
        else
            value=$(printf '%s' "$value" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
        fi
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

# Merge existing persistent values first, then current environment overrides.
while IFS= read -r key; do
    if [[ -f "$OUTPUT_FILE" ]] && value=$(read_value "$OUTPUT_FILE" "$key"); then
        set_value "$key" "$value"
    fi
    if [[ -n "${!key+x}" ]]; then
        set_value "$key" "${!key}"
    fi
done < <(list_parameters)

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
    configure_cli_only ENABLE_CURSOR CURSOR_CMD
    configure_cli_only ENABLE_KIMI KIMI_CMD
    configure_switchable ENABLE_CLAUDE CLAUDE_CMD CLAUDE_USE_API ANTHROPIC_API_KEY
    configure_switchable ENABLE_QWEN3 QWEN3_CMD QWEN3_USE_API QWEN3_API_KEY
    configure_switchable ENABLE_MINIMAX MINIMAX_CMD MINIMAX_USE_API MINIMAX_API_KEY
    configure_api_only ENABLE_GLM GLM_API_KEY
    configure_api_only ENABLE_GROK GROK_API_KEY
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
            set_value "$key" "$reply"
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
    for key in ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_CURSOR ENABLE_KIMI ENABLE_CLAUDE ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK ENABLE_MINIMAX; do
        prompt_value "$key"
    done
    for key in GEMINI_USE_API CODEX_USE_API MISTRAL_USE_API CLAUDE_USE_API QWEN3_USE_API MINIMAX_USE_API; do
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
                ENABLE_GEMINI|ENABLE_CODEX|ENABLE_MISTRAL|ENABLE_CURSOR|ENABLE_KIMI|ENABLE_CLAUDE|ENABLE_QWEN3|ENABLE_GLM|ENABLE_GROK|ENABLE_DEEPSEEK|ENABLE_MINIMAX|GEMINI_USE_API|CODEX_USE_API|MISTRAL_USE_API|CLAUDE_USE_API|QWEN3_USE_API|MINIMAX_USE_API|GEMINI_API_KEY|OPENAI_API_KEY|MISTRAL_API_KEY|ANTHROPIC_API_KEY|QWEN3_API_KEY|MINIMAX_API_KEY|GLM_API_KEY|GROK_API_KEY|DEEPSEEK_API_KEY) continue ;;
            esac
            prompt_value "$key"
        done 3< <(list_parameters)
    fi
fi

# Explicit command-line overrides have final precedence.
for ((i=0; i<${#SET_KEYS[@]}; i++)); do
    set_value "${SET_KEYS[$i]}" "${SET_VALUES[$i]}"
done

enabled_count=0
for key in ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_CURSOR ENABLE_KIMI ENABLE_CLAUDE ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK ENABLE_MINIMAX; do
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
echo "Enabled consultants: $enabled_count/11"
if [[ $enabled_count -lt 2 ]]; then
    echo "Warning: fewer than 2 consultants are currently usable." >&2
    echo "Install another CLI or add an API key, then run configure again." >&2
fi
echo "Next: ai-consultants doctor"
