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

# Initialize state arrays
for i in "${!CLI_AGENT_NAMES[@]}"; do
    CLI_DETECTED+=("missing")
    CLI_ENABLED+=("false")
done

for i in "${!API_AGENT_NAMES[@]}"; do
    API_ENABLED+=("false")
    API_KEYS_VALUES+=("")
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
    {
        echo "# ============================================================================="
        echo "# ENABLED CONSULTANTS"
        echo "# ============================================================================="
        echo ""
        echo "# CLI-based consultants"
    } >> "$OUTPUT_FILE"

    for i in "${!CLI_AGENT_NAMES[@]}"; do
        local name="${CLI_AGENT_NAMES[$i]}"
        local enabled="${CLI_ENABLED[$i]}"
        local name_upper
        name_upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')
        local var_name="ENABLE_${name_upper}"
        # Special case for Mistral
        [[ "$name" == "Mistral" ]] && var_name="ENABLE_MISTRAL"
        echo "${var_name}=$enabled" >> "$OUTPUT_FILE"
    done

    {
        echo ""
        echo "# API-based consultants"
    } >> "$OUTPUT_FILE"

    for i in "${!API_AGENT_NAMES[@]}"; do
        local name="${API_AGENT_NAMES[$i]}"
        local enabled="${API_ENABLED[$i]}"
        local name_upper
        name_upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')
        local var_name="ENABLE_${name_upper}"
        echo "${var_name}=$enabled" >> "$OUTPUT_FILE"
    done

    # API Keys
    {
        echo ""
        echo "# ============================================================================="
        echo "# API KEYS"
        echo "# ============================================================================="
        echo ""
    } >> "$OUTPUT_FILE"

    for i in "${!API_AGENT_NAMES[@]}"; do
        if [[ -n "${API_KEYS_VALUES[$i]}" ]]; then
            local key_var="${API_AGENT_KEY_VARS[$i]}"
            echo "${key_var}=${API_KEYS_VALUES[$i]}" >> "$OUTPUT_FILE"
        fi
    done

    # Custom CLI agents
    if [[ ${#CUSTOM_NAMES[@]} -gt 0 ]]; then
        {
            echo ""
            echo "# ============================================================================="
            echo "# CUSTOM CLI AGENTS"
            echo "# ============================================================================="
            echo ""
        } >> "$OUTPUT_FILE"

        for i in "${!CUSTOM_NAMES[@]}"; do
            local name="${CUSTOM_NAMES[$i]}"
            local cmd="${CUSTOM_CMDS[$i]}"
            local persona="${CUSTOM_PERSONAS[$i]}"
            local var_upper
            var_upper=$(echo "$name" | tr '[:lower:]' '[:upper:]' | tr -d ' -')
            echo "# Custom CLI agent: $name ($persona)" >> "$OUTPUT_FILE"
            echo "${var_upper}_CMD=$cmd" >> "$OUTPUT_FILE"
            echo "ENABLE_${var_upper}=true" >> "$OUTPUT_FILE"
        done
    fi

    # Custom API agents
    if [[ ${#CUSTOM_API_NAMES[@]} -gt 0 ]]; then
        {
            echo ""
            echo "# ============================================================================="
            echo "# CUSTOM API AGENTS"
            echo "# ============================================================================="
            echo ""
        } >> "$OUTPUT_FILE"

        for i in "${!CUSTOM_API_NAMES[@]}"; do
            local name="${CUSTOM_API_NAMES[$i]}"
            local url="${CUSTOM_API_URLS[$i]}"
            local key="${CUSTOM_API_KEYS[$i]}"
            local model="${CUSTOM_API_MODELS[$i]}"
            local persona="${CUSTOM_API_PERSONAS[$i]}"
            local format="${CUSTOM_API_FORMATS[$i]}"
            local var_upper
            var_upper=$(echo "$name" | tr '[:lower:]' '[:upper:]' | tr -d ' -')

            echo "# Custom API agent: $name" >> "$OUTPUT_FILE"
            echo "# Persona: $persona" >> "$OUTPUT_FILE"
            echo "${var_upper}_API_KEY=$key" >> "$OUTPUT_FILE"
            echo "${var_upper}_API_URL=$url" >> "$OUTPUT_FILE"
            echo "${var_upper}_MODEL=$model" >> "$OUTPUT_FILE"
            echo "${var_upper}_TIMEOUT=180" >> "$OUTPUT_FILE"
            echo "${var_upper}_FORMAT=$format" >> "$OUTPUT_FILE"
            echo "${var_upper}_PERSONA=\"$persona\"" >> "$OUTPUT_FILE"
            echo "ENABLE_${var_upper}=true" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        done
    fi

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

    # Step 4: Validate (minimum 2 agents)
    if ! validate_configuration; then
        log_error "Configuration incomplete. At least 2 agents required."
        exit 1
    fi

    # Step 5: Save
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
    for i in "${!CUSTOM_NAMES[@]}"; do
        echo "  [CLI] ${CUSTOM_NAMES[$i]} (custom)"
    done
    for i in "${!API_AGENT_NAMES[@]}"; do
        [[ "${API_ENABLED[$i]}" == "true" ]] && echo "  [API] ${API_AGENT_NAMES[$i]}"
    done
    for i in "${!CUSTOM_API_NAMES[@]}"; do
        echo "  [API] ${CUSTOM_API_NAMES[$i]} (custom)"
    done

    echo ""
    echo "Next steps:"
    echo "  1. Review and edit $OUTPUT_FILE if needed"
    echo "  2. Run: source $OUTPUT_FILE"
    echo "  3. Test: ./scripts/preflight_check.sh"
    echo "  4. Start: ./scripts/consult_all.sh \"Your question\""
    echo ""
}

main "$@"
