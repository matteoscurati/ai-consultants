#!/bin/bash
# configure.sh - Interactive configuration wizard for AI Consultants v2.0
#
# Detects available CLI agents, allows selection and API configuration,
# ensures minimum 2 agents are enabled, and saves configuration to .env
#
# Usage: ./configure.sh [--non-interactive] [--output FILE]
#
# Options:
#   --non-interactive   Skip prompts, detect and auto-enable available agents
#   --output FILE       Output file (default: .env in project root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load common utilities if available
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Fallback logging functions
    log_info() { echo "[INFO] $*"; }
    log_success() { echo "[OK] $*"; }
    log_warn() { echo "[WARN] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

# Load personas library for persona catalog
if [[ -f "$SCRIPT_DIR/lib/personas.sh" ]]; then
    source "$SCRIPT_DIR/lib/personas.sh"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

NON_INTERACTIVE=false
OUTPUT_FILE="$PROJECT_ROOT/.env"

# CLI Agents: name|command|install_hint|persona
CLI_AGENT_NAMES=("Gemini" "Codex" "Mistral" "Kilo" "Cursor")
CLI_AGENT_CMDS=("gemini" "codex" "vibe" "kilocode" "agent")
CLI_AGENT_HINTS=("npm install -g @google/gemini-cli" "npm install -g @openai/codex" "pip install mistral-vibe" "npm install -g @kilocode/cli" "See: https://cursor.com/")
CLI_AGENT_PERSONAS=("The Architect" "The Pragmatist" "The Devil's Advocate" "The Innovator" "The Integrator")

# API Agents: name|key_var|api_url|model|persona
API_AGENT_NAMES=("Qwen3" "GLM" "Grok")
API_AGENT_KEY_VARS=("QWEN3_API_KEY" "GLM_API_KEY" "GROK_API_KEY")
API_AGENT_URLS=("https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation" "https://open.bigmodel.cn/api/paas/v4/chat/completions" "https://api.x.ai/v1/chat/completions")
API_AGENT_MODELS=("qwen-max" "glm-4" "grok-beta")
API_AGENT_PERSONAS=("The Analyst" "The Methodologist" "The Provocateur")

# State arrays (parallel to CLI_AGENT_NAMES)
CLI_DETECTED=()      # "installed" or "missing"
CLI_ENABLED=()       # "true" or "false"

# State arrays (parallel to API_AGENT_NAMES)
API_ENABLED=()       # "true" or "false"
API_KEYS_VALUES=()   # actual API key values

# Custom CLI agents
CUSTOM_NAMES=()
CUSTOM_CMDS=()
CUSTOM_PERSONAS=()

# Custom API agents
CUSTOM_API_NAMES=()
CUSTOM_API_URLS=()
CUSTOM_API_KEYS=()
CUSTOM_API_MODELS=()
CUSTOM_API_PERSONAS=()
CUSTOM_API_FORMATS=()  # "openai" or "qwen"

# Persona assignments (maps agent name to persona ID)
# Parallel arrays for CLI and API agents
CLI_PERSONA_IDS=()     # persona ID for each CLI agent
API_PERSONA_IDS=()     # persona ID for each API agent
CUSTOM_PERSONA_IDS=()  # persona ID for each custom CLI agent
CUSTOM_API_PERSONA_IDS=()  # persona ID for each custom API agent

# Initialize state arrays
# Default persona IDs: 1=Architect, 2=Pragmatist, 3=Devil's Advocate, 4=Innovator, 5=Integrator
CLI_DEFAULT_PERSONA_IDS=(1 2 3 4 5)
for i in "${!CLI_AGENT_NAMES[@]}"; do
    CLI_DETECTED+=("missing")
    CLI_ENABLED+=("false")
    CLI_PERSONA_IDS+=("${CLI_DEFAULT_PERSONA_IDS[$i]}")
done

# Default persona IDs: 6=Analyst, 7=Methodologist, 8=Provocateur
API_DEFAULT_PERSONA_IDS=(6 7 8)
for i in "${!API_AGENT_NAMES[@]}"; do
    API_ENABLED+=("false")
    API_KEYS_VALUES+=("")
    API_PERSONA_IDS+=("${API_DEFAULT_PERSONA_IDS[$i]}")
done

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--non-interactive] [--output FILE]"
            echo ""
            echo "Interactive configuration wizard for AI Consultants."
            echo ""
            echo "Options:"
            echo "  --non-interactive   Auto-detect and enable available agents"
            echo "  --output FILE       Output file (default: .env)"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# =============================================================================
