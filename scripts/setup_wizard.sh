#!/bin/bash
# setup_wizard.sh - Interactive setup wizard for AI Consultants v2.0
# Checks CLI installation, tests authentication, and generates .env configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common.sh (which already sources config.sh)
source "$SCRIPT_DIR/lib/common.sh"

# =============================================================================
# COLORS AND FORMATTING
# =============================================================================

GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
BOLD="\033[1m"
RESET="\033[0m"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE}║       AI Consultants v2.0 - Setup Wizard                     ║${RESET}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}━━━ $1 ━━━${RESET}"
    echo ""
}

status_ok() {
    echo -e "  ${GREEN}[OK]${RESET} $1"
}

status_warn() {
    echo -e "  ${YELLOW}[WARN]${RESET} $1"
}

status_fail() {
    echo -e "  ${RED}[FAIL]${RESET} $1"
}

status_skip() {
    echo -e "  ${BLUE}[SKIP]${RESET} $1"
}

# =============================================================================
# CLI DETECTION
# =============================================================================

# Using map_* functions from common.sh for bash 3.2 compatibility
# Maps: CLI_STATUS, CLI_AUTH_STATUS
AVAILABLE_COUNT=0

check_cli() {
    local name="$1"
    local cmd="$2"
    local install_hint="$3"

    if command -v "$cmd" &> /dev/null; then
        map_set "CLI_STATUS" "$name" "installed"
        return 0
    else
        map_set "CLI_STATUS" "$name" "missing"
        return 1
    fi
}

test_cli_auth() {
    local name="$1"
    local cmd="$2"
    local test_args="$3"

    if [[ "$(map_get "CLI_STATUS" "$name")" != "installed" ]]; then
        map_set "CLI_AUTH_STATUS" "$name" "skipped"
        return 1
    fi

    # Test with timeout
    if timeout 15 $cmd $test_args &>/dev/null 2>&1; then
        map_set "CLI_AUTH_STATUS" "$name" "authenticated"
        ((AVAILABLE_COUNT++))
        return 0
    else
        map_set "CLI_AUTH_STATUS" "$name" "failed"
        return 1
    fi
}

# =============================================================================
# MAIN CHECKS
# =============================================================================

check_prerequisites() {
    print_section "Prerequisites"

    # Check jq (required)
    if command -v jq &> /dev/null; then
        status_ok "jq installed ($(jq --version))"
    else
        status_fail "jq NOT installed - REQUIRED"
        echo ""
        echo "  Install jq first:"
        echo "    macOS:  brew install jq"
        echo "    Ubuntu: sudo apt-get install jq"
        echo ""
        exit 1
    fi

    # Check optional tools
    if command -v timeout &> /dev/null; then
        status_ok "timeout available (GNU coreutils)"
    elif command -v gtimeout &> /dev/null; then
        status_ok "gtimeout available (coreutils)"
    else
        status_warn "timeout not available - using fallback"
    fi
}

check_consultants() {
    print_section "Consultant CLIs"

    # Gemini
    if check_cli "Gemini" "$GEMINI_CMD" "npm install -g @google/gemini-cli"; then
        status_ok "Gemini CLI installed"
    else
        status_warn "Gemini CLI not found"
        echo "        Install: npm install -g @google/gemini-cli"
    fi

    # Codex
    if check_cli "Codex" "$CODEX_CMD" "npm install -g @openai/codex"; then
        status_ok "Codex CLI installed"
    else
        status_warn "Codex CLI not found"
        echo "        Install: npm install -g @openai/codex"
    fi

    # Mistral
    if check_cli "Mistral" "$MISTRAL_CMD" "pip install mistral-vibe"; then
        status_ok "Mistral Vibe CLI installed"
    else
        status_warn "Mistral Vibe CLI not found"
        echo "        Install: pip install mistral-vibe"
    fi

    # Kilo
    if check_cli "Kilo" "$KILO_CMD" "npm install -g @kilocode/cli"; then
        status_ok "Kilo CLI installed"
    else
        status_warn "Kilo CLI not found"
        echo "        Install: npm install -g @kilocode/cli"
    fi

    # Cursor
    if check_cli "Cursor" "$CURSOR_CMD" "curl https://cursor.com/install -fsS | bash"; then
        status_ok "Cursor CLI installed"
    else
        status_warn "Cursor CLI not found"
        echo "        Install: curl https://cursor.com/install -fsS | bash"
    fi
}

test_authentication() {
    print_section "Authentication Test"

    echo "  Testing API connectivity (this may take a moment)..."
    echo ""

    # Gemini
    if test_cli_auth "Gemini" "$GEMINI_CMD" "--version"; then
        status_ok "Gemini authenticated"
    elif [[ "$(map_get "CLI_STATUS" "Gemini")" == "installed" ]]; then
        status_fail "Gemini auth failed"
        echo "        Run: gemini auth login"
        echo "        Or set: GOOGLE_API_KEY=your-key"
    else
        status_skip "Gemini (not installed)"
    fi

    # Codex
    if test_cli_auth "Codex" "$CODEX_CMD" "--help"; then
        status_ok "Codex authenticated"
    elif [[ "$(map_get "CLI_STATUS" "Codex")" == "installed" ]]; then
        status_fail "Codex auth failed"
        echo "        Set: OPENAI_API_KEY=sk-your-key"
    else
        status_skip "Codex (not installed)"
    fi

    # Mistral
    if test_cli_auth "Mistral" "$MISTRAL_CMD" "--help"; then
        status_ok "Mistral authenticated"
    elif [[ "$(map_get "CLI_STATUS" "Mistral")" == "installed" ]]; then
        status_fail "Mistral auth failed"
        echo "        Set: MISTRAL_API_KEY=your-key"
    else
        status_skip "Mistral (not installed)"
    fi

    # Kilo
    if test_cli_auth "Kilo" "$KILO_CMD" "--version"; then
        status_ok "Kilo authenticated"
    elif [[ "$(map_get "CLI_STATUS" "Kilo")" == "installed" ]]; then
        status_fail "Kilo auth failed"
        echo "        Run: kilocode auth login"
    else
        status_skip "Kilo (not installed)"
    fi

    # Cursor
    if test_cli_auth "Cursor" "$CURSOR_CMD" "--help"; then
        status_ok "Cursor authenticated"
    elif [[ "$(map_get "CLI_STATUS" "Cursor")" == "installed" ]]; then
        status_fail "Cursor auth failed"
        echo "        Cursor CLI uses your Cursor subscription"
    else
        status_skip "Cursor (not installed)"
    fi
}

