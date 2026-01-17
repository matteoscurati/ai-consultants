#!/bin/bash
# doctor.sh - Comprehensive diagnostic command for AI Consultants
#
# Performs in-depth health checks with specific fix suggestions:
# - Checks all CLI tools are installed
# - Verifies API keys are configured
# - Tests connectivity to each service
# - Validates configuration
# - Suggests specific commands to fix issues
#
# Usage: ./doctor.sh [--fix] [--json] [--verbose]
#
# Options:
#   --fix       Attempt to auto-fix common issues
#   --json      Output in JSON format
#   --verbose   Show detailed diagnostic information

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- Parameters ---
FIX_MODE=false
JSON_OUTPUT=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--fix] [--json] [--verbose]"
            echo ""
            echo "Comprehensive diagnostic for AI Consultants"
            echo ""
            echo "Options:"
            echo "  --fix       Attempt to auto-fix common issues"
            echo "  --json      Output in JSON format"
            echo "  --verbose   Show detailed diagnostic information"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- State tracking ---
ISSUES=()
WARNINGS=()
FIXES_APPLIED=()
TOTAL_CHECKS=0
PASSED_CHECKS=0

# =============================================================================
# DIAGNOSTIC FUNCTIONS
# =============================================================================

add_issue() {
    local category="$1"
    local description="$2"
    local fix_command="$3"
    ISSUES+=("$category|$description|$fix_command")
}

add_warning() {
    local category="$1"
    local description="$2"
    WARNINGS+=("$category|$description")
}

check_pass() {
    (( ++TOTAL_CHECKS ))
    (( ++PASSED_CHECKS ))
}

check_fail() {
    (( ++TOTAL_CHECKS ))
}

# Print only in non-JSON mode
_print() {
    [[ "$JSON_OUTPUT" != "true" ]] && echo "$@"
}

print_header() {
    _print ""
    _print "╔══════════════════════════════════════════════════════════════╗"
    _print "║           AI Consultants v${AI_CONSULTANTS_VERSION:-2.2.0} - Doctor                    ║"
    _print "╚══════════════════════════════════════════════════════════════╝"
    _print ""
}

print_section() {
    local title="$1"
    _print ""
    _print "▶ $title"
    _print "────────────────────────────────────────────────────────────────"
}

# =============================================================================
# CHECK: Required Dependencies
# =============================================================================

check_dependencies() {
    print_section "Checking Required Dependencies"

    # jq is required
    if command -v jq &> /dev/null; then
        local jq_version
        jq_version=$(jq --version 2>/dev/null || echo "unknown")
        _print "  ✓ jq: $jq_version"
        check_pass
    else
        _print "  ✗ jq: NOT INSTALLED (required)"
        add_issue "dependency" "jq is not installed" "brew install jq  # or: apt install jq"
        check_fail
    fi

    # bash version check (3.2+ for macOS compatibility)
    local bash_version="${BASH_VERSION%%(*}"
    local bash_major="${bash_version%%.*}"
    if [[ $bash_major -ge 3 ]]; then
        _print "  ✓ bash: $BASH_VERSION"
        check_pass
    else
        _print "  ✗ bash: $BASH_VERSION (need 3.2+)"
        add_issue "dependency" "Bash version too old" "brew install bash"
        check_fail
    fi

    # timeout command (optional, has fallback)
    if command -v timeout &> /dev/null || command -v gtimeout &> /dev/null; then
        _print "  ✓ timeout: available"
        check_pass
    else
        _print "  ○ timeout: not found (using fallback)"
        add_warning "dependency" "timeout command not found, using POSIX fallback"
    fi

    # curl for API checks
    if command -v curl &> /dev/null; then
        _print "  ✓ curl: available"
        check_pass
    else
        _print "  ✗ curl: NOT INSTALLED"
        add_issue "dependency" "curl is not installed" "brew install curl"
        check_fail
    fi
}

# =============================================================================
# CHECK: CLI-based Consultants
# =============================================================================