# UTILITIES
# =============================================================================

# Normalize name to uppercase (removes spaces and hyphens)
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr -d ' -'
}

# Print a header box
print_header() {
    local title="$1"
    local width=60
    echo ""
    printf '╔'; printf '═%.0s' $(seq 1 $width); printf '╗\n'
    printf "║ %-$((width-1))s║\n" "$title"
    printf '╚'; printf '═%.0s' $(seq 1 $width); printf '╝\n'
    echo ""
}

# Print a section divider
print_section() {
    local title="$1"
    echo ""
    echo "─── $title ───"
    echo ""
}

# Emit a section header to .env file
# Usage: emit_env_section "SECTION TITLE" [file]
emit_env_section() {
    local title="$1"
    local file="${2:-$OUTPUT_FILE}"
    {
        echo ""
        echo "# ============================================================================="
        echo "# $title"
        echo "# ============================================================================="
        echo ""
    } >> "$file"
}

# Prompt yes/no
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi

    local yn
    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt [Y/n]: " yn
        yn=${yn:-y}
    else
        read -r -p "$prompt [y/N]: " yn
        yn=${yn:-n}
    fi

    [[ "$yn" =~ ^[Yy] ]] && return 0 || return 1
}

# Prompt for input with default
prompt_input() {
    local prompt="$1"
    local default="${2:-}"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        REPLY="$default"
        return
    fi

    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " REPLY
        REPLY=${REPLY:-$default}
    else
        read -r -p "$prompt: " REPLY
    fi
}

# Prompt for secret (no echo)
prompt_secret() {
    local prompt="$1"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        REPLY=""
        return
    fi

    read -r -s -p "$prompt: " REPLY
    echo ""
}

# =============================================================================
# CLI AGENT DETECTION
# =============================================================================

detect_cli_agents() {
    print_section "Detecting CLI Agents"

    local found=0
    for i in "${!CLI_AGENT_NAMES[@]}"; do
        local name="${CLI_AGENT_NAMES[$i]}"
        local cmd="${CLI_AGENT_CMDS[$i]}"
        local persona="${CLI_AGENT_PERSONAS[$i]}"

        if command -v "$cmd" &> /dev/null; then
            CLI_DETECTED[$i]="installed"
            local version
            version=$("$cmd" --version 2>/dev/null | head -1 || echo "detected")
            echo "  [FOUND] $name ($persona) - $cmd"
            ((found++)) || true
        else
            CLI_DETECTED[$i]="missing"
            echo "  [-----] $name ($persona) - not found"
        fi
    done

    echo ""
    echo "Found $found CLI agent(s) installed."
    return 0
}

# =============================================================================
# CLI AGENT SELECTION
# =============================================================================