# =============================================================================
# CONFIGURATION GENERATION
# =============================================================================

generate_config() {
    print_section "Recommended Configuration"

    local gemini_enabled="false"
    local codex_enabled="false"
    local mistral_enabled="false"
    local kilo_enabled="false"
    local cursor_enabled="false"

    [[ "$(map_get "CLI_AUTH_STATUS" "Gemini")" == "authenticated" ]] && gemini_enabled="true"
    [[ "$(map_get "CLI_AUTH_STATUS" "Codex")" == "authenticated" ]] && codex_enabled="true"
    [[ "$(map_get "CLI_AUTH_STATUS" "Mistral")" == "authenticated" ]] && mistral_enabled="true"
    [[ "$(map_get "CLI_AUTH_STATUS" "Kilo")" == "authenticated" ]] && kilo_enabled="true"
    [[ "$(map_get "CLI_AUTH_STATUS" "Cursor")" == "authenticated" ]] && cursor_enabled="true"

    echo "  Based on your setup, recommended settings:"
    echo ""
    echo -e "  ${BOLD}ENABLE_GEMINI=${gemini_enabled}${RESET}"
    echo -e "  ${BOLD}ENABLE_CODEX=${codex_enabled}${RESET}"
    echo -e "  ${BOLD}ENABLE_MISTRAL=${mistral_enabled}${RESET}"
    echo -e "  ${BOLD}ENABLE_KILO=${kilo_enabled}${RESET}"
    echo -e "  ${BOLD}ENABLE_CURSOR=${cursor_enabled}${RESET}"
    echo ""

    # Check minimum requirement
    if [[ $AVAILABLE_COUNT -lt 2 ]]; then
        echo -e "  ${RED}${BOLD}WARNING: Only $AVAILABLE_COUNT consultant(s) available.${RESET}"
        echo -e "  ${RED}AI Consultants requires at least 2 consultants for comparison.${RESET}"
        echo ""
        echo "  Please configure at least one more consultant."
        echo "  See docs/SETUP.md for detailed instructions."
        echo ""
        SAVE_CONFIG="no"
        return
    fi

    echo -e "  ${GREEN}${BOLD}Status: $AVAILABLE_COUNT/5 consultants ready${RESET}"
    echo ""

    # Ask to save
    echo -n "  Save configuration to .env? [Y/n] "
    read -r SAVE_CONFIG
    SAVE_CONFIG="${SAVE_CONFIG:-Y}"

    if [[ "$SAVE_CONFIG" =~ ^[Yy]$ ]]; then
        save_env_file "$gemini_enabled" "$codex_enabled" "$mistral_enabled" "$kilo_enabled" "$cursor_enabled"
    fi
}

save_env_file() {
    local gemini="$1"
    local codex="$2"
    local mistral="$3"
    local kilo="$4"
    local cursor="$5"

    local env_file="$PROJECT_ROOT/.env"

    # Backup existing .env if present
    if [[ -f "$env_file" ]]; then
        cp "$env_file" "${env_file}.backup"
        echo ""
        echo -e "  ${YELLOW}Backed up existing .env to .env.backup${RESET}"
    fi

    cat > "$env_file" << EOF
# =============================================================================
# AI Consultants v2.0 - Generated Configuration
# =============================================================================
# Generated by setup_wizard.sh on $(date -Iseconds)
# See .env.example for all available options

# Enabled consultants (based on detected setup)
ENABLE_GEMINI=$gemini
ENABLE_CODEX=$codex
ENABLE_MISTRAL=$mistral
ENABLE_KILO=$kilo
ENABLE_CURSOR=$cursor

# Features
ENABLE_PERSONA=true
ENABLE_SYNTHESIS=true
ENABLE_DEBATE=false
ENABLE_COST_TRACKING=true

# Logging
LOG_LEVEL=INFO
EOF

    echo ""
    echo -e "  ${GREEN}${BOLD}Configuration saved to .env${RESET}"
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
    print_section "Summary"

    if [[ $AVAILABLE_COUNT -ge 2 ]]; then
        echo -e "  ${GREEN}${BOLD}Setup complete!${RESET}"
        echo ""
        echo "  You can now run:"
        echo ""
        echo "    ./scripts/consult_all.sh \"Your coding question here\""
        echo ""
        echo "  For more options, see README.md"
    else
        echo -e "  ${YELLOW}${BOLD}Setup incomplete${RESET}"
        echo ""
        echo "  You need at least 2 working consultants."
        echo "  See docs/SETUP.md for installation instructions."
    fi
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_header
    check_prerequisites
    check_consultants
    test_authentication
    generate_config
    print_summary
}

main "$@"