check_cli_consultant() {
    local name="$1"
    local cmd="$2"
    local install_cmd="$3"
    local env_var="$4"

    # Check if enabled
    local enabled_var="ENABLE_${env_var}"
    local is_enabled="${!enabled_var:-false}"

    if [[ "$is_enabled" != "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && _print "  ○ $name: disabled"
        return 0
    fi

    # Check if installed
    if ! command -v "$cmd" &> /dev/null; then
        _print "  ✗ $name: NOT INSTALLED (enabled but missing)"
        add_issue "consultant" "$name CLI not found" "$install_cmd"
        check_fail
        return 1
    fi

    # Get version (--version is standard and fast, no timeout needed)
    local version
    version=$("$cmd" --version 2>/dev/null | head -1 || echo "")

    if [[ -n "$version" ]]; then
        _print "  ✓ $name: $version"
        check_pass
    else
        # Fallback: CLI exists but --version failed, still consider it installed
        _print "  ✓ $name: installed (version unknown)"
        check_pass
    fi
}

check_cli_consultants() {
    print_section "Checking CLI-based Consultants"

    check_cli_consultant "Gemini" "$GEMINI_CMD" "npm install -g @google/gemini-cli" "GEMINI"
    check_cli_consultant "Codex" "$CODEX_CMD" "npm install -g @openai/codex" "CODEX"
    check_cli_consultant "Mistral Vibe" "$MISTRAL_CMD" "pip install mistral-vibe" "MISTRAL"
    check_cli_consultant "Kilo" "$KILO_CMD" "npm install -g @kilocode/cli" "KILO"
    check_cli_consultant "Cursor" "$CURSOR_CMD" "Visit https://cursor.com to install" "CURSOR"
    check_cli_consultant "Aider" "$AIDER_CMD" "pip install aider-chat" "AIDER"
    check_cli_consultant "Claude" "$CLAUDE_CMD" "See https://docs.anthropic.com/claude-code" "CLAUDE"
}

# =============================================================================
# CHECK: API-based Consultants
# =============================================================================

check_api_consultant() {
    local name="$1"
    local api_key_var="$2"
    local api_url_var="$3"
    local enabled_var="$4"

    local is_enabled="${!enabled_var:-false}"

    if [[ "$is_enabled" != "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && _print "  ○ $name: disabled"
        return 0
    fi

    local api_key="${!api_key_var:-}"
    local api_url="${!api_url_var:-}"

    # Check API key
    if [[ -z "$api_key" ]]; then
        _print "  ✗ $name: API key not set"
        add_issue "api" "$name API key not configured" "export ${api_key_var}='your-api-key'"
        check_fail
        return 1
    fi

    # Mask API key for display
    local masked_key="${api_key:0:4}...${api_key: -4}"

    # Test connectivity (simple HEAD request to avoid charges)
    if [[ -n "$api_url" ]] && command -v curl &> /dev/null; then
        if timeout 10 curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $api_key" "$api_url" 2>/dev/null | grep -qE "^(200|401|403)"; then
            _print "  ✓ $name: configured (key: $masked_key)"
            check_pass
        else
            _print "  △ $name: configured but API unreachable"
            add_warning "api" "$name API endpoint unreachable"
            check_pass
        fi
    else
        _print "  ✓ $name: configured (key: $masked_key)"
        check_pass
    fi
}

check_api_consultants() {
    print_section "Checking API-based Consultants"

    check_api_consultant "Qwen3" "QWEN3_API_KEY" "QWEN3_API_URL" "ENABLE_QWEN3"
    check_api_consultant "GLM" "GLM_API_KEY" "GLM_API_URL" "ENABLE_GLM"
    check_api_consultant "Grok" "GROK_API_KEY" "GROK_API_URL" "ENABLE_GROK"
    check_api_consultant "DeepSeek" "DEEPSEEK_API_KEY" "DEEPSEEK_API_URL" "ENABLE_DEEPSEEK"
}

# =============================================================================
# CHECK: Configuration
# =============================================================================

check_configuration() {
    print_section "Checking Configuration"

    # Count enabled consultants using a compact loop
    local enabled_count=0
    local consultant_flags="ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_KILO ENABLE_CURSOR ENABLE_AIDER ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK"
    for flag in $consultant_flags; do
        [[ "${!flag:-false}" == "true" ]] && ((enabled_count++))
    done

    if [[ $enabled_count -ge 2 ]]; then
        _print "  ✓ Enabled consultants: $enabled_count (minimum 2 required)"
        check_pass
    elif [[ $enabled_count -eq 1 ]]; then
        _print "  ✗ Enabled consultants: $enabled_count (need at least 2)"
        add_issue "config" "Only 1 consultant enabled, need at least 2" "Run: ./scripts/setup_wizard.sh"
        check_fail
    else
        _print "  ✗ Enabled consultants: 0 (need at least 2)"
        add_issue "config" "No consultants enabled" "Run: ./scripts/setup_wizard.sh"
        check_fail
    fi

    # Check output directory permissions
    if [[ -d "$DEFAULT_OUTPUT_DIR_BASE" ]]; then
        if [[ -w "$DEFAULT_OUTPUT_DIR_BASE" ]]; then
            _print "  ✓ Output directory: writable"
            check_pass
        else
            _print "  ✗ Output directory: not writable"
            add_issue "config" "Output directory not writable" "chmod 755 $DEFAULT_OUTPUT_DIR_BASE"
            check_fail
        fi
    else
        _print "  ○ Output directory: will be created on first run"
        check_pass
    fi

    # Check session directory
    if [[ -d "$SESSION_DIR" ]]; then
        local session_count
        session_count=$(find "$SESSION_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        _print "  ✓ Session directory: $session_count sessions"
        check_pass
    else
        _print "  ○ Session directory: will be created on first run"
        check_pass
    fi

    # Budget check
    _print "  ○ Max session cost: \$${MAX_SESSION_COST}"
}

# =============================================================================
# CHECK: Synthesis Engine
# =============================================================================

check_synthesis() {
    print_section "Checking Synthesis Engine"

    if [[ "$ENABLE_SYNTHESIS" != "true" ]]; then
        _print "  ○ Synthesis: disabled"
        return 0
    fi

    # Check for claude CLI (preferred)
    if command -v claude &> /dev/null; then
        local claude_version
        claude_version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
        _print "  ✓ Claude CLI: $claude_version"
        check_pass
    else
        _print "  △ Claude CLI: not found (will use fallback synthesis)"
        add_warning "synthesis" "Claude CLI not installed, using basic fallback synthesis"
    fi

    # Check synthesis template
    local template_file="$SCRIPT_DIR/../templates/synthesis_prompt.md"
    if [[ -f "$template_file" ]]; then
        _print "  ✓ Synthesis template: found"
        check_pass
    else
        _print "  ○ Synthesis template: using default"
    fi
}

# =============================================================================
# CHECK: Ollama (Local Models)
# =============================================================================

check_ollama() {
    print_section "Checking Local Model Support (Ollama)"

    local enable_ollama="${ENABLE_OLLAMA:-false}"

    if command -v ollama &> /dev/null; then
        local ollama_version
        ollama_version=$(ollama --version 2>/dev/null | head -1 || echo "unknown")
        _print "  ✓ Ollama: $ollama_version"
        check_pass

        # Check if server is running
        if curl -s http://localhost:11434/api/tags &>/dev/null; then
            _print "  ✓ Ollama server: running"
            check_pass

            # List available models
            if [[ "$VERBOSE" == "true" ]]; then
                local models
                models=$(curl -s http://localhost:11434/api/tags 2>/dev/null | jq -r '.models[].name' 2>/dev/null | head -5 | tr '\n' ', ' || echo "none")
                _print "  ○ Available models: ${models%,}"
            fi
        else
            _print "  △ Ollama server: not running"
            add_warning "ollama" "Ollama installed but server not running"
        fi
    else
        if [[ "$enable_ollama" == "true" ]]; then
            _print "  ✗ Ollama: enabled but not installed"
            add_issue "ollama" "Ollama enabled but not installed" "curl -fsSL https://ollama.com/install.sh | sh"
            check_fail
        else
            _print "  ○ Ollama: not installed (optional)"
        fi
    fi
}

# =============================================================================
# SUMMARY AND FIXES
# =============================================================================

print_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Build issues array
        local issues_json="[]"
        for issue in "${ISSUES[@]:-}"; do
            IFS='|' read -r category description fix <<< "$issue"
            issues_json=$(echo "$issues_json" | jq \
                --arg cat "$category" \
                --arg desc "$description" \
                --arg fix "$fix" \
                '. + [{"category": $cat, "description": $desc, "fix": $fix}]')
        done

        # Build warnings array
        local warnings_json="[]"
        for warning in "${WARNINGS[@]:-}"; do
            IFS='|' read -r category description <<< "$warning"
            warnings_json=$(echo "$warnings_json" | jq \
                --arg cat "$category" \
                --arg desc "$description" \
                '. + [{"category": $cat, "description": $desc}]')
        done

        jq -n \
            --argjson total "$TOTAL_CHECKS" \
            --argjson passed "$PASSED_CHECKS" \
            --argjson issues "${#ISSUES[@]}" \
            --argjson warnings "${#WARNINGS[@]}" \
            --argjson issues_list "$issues_json" \
            --argjson warnings_list "$warnings_json" \
            --arg version "$AI_CONSULTANTS_VERSION" \
            '{
                doctor: {
                    version: $version,
                    status: (if $issues > 0 then "unhealthy" elif $warnings > 0 then "degraded" else "healthy" end),
                    checks: {
                        total: $total,
                        passed: $passed,
                        failed: ($total - $passed)
                    },
                    issues: $issues_list,
                    warnings: $warnings_list
                }
            }'
    else
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                       Diagnosis Summary                       ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Checks: $PASSED_CHECKS/$TOTAL_CHECKS passed"
        echo "  Issues: ${#ISSUES[@]}"
        echo "  Warnings: ${#WARNINGS[@]}"
        echo ""

        if [[ ${#ISSUES[@]} -gt 0 ]]; then
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  ISSUES (must fix)                                          │"
            echo "└─────────────────────────────────────────────────────────────┘"
            for issue in "${ISSUES[@]}"; do
                IFS='|' read -r category description fix <<< "$issue"
                echo ""
                echo "  [$category] $description"
                echo "  Fix: $fix"
            done
            echo ""
        fi

        if [[ ${#WARNINGS[@]} -gt 0 ]]; then
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  WARNINGS (optional)                                        │"
            echo "└─────────────────────────────────────────────────────────────┘"
            for warning in "${WARNINGS[@]}"; do
                IFS='|' read -r category description <<< "$warning"
                echo "  [$category] $description"
            done
            echo ""
        fi

        if [[ ${#ISSUES[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
            echo "  ✓ All systems healthy!"
            echo ""
        elif [[ ${#ISSUES[@]} -eq 0 ]]; then
            echo "  △ System operational with warnings"
            echo ""
        else
            echo "  ✗ Issues found - run with --fix to attempt auto-repair"
            echo ""
        fi
    fi
}

attempt_fixes() {
    if [[ "$FIX_MODE" != "true" || ${#ISSUES[@]} -eq 0 ]]; then
        return 0
    fi

    print_section "Attempting Auto-Fixes"

    for issue in "${ISSUES[@]}"; do
        IFS='|' read -r category description fix <<< "$issue"

        # Only auto-fix safe operations with whitelisted commands
        case "$category" in
            dependency)
                # Extract package name safely (whitelist approach, no eval)
                local package=""
                if [[ "$fix" =~ ^brew\ install\ ([a-zA-Z0-9_-]+)$ ]]; then
                    package="${BASH_REMATCH[1]}"
                fi

                if [[ -n "$package" ]] && command -v brew &>/dev/null; then
                    echo "  Attempting: brew install $package"
                    if brew install "$package" 2>/dev/null; then
                        echo "  ✓ Fixed: $description"
                        FIXES_APPLIED+=("$description")
                    else
                        echo "  ✗ Failed to fix: $description"
                    fi
                else
                    echo "  ○ Manual fix required: $fix"
                fi
                ;;
            config)
                echo "  ○ Manual fix required: $fix"
                ;;
            *)
                echo "  ○ Manual fix required: $fix"
                ;;
        esac
    done

    if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
        echo ""
        echo "  Applied ${#FIXES_APPLIED[@]} fix(es). Re-run doctor to verify."
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    print_header
    check_dependencies
    check_cli_consultants
    check_api_consultants
    check_configuration
    check_synthesis
    check_ollama
    attempt_fixes
    print_summary

    # Exit code based on issues
    if [[ ${#ISSUES[@]} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main