select_cli_agents() {
    print_section "Select CLI Agents to Enable"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        # Auto-enable all detected CLI agents
        for i in "${!CLI_AGENT_NAMES[@]}"; do
            if [[ "${CLI_DETECTED[$i]}" == "installed" ]]; then
                CLI_ENABLED[$i]="true"
                log_info "Auto-enabled: ${CLI_AGENT_NAMES[$i]}"
            fi
        done
        return
    fi

    # Build list of detected agents
    local detected_indices=()
    for i in "${!CLI_AGENT_NAMES[@]}"; do
        if [[ "${CLI_DETECTED[$i]}" == "installed" ]]; then
            detected_indices+=("$i")
        fi
    done

    if [[ ${#detected_indices[@]} -eq 0 ]]; then
        echo "  No CLI agents detected. You can add custom ones or use API agents."
        echo ""
        if confirm "Add a custom CLI agent?"; then
            add_custom_cli_agent
        fi
        return
    fi

    # Pre-select all detected agents
    for i in "${detected_indices[@]}"; do
        CLI_ENABLED[$i]="true"
    done

    local done_selecting=false
    while [[ "$done_selecting" != "true" ]]; do
        echo ""
        echo "Available CLI agents (x = selected):"
        local menu_idx=1
        for i in "${detected_indices[@]}"; do
            local name="${CLI_AGENT_NAMES[$i]}"
            local persona="${CLI_AGENT_PERSONAS[$i]}"
            local mark=" "
            [[ "${CLI_ENABLED[$i]}" == "true" ]] && mark="x"
            echo "  $menu_idx) [$mark] $name ($persona)"
            ((menu_idx++)) || true
        done
        echo "  a) Select all"
        echo "  n) Select none"
        echo "  c) Add custom CLI agent"
        echo "  d) Done"
        echo ""

        read -r -p "Choice: " choice

        case "$choice" in
            [1-9]|[1-9][0-9])
                if [[ $choice -le ${#detected_indices[@]} ]]; then
                    local idx="${detected_indices[$((choice-1))]}"
                    if [[ "${CLI_ENABLED[$idx]}" == "true" ]]; then
                        CLI_ENABLED[$idx]="false"
                    else
                        CLI_ENABLED[$idx]="true"
                    fi
                fi
                ;;
            a|A)
                for i in "${detected_indices[@]}"; do
                    CLI_ENABLED[$i]="true"
                done
                ;;
            n|N)
                for i in "${detected_indices[@]}"; do
                    CLI_ENABLED[$i]="false"
                done
                ;;
            c|C)
                add_custom_cli_agent
                ;;
            d|D)
                done_selecting=true
                ;;
        esac
    done
}

# =============================================================================
# CUSTOM CLI AGENT
# =============================================================================

add_custom_cli_agent() {
    print_section "Add Custom CLI Agent"

    prompt_input "Agent name (e.g., 'Claude', 'GPT4All')" ""
    local name="$REPLY"
    [[ -z "$name" ]] && return

    prompt_input "Command to execute (e.g., 'claude', 'gpt4all')" ""
    local cmd="$REPLY"
    [[ -z "$cmd" ]] && return

    # Check if command exists
    if ! command -v "$cmd" &> /dev/null; then
        log_warn "Command '$cmd' not found in PATH."
        if ! confirm "Add anyway?"; then
            return
        fi
    fi

    prompt_input "Persona/Role description" "Custom Agent"
    local persona="$REPLY"

    # Store custom agent
    CUSTOM_NAMES+=("$name")
    CUSTOM_CMDS+=("$cmd")
    CUSTOM_PERSONAS+=("$persona")

    log_success "Added custom CLI agent: $name ($cmd)"
}

# =============================================================================
# CUSTOM API AGENT
# =============================================================================

add_custom_api_agent() {
    print_section "Add Custom API Agent"

    echo "Add any OpenAI-compatible or custom API endpoint."
    echo ""

    prompt_input "Agent name (e.g., 'OpenRouter', 'Groq', 'Together')" ""
    local name="$REPLY"
    [[ -z "$name" ]] && return

    prompt_input "API endpoint URL (e.g., https://api.openrouter.ai/api/v1/chat/completions)" ""
    local url="$REPLY"
    [[ -z "$url" ]] && return

    prompt_secret "API key"
    local key="$REPLY"
    [[ -z "$key" ]] && { log_warn "API key required"; return; }

    prompt_input "Model name (e.g., 'gpt-4', 'anthropic/claude-3')" "gpt-4"
    local model="$REPLY"

    prompt_input "Persona/Role description" "External API Consultant"
    local persona="$REPLY"

    echo ""
    echo "Response format:"
    echo "  1) OpenAI-compatible (most APIs - recommended)"
    echo "  2) Qwen/DashScope format"
    read -r -p "Choice [1]: " format_choice
    local format="openai"
    [[ "$format_choice" == "2" ]] && format="qwen"

    # Store custom API agent
    CUSTOM_API_NAMES+=("$name")
    CUSTOM_API_URLS+=("$url")
    CUSTOM_API_KEYS+=("$key")
    CUSTOM_API_MODELS+=("$model")
    CUSTOM_API_PERSONAS+=("$persona")
    CUSTOM_API_FORMATS+=("$format")

    log_success "Added custom API agent: $name ($url)"
}

# =============================================================================
# API AGENT CONFIGURATION
# =============================================================================

configure_api_agents() {
    print_section "Configure API-Based Agents"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        # Auto-enable API agents with existing keys
        for i in "${!API_AGENT_NAMES[@]}"; do
            local key_var="${API_AGENT_KEY_VARS[$i]}"
            local existing_key="${!key_var:-}"
            if [[ -n "$existing_key" ]]; then
                API_ENABLED[$i]="true"
                API_KEYS_VALUES[$i]="$existing_key"
                log_info "Auto-enabled: ${API_AGENT_NAMES[$i]} (API key found)"
            fi
        done
        # Also check for custom API agents via naming convention
        # (e.g., CUSTOMAGENT_API_KEY, CUSTOMAGENT_API_URL, ENABLE_CUSTOMAGENT=true)
        return
    fi

    echo "API-based agents require API keys but no CLI installation."
    echo ""
    echo "Predefined API agents:"
    for i in "${!API_AGENT_NAMES[@]}"; do
        local name="${API_AGENT_NAMES[$i]}"
        local model="${API_AGENT_MODELS[$i]}"
        local persona="${API_AGENT_PERSONAS[$i]}"
        echo "  - $name ($persona) - Model: $model"
    done
    echo ""
    echo "You can also add custom API agents (OpenRouter, Groq, Together, etc.)"
    echo ""

    if ! confirm "Configure API-based agents?"; then
        return
    fi

    local done_api_config=false
    while [[ "$done_api_config" != "true" ]]; do
        echo ""
        echo "API Agent Configuration:"
        echo "  1) Configure predefined agents (Qwen3, GLM, Grok)"
        echo "  2) Add custom API agent"
        echo "  3) Done with API configuration"
        echo ""

        read -r -p "Choice [1-3]: " api_choice

        case "$api_choice" in
            1)
                _configure_predefined_api_agents
                ;;
            2)
                add_custom_api_agent
                ;;
            3|"")
                done_api_config=true
                ;;
        esac
    done
}

# Internal function to configure predefined API agents
_configure_predefined_api_agents() {
    for i in "${!API_AGENT_NAMES[@]}"; do
        local name="${API_AGENT_NAMES[$i]}"
        local key_var="${API_AGENT_KEY_VARS[$i]}"
        local persona="${API_AGENT_PERSONAS[$i]}"

        echo ""
        if confirm "Enable $name ($persona)?"; then
            # Check for existing key in environment
            local existing_key="${!key_var:-}"

            if [[ -n "$existing_key" ]]; then
                local masked="${existing_key:0:8}...${existing_key: -4}"
                echo "  Existing key found: $masked"
                if confirm "  Use existing key?" "y"; then
                    API_ENABLED[$i]="true"
                    API_KEYS_VALUES[$i]="$existing_key"
                    continue
                fi
            fi

            # Prompt for new key
            prompt_secret "  Enter $name API key ($key_var)"
            local api_key="$REPLY"

            if [[ -n "$api_key" ]]; then
                API_ENABLED[$i]="true"
                API_KEYS_VALUES[$i]="$api_key"
                log_success "$name enabled"
            else
                log_warn "$name skipped (no API key)"
            fi
        fi
    done
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_configuration() {
    print_section "Validating Configuration"

    local cli_count=0
    local api_count=0
    local custom_cli_count=${#CUSTOM_NAMES[@]}
    local custom_api_count=${#CUSTOM_API_NAMES[@]}

    # Count enabled CLI agents
    for i in "${!CLI_AGENT_NAMES[@]}"; do
        if [[ "${CLI_ENABLED[$i]}" == "true" ]]; then
            ((cli_count++)) || true
        fi
    done

    # Count enabled predefined API agents
    for i in "${!API_AGENT_NAMES[@]}"; do
        if [[ "${API_ENABLED[$i]}" == "true" ]]; then
            ((api_count++)) || true
        fi
    done

    local total_cli=$((cli_count + custom_cli_count))
    local total_api=$((api_count + custom_api_count))
    local total_enabled=$((total_cli + total_api))

    echo "Summary:"
    echo "  CLI agents enabled: $total_cli (predefined: $cli_count, custom: $custom_cli_count)"
    echo "  API agents enabled: $total_api (predefined: $api_count, custom: $custom_api_count)"
    echo "  Total enabled: $total_enabled"
    echo ""

    # Validation: minimum 2 agents required
    if [[ $total_enabled -lt 2 ]]; then
        log_error "At least 2 agents must be enabled for AI Consultants to work."
        echo ""
        echo "The system requires multiple perspectives for:"
        echo "  - Comparison and voting"
        echo "  - Multi-Agent Debate"
        echo "  - Consensus building"
        echo ""

        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            return 1
        fi

        echo "Options:"
        echo "  1) Add custom CLI agent"
        echo "  2) Configure API agents"
        echo "  3) Abort configuration"
        echo ""

        read -r -p "Choice [1-3]: " choice

        case "$choice" in
            1)
                add_custom_cli_agent
                validate_configuration
                return $?
                ;;
            2)
                configure_api_agents
                validate_configuration
                return $?
                ;;
            *)
                return 1
                ;;
        esac
    else
        log_success "Configuration valid: $total_enabled agents enabled"
        return 0
    fi
}

# =============================================================================
# SAVE CONFIGURATION
# =============================================================================

save_configuration() {
    print_section "Saving Configuration"

    # Backup existing .env if present
    if [[ -f "$OUTPUT_FILE" ]]; then
        local backup="${OUTPUT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$OUTPUT_FILE" "$backup"
        log_info "Backed up existing config to: $backup"
    fi

    # Generate .env file
    cat > "$OUTPUT_FILE" << 'HEADER'
# =============================================================================
# AI Consultants v2.0 - Generated Configuration
# =============================================================================
# Generated by: ./scripts/configure.sh
#
# This file was auto-generated. You can edit it manually or re-run configure.sh
#
# Export variables before running:
#   source .env && ./scripts/consult_all.sh "Your question"

HEADER

    # CLI Agents
    emit_env_section "ENABLED CONSULTANTS"
    echo "# CLI-based consultants" >> "$OUTPUT_FILE"

    for i in "${!CLI_AGENT_NAMES[@]}"; do
        local name_upper
        name_upper=$(to_upper "${CLI_AGENT_NAMES[$i]}")
        echo "ENABLE_${name_upper}=${CLI_ENABLED[$i]}" >> "$OUTPUT_FILE"
    done

    echo -e "\n# API-based consultants" >> "$OUTPUT_FILE"

    for i in "${!API_AGENT_NAMES[@]}"; do
        local name_upper
        name_upper=$(to_upper "${API_AGENT_NAMES[$i]}")
        echo "ENABLE_${name_upper}=${API_ENABLED[$i]}" >> "$OUTPUT_FILE"
    done

    # API Keys
    emit_env_section "API KEYS"

    for i in "${!API_AGENT_NAMES[@]}"; do
        if [[ -n "${API_KEYS_VALUES[$i]}" ]]; then
            local key_var="${API_AGENT_KEY_VARS[$i]}"
            echo "${key_var}=${API_KEYS_VALUES[$i]}" >> "$OUTPUT_FILE"
        fi
    done

    # Custom CLI agents
    if [[ ${#CUSTOM_NAMES[@]} -gt 0 ]]; then
        emit_env_section "CUSTOM CLI AGENTS"

        for i in "${!CUSTOM_NAMES[@]}"; do
            local var_upper
            var_upper=$(to_upper "${CUSTOM_NAMES[$i]}")
            echo "# Custom CLI agent: ${CUSTOM_NAMES[$i]} (${CUSTOM_PERSONAS[$i]})" >> "$OUTPUT_FILE"
            echo "${var_upper}_CMD=${CUSTOM_CMDS[$i]}" >> "$OUTPUT_FILE"
            echo "ENABLE_${var_upper}=true" >> "$OUTPUT_FILE"
        done
    fi

    # Custom API agents
    if [[ ${#CUSTOM_API_NAMES[@]} -gt 0 ]]; then
        emit_env_section "CUSTOM API AGENTS"

        for i in "${!CUSTOM_API_NAMES[@]}"; do
            local var_upper
            var_upper=$(to_upper "${CUSTOM_API_NAMES[$i]}")
            {
                echo "# Custom API agent: ${CUSTOM_API_NAMES[$i]}"
                echo "# Persona: ${CUSTOM_API_PERSONAS[$i]}"
                echo "${var_upper}_API_KEY=${CUSTOM_API_KEYS[$i]}"
                echo "${var_upper}_API_URL=${CUSTOM_API_URLS[$i]}"
                echo "${var_upper}_MODEL=${CUSTOM_API_MODELS[$i]}"
                echo "${var_upper}_TIMEOUT=180"
                echo "${var_upper}_FORMAT=${CUSTOM_API_FORMATS[$i]}"
                echo "${var_upper}_PERSONA=\"${CUSTOM_API_PERSONAS[$i]}\""
                echo "ENABLE_${var_upper}=true"
                echo ""
            } >> "$OUTPUT_FILE"
        done
    fi

    # Persona assignments (only output non-default assignments)
    emit_env_section "PERSONA ASSIGNMENTS"
    {
        echo "# Default personas are used unless overridden here"
        echo "# Persona IDs: 1=Architect, 2=Pragmatist, 3=Devil's Advocate, 4=Innovator,"
        echo "# 5=Integrator, 6=Analyst, 7=Methodologist, 8=Provocateur, 9=Mentor,"
        echo "# 10=Optimizer, 11=Security Expert, 12=Minimalist, 13=DX Advocate,"
        echo "# 14=Debugger, 15=Reviewer"
        echo ""
    } >> "$OUTPUT_FILE"

    # Helper to write persona assignment if non-default
    _write_persona_if_changed() {
        local name_upper="$1" persona_id="$2" default_id="$3" custom_text="$4"
        if [[ "$persona_id" == "0" && -n "$custom_text" ]]; then
            echo "${name_upper}_PERSONA=\"$custom_text\"" >> "$OUTPUT_FILE"
        elif [[ "$persona_id" != "$default_id" ]]; then
            echo "${name_upper}_PERSONA_ID=$persona_id" >> "$OUTPUT_FILE"
        fi
    }

    # CLI agent personas
    for i in "${!CLI_AGENT_NAMES[@]}"; do
        [[ "${CLI_ENABLED[$i]}" != "true" ]] && continue
        _write_persona_if_changed "$(to_upper "${CLI_AGENT_NAMES[$i]}")" \
            "${CLI_PERSONA_IDS[$i]}" "${CLI_DEFAULT_PERSONA_IDS[$i]}" "${CLI_AGENT_PERSONAS[$i]:-}"
    done

    # API agent personas
    for i in "${!API_AGENT_NAMES[@]}"; do
        [[ "${API_ENABLED[$i]}" != "true" ]] && continue
        _write_persona_if_changed "$(to_upper "${API_AGENT_NAMES[$i]}")" \
            "${API_PERSONA_IDS[$i]}" "${API_DEFAULT_PERSONA_IDS[$i]}" "${API_AGENT_PERSONAS[$i]:-}"
    done

    # Custom CLI agent personas
    for i in "${!CUSTOM_NAMES[@]}"; do
        [[ ${#CUSTOM_PERSONA_IDS[@]} -le $i ]] && continue
        _write_persona_if_changed "$(to_upper "${CUSTOM_NAMES[$i]}")" \
            "${CUSTOM_PERSONA_IDS[$i]}" "1" "${CUSTOM_PERSONAS[$i]:-}"
    done

    # Default configuration from template
    cat >> "$OUTPUT_FILE" << 'DEFAULTS'

# =============================================================================
# MODEL CONFIGURATION
# =============================================================================

GEMINI_MODEL=gemini-2.5-pro
GEMINI_TIMEOUT=180

CODEX_MODEL=
CODEX_TIMEOUT=180

MISTRAL_TIMEOUT=180

KILO_TIMEOUT=180

CURSOR_TIMEOUT=180

# API models
QWEN3_MODEL=qwen-max
QWEN3_TIMEOUT=180

GLM_MODEL=glm-4
GLM_TIMEOUT=180

GROK_MODEL=grok-beta
GROK_TIMEOUT=180

# =============================================================================
# FEATURES
# =============================================================================

ENABLE_PERSONA=true
ENABLE_SYNTHESIS=true
SYNTHESIS_CMD=claude

ENABLE_DEBATE=false
DEBATE_ROUNDS=1

ENABLE_REFLECTION=false
REFLECTION_CYCLES=1

# =============================================================================
# SMART ROUTING
# =============================================================================

ENABLE_CLASSIFICATION=true
CLASSIFICATION_MODE=pattern
ENABLE_SMART_ROUTING=false
MIN_AFFINITY=7

# =============================================================================
# COST & SESSION
# =============================================================================

ENABLE_COST_TRACKING=true
MAX_SESSION_COST=1.00
WARN_AT_COST=0.50

SESSION_DIR=/tmp/ai_consultants_sessions
SESSION_CLEANUP_DAYS=7

# =============================================================================
# OTHER
# =============================================================================

ENABLE_PROGRESS_BARS=true
ENABLE_EARLY_TERMINATION=true
ENABLE_PREFLIGHT=false
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
LOG_LEVEL=INFO
DEFAULTS

    log_success "Configuration saved to: $OUTPUT_FILE"
    echo ""
    echo "To use this configuration:"
    echo "  source $OUTPUT_FILE && ./scripts/consult_all.sh \"Your question\""
}

# =============================================================================
# PERSONA CONFIGURATION
# =============================================================================

configure_personas() {
    print_section "Configure Personas"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_info "Using default personas (non-interactive mode)"
        return
    fi

    echo "Each agent can have a different persona that shapes its response style."
    echo "Default personas are pre-configured, but you can customize them."
    echo ""

    if ! confirm "Customize agent personas?" "n"; then
        return
    fi

    local done_personas=false
    while [[ "$done_personas" != "true" ]]; do
        echo ""
        echo "Enabled agents and their personas:"
        echo ""

        local menu_idx=1
        local agent_list=()  # Track: "type|index" (e.g., "cli|0", "api|2")

        # List CLI agents
        for i in "${!CLI_AGENT_NAMES[@]}"; do
            if [[ "${CLI_ENABLED[$i]}" == "true" ]]; then
                local name="${CLI_AGENT_NAMES[$i]}"
                local persona_id="${CLI_PERSONA_IDS[$i]}"
                local persona_name
                persona_name=$(get_persona_by_id "$persona_id" "name" 2>/dev/null || echo "Unknown")
                printf "  %2s) %-12s - %s\n" "$menu_idx" "$name" "$persona_name"
                agent_list+=("cli|$i")
                ((menu_idx++)) || true
            fi
        done

        # List API agents
        for i in "${!API_AGENT_NAMES[@]}"; do
            if [[ "${API_ENABLED[$i]}" == "true" ]]; then
                local name="${API_AGENT_NAMES[$i]}"
                local persona_id="${API_PERSONA_IDS[$i]}"
                local persona_name
                persona_name=$(get_persona_by_id "$persona_id" "name" 2>/dev/null || echo "Unknown")
                printf "  %2s) %-12s - %s\n" "$menu_idx" "$name" "$persona_name"
                agent_list+=("api|$i")
                ((menu_idx++)) || true
            fi
        done

        # List custom CLI agents
        for i in "${!CUSTOM_NAMES[@]}"; do
            local name="${CUSTOM_NAMES[$i]}"
            local persona_id="${CUSTOM_PERSONA_IDS[$i]:-1}"
            local persona_name
            persona_name=$(get_persona_by_id "$persona_id" "name" 2>/dev/null || echo "Custom")
            printf "  %2s) %-12s - %s (custom)\n" "$menu_idx" "$name" "$persona_name"
            agent_list+=("custom_cli|$i")
            ((menu_idx++)) || true
        done

        # List custom API agents
        for i in "${!CUSTOM_API_NAMES[@]}"; do
            local name="${CUSTOM_API_NAMES[$i]}"
            local persona_id="${CUSTOM_API_PERSONA_IDS[$i]:-1}"
            local persona_name
            persona_name=$(get_persona_by_id "$persona_id" "name" 2>/dev/null || echo "Custom")
            printf "  %2s) %-12s - %s (custom API)\n" "$menu_idx" "$name" "$persona_name"
            agent_list+=("custom_api|$i")
            ((menu_idx++)) || true
        done

        echo ""
        echo "   d) Done with persona configuration"
        echo ""

        read -r -p "Select agent to change persona (or 'd' for done): " choice

        if [[ "$choice" == "d" || "$choice" == "D" ]]; then
            done_personas=true
            continue
        fi

        # Validate selection
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#agent_list[@]} ]]; then
            log_warn "Invalid selection"
            continue
        fi

        # Get selected agent info
        local selected="${agent_list[$((choice-1))]}"
        local agent_type="${selected%%|*}"
        local agent_idx="${selected##*|}"

        local agent_name
        case "$agent_type" in
            cli) agent_name="${CLI_AGENT_NAMES[$agent_idx]}" ;;
            api) agent_name="${API_AGENT_NAMES[$agent_idx]}" ;;
            custom_cli) agent_name="${CUSTOM_NAMES[$agent_idx]}" ;;
            custom_api) agent_name="${CUSTOM_API_NAMES[$agent_idx]}" ;;
        esac

        # Show persona selection menu
        _select_persona_for_agent "$agent_type" "$agent_idx" "$agent_name"
    done

    log_success "Persona configuration complete"
}

# Internal: Select a persona for a specific agent
_select_persona_for_agent() {
    local agent_type="$1"
    local agent_idx="$2"
    local agent_name="$3"

    echo ""
    echo "Select persona for $agent_name:"
    echo ""

    # Get current persona ID
    local current_id
    case "$agent_type" in
        cli) current_id="${CLI_PERSONA_IDS[$agent_idx]}" ;;
        api) current_id="${API_PERSONA_IDS[$agent_idx]}" ;;
        custom_cli) current_id="${CUSTOM_PERSONA_IDS[$agent_idx]:-1}" ;;
        custom_api) current_id="${CUSTOM_API_PERSONA_IDS[$agent_idx]:-1}" ;;
    esac

    # Display persona catalog
    echo "$PERSONA_CATALOG" | grep -v '^$' | while IFS='|' read -r id name var desc; do
        local marker="  "
        [[ "$id" == "$current_id" ]] && marker="* "
        printf "  %s%2s) %-22s - %s\n" "$marker" "$id" "$name" "$desc"
    done

    echo ""
    echo "   c) Enter custom persona text"
    echo ""

    read -r -p "Choice [$current_id]: " persona_choice
    persona_choice="${persona_choice:-$current_id}"

    if [[ "$persona_choice" == "c" || "$persona_choice" == "C" ]]; then
        prompt_input "Enter custom persona description" ""
        local custom_text="$REPLY"
        if [[ -n "$custom_text" ]]; then
            # For custom text, we store it differently - use ID 0 to indicate custom
            case "$agent_type" in
                cli)
                    CLI_PERSONA_IDS[$agent_idx]="0"
                    CLI_AGENT_PERSONAS[$agent_idx]="$custom_text"
                    ;;
                api)
                    API_PERSONA_IDS[$agent_idx]="0"
                    API_AGENT_PERSONAS[$agent_idx]="$custom_text"
                    ;;
                custom_cli)
                    CUSTOM_PERSONA_IDS[$agent_idx]="0"
                    CUSTOM_PERSONAS[$agent_idx]="$custom_text"
                    ;;
                custom_api)
                    CUSTOM_API_PERSONA_IDS[$agent_idx]="0"
                    CUSTOM_API_PERSONAS[$agent_idx]="$custom_text"
                    ;;
            esac
            log_success "$agent_name: Custom persona set"
        fi
        return
    fi

    # Validate persona ID selection
    if [[ "$persona_choice" =~ ^[0-9]+$ ]] && [[ $persona_choice -ge 1 ]] && [[ $persona_choice -le 15 ]]; then
        case "$agent_type" in
            cli) CLI_PERSONA_IDS[$agent_idx]="$persona_choice" ;;
            api) API_PERSONA_IDS[$agent_idx]="$persona_choice" ;;
            custom_cli)
                # Ensure array is large enough
                while [[ ${#CUSTOM_PERSONA_IDS[@]} -le $agent_idx ]]; do
                    CUSTOM_PERSONA_IDS+=("1")
                done
                CUSTOM_PERSONA_IDS[$agent_idx]="$persona_choice"
                ;;
            custom_api)
                while [[ ${#CUSTOM_API_PERSONA_IDS[@]} -le $agent_idx ]]; do
                    CUSTOM_API_PERSONA_IDS+=("1")
                done
                CUSTOM_API_PERSONA_IDS[$agent_idx]="$persona_choice"
                ;;
        esac
        local new_name
        new_name=$(get_persona_by_id "$persona_choice" "name")
        log_success "$agent_name: Persona changed to $new_name"
    else
        log_warn "Invalid selection, keeping current persona"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_header "AI Consultants v2.0 - Configuration Wizard"

    echo "This wizard will help you configure AI Consultants."
    echo "You need at least 2 agents enabled (CLI or API-based)."
    echo ""

    # Step 1: Detect CLI agents
    detect_cli_agents

    # Step 2: Select CLI agents
    select_cli_agents

    # Step 3: Configure API agents
    configure_api_agents

    # Step 4: Configure personas
    configure_personas

    # Step 5: Validate (minimum 2 agents)
    if ! validate_configuration; then
        log_error "Configuration incomplete. At least 2 agents required."
        exit 1
    fi

    # Step 6: Save
    if [[ "$NON_INTERACTIVE" == "true" ]] || confirm "Save configuration to $OUTPUT_FILE?" "y"; then
        save_configuration
    else
        log_warn "Configuration not saved."
        exit 1
    fi

    print_header "Configuration Complete"

    # Show summary
    echo "Enabled agents:"
    for i in "${!CLI_AGENT_NAMES[@]}"; do
        [[ "${CLI_ENABLED[$i]}" == "true" ]] && echo "  [CLI] ${CLI_AGENT_NAMES[$i]}"
    done
    for name in "${CUSTOM_NAMES[@]}"; do echo "  [CLI] $name (custom)"; done
    for i in "${!API_AGENT_NAMES[@]}"; do
        [[ "${API_ENABLED[$i]}" == "true" ]] && echo "  [API] ${API_AGENT_NAMES[$i]}"
    done
    for name in "${CUSTOM_API_NAMES[@]}"; do echo "  [API] $name (custom)"; done

    echo ""
    echo "Next steps:"
    echo "  1. Review and edit $OUTPUT_FILE if needed"
    echo "  2. Run: source $OUTPUT_FILE"
    echo "  3. Test: ./scripts/preflight_check.sh"
    echo "  4. Start: ./scripts/consult_all.sh \"Your question\""
    echo ""
}

main "$@"
